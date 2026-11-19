// Swift (iOS 16+) — Native in-app BotGuard / WebPO Token provider (bgutil-compatible)
import Foundation
import WebKit

/// Generates YouTube Proof-of-Origin (PO) Tokens natively inside the app using a hidden
/// `WKWebView` to execute Google's BotGuard VM (`att/get` -> `vm.a` -> `Waa/GenerateIT` -> `WebPoMinter`),
/// with automatic cold-start fallback if BotGuard is unreachable.
public actor YTBotGuardPOTProvider {
    public static let shared = YTBotGuardPOTProvider()

    public struct POTBundle: Sendable {
        public let visitorData: String
        public let playerPoToken: String
        public let gvsPoToken: String
        public let isColdStartFallback: Bool
    }

    private let session: URLSession
    private var visitorData: String?
    private var minterReady = false
    private var minterExpiresAt: Date = .distantPast
    private var sessionPoToken: String?
    private var videoTokenCache: [String: (token: String, expiresAt: Date)] = [:]
    private var initTask: Task<Bool, Never>?

    private let webUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36(KHTML, like Gecko)"
    private let waaRequestKey = "O43z0dpjhgX20SCx4KAo"
    private let googApiKey = "AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw"

    public init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: cfg)
    }

    public func invalidate() {
        visitorData = nil
        minterReady = false
        minterExpiresAt = .distantPast
        sessionPoToken = nil
        videoTokenCache.removeAll()
    }

    /// Lightweight ~50ms visitorData fetch (cached per session) — no WKWebView or BotGuard needed.
    /// Required by VISIONOS and TV_SAMSUNG InnerTube clients to bypass bot/LOGIN_REQUIRED checks.
    public func fastVisitorData(forceRefresh: Bool = false) async -> String {
        if forceRefresh {
            visitorData = nil
        }
        return await ensureVisitorData()
    }

    public func tokens(for videoId: String, forceRefresh: Bool = false) async -> POTBundle {
        if forceRefresh {
            videoTokenCache.removeValue(forKey: videoId)
            if Date() >= minterExpiresAt {
                invalidate()
            }
        }

        let vd = await ensureVisitorData()

        if !forceRefresh,
           minterReady,
           Date() < minterExpiresAt,
           let cached = videoTokenCache[videoId],
           Date() < cached.expiresAt,
           let gvsPot = sessionPoToken {
            return POTBundle(
                visitorData: vd,
                playerPoToken: cached.token,
                gvsPoToken: gvsPot,
                isColdStartFallback: false
            )
        }

        let ready = await ensureMinter(visitorData: vd, forceRefresh: forceRefresh)
        let activeVD = (self.visitorData?.isEmpty == false ? self.visitorData! : vd)
        if ready {
            // yt-dlp WebPO spec: GVS binds to visitorData, Player binds to videoId
            let gvsPot = (sessionPoToken != nil && !forceRefresh) ? sessionPoToken : await mintToken(binding: activeVD)
            let playerPot = await mintToken(binding: videoId) ?? gvsPot
            if let gvsPot, let playerPot {
                self.sessionPoToken = gvsPot
                self.videoTokenCache[videoId] = (playerPot, Date().addingTimeInterval(3600))
                return POTBundle(
                    visitorData: activeVD,
                    playerPoToken: playerPot,
                    gvsPoToken: gvsPot,
                    isColdStartFallback: false
                )
            }
        }

        // Fallback: BgUtils-compatible cold-start token so playback is never blocked
        let coldGvs = Self.createColdStartToken(contentBinding: vd)
        let coldPlayer = Self.createColdStartToken(contentBinding: videoId)
        YTDebugLogger.shared.log(.stream, tag: "BotGuard", "Using cold-start PO token fallback for \(videoId)")
        return POTBundle(
            visitorData: vd,
            playerPoToken: coldPlayer,
            gvsPoToken: coldGvs,
            isColdStartFallback: true
        )
    }

    // MARK: - Visitor Data
    private func ensureVisitorData() async -> String {
        if let vd = visitorData, !vd.isEmpty {
            return vd
        }
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/visitor_id?prettyPrint=false") else {
            return ""
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(webUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": "2.20260708.00.00",
                    "hl": "fr",
                    "gl": "FR"
                ]
            ]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        if let (data, _) = try? await session.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let rc = json["responseContext"] as? [String: Any],
           let vd = rc["visitorData"] as? String, !vd.isEmpty {
            self.visitorData = vd
            return vd
        }
        return ""
    }

    // MARK: - BotGuard Minter Lifecycle
    private func ensureMinter(visitorData: String, forceRefresh: Bool) async -> Bool {
        if !forceRefresh && minterReady && Date() < minterExpiresAt {
            return true
        }
        if let existing = initTask {
            return await existing.value
        }

        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            return await self.performBotGuardHandshake(visitorData: visitorData)
        }
        initTask = task
        let result = await task.value
        initTask = nil
        return result
    }

    private func performBotGuardHandshake(visitorData: String) async -> Bool {
        do {
            // 1. Primary (bgutil-ytdlp-pot-provider 2026-08+): fetch homepage (ytcfg + window.ytAtN)
            //    so BotGuard sees window.yt.config_.EVENT_ID and a matching VISITOR_DATA.
            var challengeProgram: String?
            var challengeGlobalName: String?
            var challengeInterpreterURL: String?
            var challengeInlineJS: String?
            var ytcfgJSONString: String?

            if let hpURL = URL(string: "https://www.youtube.com") {
                var hpReq = URLRequest(url: hpURL)
                hpReq.httpMethod = "GET"
                hpReq.setValue("*/*", forHTTPHeaderField: "accept")
                hpReq.setValue("en-US,en;q=0.7", forHTTPHeaderField: "accept-language")
                hpReq.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36(KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")

                if let (hpData, hpResp) = try? await session.data(for: hpReq),
                   let hpHttp = hpResp as? HTTPURLResponse, (200..<300).contains(hpHttp.statusCode),
                   let html = String(data: hpData, encoding: .utf8) {
                    if let cfgMatch = Self.firstRegexCapture(#"ytcfg\.set\((\{.+?\})\);"#, in: html, options: [.dotMatchesLineSeparators]) {
                        ytcfgJSONString = cfgMatch
                    }
                    if let attLiteral = Self.firstRegexCapture(#"window\.ytAtN\(\s*(\{[\s\S]*?\})\s*\)"#, in: html, options: []),
                       let bg = try? await BotGuardWebRunner.shared.parseYtAtNAndInjectConfig(
                           ytcfgJSON: ytcfgJSONString,
                           ytAtNLiteral: attLiteral
                       ) {
                        challengeProgram = bg.program
                        challengeGlobalName = bg.globalName
                        challengeInterpreterURL = bg.interpreterURL
                        challengeInlineJS = bg.inlineJS
                        YTDebugLogger.shared.log(.stream, tag: "BotGuard", "Loaded homepage ytcfg + ytAtN challenge (global=\(bg.globalName))")
                    }
                }
            }

            // Fallback to /youtubei/v1/att/get if homepage extraction didn't yield a challenge
            if challengeProgram == nil || challengeGlobalName == nil {
                guard let attURL = URL(string: "https://www.youtube.com/youtubei/v1/att/get?prettyPrint=false") else {
                    return false
                }
                var attReq = URLRequest(url: attURL)
                attReq.httpMethod = "POST"
                attReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                attReq.setValue(webUserAgent, forHTTPHeaderField: "User-Agent")
                attReq.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
                attReq.httpBody = try JSONSerialization.data(withJSONObject: [
                    "context": [
                        "client": [
                            "clientName": "MWEB",
                            "clientVersion": "2.20261118.01.00",
                            "visitorData": self.visitorData ?? visitorData
                        ]
                    ],
                    "engagementType": "ENGAGEMENT_TYPE_UNBOUND"
                ])

                let (attData, attResp) = try await session.data(for: attReq)
                guard let attHttp = attResp as? HTTPURLResponse, (200..<300).contains(attHttp.statusCode),
                      let attJson = try JSONSerialization.jsonObject(with: attData) as? [String: Any],
                      let bg = attJson["bgChallenge"] as? [String: Any],
                      let program = bg["program"] as? String,
                      let globalName = bg["globalName"] as? String else {
                    YTDebugLogger.shared.log(.error, tag: "BotGuard", "att/get missing bgChallenge")
                    return false
                }
                challengeProgram = program
                challengeGlobalName = globalName
                if let wrapped = bg["interpreterJavascript"] as? [String: Any],
                   let inlineJS = wrapped["privateDoNotAccessOrElseSafeScriptWrappedValue"] as? String, !inlineJS.isEmpty {
                    challengeInlineJS = inlineJS
                } else if let wrappedUrl = bg["interpreterUrl"] as? [String: Any],
                          let rawUrl = wrappedUrl["privateDoNotAccessOrElseTrustedResourceUrlWrappedValue"] as? String, !rawUrl.isEmpty {
                    challengeInterpreterURL = rawUrl
                }
            }

            guard let program = challengeProgram, let globalName = challengeGlobalName else {
                return false
            }

            var interpreterJS = challengeInlineJS
            if interpreterJS == nil, var rawUrl = challengeInterpreterURL, !rawUrl.isEmpty {
                if rawUrl.hasPrefix("//") { rawUrl = "https:" + rawUrl }
                if let jsURL = URL(string: rawUrl) {
                    var jsReq = URLRequest(url: jsURL)
                    jsReq.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36(KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
                    let (jsData, _) = try await session.data(for: jsReq)
                    interpreterJS = String(data: jsData, encoding: .utf8)
                }
            }

            guard let vmScript = interpreterJS, !vmScript.isEmpty else {
                YTDebugLogger.shared.log(.error, tag: "BotGuard", "Failed to load BotGuard interpreter JS")
                return false
            }

            // 2. Execute BotGuard VM + snapshot in hidden WKWebView
            let bgResponse = try await BotGuardWebRunner.shared.runSnapshot(
                interpreterJS: vmScript,
                program: program,
                globalName: globalName
            )

            // 3. Exchange botguardResponse for integrityToken via Waa/GenerateIT
            let integrityJson = try await callGenerateIT(botguardResponse: bgResponse)
            guard let integrityToken = integrityJson.first as? String, !integrityToken.isEmpty else {
                YTDebugLogger.shared.log(.error, tag: "BotGuard", "GenerateIT returned empty integrityToken")
                return false
            }
            let ttlSecs = (integrityJson.count > 1 ? (integrityJson[1] as? NSNumber)?.doubleValue : nil) ?? 43200
            let refreshSecs = (integrityJson.count > 2 ? (integrityJson[2] as? NSNumber)?.doubleValue : nil) ?? (ttlSecs * 0.75)

            // 4. Initialize WebPoMinter inside WKWebView
            let minterOK = try await BotGuardWebRunner.shared.initMinter(integrityTokenBase64: integrityToken)
            guard minterOK else {
                YTDebugLogger.shared.log(.error, tag: "BotGuard", "WebPoMinter init failed")
                return false
            }

            self.minterReady = true
            let effectiveTTL = max(300, ttlSecs - refreshSecs)
            self.minterExpiresAt = Date().addingTimeInterval(effectiveTTL)
            YTDebugLogger.shared.log(.stream, tag: "BotGuard", "WebPoMinter ready (TTL ~\(Int(effectiveTTL))s)")
            return true
        } catch {
            YTDebugLogger.shared.log(.error, tag: "BotGuard", "Handshake error: \(error.localizedDescription)")
            return false
        }
    }

    private func callGenerateIT(botguardResponse: String) async throws -> [Any] {
        let payload: [Any] = [waaRequestKey, botguardResponse]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)

        if let rpcURL = URL(string: "https://jnn-pa.googleapis.com/$rpc/google.internal.waa.v1.Waa/GenerateIT") {
            var req = URLRequest(url: rpcURL)
            req.httpMethod = "POST"
            req.setValue("application/json+protobuf", forHTTPHeaderField: "Content-Type")
            req.setValue(googApiKey, forHTTPHeaderField: "x-goog-api-key")
            req.setValue("grpc-web-javascript/0.1", forHTTPHeaderField: "x-user-agent")
            req.setValue(webUserAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
            req.httpBody = payloadData

            if let (data, resp) = try? await session.data(for: req),
               let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                return arr
            }
        }

        // Fallback to YouTube GenerateIT proxy endpoint
        guard let ytURL = URL(string: "https://www.youtube.com/youtubei/v1/att/GenerateIT?prettyPrint=false") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: ytURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(webUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        req.httpBody = payloadData
        let (data, _) = try await session.data(for: req)
        return (try JSONSerialization.jsonObject(with: data) as? [Any]) ?? []
    }

    private func mintToken(binding: String) async -> String? {
        guard !binding.isEmpty else { return nil }
        return try? await BotGuardWebRunner.shared.mint(binding: binding)
    }

    // MARK: - Cold-Start Token Fallback (BgUtils WebPoMinter.createColdStartToken)
    public static func createColdStartToken(contentBinding: String, clientState: UInt8 = 1) -> String {
        let bindingBytes = Array(contentBinding.utf8)
        let ts = UInt32(Date().timeIntervalSince1970)
        let k0 = UInt8.random(in: 0...255)
        let k1 = UInt8.random(in: 0...255)

        let header: [UInt8] = [
            k0, k1, 0, clientState,
            UInt8((ts >> 24) & 0xFF),
            UInt8((ts >> 16) & 0xFF),
            UInt8((ts >> 8) & 0xFF),
            UInt8(ts & 0xFF)
        ]

        var packet = [UInt8](repeating: 0, count: 2 + header.count + bindingBytes.count)
        packet[0] = 34
        packet[1] = UInt8(truncatingIfNeeded: header.count + bindingBytes.count)
        packet.replaceSubrange(2..<(2 + header.count), with: header)
        packet.replaceSubrange((2 + header.count)..<packet.count, with: bindingBytes)

        for i in 2..<packet.count where (i - 2) >= 2 {
            packet[i] ^= packet[2 + ((i - 2) % 2)]
        }

        return Data(packet).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func firstRegexCapture(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}

// MARK: - Hidden WKWebView BotGuard VM Runner
@MainActor
private final class BotGuardWebRunner: NSObject, WKNavigationDelegate {
    static let shared = BotGuardWebRunner()

    private var webView: WKWebView?
    private var isLoaded = false
    private var loadContinuation: CheckedContinuation<Void, Never>?

    private func ensureWebView() async -> WKWebView {
        if let wv = webView, isLoaded {
            return wv
        }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36(KHTML, like Gecko)"
        wv.navigationDelegate = self
        self.webView = wv

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.loadContinuation = cont
            wv.loadHTMLString(
                "<!DOCTYPE html><html lang=\"en\"><head><title></title></head><body></body></html>",
                baseURL: URL(string: "https://www.youtube.com")
            )
        }
        isLoaded = true
        return wv
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    private func evalAsyncJS(_ script: String, arguments: [String: Any] = [:], in wv: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { cont in
            wv.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    cont.resume(returning: value)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func parseYtAtNAndInjectConfig(
        ytcfgJSON: String?,
        ytAtNLiteral: String
    ) async throws -> (program: String, globalName: String, interpreterURL: String?, inlineJS: String?)? {
        let wv = await ensureWebView()
        let script = """
        if (ytcfgStr) {
            try {
                window.yt = { config_: JSON.parse(ytcfgStr) };
            } catch (_) {}
        }
        const attObj = (0, eval)('(' + literal + ')');
        let rObj = attObj && attObj.R ? attObj.R : null;
        if (typeof rObj === 'string') {
            rObj = JSON.parse(rObj);
        }
        const bg = rObj && rObj.bgChallenge ? rObj.bgChallenge : null;
        if (!bg || !bg.program || !bg.globalName) return null;
        return {
            program: String(bg.program),
            globalName: String(bg.globalName),
            interpreterURL: bg.interpreterUrl && bg.interpreterUrl.privateDoNotAccessOrElseTrustedResourceUrlWrappedValue ? String(bg.interpreterUrl.privateDoNotAccessOrElseTrustedResourceUrlWrappedValue) : '',
            inlineJS: bg.interpreterJavascript && bg.interpreterJavascript.privateDoNotAccessOrElseSafeScriptWrappedValue ? String(bg.interpreterJavascript.privateDoNotAccessOrElseSafeScriptWrappedValue) : ''
        };
        """
        let res = try await evalAsyncJS(
            script,
            arguments: ["ytcfgStr": ytcfgJSON ?? "", "literal": ytAtNLiteral],
            in: wv
        )
        guard let dict = res as? [String: Any],
              let program = dict["program"] as? String, !program.isEmpty,
              let globalName = dict["globalName"] as? String, !globalName.isEmpty else {
            return nil
        }
        let interpURL = (dict["interpreterURL"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let inlineJS = (dict["inlineJS"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return (program, globalName, interpURL, inlineJS)
    }

    func runSnapshot(interpreterJS: String, program: String, globalName: String) async throws -> String {
        let wv = await ensureWebView()
        // Evaluate interpreter JS in page global scope
        _ = try await evalAsyncJS("(0, eval)(script);", arguments: ["script": interpreterJS], in: wv)

        let snapshotScript = """
        const vm = window[globalName];
        if (!vm || typeof vm.a !== 'function') {
            throw new Error('BotGuard VM unavailable: ' + globalName);
        }
        let asyncSnapshotFn = null;
        const vmReady = new Promise((resolve) => {
            const cb = (asyncSnap) => {
                asyncSnapshotFn = asyncSnap;
                resolve();
            };
            const loggers = [()=>{}, ()=>{}, ()=>{}, ()=>{}, ()=>{}];
            vm.a(program, cb, true, undefined, ()=>{}, [[], []], undefined, false, loggers);
        });
        await Promise.race([
            vmReady,
            new Promise((_, rej) => setTimeout(() => rej(new Error('BotGuard VM init timeout')), 4000))
        ]);
        if (typeof asyncSnapshotFn !== 'function') {
            throw new Error('asyncSnapshotFunction missing');
        }
        window.__bgWebPoSignalOutput = [];
        const bgResp = await new Promise((resolve, reject) => {
            const timer = setTimeout(() => reject(new Error('BotGuard snapshot timeout')), 4000);
            try {
                asyncSnapshotFn(
                    (res) => { clearTimeout(timer); resolve(res); },
                    [undefined, undefined, window.__bgWebPoSignalOutput, undefined]
                );
            } catch (e) {
                clearTimeout(timer);
                reject(e);
            }
        });
        return String(bgResp || '');
        """

        let result = try await evalAsyncJS(
            snapshotScript,
            arguments: ["globalName": globalName, "program": program],
            in: wv
        )
        guard let str = result as? String, !str.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return str
    }

    func initMinter(integrityTokenBase64: String) async throws -> Bool {
        let wv = await ensureWebView()
        let script = """
        const sig = window.__bgWebPoSignalOutput;
        if (!sig || typeof sig[0] !== 'function') return false;
        const b64 = token.replace(/-/g, '+').replace(/_/g, '/');
        const bin = atob(b64);
        const bytes = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
        const minter = await sig[0](bytes);
        if (typeof minter !== 'function') return false;
        window.__bgMintFn = minter;
        return true;
        """
        let res = try await evalAsyncJS(script, arguments: ["token": integrityTokenBase64], in: wv)
        return (res as? Bool) == true
    }

    func mint(binding: String) async throws -> String {
        let wv = await ensureWebView()
        let script = """
        if (typeof window.__bgMintFn !== 'function') {
            throw new Error('WebPoMinter not initialized');
        }
        const bytes = new TextEncoder().encode(binding);
        const out = await window.__bgMintFn(bytes);
        let bin = '';
        for (let i = 0; i < out.length; i++) bin += String.fromCharCode(out[i]);
        return btoa(bin).replace(/\\+/g, '-').replace(/\\//g, '_');
        """
        let res = try await evalAsyncJS(script, arguments: ["binding": binding], in: wv)
        guard let token = res as? String, !token.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return token
    }
}
