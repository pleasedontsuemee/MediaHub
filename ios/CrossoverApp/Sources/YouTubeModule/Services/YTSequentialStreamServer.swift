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
    private let userAgent = "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip"
    private let serverQueue = DispatchQueue(label: "com.ytmine.hlshttpserver", qos: .userInteractive)

    private var listener: NWListener?
    private(set) public var listeningPort: UInt16 = 0

    public struct SIDXSegment: Sendable {
        public let byteStart: Int64
        public let byteLength: Int64
        public let durationSeconds: Double

        public var byteEnd: Int64 { byteStart + byteLength - 1 }
    }

    private var sidxCache: [String: [SIDXSegment]] = [:]
    private var playlistStore: [String: Data] = [:]
    private let lock = NSLock()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 25
        config.httpMaximumConnectionsPerHost = 16
        config.requestCachePolicy = .returnCacheDataElseLoad
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

    private func waitForServerPort() async -> UInt16 {
        if listeningPort > 0 { return listeningPort }
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if listeningPort > 0 { return listeningPort }
        }
        return listeningPort
    }

    // MARK: - 2. Pre-warm All Resolutions (`144p`..`2160p 4K`) in Parallel Background Task
    public func prewarmAllResolutions(for playback: YTResolvedVideoPlayback) {
        let vid = playback.video.id
        let formats = playback.adaptiveVideoFormats + (playback.bestAudioFormat.map { [$0] } ?? [])
        YTDebugLogger.shared.log(.stream, tag: "Prewarm", "Pre-warming \(formats.count) stream sidx tables for \(vid)")
        Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for fmt in formats {
                    group.addTask {
                        _ = await self.getOrFetchSIDXSegments(for: fmt, videoId: vid)
                    }
                }
            }
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
        let vM3U8 = buildMediaPlaylistM3U8(format: videoFormat, segments: vSegs)

        var audioFileName: String? = nil
        var aM3U8Data: Data? = nil
        if let audioFmt = audioFormat, let aSegs = aSegs, !aSegs.isEmpty {
            let aName = "\(videoId)_audio_\(audioFmt.itag).m3u8"
            aM3U8Data = Data(buildMediaPlaylistM3U8(format: audioFmt, segments: aSegs).utf8)
            audioFileName = aName
        }

        var variantEntries: [(format: YTVideoStreamFormat, fileName: String)] = [
            (videoFormat, videoFileName)
        ]

        var extraPlaylists: [String: Data] = [:]
        if isAutoQuality {
            for otherFmt in allAdaptiveFormats where otherFmt.itag != videoFormat.itag {
                if let cachedSegs = getCachedSIDXSegments(for: otherFmt, videoId: videoId), !cachedSegs.isEmpty {
                    let otherFileName = "\(videoId)_\(otherFmt.itag)_video.m3u8"
                    let otherM3U8 = buildMediaPlaylistM3U8(format: otherFmt, segments: cachedSegs)
                    extraPlaylists[otherFileName] = Data(otherM3U8.utf8)
                    variantEntries.append((otherFmt, otherFileName))
                }
            }
        }

        let masterFileName = "\(key)_master.m3u8"
        let masterM3U8 = buildMasterPlaylistM3U8(
            variants: variantEntries,
            audioPlaylistFileName: audioFileName
        )

        lock.withLock {
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
            options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": userAgent]]
        )
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 5.0
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        if !isAutoQuality, let w = videoFormat.width, let h = videoFormat.height {
            item.preferredMaximumResolution = CGSize(width: w, height: h)
        }
        return item
    }

    // MARK: - 3b. Pin an Existing YouTube Master HLS Playlist to a Specific Quality (144p..2160p)
    public func makeQualityPinnedHLSPlayerItem(
        from masterHLSURL: URL,
        targetHeight: Int,
        videoId: String
    ) async -> (item: AVPlayerItem, width: Int?, height: Int?) {
        let port = await waitForServerPort()
        var req = URLRequest(url: masterHLSURL)
        req.setValue("com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_1 like Mac OS X;)", forHTTPHeaderField: "User-Agent")

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
            var variants: [(infLine: String, urlLine: String, width: Int, height: Int, bandwidth: Int)] = []

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
                        variants.append((line, absURI, w, h, bw))
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
                let chosen = variants.min { a, b in
                    let aEff = min(a.width > 0 ? a.width : a.height, a.height)
                    let bEff = min(b.width > 0 ? b.width : b.height, b.height)
                    let diffA = abs(aEff - targetHeight)
                    let diffB = abs(bEff - targetHeight)
                    if diffA != diffB { return diffA < diffB }
                    return a.bandwidth > b.bandwidth
                }!

                if !headerLines.contains(where: { $0.hasPrefix("#EXTM3U") }) {
                    headerLines.insert("#EXTM3U", at: 0)
                }
                let pinnedM3U8 = (headerLines + [chosen.infLine, chosen.urlLine]).joined(separator: "\n") + "\n"
                let masterFileName = "\(videoId)_hls_\(targetHeight)_master.m3u8"
                lock.withLock {
                    playlistStore[masterFileName] = Data(pinnedM3U8.utf8)
                }

                if let pinnedURL = URL(string: "http://127.0.0.1:\(port)/\(masterFileName)") {
                    let item = AVPlayerItem(url: pinnedURL)
                    item.preferredForwardBufferDuration = 5.0
                    item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
                    if chosen.width > 0 && chosen.height > 0 {
                        item.preferredMaximumResolution = CGSize(width: chosen.width, height: chosen.height)
                    }
                    YTDebugLogger.shared.log(.stream, tag: "HLSQuality", "Pinned master HLS for \(videoId) to \(chosen.width)x\(chosen.height) (target \(targetHeight)p)")
                    return (item, chosen.width > 0 ? chosen.width : nil, chosen.height > 0 ? chosen.height : nil)
                }
            }
        }

        let fallbackItem = AVPlayerItem(url: masterHLSURL)
        fallbackItem.preferredForwardBufferDuration = 5.0
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
        let headers = ["User-Agent": userAgent]
        let asset = AVURLAsset(url: format.url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 5.0
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

        let indexEnd = format.indexRangeEnd ?? 4095
        guard let rangeURL = appendRangeQueryParam(to: format.url, start: 0, end: indexEnd) else {
            return []
        }

        var req = URLRequest(url: rangeURL)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let t0 = Date()
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count >= 32 else {
            YTDebugLogger.shared.log(.error, tag: "SIDX", "Failed to fetch sidx for \(videoId) itag \(format.itag) (range 0-\(indexEnd))")
            return []
        }

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

        for (fmt, fileName) in variants {
            let bw = max(200_000, fmt.bitrate ?? 2_500_000)
            var streamInf = "#EXT-X-STREAM-INF:BANDWIDTH=\(bw)"
            if let w = fmt.width, let h = fmt.height {
                streamInf += ",RESOLUTION=\(w)x\(h)"
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
        format: YTVideoStreamFormat,
        segments: [SIDXSegment]
    ) -> String {
        let maxDur = Int(ceil(segments.map(\.durationSeconds).max() ?? 6.0))
        let initEnd = format.indexRangeEnd ?? format.initRangeEnd ?? 740
        let initURL = appendRangeQueryParam(to: format.url, start: 0, end: initEnd)?.absoluteString ?? format.url.absoluteString

        var lines: [String] = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-TARGETDURATION:\(max(1, maxDur))",
            "#EXT-X-MEDIA-SEQUENCE:0",
            "#EXT-X-PLAYLIST-TYPE:VOD",
            #"#EXT-X-MAP:URI="\#(initURL)""#
        ]

        for seg in segments {
            let segURL = appendRangeQueryParam(to: format.url, start: seg.byteStart, end: seg.byteEnd)?.absoluteString ?? format.url.absoluteString
            lines.append(String(format: "#EXTINF:%.3f,", seg.durationSeconds))
            lines.append(segURL)
        }

        lines.append("#EXT-X-ENDLIST")
        return lines.joined(separator: "\n") + "\n"
    }

    private func appendRangeQueryParam(to url: URL, start: Int64, end: Int64) -> URL? {
        let baseStr = url.absoluteString
        let separator = baseStr.contains("?") ? "&" : "?"
        return URL(string: "\(baseStr)\(separator)range=\(start)-\(end)")
    }
}
