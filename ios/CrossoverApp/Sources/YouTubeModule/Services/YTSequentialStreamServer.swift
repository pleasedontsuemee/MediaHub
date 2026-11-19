import Foundation
import AVFoundation
import Network

// MARK: - Embedded Localhost HTTP HLS Server (`NWListener` on 127.0.0.1) + Sequential 5s fMP4 Engine
// Apple's AVPlayer natively requires `http://` or `https://` for `.m3u8` HLS playlists (it rejects `file://`).
// This embedded localhost HTTP server runs 100% inside the app on `127.0.0.1:<port>` using `Network.framework`:
// 1. Parses MP4 `sidx` (Segment Index) boxes (~2.7 KB) in ~35ms and memoizes them per `(videoId, itag)`.
// 2. Serves `master.m3u8`, `video.m3u8`, and `audio.m3u8` over HTTP on `127.0.0.1:<port>` with 5.2s segments.
// 3. Logs every request, segment count, and timing to `YTDebugLogger`.

public final class YTSequentialStreamServer: @unchecked Sendable {
    public static let shared = YTSequentialStreamServer()

    private let session: URLSession
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    private let serverQueue = DispatchQueue(label: "com.ytmine.hlshttpserver", qos: .userInteractive)

    private var listener: NWListener?
    private(set) public var listeningPort: UInt16 = 0

    public struct SIDXSegment: Sendable {
        public let byteStart: Int64
        public let byteLength: Int64
        public let durationSeconds: Double

        public var byteEnd: Int64 { byteStart + byteLength - 1 }
    }

    private struct SegmentEntry: Sendable {
        let url: URL
        let userAgent: String
        let videoId: String
        let itag: Int
        let index: Int?
        let isAudio: Bool
    }

    private var sidxCache: [String: [SIDXSegment]] = [:]
    private var playlistStore: [String: Data] = [:]
    private var segmentURLStore: [String: SegmentEntry] = [:]
    private var segmentDataCache: [String: Data] = [:]
    private var segmentCacheOrder: [String] = []
    private var segmentCacheBytes: Int = 0
    private let maxSegmentCacheBytes: Int = 150 * 1024 * 1024 // 150 MB lookahead ring buffer (~50s+ of 4K or ~6min of 1080p)
    private var inFlightSegmentTasks: [String: (task: Task<Data?, Never>, isPrefetch: Bool, index: Int?, videoId: String)] = [:]
    private var streamPlayheadIndex: [String: Int] = [:]
    private var streamPrefetchWorkers: [String: (videoId: String, task: Task<Void, Never>)] = [:]
    private var prewarmTasks: [String: Task<Void, Never>] = [:]
    private var failedSegmentKeys: Set<String> = []
    private var authRejectedVideos: Set<String> = []
    private var lastRefreshNotificationAt: [String: Date] = [:]
    private let lock = NSLock()

