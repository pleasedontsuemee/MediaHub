// Swift (iOS 17+) — Embedded YouTube player.js `n` & `sig` challenge solver via yt-dlp-ejs + JavaScriptCore
import Foundation
import JavaScriptCore

/// Solves YouTube's `n` throttling/anti-bot parameter and `signatureCipher` (`s`)
/// using the bundled `yt-dlp-ejs` AST solver (`yt.solver.lib.min.js` + `yt.solver.core.min.js`)
/// inside a persistent `JSContext`.
public actor YTPlayerScriptSolver {
    public static let shared = YTPlayerScriptSolver()

    private let session: URLSession
    private var jsContext: JSContext?
    private var cachedPlayerId: String?
    private var cachedSTS: Int?
    private var cachedPreprocessedPlayer: String?
    private var cachedRawPlayerJS: String?
    private var cacheTimestamp: Date = .distantPast
    private let cacheTTL: TimeInterval = 21600 // 6 hours

    private let webUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15"

    public init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 25
        self.session = URLSession(configuration: cfg)
    }

    public func signatureTimestamp() async -> Int? {
        await ensurePlayerLoaded()
        return cachedSTS
    }

    public func solveChallenges(
        nChallenges: [String],
        sigChallenges: [String]
    ) async -> (nMap: [String: String], sigMap: [String: String]) {
        let uniqueN = Array(Set(nChallenges.filter { !$0.isEmpty }))
        let uniqueSig = Array(Set(sigChallenges.filter { !$0.isEmpty }))
        guard !uniqueN.isEmpty || !uniqueSig.isEmpty else {
            return ([:], [:])
        }

        await ensurePlayerLoaded()
        guard let ctx = ensureJSContext() else {
            return ([:], [:])
        }

        var requests: [[String: Any]] = []
        if !uniqueN.isEmpty {
            requests.append(["type": "n", "challenges": uniqueN])
        }
        if !uniqueSig.isEmpty {
            requests.append(["type": "sig", "challenges": uniqueSig])
        }

        var input: [String: Any] = ["requests": requests]
        if let prep = cachedPreprocessedPlayer, !prep.isEmpty {
            input["type"] = "preprocessed"
            input["preprocessed_player"] = prep
        } else if let rawJS = cachedRawPlayerJS, !rawJS.isEmpty {
            input["type"] = "player"
            input["player"] = rawJS
            input["output_preprocessed"] = true
        } else {
            return ([:], [:])
        }

        guard let jscFn = ctx.objectForKeyedSubscript("jsc"), !jscFn.isUndefined else {
            YTDebugLogger.shared.log(.error, tag: "EJS", "jsc function missing in JSContext")
            return ([:], [:])
        }

        guard let outVal = jscFn.call(withArguments: [input]),
              let outDict = outVal.toDictionary() as? [String: Any] else {
            YTDebugLogger.shared.log(.error, tag: "EJS", "jsc returned nil/invalid dictionary")
            return ([:], [:])
        }

        if let outType = outDict["type"] as? String, outType == "error" {
            let errMsg = outDict["error"] as? String ?? "unknown"
            YTDebugLogger.shared.log(.error, tag: "EJS", "jsc error: \(errMsg)")
            return ([:], [:])
        }

        if let prepOut = outDict["preprocessed_player"] as? String, !prepOut.isEmpty {
            self.cachedPreprocessedPlayer = prepOut
            self.cachedRawPlayerJS = nil // Free ~3MB raw JS string once preprocessed
            YTDebugLogger.shared.log(.stream, tag: "EJS", "Preprocessed player \(cachedPlayerId ?? "?") cached (\(prepOut.count) chars)")
        }

        var nMap: [String: String] = [:]
        var sigMap: [String: String] = [:]

        if let responses = outDict["responses"] as? [[String: Any]] {
            var reqIdx = 0
            if !uniqueN.isEmpty, reqIdx < responses.count {
                if let data = responses[reqIdx]["data"] as? [String: String] {
                    nMap = data
                } else if let err = responses[reqIdx]["error"] as? String {
                    YTDebugLogger.shared.log(.error, tag: "EJS", "n solve error: \(err)")
                }
                reqIdx += 1
            }
            if !uniqueSig.isEmpty, reqIdx < responses.count {
                if let data = responses[reqIdx]["data"] as? [String: String] {
                    sigMap = data
                } else if let err = responses[reqIdx]["error"] as? String {
                    YTDebugLogger.shared.log(.error, tag: "EJS", "sig solve error: \(err)")
                }
            }
        }

        return (nMap, sigMap)
    }

    // MARK: - Private Setup
    private func ensureJSContext() -> JSContext? {
        if let existing = jsContext {
            return existing
        }
        guard let libURL = YTResourceBundle.url(forResource: "yt.solver.lib.min", withExtension: "js"),
              let coreURL = YTResourceBundle.url(forResource: "yt.solver.core.min", withExtension: "js"),
              let libJS = try? String(contentsOf: libURL, encoding: .utf8),
              let coreJS = try? String(contentsOf: coreURL, encoding: .utf8) else {
            YTDebugLogger.shared.log(.error, tag: "EJS", "Missing yt.solver.*.min.js in resource bundle")
            return nil
        }

        let ctx = JSContext()
        ctx?.exceptionHandler = { _, exception in
            if let msg = exception?.toString() {
                YTDebugLogger.shared.log(.error, tag: "EJS", "JSContext exception: \(msg)")
            }
        }
        ctx?.evaluateScript(libJS)
        ctx?.evaluateScript("var meriyah = lib.meriyah; var astring = lib.astring;")
        ctx?.evaluateScript(coreJS)
        self.jsContext = ctx
        return ctx
    }

    private func ensurePlayerLoaded() async {
        if cachedSTS != nil,
           (cachedPreprocessedPlayer != nil || cachedRawPlayerJS != nil),
           Date().timeIntervalSince(cacheTimestamp) < cacheTTL {
            return
        }

        guard let iframeURL = URL(string: "https://www.youtube.com/iframe_api") else { return }
        var req = URLRequest(url: iframeURL)
        req.setValue(webUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: req),
              let body = String(data: data, encoding: .utf8) else { return }

        let pattern = #"player\\?\/([a-f0-9]+)\\?\/"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              let range = Range(match.range(at: 1), in: body) else { return }
        let playerId = String(body[range])

        if playerId == cachedPlayerId,
           cachedSTS != nil,
           (cachedPreprocessedPlayer != nil || cachedRawPlayerJS != nil) {
            self.cacheTimestamp = Date()
            return
        }

        guard let jsURL = URL(string: "https://www.youtube.com/s/player/\(playerId)/player_ias.vflset/en_US/base.js") else { return }
        var jsReq = URLRequest(url: jsURL)
        jsReq.setValue(webUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (jsData, _) = try? await session.data(for: jsReq),
              let js = String(data: jsData, encoding: .utf8),
              let stsRegex = try? NSRegularExpression(pattern: #"signatureTimestamp:(\d+)"#),
              let stsMatch = stsRegex.firstMatch(in: js, range: NSRange(js.startIndex..., in: js)),
              let stsRange = Range(stsMatch.range(at: 1), in: js),
              let sts = Int(js[stsRange]) else { return }

        self.cachedPlayerId = playerId
        self.cachedSTS = sts
        self.cachedRawPlayerJS = js
        self.cachedPreprocessedPlayer = nil
        self.cacheTimestamp = Date()
        YTDebugLogger.shared.log(.net, tag: "EJS", "Loaded player \(playerId) sts=\(sts) (\(js.count) bytes)")
    }
}
