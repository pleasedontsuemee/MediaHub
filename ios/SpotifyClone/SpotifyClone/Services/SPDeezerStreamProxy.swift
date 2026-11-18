import Foundation
import Network
import CryptoKit
import CommonCrypto

// MARK: - On-Device OpenDeezer Blowfish-CBC Decryptor & Local Streaming HTTP Proxy
public final class SPDeezerStreamProxy {
    public static let shared = SPDeezerStreamProxy()

    private var listener: NWListener?
    private var port: UInt16 = 0
    private let queue = DispatchQueue(label: "com.skyrock.opendeezer.proxy", attributes: .concurrent)
    private var trackURLs: [String: URL] = [:]
    private var trackSizes: [String: Int64] = [:]
    private let lock = NSLock()

    private init() {}

    public func ensureStarted() async -> UInt16 {
        if port != 0, listener != nil { return port }
        return await withCheckedContinuation { cont in
            do {
                let params = NWParameters.tcp
                let l = try NWListener(using: params, on: .any)
                self.listener = l
                l.stateUpdateHandler = { [weak self] state in
                    if case .ready = state, let p = l.port?.rawValue {
                        self?.port = p
                        cont.resume(returning: p)
                    } else if case .failed = state {
                        cont.resume(returning: 0)
                    }
                }
                l.newConnectionHandler = { [weak self] conn in
                    self?.handleConnection(conn)
                }
                l.start(queue: queue)
            } catch {
                cont.resume(returning: 0)
            }
        }
    }

    public func register(trackId: String, encryptedURL: URL) async -> URL? {
        let p = await ensureStarted()
        guard p > 0 else { return nil }
        lock.lock()
        trackURLs[trackId] = encryptedURL
        lock.unlock()
        return URL(string: "http://127.0.0.1:\(p)/track/\(trackId).mp3")
    }