    public static let streamNeedsRefreshNotification = Notification.Name("YTStreamNeedsRefreshNotification")

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 45
        config.httpMaximumConnectionsPerHost = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        self.session = URLSession(configuration: config)
        startLocalHTTPServer()
    }

    // MARK: - 1. Embedded Localhost HTTP Server (`http://127.0.0.1:<port>`)
    private func startLocalHTTPServer() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let nwListener = try NWListener(using: params, on: .any)
            nwListener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let port = nwListener.port?.rawValue {
                        self?.listeningPort = port
                        YTDebugLogger.shared.log(.stream, tag: "HLSServer", "Localhost HTTP HLS server listening on http://127.0.0.1:\(port)")
                    }
                case .failed(let err):
                    YTDebugLogger.shared.log(.error, tag: "HLSServer", "NWListener failed: \(err.localizedDescription)")
                default:
                    break
                }
            }
            nwListener.newConnectionHandler = { [weak self] connection in
                self?.handleHTTPConnection(connection)
            }
            nwListener.start(queue: serverQueue)
            self.listener = nwListener
        } catch {
            YTDebugLogger.shared.log(.error, tag: "HLSServer", "Failed to create NWListener: \(error.localizedDescription)")
        }
    }

    private func handleHTTPConnection(_ connection: NWConnection) {
        connection.start(queue: serverQueue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, error in
            guard let self = self else {
                connection.cancel()
                return
            }
            if let error = error {
                YTDebugLogger.shared.log(.error, tag: "HLSServer", "Conn receive error: \(error.localizedDescription)")
                connection.cancel()
                return
            }
            guard let data = data, let requestText = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let firstLine = requestText.components(separatedBy: "\r\n").first ?? ""
            let parts = firstLine.components(separatedBy: " ")
            let method = parts.count > 0 ? parts[0] : "GET"
            let rawPath = parts.count > 1 ? parts[1] : "/"
            let cleanPath = rawPath.components(separatedBy: "?").first ?? rawPath
            let key = cleanPath.hasPrefix("/") ? String(cleanPath.dropFirst()) : cleanPath

            if key.hasPrefix("seg/") {
                let segKey = String(key.dropFirst(4))
                let entry = self.lock.withLock { self.segmentURLStore[segKey] }
                guard let entry else {
                    let notFound = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
                    connection.send(content: notFound, completion: .contentProcessed { _ in connection.cancel() })
                    return
                }
                let byteRange = Self.parseHTTPByteRange(from: requestText)
                self.proxySegment(segKey: segKey, entry: entry, method: method, byteRange: byteRange, on: connection)
                return
            }

            let payload: Data? = self.lock.withLock { self.playlistStore[key] }

            if let body = payload {
                YTDebugLogger.shared.log(.stream, tag: "HLSServer", "\(method) /\(key) -> 200 OK (\(body.count) bytes)")
                var header = "HTTP/1.1 200 OK\r\n"
                header += "Content-Type: application/vnd.apple.mpegurl\r\n"
                header += "Content-Length: \(body.count)\r\n"
                header += "Access-Control-Allow-Origin: *\r\n"
                header += "Connection: close\r\n\r\n"
                var responseData = Data(header.utf8)
                if method != "HEAD" {
                    responseData.append(body)
                }
                connection.send(content: responseData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else {
                YTDebugLogger.shared.log(.error, tag: "HLSServer", "\(method) /\(key) -> 404 Not Found")
                let notFound = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
                connection.send(content: notFound, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private static func parseHTTPByteRange(from requestText: String) -> (start: Int, end: Int?)? {
        for line in requestText.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("range:") {
                let val = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                guard val.lowercased().hasPrefix("bytes=") else { return nil }
                let spec = val.dropFirst(6).components(separatedBy: ",").first ?? ""
                let bounds = spec.components(separatedBy: "-")
                if bounds.count == 2, let start = Int(bounds[0].trimmingCharacters(in: .whitespaces)) {
                    let endStr = bounds[1].trimmingCharacters(in: .whitespaces)
                    let end = endStr.isEmpty ? nil : Int(endStr)
                    return (start, end)
                }
            }
        }
        return nil
    }

    private func proxySegment(
        segKey: String,
        entry: SegmentEntry,
        method: String,
        byteRange: (start: Int, end: Int?)?,
        on connection: NWConnection
    ) {
        let wasCached = lock.withLock { segmentDataCache[segKey] != nil }
        if let idx = entry.index {
            // Keep 10 video segments (~50s) or 6 audio segments (~60s) continuously buffered ahead of playhead
            updatePlayheadAndPrefetch(videoId: entry.videoId, itag: entry.itag, anchorIndex: idx, isAudio: entry.isAudio)
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else {
                connection.cancel()
                return
            }
            if let data = await self.fetchOrCacheSegment(segKey: segKey, isPrefetch: false) {
                if wasCached, let idx = entry.index, (idx == 0 || idx % 5 == 0) {
                    let windowAhead = entry.isAudio ? 6 : 10
                    let (aheadCount, cacheMB) = self.bufferStats(videoId: entry.videoId, itag: entry.itag, fromIndex: idx, windowAhead: windowAhead)
                    YTDebugLogger.shared.log(.net, tag: "HLSProxy", "HIT \(segKey) (\(data.count)B) [bufAhead=\(aheadCount)/\(windowAhead) cache=\(String(format: "%.1f", cacheMB))MB]")
                }

                let total = data.count
                if let br = byteRange, br.start >= 0, br.start < total {
                    let clampedEnd = min(total - 1, br.end ?? (total - 1))
                    if clampedEnd >= br.start {
                        let slice = data.subdata(in: br.start..<(clampedEnd + 1))
                        var header = "HTTP/1.1 206 Partial Content\r\n"
                        header += "Content-Type: video/mp4\r\n"
                        header += "Content-Length: \(slice.count)\r\n"
                        header += "Content-Range: bytes \(br.start)-\(clampedEnd)/\(total)\r\n"
                        header += "Accept-Ranges: bytes\r\n"
                        header += "Access-Control-Allow-Origin: *\r\n"
                        header += "Connection: close\r\n\r\n"
                        var responseData = Data(header.utf8)
                        if method != "HEAD" {
                            responseData.append(slice)
                        }
                        connection.send(content: responseData, completion: .contentProcessed { _ in
                            connection.cancel()
                        })
                        return
                    }
                }

                var header = "HTTP/1.1 200 OK\r\n"
                header += "Content-Type: video/mp4\r\n"
                header += "Content-Length: \(total)\r\n"
                header += "Accept-Ranges: bytes\r\n"
                header += "Access-Control-Allow-Origin: *\r\n"
                header += "Connection: close\r\n\r\n"
                var responseData = Data(header.utf8)
                if method != "HEAD" {
                    responseData.append(data)
                }
                connection.send(content: responseData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            let bad = Data("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: bad, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func bufferStats(videoId: String, itag: Int, fromIndex: Int, windowAhead: Int) -> (aheadCached: Int, cacheMB: Double) {
        lock.withLock {
            var count = 0
            for offset in 1...windowAhead {
                let k = "\(videoId)_\(itag)_\(fromIndex + offset).mp4"
                if segmentDataCache[k] != nil {
                    count += 1
                }
            }
            return (count, Double(segmentCacheBytes) / (1024.0 * 1024.0))
        }
    }

    private func fetchOrCacheSegment(segKey: String, isPrefetch: Bool = false) async -> Data? {
        if let cached = lock.withLock({ segmentDataCache[segKey] }) {
            return cached
        }

        let existingTask = lock.withLock { inFlightSegmentTasks[segKey]?.task }
        if let task = existingTask {
            return await task.value
        }

        guard let entry = lock.withLock({ segmentURLStore[segKey] }) else {
            return nil
        }

        let task = Task<Data?, Never> { [weak self] in
            guard let self else { return nil }
            var lastStatusCode = 0
            var lastErrorDesc = ""
            var lastRespHeaders = ""
            let qItems = URLComponents(url: entry.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let cParam = qItems.first(where: { $0.name == "c" })?.value ?? "?"
            let hasPot = qItems.contains(where: { $0.name == "pot" && !($0.value ?? "").isEmpty })
            let rangeParam = qItems.first(where: { $0.name == "range" })?.value ?? "?"
            let host = entry.url.host ?? "?"

            for attempt in 0..<3 {
                if Task.isCancelled { return nil }
                var req = URLRequest(url: entry.url)
                req.httpMethod = "GET"
                req.setValue(entry.userAgent, forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 18
                let t0 = Date()

                do {
                    let (data, resp) = try await self.session.data(for: req)
                    if let http = resp as? HTTPURLResponse {
                        lastStatusCode = http.statusCode
                        let elapsed = max(0.001, Date().timeIntervalSince(t0))
                        let ms = Int(elapsed * 1000)
                        if (200..<300).contains(http.statusCode) {
                            self.storeSegmentInCache(segKey: segKey, data: data)
                            let shouldLog = (entry.index == nil) || ((entry.index ?? -1) <= 1) || ((entry.index ?? 0) % 5 == 0)
                            if shouldLog {
                                let mbps = (Double(data.count) / (1024.0 * 1024.0)) / elapsed
                                let cacheMB = self.lock.withLock { Double(self.segmentCacheBytes) / (1024.0 * 1024.0) }
                                YTDebugLogger.shared.log(.net, tag: "HLSProxy", "OK \(segKey) [c=\(cParam) pot=\(hasPot) range=\(rangeParam)] -> \(data.count)B in \(ms)ms (\(String(format: "%.1f", mbps)) MB/s) [cache=\(String(format: "%.1f", cacheMB))MB]")
                            }
                            return data
                        }
                        let interesting = ["x-reject-reason", "content-type", "server", "via"]
                        lastRespHeaders = interesting.compactMap { k in
                            http.value(forHTTPHeaderField: k).map { "\(k)=\($0)" }
                        }.joined(separator: " ")
                        if http.statusCode == 401 || http.statusCode == 403 || http.statusCode == 410 {
                            break
                        }
                    }
                } catch {
                    if Task.isCancelled { return nil }
                    lastErrorDesc = error.localizedDescription
                }
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(250_000_000 * (attempt + 1)))
                }
            }

            if Task.isCancelled { return nil }
            let isAuthError = (lastStatusCode == 401 || lastStatusCode == 403 || lastStatusCode == 410)
            self.lock.withLock {
                _ = self.failedSegmentKeys.insert(segKey)
                if isAuthError {
                    _ = self.authRejectedVideos.insert(entry.videoId)
                }
            }
            YTDebugLogger.shared.log(.error, tag: "HLSProxy", "FAIL \(segKey) HTTP=\(lastStatusCode) host=\(host) c=\(cParam) pot=\(hasPot) range=\(rangeParam) ua=\(entry.userAgent.prefix(32)) hdr=[\(lastRespHeaders)] err=[\(lastErrorDesc)]")
            if !isPrefetch && isAuthError {
                let videoId = entry.videoId
                let shouldNotify: Bool = self.lock.withLock {
                    let now = Date()
                    if let last = self.lastRefreshNotificationAt[videoId], now.timeIntervalSince(last) < 8.0 {
                        return false
                    }
                    self.lastRefreshNotificationAt[videoId] = now
                    return true
                }
                if shouldNotify && !videoId.isEmpty {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: YTSequentialStreamServer.streamNeedsRefreshNotification,
                            object: nil,
                            userInfo: [
                                "videoId": videoId,
                                "segIndex": entry.index ?? -1,
                                "isAudio": entry.isAudio
                            ]
                        )
                    }
                }
            }
            return nil
        }

        lock.withLock {
            inFlightSegmentTasks[segKey] = (task, isPrefetch, entry.index, entry.videoId)
        }
        let result = await task.value
        _ = lock.withLock {
            inFlightSegmentTasks.removeValue(forKey: segKey)
        }
        return result
    }

    private func storeSegmentInCache(segKey: String, data: Data) {
        lock.withLock {
            if let old = segmentDataCache.removeValue(forKey: segKey) {
                segmentCacheBytes -= old.count
                segmentCacheOrder.removeAll { $0 == segKey }
            }
            segmentDataCache[segKey] = data
            segmentCacheOrder.append(segKey)
            segmentCacheBytes += data.count

            while segmentCacheBytes > maxSegmentCacheBytes, !segmentCacheOrder.isEmpty {
                let oldest = segmentCacheOrder.removeFirst()
                if let removed = segmentDataCache.removeValue(forKey: oldest) {
                    segmentCacheBytes -= removed.count
                }
            }
        }
    }

    /// Maintains a continuous sliding forward buffer (~50s = 10 segments video, ~60s = 6 segments audio)
    /// ahead of the active playhead, cancelling out-of-window prefetches on seek and stopping cleanly on auth errors.
    private func updatePlayheadAndPrefetch(videoId: String, itag: Int, anchorIndex: Int, isAudio: Bool) {
        let streamKey = "\(videoId)_\(itag)"
        let windowAhead = isAudio ? 6 : 10
        var shouldStartWorker = false
        var wasSeek = false

        lock.withLock {
            if authRejectedVideos.contains(videoId) {
                return
            }
            let previousAnchor = streamPlayheadIndex[streamKey]
            streamPlayheadIndex[streamKey] = anchorIndex

            // If user jumped (seek), cancel stale prefetch tasks far outside the new window
            if let prev = previousAnchor, abs(anchorIndex - prev) > 3 {
                wasSeek = true
                for (k, info) in inFlightSegmentTasks where info.isPrefetch && k.hasPrefix("\(streamKey)_") {
                    if let tIdx = info.index, (tIdx < anchorIndex || tIdx > anchorIndex + windowAhead + 2) {
                        info.task.cancel()
                    }
                }
            }

            if streamPrefetchWorkers[streamKey] == nil {
                shouldStartWorker = true
            }
        }

        guard shouldStartWorker else { return }

        let delayNs: UInt64 = wasSeek ? 160_000_000 : 0
        let worker = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                _ = self.lock.withLock {
                    self.streamPrefetchWorkers.removeValue(forKey: streamKey)
                }
            }

            if delayNs > 0 {
                try? await Task.sleep(nanoseconds: delayNs)
                if Task.isCancelled { return }
            }

            let maxConcurrent = isAudio ? 2 : 3
            while !Task.isCancelled {
                let (batch, authRejected): ([String], Bool) = self.lock.withLock {
                    if self.authRejectedVideos.contains(videoId) {
                        return ([], true)
                    }
                    let anchor = self.streamPlayheadIndex[streamKey] ?? anchorIndex
                    let startIdx = max(0, anchor + 1)
                    let endIdx = anchor + windowAhead
                    var missing: [String] = []
                    if startIdx <= endIdx {
                        for idx in startIdx...endIdx {
                            let k = "\(streamKey)_\(idx).mp4"
                            if self.segmentURLStore[k] != nil
                                && self.segmentDataCache[k] == nil
                                && self.inFlightSegmentTasks[k] == nil
                                && !self.failedSegmentKeys.contains(k) {
                                missing.append(k)
                            }
                        }
                    }
                    return (missing, false)
                }

                if authRejected || batch.isEmpty { break }

                await withTaskGroup(of: Void.self) { group in
                    for k in batch.prefix(maxConcurrent) {
                        group.addTask {
                            _ = await self.fetchOrCacheSegment(segKey: k, isPrefetch: true)
                        }
                    }
                }
            }
        }

        lock.withLock {
            streamPrefetchWorkers[streamKey] = (videoId, worker)
        }
    }

    /// Stage 1: Give segment 0 (~5s) 100% of startup bandwidth so even heavy 4K60 HDR starts in <1s.
    /// Stage 2: Once segment 0 is ready, expand smoothly to ~50-60s forward lookahead in RAM.
    private func prebufferInitialWindow(videoId: String, videoItag: Int, audioItag: Int?) {
        let v0 = "\(videoId)_\(videoItag)_0.mp4"
        let a0 = audioItag.map { "\(videoId)_\($0)_0.mp4" }

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            // Stage 1: ONLY seg 0 (video + audio) gets full bandwidth for fastest possible first frame!
            await withTaskGroup(of: Void.self) { group in
                group.addTask { _ = await self.fetchOrCacheSegment(segKey: v0, isPrefetch: true) }
                if let a0 {
                    group.addTask { _ = await self.fetchOrCacheSegment(segKey: a0, isPrefetch: true) }
                }
            }
            if Task.isCancelled { return }
            // Stage 2: Deep 50-60s lookahead buffer in background
            self.updatePlayheadAndPrefetch(videoId: videoId, itag: videoItag, anchorIndex: 0, isAudio: false)
            if let aItag = audioItag {
                self.updatePlayheadAndPrefetch(videoId: videoId, itag: aItag, anchorIndex: 0, isAudio: true)
            }
        }
        lock.withLock {
            prewarmTasks["init_\(videoId)"]?.cancel()
            prewarmTasks["init_\(videoId)"] = task
        }
    }

    /// Immediately cancels all prefetch workers, in-flight segment downloads, and sidx prewarms
    /// belonging to any video other than `exceptVideoId` (or all videos if nil).
    public func cancelAllWork(exceptVideoId: String? = nil) {
        lock.withLock {
            for (_, info) in inFlightSegmentTasks where info.videoId != exceptVideoId {
                info.task.cancel()
            }
            inFlightSegmentTasks = inFlightSegmentTasks.filter { $0.value.videoId == exceptVideoId }

            for (_, entry) in streamPrefetchWorkers where entry.videoId != exceptVideoId {
                entry.task.cancel()
            }
            streamPrefetchWorkers = streamPrefetchWorkers.filter { $0.value.videoId == exceptVideoId }

            for (k, task) in prewarmTasks {
                let keep = exceptVideoId.map { k == $0 || k == "init_\($0)" } ?? false
                if !keep {
                    task.cancel()
                }
            }
            if let keepId = exceptVideoId {
                prewarmTasks = prewarmTasks.filter { $0.key == keepId || $0.key == "init_\(keepId)" }
            } else {
                prewarmTasks.removeAll()
            }
        }
    }

    public func clearCache(for videoId: String) {
        lock.withLock {
            sidxCache = sidxCache.filter { !$0.key.hasPrefix("\(videoId)-") }
            playlistStore = playlistStore.filter { !$0.key.hasPrefix("\(videoId)_") }
            segmentURLStore = segmentURLStore.filter { $0.value.videoId != videoId }
            segmentDataCache = segmentDataCache.filter { !$0.key.hasPrefix("\(videoId)_") }
            segmentCacheOrder.removeAll { $0.hasPrefix("\(videoId)_") }
            segmentCacheBytes = segmentDataCache.values.reduce(0) { $0 + $1.count }
            inFlightSegmentTasks.forEach { if $0.value.videoId == videoId { $0.value.task.cancel() } }
            inFlightSegmentTasks = inFlightSegmentTasks.filter { $0.value.videoId != videoId }
            streamPrefetchWorkers.forEach { if $0.value.videoId == videoId { $0.value.task.cancel() } }
            streamPrefetchWorkers = streamPrefetchWorkers.filter { $0.value.videoId != videoId }
            prewarmTasks[videoId]?.cancel()
            prewarmTasks.removeValue(forKey: videoId)
            prewarmTasks["init_\(videoId)"]?.cancel()
            prewarmTasks.removeValue(forKey: "init_\(videoId)")
            streamPlayheadIndex = streamPlayheadIndex.filter { !$0.key.hasPrefix("\(videoId)_") }
            failedSegmentKeys = failedSegmentKeys.filter { !$0.hasPrefix("\(videoId)_") }
            _ = authRejectedVideos.remove(videoId)
            _ = lastRefreshNotificationAt.removeValue(forKey: videoId)
        }
    }

    private func waitForServerPort() async -> UInt16 {
        if listeningPort > 0 { return listeningPort }
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if listeningPort > 0 { return listeningPort }
        }
        return listeningPort
    }

    // MARK: - 2. Pre-warm All Resolutions (`144p`..`4320p 8K`) After Active Stream Starts
    public func prewarmAllResolutions(for playback: YTResolvedVideoPlayback) {
        let vid = playback.video.id
        let formats = playback.adaptiveVideoFormats + (playback.bestAudioFormat.map { [$0] } ?? [])
        let task = Task.detached(priority: .utility) { [weak self] in
            // Wait 1.2s so active stream's seg 0 gets 100% of startup bandwidth first!
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, !Task.isCancelled else { return }
            YTDebugLogger.shared.log(.stream, tag: "Prewarm", "Pre-warming \(formats.count) stream sidx tables for \(vid)")
            await withTaskGroup(of: Void.self) { group in
                for fmt in formats {
                    group.addTask {
                        if Task.isCancelled { return }
                        _ = await self.getOrFetchSIDXSegments(for: fmt, videoId: vid)
                    }
                }
            }
        }
        lock.withLock {
            prewarmTasks[vid]?.cancel()
            prewarmTasks[vid] = task
        }
    }

    // MARK: - 3. Build Sequential 5-Second Segment HLS `AVPlayerItem` via `http://127.0.0.1:<port>/...`
    public func makeSequentialHLSPlayerItem(
        videoFormat: YTVideoStreamFormat,
        audioFormat: YTVideoStreamFormat?,
        videoId: String,
        allAdaptiveFormats: [YTVideoStreamFormat] = [],
        isAutoQuality: Bool = false
    ) async -> AVPlayerItem? {
        // Cancel any stale downloads/prefetchers from previously watched videos immediately
        cancelAllWork(exceptVideoId: videoId)
        lock.withLock {
            authRejectedVideos.remove(videoId)
            failedSegmentKeys = failedSegmentKeys.filter { !$0.hasPrefix("\(videoId)_") }
        }

        let port = await waitForServerPort()
        guard port > 0 else {
            YTDebugLogger.shared.log(.error, tag: "HLSServer", "Localhost HTTP server port is 0! Cannot serve HLS.")
            return nil
        }

        async let vSegsTask = getOrFetchSIDXSegments(for: videoFormat, videoId: videoId)
        async let aSegsTask: [SIDXSegment]? = audioFormat != nil ? getOrFetchSIDXSegments(for: audioFormat!, videoId: videoId) : nil

        let (vSegs, aSegs) = await (vSegsTask, aSegsTask)
        guard !vSegs.isEmpty else {
            YTDebugLogger.shared.log(.error, tag: "HLSServer", "SIDX empty for \(videoId) itag \(videoFormat.itag) (\(videoFormat.qualityLabel))")
            return nil
        }

        let key = "\(videoId)_\(videoFormat.itag)"
        let videoFileName = "\(key)_video.m3u8"
        let (vM3U8, vSegMap) = buildMediaPlaylistM3U8(videoId: videoId, format: videoFormat, segments: vSegs, port: port)

        var audioFileName: String? = nil
        var aM3U8Data: Data? = nil
        var aSegMap: [String: SegmentEntry] = [:]
        if let audioFmt = audioFormat, let aSegs = aSegs, !aSegs.isEmpty {
            let aName = "\(videoId)_audio_\(audioFmt.itag).m3u8"
            let (aM3U8, aMap) = buildMediaPlaylistM3U8(videoId: videoId, format: audioFmt, segments: aSegs, port: port)
            aM3U8Data = Data(aM3U8.utf8)
            aSegMap = aMap
            audioFileName = aName
        }

        var variantEntries: [(format: YTVideoStreamFormat, fileName: String)] = [
            (videoFormat, videoFileName)
        ]

        var extraPlaylists: [String: Data] = [:]
        var extraSegMaps: [String: SegmentEntry] = [:]
        if isAutoQuality {
            for otherFmt in allAdaptiveFormats where otherFmt.itag != videoFormat.itag {
                if let cachedSegs = getCachedSIDXSegments(for: otherFmt, videoId: videoId), !cachedSegs.isEmpty {
                    let otherFileName = "\(videoId)_\(otherFmt.itag)_video.m3u8"
                    let (otherM3U8, otherMap) = buildMediaPlaylistM3U8(videoId: videoId, format: otherFmt, segments: cachedSegs, port: port)
                    extraPlaylists[otherFileName] = Data(otherM3U8.utf8)
                    for (k, v) in otherMap { extraSegMaps[k] = v }
                    variantEntries.append((otherFmt, otherFileName))
                }
            }
        }

        let masterFileName = "\(key)_master.m3u8"
        let masterM3U8 = buildMasterPlaylistM3U8(
            variants: variantEntries,
            audioFormat: audioFormat,
            audioPlaylistFileName: audioFileName
        )

        lock.withLock {
            for (k, v) in vSegMap { segmentURLStore[k] = v }
            for (k, v) in aSegMap { segmentURLStore[k] = v }
            for (k, v) in extraSegMaps { segmentURLStore[k] = v }
            playlistStore[videoFileName] = Data(vM3U8.utf8)
            if let aName = audioFileName, let aData = aM3U8Data {
                playlistStore[aName] = aData
            }
            for (k, v) in extraPlaylists {
                playlistStore[k] = v
            }
            playlistStore[masterFileName] = Data(masterM3U8.utf8)
        }

        guard let masterURL = URL(string: "http://127.0.0.1:\(port)/\(masterFileName)") else { return nil }
        YTDebugLogger.shared.log(.stream, tag: "HLSServer", "Created HLS item: \(masterURL.absoluteString) (vSegs: \(vSegs.count), aSegs: \(aSegs?.count ?? 0), quality: \(videoFormat.displayResolutionTitle))")

        let asset = AVURLAsset(
            url: masterURL,
            options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": videoFormat.userAgent ?? userAgent]]
        )
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 50.0
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        if !isAutoQuality, let w = videoFormat.width, let h = videoFormat.height {
            item.preferredMaximumResolution = CGSize(width: w, height: h)
        }
        prebufferInitialWindow(videoId: videoId, videoItag: videoFormat.itag, audioItag: audioFormat?.itag)
        return item
    }

    // MARK: - 3b. Pin an Existing YouTube Master HLS Playlist to a Specific Quality (144p..2160p, HDR/SDR aware)
    public func makeQualityPinnedHLSPlayerItem(
        from masterHLSURL: URL,
        targetHeight: Int,
        videoId: String,
        preferHDR: Bool = false
    ) async -> (item: AVPlayerItem, width: Int?, height: Int?) {
        cancelAllWork(exceptVideoId: videoId)
        let port = await waitForServerPort()
        var req = URLRequest(url: masterHLSURL)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        if port > 0,
           let (data, resp) = try? await session.data(for: req),
           let http = resp as? HTTPURLResponse,
           (200..<300).contains(http.statusCode),
           let m3u8Text = String(data: data, encoding: .utf8),
           m3u8Text.contains("#EXT-X-STREAM-INF") {

            let rawLines = m3u8Text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .components(separatedBy: "\n")

            var headerLines: [String] = []
            var variants: [(infLine: String, urlLine: String, width: Int, height: Int, bandwidth: Int, isHDR: Bool, isAvc: Bool)] = []

            var i = 0
            while i < rawLines.count {
                let line = rawLines[i].trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#EXT-X-STREAM-INF:") {
                    var nextIdx = i + 1
                    while nextIdx < rawLines.count && rawLines[nextIdx].trimmingCharacters(in: .whitespaces).isEmpty {
                        nextIdx += 1
                    }
                    if nextIdx < rawLines.count {
                        let rawURI = rawLines[nextIdx].trimmingCharacters(in: .whitespaces)
                        let absURI = URL(string: rawURI, relativeTo: masterHLSURL)?.absoluteString ?? rawURI
                        let (w, h) = Self.parseHLSResolution(from: line)
                        let bw = Self.parseHLSBandwidth(from: line)
                        let isHDRVariant = line.contains("VIDEO-RANGE=PQ") || line.contains("VIDEO-RANGE=HLG")
                        let isAvcVariant = line.contains("avc1")
                        variants.append((line, absURI, w, h, bw, isHDRVariant, isAvcVariant))
                        i = nextIdx + 1
                        continue
                    }
                } else if line.hasPrefix("#EXT-X-MEDIA:") {
                    let resolvedMedia = Self.resolveHLSAttributeURI(in: line, relativeTo: masterHLSURL)
                    headerLines.append(resolvedMedia)
                } else if line.hasPrefix("#EXTM3U") || line.hasPrefix("#EXT-X-VERSION") || line.hasPrefix("#EXT-X-INDEPENDENT-SEGMENTS") {
                    headerLines.append(line)
                }
                i += 1
            }

            if !variants.isEmpty {
                let rangeFiltered = variants.filter { $0.isHDR == preferHDR }
                let candidatePool = rangeFiltered.isEmpty ? variants : rangeFiltered
                let chosen = candidatePool.min { a, b in
                    let aEff = min(a.width > 0 ? a.width : a.height, a.height)
                    let bEff = min(b.width > 0 ? b.width : b.height, b.height)
                    let diffA = abs(aEff - targetHeight)
                    let diffB = abs(bEff - targetHeight)
                    if diffA != diffB { return diffA < diffB }
                    if !preferHDR && targetHeight <= 1080 && a.isAvc != b.isAvc {
                        return a.isAvc
                    }
                    return a.bandwidth > b.bandwidth
                }!

                if !headerLines.contains(where: { $0.hasPrefix("#EXTM3U") }) {
                    headerLines.insert("#EXTM3U", at: 0)
                }
                let pinnedM3U8 = (headerLines + [chosen.infLine, chosen.urlLine]).joined(separator: "\n") + "\n"
                let rangeTag = preferHDR ? "hdr" : "sdr"
                let masterFileName = "\(videoId)_hls_\(targetHeight)_\(rangeTag)_master.m3u8"
                lock.withLock {
                    playlistStore[masterFileName] = Data(pinnedM3U8.utf8)
                }

                if let pinnedURL = URL(string: "http://127.0.0.1:\(port)/\(masterFileName)") {
                    let asset = AVURLAsset(
                        url: pinnedURL,
                        options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": userAgent]]
                    )
                    let item = AVPlayerItem(asset: asset)
                    item.preferredForwardBufferDuration = 45.0
                    item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
                    if chosen.width > 0 && chosen.height > 0 {
                        item.preferredMaximumResolution = CGSize(width: chosen.width, height: chosen.height)
                    }
                    YTDebugLogger.shared.log(.stream, tag: "HLSQuality", "Pinned master HLS for \(videoId) to \(chosen.width)x\(chosen.height) hdr=\(chosen.isHDR) (target \(targetHeight)p preferHDR=\(preferHDR))")
                    return (item, chosen.width > 0 ? chosen.width : nil, chosen.height > 0 ? chosen.height : nil)
                }
            }
        }

        let fallbackAsset = AVURLAsset(
            url: masterHLSURL,
            options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": userAgent]]
        )
        let fallbackItem = AVPlayerItem(asset: fallbackAsset)
        fallbackItem.preferredForwardBufferDuration = 45.0
        fallbackItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        fallbackItem.preferredMaximumResolution = CGSize(width: targetHeight * 16 / 9, height: targetHeight)
        return (fallbackItem, nil, targetHeight)
    }

    private static func parseHLSResolution(from line: String) -> (Int, Int) {
        guard let range = line.range(of: #"RESOLUTION=(\d+)x(\d+)"#, options: .regularExpression) else {
            return (0, 0)
        }
        let sub = String(line[range]).replacingOccurrences(of: "RESOLUTION=", with: "")
        let parts = sub.components(separatedBy: "x")
        if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) {
            return (w, h)
        }
        return (0, 0)
    }

    private static func parseHLSBandwidth(from line: String) -> Int {
        guard let range = line.range(of: #"BANDWIDTH=(\d+)"#, options: .regularExpression) else {
            return 0
        }
        let sub = String(line[range]).replacingOccurrences(of: "BANDWIDTH=", with: "")
        return Int(sub) ?? 0
    }

    private static func resolveHLSAttributeURI(in line: String, relativeTo baseURL: URL) -> String {
        guard let range = line.range(of: #"URI="([^"]+)""#, options: .regularExpression) else {
            return line
        }
        let attr = String(line[range])
        let rawURI = attr.replacingOccurrences(of: "URI=\"", with: "").replacingOccurrences(of: "\"", with: "")
        guard let abs = URL(string: rawURI, relativeTo: baseURL)?.absoluteString else {
            return line
        }
        return line.replacingCharacters(in: range, with: "URI=\"\(abs)\"")
    }

    // MARK: - 4. Build Fast Progressive `AVPlayerItem` (for Muxed `itag 18`)
    public func makeFastProgressivePlayerItem(format: YTVideoStreamFormat) -> AVPlayerItem {
        let headers = ["User-Agent": format.userAgent ?? userAgent]
        let asset = AVURLAsset(url: format.url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 45.0
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        YTDebugLogger.shared.log(.stream, tag: "Progressive", "Created progressive item itag \(format.itag) (\(format.qualityLabel))")
        return item
    }

    // MARK: - 5. Fetch & Memoize `sidx` Segment Index Box
    private func sidxCacheKey(for format: YTVideoStreamFormat, videoId: String) -> String {
        if let tid = format.audioTrackId, !tid.isEmpty {
            return "\(videoId)-\(format.itag)-\(tid)"
        }
        return "\(videoId)-\(format.itag)"
    }

    private func getCachedSIDXSegments(for format: YTVideoStreamFormat, videoId: String) -> [SIDXSegment]? {
        let cacheKey = sidxCacheKey(for: format, videoId: videoId)
        return lock.withLock { sidxCache[cacheKey] }
    }

    public func getOrFetchSIDXSegments(for format: YTVideoStreamFormat, videoId: String) async -> [SIDXSegment] {
        if let cached = getCachedSIDXSegments(for: format, videoId: videoId), !cached.isEmpty {
            return cached
        }

        let indexEnd = format.indexRangeEnd ?? format.initRangeEnd ?? 4095
        guard let rangeURL = appendRangeQueryParam(to: format.url, start: 0, end: indexEnd) else {
            return []
        }

        var req = URLRequest(url: rangeURL)
        req.setValue(format.userAgent ?? userAgent, forHTTPHeaderField: "User-Agent")

        let t0 = Date()
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count >= 32 else {
            YTDebugLogger.shared.log(.error, tag: "SIDX", "Failed to fetch sidx for \(videoId) itag \(format.itag) (range 0-\(indexEnd))")
            return []
        }

        // Cache pure ftyp+moov init segment (0...initRangeEnd) so #EXT-X-MAP hits RAM in 0ms without stray sidx!
        let initSlice: Data
        if let initEnd = format.initRangeEnd, initEnd > 0, Int(initEnd + 1) <= data.count {
            initSlice = Data(data.prefix(Int(initEnd + 1)))
        } else {
            initSlice = data
        }
        storeSegmentInCache(segKey: "\(videoId)_\(format.itag)_init.mp4", data: initSlice)

        let parsed = Self.parseSIDXBox(from: data)
        let elapsedMs = Int(Date().timeIntervalSince(t0) * 1000)
        YTDebugLogger.shared.log(.stream, tag: "SIDX", "Parsed \(parsed.count) segments for \(videoId) itag \(format.itag) (\(format.qualityLabel)) in \(elapsedMs)ms (\(data.count) bytes)")

        if !parsed.isEmpty {
            let cacheKey = sidxCacheKey(for: format, videoId: videoId)
            lock.withLock {
                sidxCache[cacheKey] = parsed
            }
        }
        return parsed
    }

    public static func parseSIDXBox(from data: Data) -> [SIDXSegment] {
        let bytes = [UInt8](data)
        let total = bytes.count
        var pos = 0

        func readUInt32(_ offset: Int) -> UInt32 {
            guard offset + 4 <= total else { return 0 }
            return (UInt32(bytes[offset]) << 24)
                | (UInt32(bytes[offset + 1]) << 16)
                | (UInt32(bytes[offset + 2]) << 8)
                | UInt32(bytes[offset + 3])
        }

        func readUInt16(_ offset: Int) -> UInt16 {
            guard offset + 2 <= total else { return 0 }
            return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
        }

        func readUInt64(_ offset: Int) -> UInt64 {
            let hi = UInt64(readUInt32(offset))
            let lo = UInt64(readUInt32(offset + 4))
            return (hi << 32) | lo
        }

        while pos + 8 <= total {
            let boxSize = Int(readUInt32(pos))
            guard boxSize >= 8 else { break }
            let typeStr = String(bytes: bytes[(pos + 4)..<(pos + 8)], encoding: .ascii) ?? ""

            if typeStr == "sidx" {
                let version = Int(bytes[pos + 8])
                let timescale = Double(max(1, readUInt32(pos + 16)))
                let firstOffset: Int64
                let refCountOffset: Int

                if version == 0 {
                    guard pos + 32 <= total else { break }
                    firstOffset = Int64(readUInt32(pos + 24))
                    refCountOffset = pos + 30
                } else {
                    guard pos + 40 <= total else { break }
                    firstOffset = Int64(readUInt64(pos + 28))
                    refCountOffset = pos + 38
                }

                let referenceCount = Int(readUInt16(refCountOffset))
                let entriesStart = refCountOffset + 2
                var currentByteOffset = Int64(pos + boxSize) + firstOffset
                var segments: [SIDXSegment] = []
                segments.reserveCapacity(referenceCount)

                for i in 0..<referenceCount {
                    let entryOffset = entriesStart + (i * 12)
                    guard entryOffset + 12 <= total else { break }
                    let word1 = readUInt32(entryOffset)
                    let subsegmentDuration = readUInt32(entryOffset + 4)
                    let referencedSize = Int64(word1 & 0x7FFFFFFF)
                    let durSec = Double(subsegmentDuration) / timescale
                    if referencedSize > 0 && durSec > 0 {
                        segments.append(SIDXSegment(
                            byteStart: currentByteOffset,
                            byteLength: referencedSize,
                            durationSeconds: durSec
                        ))
                        currentByteOffset += referencedSize
                    }
                }
                return segments
            }

            pos += boxSize
        }

        return []
    }

    // MARK: - 6. Generate Standard Apple HLS Master & Media Playlists (`.m3u8`)
    private func buildMasterPlaylistM3U8(
        variants: [(format: YTVideoStreamFormat, fileName: String)],
        audioFormat: YTVideoStreamFormat?,
        audioPlaylistFileName: String?
    ) -> String {
        var lines: [String] = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-INDEPENDENT-SEGMENTS"
        ]

        if let audioFile = audioPlaylistFileName {
            lines.append(#"#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Original",DEFAULT=YES,AUTOSELECT=YES,URI="\#(audioFile)""#)
        }

        let audioCodec = audioFormat?.extractedCodec ?? (audioPlaylistFileName != nil ? "mp4a.40.2" : nil)

        for (fmt, fileName) in variants {
            let bw = max(200_000, fmt.bitrate ?? 2_500_000)
            var streamInf = "#EXT-X-STREAM-INF:BANDWIDTH=\(bw)"
            if let vCodec = fmt.extractedCodec, !vCodec.isEmpty {
                let codecs = [vCodec, audioCodec].compactMap { $0 }.joined(separator: ",")
                streamInf += #",CODECS="\#(codecs)""#
            }
            if let w = fmt.width, let h = fmt.height {
                streamInf += ",RESOLUTION=\(w)x\(h)"
            }
            if let fps = fmt.fps, fps > 0 {
                streamInf += ",FRAME-RATE=\(fps)"
            }
            if let vr = fmt.videoRange, !vr.isEmpty {
                streamInf += ",VIDEO-RANGE=\(vr)"
            } else if fmt.isHDR {
                streamInf += ",VIDEO-RANGE=PQ"
            } else {
                streamInf += ",VIDEO-RANGE=SDR"
            }
            if audioPlaylistFileName != nil {
                streamInf += #",AUDIO="aud""#
            }
            lines.append(streamInf)
            lines.append(fileName)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func buildMediaPlaylistM3U8(
        videoId: String,
        format: YTVideoStreamFormat,
        segments: [SIDXSegment],
        port: UInt16
    ) -> (m3u8: String, segMap: [String: SegmentEntry]) {
        let maxDur = Int(ceil(segments.map(\.durationSeconds).max() ?? 6.0))
        let initEnd = format.initRangeEnd ?? format.indexRangeEnd ?? 4095
        let initRemoteURL = appendRangeQueryParam(to: format.url, start: 0, end: initEnd) ?? format.url
        let fmtUA = format.userAgent ?? userAgent

        var segMap: [String: SegmentEntry] = [:]
        let initKey = "\(videoId)_\(format.itag)_init.mp4"
        segMap[initKey] = SegmentEntry(
            url: initRemoteURL,
            userAgent: fmtUA,
            videoId: videoId,
            itag: format.itag,
            index: nil,
            isAudio: format.isAudioOnly
        )
        let localInitURL = "http://127.0.0.1:\(port)/seg/\(initKey)"

        var lines: [String] = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-TARGETDURATION:\(max(1, maxDur))",
            "#EXT-X-MEDIA-SEQUENCE:0",
            "#EXT-X-PLAYLIST-TYPE:VOD",
            #"#EXT-X-MAP:URI="\#(localInitURL)""#
        ]

        for (idx, seg) in segments.enumerated() {
            let segRemoteURL = appendRangeQueryParam(to: format.url, start: seg.byteStart, end: seg.byteEnd) ?? format.url
            let segKey = "\(videoId)_\(format.itag)_\(idx).mp4"
            segMap[segKey] = SegmentEntry(
                url: segRemoteURL,
                userAgent: fmtUA,
                videoId: videoId,
                itag: format.itag,
                index: idx,
                isAudio: format.isAudioOnly
            )
            lines.append(String(format: "#EXTINF:%.3f,", seg.durationSeconds))
            lines.append("http://127.0.0.1:\(port)/seg/\(segKey)")
        }

        lines.append("#EXT-X-ENDLIST")
        return (lines.joined(separator: "\n") + "\n", segMap)
    }

    private func appendRangeQueryParam(to url: URL, start: Int64, end: Int64) -> URL? {
        let baseStr = url.absoluteString
        let separator = baseStr.contains("?") ? "&" : "?"
        return URL(string: "\(baseStr)\(separator)range=\(start)-\(end)")
    }
}