    public static func decryptTrackData(_ data: Data, trackId: String, startChunkIndex: Int = 0) -> Data {
        let key = deriveBlowfishKey(trackId: trackId)
        let iv: [UInt8] = [0, 1, 2, 3, 4, 5, 6, 7]
        var out = Data(capacity: data.count)
        let chunkSize = 2048
        var offset = 0
        var chunkIdx = startChunkIndex

        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let slice = data.subdata(in: offset..<end)
            if chunkIdx % 3 == 0 && slice.count == chunkSize {
                if let decrypted = blowfishCBCDecrypt(slice, key: key, iv: iv) {
                    out.append(decrypted)
                } else {
                    out.append(slice)
                }
            } else {
                out.append(slice)
            }
            offset = end
            chunkIdx += 1
        }
        return out
    }

    private static func deriveBlowfishKey(trackId: String) -> [UInt8] {
        let digest = Insecure.MD5.hash(data: Data(trackId.utf8))
        let hexBytes = Array(digest.map { String(format: "%02x", $0) }.joined().utf8)
        let secret = Array("g4el58wc0zvf9na1".utf8)
        var key = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 {
            key[i] = hexBytes[i] ^ hexBytes[i + 16] ^ secret[i]
        }
        return key
    }

    private static func blowfishCBCDecrypt(_ input: Data, key: [UInt8], iv: [UInt8]) -> Data? {
        var outLength: size_t = 0
        var outData = Data(count: input.count)
        let status = outData.withUnsafeMutableBytes { outPtr in
            input.withUnsafeBytes { inPtr in
                CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmBlowfish),
                    CCOptions(0), // No padding, CBC is default
                    key, key.count,
                    iv,
                    inPtr.baseAddress, input.count,
                    outPtr.baseAddress, input.count,
                    &outLength
                )
            }
        }
        guard status == kCCSuccess else { return nil }
        return outData.prefix(outLength)
    }

    // MARK: - Local HTTP Range Server for AVPlayer
    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            guard let self = self, let data = data, let reqStr = String(data: data, encoding: .utf8) else {
                conn.cancel()
                return
            }
            self.processHTTPRequest(reqStr, on: conn)
        }
    }

    private func processHTTPRequest(_ reqStr: String, on conn: NWConnection) {
        let lines = reqStr.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { conn.cancel(); return }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { conn.cancel(); return }
        let method = parts[0]
        let path = parts[1]

        // Parse /track/<trackId>.mp3
        let cleanId = path
            .replacingOccurrences(of: "/track/", with: "")
            .replacingOccurrences(of: ".mp3", with: "")

        lock.lock()
        let remoteURL = trackURLs[cleanId]
        let cachedSize = trackSizes[cleanId]
        lock.unlock()

        guard let cdnURL = remoteURL else {
            sendResponse(conn, status: "404 Not Found", headers: ["Content-Length": "0"], body: Data())
            return
        }

        // Parse Range header if present
        var rangeStart: Int64 = 0
        var rangeEnd: Int64? = nil
        for line in lines {
            if line.lowercased().hasPrefix("range: bytes=") {
                let val = line.dropFirst("range: bytes=".count).trimmingCharacters(in: .whitespaces)
                let bounds = val.components(separatedBy: "-")
                if let s = Int64(bounds[0]) { rangeStart = s }
                if bounds.count > 1, let e = Int64(bounds[1]) { rangeEnd = e }
            }
        }

        Task {
            do {
                let totalSize: Int64
                if let cs = cachedSize {
                    totalSize = cs
                } else {
                    var headReq = URLRequest(url: cdnURL)
                    headReq.httpMethod = "HEAD"
                    let (_, headResp) = try await URLSession.shared.data(for: headReq)
                    totalSize = (headResp as? HTTPURLResponse)?.expectedContentLength ?? 0
                    if totalSize > 0 {
                        self.lock.lock()
                        self.trackSizes[cleanId] = totalSize
                        self.lock.unlock()
                    }
                }

                if method == "HEAD" {
                    let hdrs: [String: String] = [
                        "Content-Type": "audio/mpeg",
                        "Accept-Ranges": "bytes",
                        "Content-Length": "\(max(0, totalSize))"
                    ]
                    self.sendResponse(conn, status: "200 OK", headers: hdrs, body: Data())
                    return
                }

                // Align fetch range to 2048-byte Blowfish stripe boundaries
                let alignedStart = (rangeStart / 2048) * 2048
                let effectiveEnd = rangeEnd ?? (totalSize > 0 ? totalSize - 1 : alignedStart + 524_287)
                let alignedEnd = totalSize > 0 ? min(totalSize - 1, ((effectiveEnd / 2048) + 1) * 2048 - 1) : effectiveEnd

                var fetchReq = URLRequest(url: cdnURL)
                fetchReq.setValue("bytes=\(alignedStart)-\(alignedEnd)", forHTTPHeaderField: "Range")
                let (encData, _) = try await URLSession.shared.data(for: fetchReq)

                let startChunk = Int(alignedStart / 2048)
                let decryptedAligned = Self.decryptTrackData(encData, trackId: cleanId, startChunkIndex: startChunk)

                let skipHead = Int(rangeStart - alignedStart)
                let desiredLen = Int(effectiveEnd - rangeStart + 1)
                let sliceEnd = min(decryptedAligned.count, skipHead + desiredLen)
                let body = skipHead < sliceEnd ? decryptedAligned.subdata(in: skipHead..<sliceEnd) : Data()

                let isRange = lines.contains { $0.lowercased().hasPrefix("range:") }
                var hdrs: [String: String] = [
                    "Content-Type": "audio/mpeg",
                    "Accept-Ranges": "bytes",
                    "Content-Length": "\(body.count)"
                ]
                if isRange && totalSize > 0 {
                    hdrs["Content-Range"] = "bytes \(rangeStart)-\(rangeStart + Int64(body.count) - 1)/\(totalSize)"
                    self.sendResponse(conn, status: "206 Partial Content", headers: hdrs, body: body)
                } else {
                    self.sendResponse(conn, status: "200 OK", headers: hdrs, body: body)
                }
            } catch {
                self.sendResponse(conn, status: "502 Bad Gateway", headers: ["Content-Length": "0"], body: Data())
            }
        }
    }

    private func sendResponse(_ conn: NWConnection, status: String, headers: [String: String], body: Data) {
        var head = "HTTP/1.1 \(status)\r\nConnection: close\r\n"
        for (k, v) in headers {
            head += "\(k): \(v)\r\n"
        }
        head += "\r\n"
        var payload = Data(head.utf8)
        payload.append(body)
        conn.send(content: payload, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
