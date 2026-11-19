import Foundation
import AVFoundation

/// 100% Embedded In-App YouTube Extractor Engine (`yt-dlp` / `InnerTube` / `Piped` equivalent in native Swift).
/// Fetches live videos, Shorts (`shortsLockupViewModel`), recommendations (`lockupViewModel`),
/// real video comments (`commentEntityPayload` via continuation tokens), live subtitles (`TimedText JSON3`),
/// and direct H.264/AAC MP4 & HLS streams from YouTube.
public actor YTInnerTubeEngine {
    public static let shared = YTInnerTubeEngine()

    private let session: URLSession
    private var playbackCache: [String: (timestamp: Date, bundle: YTResolvedVideoPlayback)] = [:]
    private var searchCache: [String: (timestamp: Date, videos: [YTVideo])] = [:]
    private let cacheTTL: TimeInterval = 600 // 10 minutes

    private struct ClientProfile {
        let id: Int
        let name: String
        let version: String
        let userAgent: String
        let extraFields: [String: Any]
    }

    private let tvSamsungClient = ClientProfile(
        id: 7,
        name: "TVHTML5",
        version: "5.20260707",
        userAgent: "Mozilla/5.0 (SMART-TV; Linux; Tizen 2.4.0) AppleWebKit/538.1 (KHTML, like Gecko) Version/2.4.0 TV Safari/538.1",
        extraFields: [
            "deviceMake": "Samsung",
            "deviceModel": "UKS9800",
            "osName": "Tizen",
            "osVersion": "2.4.0"
        ]
    )

    private let visionOSClient = ClientProfile(
        id: 101,
        name: "VISIONOS",
        version: "1.02",
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
        extraFields: [
            "deviceMake": "Apple",
            "deviceModel": "RealityDevice17,1",
            "osName": "visionOS",
            "osVersion": "26.5.23O471"
        ]
    )

    private let androidVRClient = ClientProfile(
        id: 28,
        name: "ANDROID_VR",
        version: "1.60.19",
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
        extraFields: [
            "deviceMake": "Oculus",
            "deviceModel": "Quest 3",
            "osName": "Android",
            "osVersion": "12L",
            "androidSdkVersion": 32
        ]
    )

    private let androidClient = ClientProfile(
        id: 3,
        name: "ANDROID",
        version: "21.26.364",
        userAgent: "com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip",
        extraFields: [
            "osName": "Android",
            "osVersion": "11",
            "androidSdkVersion": 30
        ]
    )

    private let iosClient = ClientProfile(
        id: 5,
        name: "IOS",
        version: "21.26.4",
        userAgent: "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
        extraFields: [
            "deviceMake": "Apple",
            "deviceModel": "iPhone16,2",
            "osName": "iPhone",
            "osVersion": "18.3.2.22D82"
        ]
    )

    private let webClient = ClientProfile(
        id: 1,
        name: "WEB",
        version: "2.20260708.00.00",
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15",
        extraFields: [:]
    )

    private let mwebClient = ClientProfile(
        id: 2,
        name: "MWEB",
        version: "2.20260708.05.00",
        userAgent: "Mozilla/5.0 (iPad; CPU OS 16_7_10 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1,gzip(gfe)",
        extraFields: [
            "deviceMake": "Apple",
            "deviceModel": "iPad",
            "osName": "iOS",
            "osVersion": "16.7.10"
        ]
    )

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 30
        config.urlCache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
        self.session = URLSession(configuration: config)
    }

    // MARK: - 1. Autocomplete Search Suggestions
    public func fetchSearchSuggestions(query: String) async -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard var comps = URLComponents(string: "https://suggestqueries-clients6.youtube.com/complete/search") else {
            return []
        }
        comps.queryItems = [
            URLQueryItem(name: "client", value: "youtube"),
            URLQueryItem(name: "ds", value: "yt"),
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "hl", value: "fr"),
            URLQueryItem(name: "gl", value: "FR")
        ]
        guard let url = comps.url else { return [] }

        do {
            let (data, _) = try await session.data(from: url)
            if let raw = String(data: data, encoding: .utf8),
               let startIdx = raw.firstIndex(of: "("),
               let endIdx = raw.lastIndex(of: ")") {
                let jsonSlice = String(raw[raw.index(after: startIdx)..<endIdx])
                if let jsonData = jsonSlice.data(using: .utf8),
                   let arr = try JSONSerialization.jsonObject(with: jsonData) as? [Any],
                   arr.count > 1,
                   let items = arr[1] as? [[Any]] {
                    let suggestions = items.compactMap { $0.first as? String }
                    if !suggestions.isEmpty {
                        return suggestions
                    }
                }
            }
        } catch {}

        return []
    }

    // MARK: - 2. Live YouTube Search (/youtubei/v1/search)
    public func searchVideos(query: String, filters: YTSearchFilters = YTSearchFilters()) async -> [YTVideo] {
        let cacheKey = "\(query.lowercased())|\(filters.sortBy.rawValue)|\(filters.contentType.rawValue)|\(filters.uploadDate.rawValue)"
        if let cached = searchCache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.videos
        }

        var effectiveQuery = query
        if filters.contentType == .playlist {
            effectiveQuery += " playlist"
        } else if filters.contentType == .movie {
            effectiveQuery += " film complet"
        }

        let body: [String: Any] = [
            "context": makeContext(for: webClient),
            "query": effectiveQuery
        ]

        if let data = try? await postInnerTube(endpoint: "search", body: body, client: webClient),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var extracted = parseVideosFromInnerTubeTree(json)
            if !extracted.isEmpty {
                if filters.sortBy == .viewCount {
                    extracted.sort { parseViewCount($0.viewCountText) > parseViewCount($1.viewCountText) }
                }
                searchCache[cacheKey] = (Date(), extracted)
                return extracted
            }
        }

        return []
    }

    // MARK: - 3. Fetch Live Shorts Feed (`shortsLockupViewModel` + `#shorts` queries)
    public func fetchShortsFeed(seedKeywords: [String]) async -> [YTVideo] {
        let query: String
        if let firstKeyword = seedKeywords.first, !firstKeyword.isEmpty {
            query = "\(firstKeyword) #shorts"
        } else {
            let topics = ["#shorts viral France", "#shorts humour", "#shorts musique", "#shorts gaming", "#shorts sport"]
            query = topics.randomElement() ?? "#shorts trending"
        }

        let body: [String: Any] = [
            "context": makeContext(for: webClient),
            "query": query
        ]

        if let data = try? await postInnerTube(endpoint: "search", body: body, client: webClient),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let all = parseVideosFromInnerTubeTree(json)
            let shortsOnly = all.filter { $0.isShort }
            if !shortsOnly.isEmpty {
                return shortsOnly
            }
            // Mark returned short-duration videos as shorts
            return all.map { copy in
                return YTVideo(
                    id: copy.id,
                    title: copy.title,
                    channelId: copy.channelId,
                    channelTitle: copy.channelTitle,
                    channelAvatarURL: copy.channelAvatarURL,
                    channelSubscribers: copy.channelSubscribers,
                    isChannelVerified: copy.isChannelVerified,
                    thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(copy.id)/oar2.jpg") ?? copy.thumbnailURL,
                    durationText: copy.durationText,
                    durationSeconds: copy.durationSeconds,
                    viewCountText: copy.viewCountText,
                    publishedTimeText: copy.publishedTimeText,
                    descriptionText: copy.descriptionText,
                    hashtags: copy.hashtags,
                    likeCountText: copy.likeCountText,
                    commentCountText: copy.commentCountText,
                    isLive: false,
                    isUpcoming: false,
                    isShort: true,
                    watchProgress: 0
                )
            }
        }
        return []
    }

    // MARK: - 4. Fetch Personalized Home Feed Based on Watch Profile, Subscriptions & Category Chip
    public func fetchPersonalizedHomeFeed(
        chip: String,
        watchKeywords: [String],
        subscribedChannels: [String] = [],
        watchedVideoIds: Set<String> = []
    ) async -> (videos: [YTVideo], shorts: [YTVideo]) {
        var queries: [String] = []

        if chip == "New to you" {
            let discoveryPool = [
                "Découverte documentaire tech science France",
                "Nouveautés musique indépendante clip",
                "Reportage insolite histoire culture",
                "Créateurs émergents gaming humour France"
            ]
            queries = Array(discoveryPool.shuffled().prefix(2))
        } else if chip != "All" && !chip.isEmpty {
            let chipQueries: [String: [String]] = [
                "Music": ["Nouveautés musique clip officiel France", "Top hits musique 2025"],
                "Gaming": ["Gaming let's play France", "Jeux vidéo gameplay nouveautés"],
                "Live": ["Live stream direct France", "Musique lofi radio live"],
                "Podcasts": ["Podcast interview discussion France", "Débat société culture podcast"],
                "News": ["Actualités France journal info", "Tech économie actualité"],
                "Tech": ["High-tech test smartphone iPhone", "Programmation IA nouveautés tech"],
                "Sports": ["Sport résumé match highlights", "Football NBA UFC highlights"],
                "Comedy": ["Humour stand up sketch France", "Vidéo drôle divertissement"]
            ]
            if let mapped = chipQueries[chip] {
                queries = mapped
            } else {
                queries = ["\(chip) France", chip]
            }
            if let firstInterest = watchKeywords.first, !firstInterest.isEmpty {
                queries.append("\(chip) \(firstInterest)")
            }
        } else {
            // "All" — Blend recent watch/search interests, subscribed channels, and trending discovery
            if let primary = watchKeywords.first, !primary.isEmpty {
                queries.append(primary)
            }
            if watchKeywords.count > 1 {
                let secondaryPool = Array(watchKeywords.dropFirst().prefix(4))
                if let picked = secondaryPool.randomElement(), !picked.isEmpty {
                    queries.append(picked)
                }
            }
            if let sub = subscribedChannels.randomElement(), !sub.isEmpty {
                queries.append(sub)
            }
            if queries.count < 3 {
                let fallbacks = [
                    "Tendances France vidéos populaires",
                    "Musique clip officiel France 2025",
                    "Divertissement gaming tech France"
                ]
                for fb in fallbacks where queries.count < 3 {
                    queries.append(fb)
                }
            }
        }

        let uniqueQueries = Array(NSOrderedSet(array: queries).compactMap { $0 as? String }.prefix(3))

        async let shortsTask = fetchShortsFeed(seedKeywords: watchKeywords)
        var buckets: [[YTVideo]] = []
        await withTaskGroup(of: [YTVideo].self) { group in
            for q in uniqueQueries {
                group.addTask {
                    await self.searchVideos(query: q)
                }
            }
            for await res in group {
                buckets.append(res.filter { !$0.isShort })
            }
        }

        let shorts = await shortsTask

        // Interleave across query buckets so home feed is diverse and not dominated by 1 topic/channel
        var merged: [YTVideo] = []
        var seenIds = Set<String>()
        var channelCounts: [String: Int] = [:]
        let subSet = Set(subscribedChannels.map { $0.lowercased() })

        let maxLen = buckets.map(\.count).max() ?? 0
        for idx in 0..<maxLen {
            for bucket in buckets where idx < bucket.count {
                let vid = bucket[idx]
                guard !seenIds.contains(vid.id) else { continue }
                if chip == "New to you" && subSet.contains(vid.channelTitle.lowercased()) {
                    continue
                }
                if watchedVideoIds.contains(vid.id) {
                    continue
                }
                let chKey = vid.channelTitle.lowercased()
                let count = channelCounts[chKey, default: 0]
                if count >= 2 && merged.count < 18 {
                    continue
                }
                seenIds.insert(vid.id)
                channelCounts[chKey] = count + 1
                merged.append(vid)
            }
        }

        // If filtering watched videos left too few results, backfill from remaining non-short items
        if merged.count < 8 {
            for bucket in buckets {
                for vid in bucket where !seenIds.contains(vid.id) {
                    seenIds.insert(vid.id)
                    merged.append(vid)
                }
            }
        }

        return (Array(merged.prefix(30)), Array(shorts.prefix(12)))
    }

    // MARK: - 5. Fetch Channel Videos Dynamically
    public func fetchChannelVideos(channelTitle: String, channelId: String) async -> [YTVideo] {
        let cleanTitle = channelTitle.replacingOccurrences(of: "@", with: "")
        let results = await searchVideos(query: cleanTitle)
        return results
    }

    public func invalidatePlaybackCache(for videoId: String) {
        playbackCache.removeValue(forKey: videoId)
    }

    // MARK: - 6. Resolve Playable Video Stream FAST (Does NOT block on comments/related)
    public func resolveVideoPlayback(
        for video: YTVideo,
        userProfileKeywords: [String] = [],
        customPipedInstance: String? = nil,
        forceRefresh: Bool = false
    ) async -> YTResolvedVideoPlayback {
        if !forceRefresh, let cached = playbackCache[video.id], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.bundle
        }
        if forceRefresh {
            playbackCache.removeValue(forKey: video.id)
            YTSequentialStreamServer.shared.clearCache(for: video.id)
        }

        var hlsURL: URL?
        var muxedFormats: [YTVideoStreamFormat] = []
        var adaptiveVideo: [YTVideoStreamFormat] = []
        var adaptiveAudio: [YTVideoStreamFormat] = []
        var captions: [YTCaptionTrack] = []
        var updatedVideo = video

        let fastVD = await YTBotGuardPOTProvider.shared.fastVisitorData(forceRefresh: forceRefresh)
        let vdCtx: String? = fastVD.isEmpty ? nil : fastVD

        // yt-dlp 2026 fast & reliable client cascade (all with visitorData to avoid LOGIN_REQUIRED):
        // 1. VISIONOS (1.02, ID 101) -> NO JS, NO PO Token, 144p..4K/8K + Live HLS, HTTP 200 across 100% of video (~80ms!)
        // 2. TV_SAMSUNG (TVHTML5 5.20260707, ID 7) -> NO PO Token, handles "Made for kids" videos via EJS n/sig
        // 3. MWEB + BotGuard WebPO + EJS (fallback only)
        // 4. WEB + BotGuard WebPO + EJS (fallback only)
        // 5. ANDROID / 6. IOS (last resort)

        // Step 1: VISIONOS (fastest — zero BotGuard, zero JS preprocessing, full 144p..4K..8K + HLS)
        do {
            let visBody: [String: Any] = [
                "context": makeContext(for: visionOSClient, visitorData: vdCtx),
                "videoId": video.id,
                "contentCheckOk": true,
                "racyCheckOk": true
            ]
            if let visData = try? await postInnerTube(endpoint: "player", body: visBody, client: visionOSClient),
               let json = try? JSONSerialization.jsonObject(with: visData) as? [String: Any] {
                let status = (json["playabilityStatus"] as? [String: Any])?["status"] as? String ?? "unknown"
                let parsed = await parsePlayerResponse(json, baseVideo: updatedVideo, pot: nil, userAgent: visionOSClient.userAgent, clientLabel: "VISIONOS")
                updatedVideo = parsed.video
                if let h = parsed.hlsURL { hlsURL = h }
                muxedFormats.append(contentsOf: parsed.muxed)
                adaptiveVideo.append(contentsOf: parsed.adaptiveVideo)
                adaptiveAudio.append(contentsOf: parsed.adaptiveAudio)
                captions.append(contentsOf: parsed.captions)
                YTDebugLogger.shared.log(.net, tag: "InnerTube", "VISIONOS /player \(video.id) status=\(status) vd=\(vdCtx != nil) muxed=\(parsed.muxed.count) adaptiveV=\(parsed.adaptiveVideo.count) adaptiveA=\(parsed.adaptiveAudio.count) hls=\(parsed.hlsURL != nil)")
            }
        }

        // Step 2: TV_SAMSUNG (only if VISIONOS returned no playable streams — e.g. Made for Kids)
        if adaptiveVideo.isEmpty && hlsURL == nil {
            if let stsVal = await YTPlayerScriptSolver.shared.signatureTimestamp() {
                let tvBody: [String: Any] = [
                    "context": makeContext(for: tvSamsungClient, visitorData: vdCtx),
                    "videoId": video.id,
                    "playbackContext": ["contentPlaybackContext": ["signatureTimestamp": stsVal]],
                    "contentCheckOk": true,
                    "racyCheckOk": true
                ]
                if let tvData = try? await postInnerTube(endpoint: "player", body: tvBody, client: tvSamsungClient),
                   let json = try? JSONSerialization.jsonObject(with: tvData) as? [String: Any] {
                    let status = (json["playabilityStatus"] as? [String: Any])?["status"] as? String ?? "unknown"
                    let parsed = await parsePlayerResponse(json, baseVideo: updatedVideo, pot: nil, userAgent: tvSamsungClient.userAgent, clientLabel: "TV_SAMSUNG")
                    updatedVideo = parsed.video
                    if let h = parsed.hlsURL { hlsURL = h }
                    for m in parsed.muxed where !muxedFormats.contains(where: { $0.itag == m.itag }) { muxedFormats.append(m) }
                    adaptiveVideo.append(contentsOf: parsed.adaptiveVideo)
                    adaptiveAudio.append(contentsOf: parsed.adaptiveAudio)
                    if captions.isEmpty { captions.append(contentsOf: parsed.captions) }
                    YTDebugLogger.shared.log(.net, tag: "InnerTube", "TV_SAMSUNG /player \(video.id) status=\(status) vd=\(vdCtx != nil) muxed=\(parsed.muxed.count) adaptiveV=\(parsed.adaptiveVideo.count) adaptiveA=\(parsed.adaptiveAudio.count) hls=\(parsed.hlsURL != nil)")
                }
            }
        }

        // Step 3 & 4: MWEB / WEB with lazy BotGuard WebPO + EJS (only if VISIONOS and TV_SAMSUNG both failed)
        if adaptiveVideo.isEmpty && hlsURL == nil {
            async let potTask = YTBotGuardPOTProvider.shared.tokens(for: video.id, forceRefresh: forceRefresh)
            async let stsTask = YTPlayerScriptSolver.shared.signatureTimestamp()
            let (potBundle, sts) = await (potTask, stsTask)
            let potCtx: String? = potBundle.visitorData.isEmpty ? vdCtx : potBundle.visitorData

            if !potBundle.isColdStartFallback, let stsVal = sts {
                let mwebBody: [String: Any] = [
                    "context": makeContext(for: mwebClient, visitorData: potCtx),
                    "videoId": video.id,
                    "playbackContext": [
                        "contentPlaybackContext": [
                            "signatureTimestamp": stsVal
                        ]
                    ],
                    "serviceIntegrityDimensions": ["poToken": potBundle.playerPoToken],
                    "contentCheckOk": true,
                    "racyCheckOk": true
                ]
                if let mwebData = try? await postInnerTube(
                    endpoint: "player",
                    body: mwebBody,
                    client: mwebClient
                ),
                let json = try? JSONSerialization.jsonObject(with: mwebData) as? [String: Any] {
                    let status = (json["playabilityStatus"] as? [String: Any])?["status"] as? String ?? "unknown"
                    let parsed = await parsePlayerResponse(json, baseVideo: updatedVideo, pot: potBundle.gvsPoToken, userAgent: mwebClient.userAgent, clientLabel: "MWEB")
                    updatedVideo = parsed.video
                    if let h = parsed.hlsURL { hlsURL = h }
                    for m in parsed.muxed where !muxedFormats.contains(where: { $0.itag == m.itag }) { muxedFormats.append(m) }
                    adaptiveVideo.append(contentsOf: parsed.adaptiveVideo)
                    adaptiveAudio.append(contentsOf: parsed.adaptiveAudio)
                    if captions.isEmpty { captions.append(contentsOf: parsed.captions) }
                    YTDebugLogger.shared.log(.net, tag: "InnerTube", "MWEB /player \(video.id) status=\(status) pot=bg muxed=\(parsed.muxed.count) adaptiveV=\(parsed.adaptiveVideo.count) adaptiveA=\(parsed.adaptiveAudio.count) hls=\(parsed.hlsURL != nil)")
                }
            }

            if adaptiveVideo.isEmpty && hlsURL == nil && !potBundle.isColdStartFallback, let stsVal = sts {
                let webBody: [String: Any] = [
                    "context": makeContext(for: webClient, visitorData: potCtx),
                    "videoId": video.id,
                    "playbackContext": [
                        "contentPlaybackContext": [
                            "signatureTimestamp": stsVal
                        ]
                    ],
                    "serviceIntegrityDimensions": ["poToken": potBundle.playerPoToken],
                    "contentCheckOk": true,
                    "racyCheckOk": true
                ]
                if let webData = try? await postInnerTube(
                    endpoint: "player",
                    body: webBody,
                    client: webClient
                ),
                let json = try? JSONSerialization.jsonObject(with: webData) as? [String: Any] {
                    let status = (json["playabilityStatus"] as? [String: Any])?["status"] as? String ?? "unknown"
                    let parsed = await parsePlayerResponse(json, baseVideo: updatedVideo, pot: potBundle.gvsPoToken, userAgent: webClient.userAgent, clientLabel: "WEB")
                    updatedVideo = parsed.video
                    if let h = parsed.hlsURL { hlsURL = h }
                    for m in parsed.muxed where !muxedFormats.contains(where: { $0.itag == m.itag }) { muxedFormats.append(m) }
                    adaptiveVideo.append(contentsOf: parsed.adaptiveVideo)
                    adaptiveAudio.append(contentsOf: parsed.adaptiveAudio)
                    if captions.isEmpty { captions.append(contentsOf: parsed.captions) }
                    YTDebugLogger.shared.log(.net, tag: "InnerTube", "WEB /player \(video.id) status=\(status) pot=bg muxed=\(parsed.muxed.count) adaptiveV=\(parsed.adaptiveVideo.count) adaptiveA=\(parsed.adaptiveAudio.count) hls=\(parsed.hlsURL != nil)")
                } else {
                    YTDebugLogger.shared.log(.error, tag: "InnerTube", "WEB /player failed for \(video.id)")
                }
            }
        }

        // Step 5: Fallback to ANDROID if still no adaptive/HLS streams
        if adaptiveVideo.isEmpty && hlsURL == nil {
            let androidBody: [String: Any] = [
                "context": makeContext(for: androidClient, visitorData: vdCtx),
                "videoId": video.id,
                "contentCheckOk": true,
                "racyCheckOk": true
            ]
            if let androidData = try? await postInnerTube(
                endpoint: "player",
                body: androidBody,
                client: androidClient
            ),
            let json = try? JSONSerialization.jsonObject(with: androidData) as? [String: Any] {
                let status = (json["playabilityStatus"] as? [String: Any])?["status"] as? String ?? "unknown"
                let parsed = await parsePlayerResponse(json, baseVideo: updatedVideo, pot: nil, userAgent: androidClient.userAgent, clientLabel: "ANDROID")
                updatedVideo = parsed.video
                if let h = parsed.hlsURL { hlsURL = h }
                muxedFormats.append(contentsOf: parsed.muxed)
                adaptiveVideo.append(contentsOf: parsed.adaptiveVideo)
                adaptiveAudio.append(contentsOf: parsed.adaptiveAudio)
                if captions.isEmpty { captions.append(contentsOf: parsed.captions) }
                YTDebugLogger.shared.log(.net, tag: "InnerTube", "ANDROID /player \(video.id) status=\(status) muxed=\(parsed.muxed.count) adaptiveV=\(parsed.adaptiveVideo.count) adaptiveA=\(parsed.adaptiveAudio.count) hls=\(parsed.hlsURL != nil)")
            } else {
                YTDebugLogger.shared.log(.error, tag: "InnerTube", "ANDROID /player failed for \(video.id)")
            }
        }

        // Step 6: Query IOS InnerTube Player if still no adaptive/HLS streams
        if adaptiveVideo.isEmpty && hlsURL == nil {
            let iosBody: [String: Any] = [
                "context": makeContext(for: iosClient, visitorData: vdCtx),
                "videoId": video.id,
                "contentCheckOk": true,
                "racyCheckOk": true
            ]
            if let iosData = try? await postInnerTube(
                endpoint: "player",
                body: iosBody,
                client: iosClient
            ),
            let json = try? JSONSerialization.jsonObject(with: iosData) as? [String: Any] {
                let status = (json["playabilityStatus"] as? [String: Any])?["status"] as? String ?? "unknown"
                let parsed = await parsePlayerResponse(json, baseVideo: updatedVideo, pot: nil, userAgent: iosClient.userAgent, clientLabel: "IOS")
                updatedVideo = parsed.video
                if let h = parsed.hlsURL { hlsURL = h }
                for m in parsed.muxed where !muxedFormats.contains(where: { $0.itag == m.itag }) {
                    muxedFormats.append(m)
                }
                for v in parsed.adaptiveVideo where !adaptiveVideo.contains(where: { $0.itag == v.itag }) {
                    adaptiveVideo.append(v)
                }
                for a in parsed.adaptiveAudio where !adaptiveAudio.contains(where: { $0.itag == a.itag }) {
                    adaptiveAudio.append(a)
                }
                if captions.isEmpty {
                    captions = parsed.captions
                }
                YTDebugLogger.shared.log(.net, tag: "InnerTube", "IOS /player \(video.id) status=\(status) muxed=\(parsed.muxed.count) adaptiveV=\(parsed.adaptiveVideo.count) adaptiveA=\(parsed.adaptiveAudio.count)")
            } else {
                YTDebugLogger.shared.log(.error, tag: "InnerTube", "IOS /player failed for \(video.id)")
            }
        }

        let bundle = YTResolvedVideoPlayback(
            video: updatedVideo,
            hlsManifestURL: hlsURL,
            muxedFormats: muxedFormats,
            adaptiveVideoFormats: adaptiveVideo,
            adaptiveAudioFormats: adaptiveAudio,
            captionTracks: captions,
            relatedVideos: [],
            comments: []
        )
        playbackCache[video.id] = (Date(), bundle)
        YTSequentialStreamServer.shared.prewarmAllResolutions(for: bundle)
        return bundle
    }

    // MARK: - 6b. Fetch Real Related Videos & Real Comments in Parallel Background Task
    public func fetchRelatedAndComments(for video: YTVideo) async -> (related: [YTVideo], comments: [YTComment]) {
        var relatedVideos: [YTVideo] = []
        var realComments: [YTComment] = []

        async let topicMatchesTask = searchVideos(
            query: "\(video.channelTitle) \(Self.extractTopicKeywords(from: video.title))"
        )

        if let nextData = try? await postInnerTube(
            endpoint: "next",
            body: [
                "context": makeContext(for: webClient),
                "videoId": video.id
            ],
            client: webClient
        ),
        let nextJson = try? JSONSerialization.jsonObject(with: nextData) as? [String: Any] {
            let extractedNextVideos = parseVideosFromInnerTubeTree(nextJson).filter { $0.id != video.id }
            relatedVideos.append(contentsOf: extractedNextVideos)

            let continuationTokens = extractContinuationTokens(from: nextJson)
            for token in continuationTokens.prefix(3) {
                if let contData = try? await postInnerTube(
                    endpoint: "next",
                    body: [
                        "context": makeContext(for: webClient),
                        "continuation": token
                    ],
                    client: webClient
                ),
                let contJson = try? JSONSerialization.jsonObject(with: contData) as? [String: Any] {
                    let parsedComments = parseCommentsFromInnerTubeTree(contJson)
                    if !parsedComments.isEmpty {
                        realComments = parsedComments
                        break
                    }
                }
            }
        }

        let topicMatches = await topicMatchesTask
        for tm in topicMatches where tm.id != video.id && !tm.isShort {
            if !relatedVideos.contains(where: { $0.id == tm.id }) {
                relatedVideos.insert(tm, at: 0)
            }
        }

        return (relatedVideos, realComments)
    }

    // MARK: - 7. Fetch & Parse Real TimedText Captions (JSON3 + XML fallback)
    public func fetchCaptionCues(from track: YTCaptionTrack) async -> [YTCaptionCue] {
        var comps = URLComponents(url: track.baseUrl, resolvingAgainstBaseURL: false)
        var items = comps?.queryItems ?? []
        items.removeAll { $0.name == "fmt" }
        items.append(URLQueryItem(name: "fmt", value: "json3"))
        comps?.queryItems = items

        if let json3URL = comps?.url {
            var req = URLRequest(url: json3URL)
            req.setValue(androidClient.userAgent, forHTTPHeaderField: "User-Agent")
            if let (data, _) = try? await session.data(for: req),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let events = root["events"] as? [[String: Any]] {
                var cues: [YTCaptionCue] = []
                for ev in events {
                    guard let tStartMs = ev["tStartMs"] as? Double,
                          let segs = ev["segs"] as? [[String: Any]] else { continue }
                    let dDurationMs = (ev["dDurationMs"] as? Double) ?? 3000
                    let text = segs.compactMap { $0["utf8"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        cues.append(YTCaptionCue(
                            startTime: tStartMs / 1000.0,
                            duration: max(1.0, dDurationMs / 1000.0),
                            text: text.replacingOccurrences(of: "\n", with: " ")
                        ))
                    }
                }
                if !cues.isEmpty {
                    return cues
                }
            }
        }

        // Fallback: parse raw XML `<text start="1.23" dur="3.45">...</text>` if json3 wasn't returned
        if let (xmlData, _) = try? await session.data(from: track.baseUrl),
           let xmlStr = String(data: xmlData, encoding: .utf8) {
            var cues: [YTCaptionCue] = []
            let pattern = #"<text start="([0-9.]+)"(?:\s+dur="([0-9.]+)")?[^>]*>(.*?)</text>"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                let nsRange = NSRange(xmlStr.startIndex..<xmlStr.endIndex, in: xmlStr)
                let matches = regex.matches(in: xmlStr, range: nsRange)
                for m in matches {
                    if let r1 = Range(m.range(at: 1), in: xmlStr),
                       let r3 = Range(m.range(at: 3), in: xmlStr),
                       let start = Double(xmlStr[r1]) {
                        var dur = 3.0
                        if m.range(at: 2).location != NSNotFound,
                           let r2 = Range(m.range(at: 2), in: xmlStr),
                           let d = Double(xmlStr[r2]) {
                            dur = d
                        }
                        let rawText = String(xmlStr[r3])
                            .replacingOccurrences(of: "&amp;", with: "&")
                            .replacingOccurrences(of: "&#39;", with: "'")
                            .replacingOccurrences(of: "&quot;", with: "\"")
                            .replacingOccurrences(of: "\n", with: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !rawText.isEmpty {
                            cues.append(YTCaptionCue(startTime: start, duration: dur, text: rawText))
                        }
                    }
                }
            }
            if !cues.isEmpty {
                return cues
            }
        }

        return []
    }

    // MARK: - 8. Make Playable AVPlayerItem(s) for Any Selected Resolution (144p -> 4K 2160p + Ultrawide)
    // Uses YTSequentialStreamServer to stream 5-second sequential fMP4 segments via HLS (`ytstream://`)
    // so playback starts in <0.4s without downloading the whole video file!
    public func makeAVPlayerItems(
        for playback: YTResolvedVideoPlayback,
        preferredQuality: String = "Auto (recommended)"
    ) async -> (videoItem: AVPlayerItem, separateAudioItem: AVPlayerItem?, activeFormat: YTVideoStreamFormat?) {
        if let localURL = YTOfflineDownloadManager.localFileURL(forVideoId: playback.video.id) {
            return (AVPlayerItem(url: localURL), nil, nil)
        }

        // 0. Live streams MUST use YouTube's native HLS manifest (no static sidx table)
        if playback.video.isLive, let hls = playback.hlsManifestURL {
            let asset = AVURLAsset(
                url: hls,
                options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": visionOSClient.userAgent]]
            )
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 30.0
            return (item, nil, nil)
        }

        // 1. If a specific resolution is chosen (e.g. "4320p (8K)", "2160p (4K)", "1440p (QHD)", "1080p", "720p", "480p", "360p", "240p", "144p")
        if preferredQuality != "Auto (recommended)" && !preferredQuality.isEmpty {
            if let chosenFormat = playback.matchingVideoFormat(for: preferredQuality) {
                if chosenFormat.isMuxed {
                    let vItem = YTSequentialStreamServer.shared.makeFastProgressivePlayerItem(format: chosenFormat)
                    return (vItem, nil, chosenFormat)
                }
                // Build a 5-second sequential HLS stream with 50s RAM preloading combining chosen video (144p..4K..8K) + AAC audio!
                if let hlsItem = await YTSequentialStreamServer.shared.makeSequentialHLSPlayerItem(
                    videoFormat: chosenFormat,
                    audioFormat: playback.bestAudioFormat,
                    videoId: playback.video.id
                ) {
                    return (hlsItem, nil, chosenFormat)
                }
                // Fallback if sidx wasn't present: if master HLS exists, pin its variant to the chosen height first
                if let hls = playback.hlsManifestURL,
                   let targetH = YTResolvedVideoPlayback.targetHeight(for: preferredQuality) {
                    let pinned = await YTSequentialStreamServer.shared.makeQualityPinnedHLSPlayerItem(
                        from: hls,
                        targetHeight: targetH,
                        videoId: playback.video.id
                    )
                    return (pinned.item, nil, chosenFormat)
                }
                // Otherwise pair video item + separate audio item
                let vItem = YTSequentialStreamServer.shared.makeFastProgressivePlayerItem(format: chosenFormat)
                if let audioFmt = playback.bestAudioFormat {
                    let aItem = YTSequentialStreamServer.shared.makeFastProgressivePlayerItem(format: audioFmt)
                    return (vItem, aItem, chosenFormat)
                }
                return (vItem, nil, chosenFormat)
            }

            // If adaptiveVideoFormats was empty (e.g. client returned only hlsManifestURL), pin the HLS master playlist to the target height!
            if let hls = playback.hlsManifestURL,
               let targetH = YTResolvedVideoPlayback.targetHeight(for: preferredQuality) {
                let pinned = await YTSequentialStreamServer.shared.makeQualityPinnedHLSPlayerItem(
                    from: hls,
                    targetHeight: targetH,
                    videoId: playback.video.id
                )
                let synthFmt = YTVideoStreamFormat(
                    itag: 0,
                    url: hls,
                    mimeType: "application/x-mpegURL",
                    qualityLabel: preferredQuality,
                    width: pinned.width,
                    height: pinned.height,
                    bitrate: nil,
                    isAudioOnly: false,
                    isMuxed: false
                )
                return (pinned.item, nil, synthFmt)
            }
        }

        // 2. For Auto VOD: prefer our RAM-buffered YTSequentialStreamServer starting directly at crisp 1080p/720p H.264
        //    (never drops to blurry 144p at start, and preloads 50s ahead in RAM for zero stutter!)
        let preferredAutoHD = playback.adaptiveVideoFormats
            .filter { ($0.height ?? 0) >= 720 && ($0.height ?? 0) <= 1080 && $0.mimeType.contains("avc1") }
            .sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        if let hdFormat = preferredAutoHD.first
            ?? playback.adaptiveVideoFormats.first(where: { ($0.height ?? 0) >= 720 && ($0.height ?? 0) <= 1080 })
            ?? playback.adaptiveVideoFormats.first(where: { $0.mimeType.contains("avc1") })
            ?? playback.adaptiveVideoFormats.first {
            // Keep Auto variants strictly HD (>=720p H.264) so AVPlayer never starts in blurry 144p
            let crispAutoPool = preferredAutoHD.isEmpty ? [hdFormat] : preferredAutoHD
            if let hlsItem = await YTSequentialStreamServer.shared.makeSequentialHLSPlayerItem(
                videoFormat: hdFormat,
                audioFormat: playback.bestAudioFormat,
                videoId: playback.video.id,
                allAdaptiveFormats: crispAutoPool,
                isAutoQuality: true
            ) {
                return (hlsItem, nil, hdFormat)
            }
        }

        // Fallback to native HLS if sidx parsing wasn't available
        if let hls = playback.hlsManifestURL {
            let asset = AVURLAsset(
                url: hls,
                options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": visionOSClient.userAgent]]
            )
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 45.0
            return (item, nil, nil)
        }

        if let muxed = playback.muxedFormats.first {
            let item = YTSequentialStreamServer.shared.makeFastProgressivePlayerItem(format: muxed)
            return (item, nil, muxed)
        }

        if let bundledURL = YTResourceBundle.url(forResource: "90s-video", withExtension: "mp4") {
            return (AVPlayerItem(url: bundledURL), nil, nil)
        }

        return (AVPlayerItem(url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!), nil, nil)
    }

    // MARK: - Private InnerTube Parsers
    private func makeContext(for client: ClientProfile, visitorData: String? = nil) -> [String: Any] {
        var clientDict: [String: Any] = [
            "clientName": client.name,
            "clientVersion": client.version,
            "hl": "fr",
            "gl": "FR"
        ]
        if let vd = visitorData, !vd.isEmpty {
            clientDict["visitorData"] = vd
        }
        for (k, v) in client.extraFields {
            clientDict[k] = v
        }
        return ["client": clientDict]
    }

    /// Updates or appends query parameters without decoding/corrupting existing percent-encoded YouTube params (`sparams`, `mime`, etc.).
    private func safelyUpdateURL(_ url: URL, setParams: [(name: String, value: String)]) -> URL {
        guard !setParams.isEmpty else { return url }
        var raw = url.absoluteString
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+%")

        for (name, value) in setParams {
            let encodedVal = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            let pattern = #"([?&])"# + NSRegularExpression.escapedPattern(for: name) + #"=[^&]*"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
               let fullRange = Range(match.range, in: raw),
               let prefixRange = Range(match.range(at: 1), in: raw) {
                let prefix = String(raw[prefixRange])
                raw.replaceSubrange(fullRange, with: "\(prefix)\(name)=\(encodedVal)")
            } else {
                let sep = raw.contains("?") ? "&" : "?"
                raw += "\(sep)\(name)=\(encodedVal)"
            }
        }
        return URL(string: raw) ?? url
    }

    private func appendPOT(_ url: URL, pot: String?) -> URL {
        guard let pot, !pot.isEmpty else { return url }
        if url.absoluteString.contains("&pot=") || url.absoluteString.contains("?pot=") {
            return url
        }
        return safelyUpdateURL(url, setParams: [("pot", pot)])
    }

    private func postInnerTube(endpoint: String, body: [String: Any], client: ClientProfile) async throws -> Data {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("\(client.id)", forHTTPHeaderField: "X-YouTube-Client-Name")
        req.setValue(client.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        if let ctx = body["context"] as? [String: Any],
           let cl = ctx["client"] as? [String: Any],
           let vd = cl["visitorData"] as? String, !vd.isEmpty {
            req.setValue(vd, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func parsePlayerResponse(
        _ json: [String: Any],
        baseVideo: YTVideo,
        pot: String? = nil,
        userAgent: String? = nil,
        clientLabel: String = "?"
    ) async -> (
        video: YTVideo,
        hlsURL: URL?,
        muxed: [YTVideoStreamFormat],
        adaptiveVideo: [YTVideoStreamFormat],
        adaptiveAudio: [YTVideoStreamFormat],
        captions: [YTCaptionTrack]
    ) {
        var updatedTitle = baseVideo.title
        var updatedChannelTitle = baseVideo.channelTitle
        var updatedChannelId = baseVideo.channelId
        var updatedDesc = baseVideo.descriptionText
        var updatedDurationSec = baseVideo.durationSeconds
        var updatedDurationText = baseVideo.durationText
        var updatedViews = baseVideo.viewCountText
        var updatedThumb = baseVideo.thumbnailURL
        var isLive = baseVideo.isLive

        if let vd = json["videoDetails"] as? [String: Any] {
            if let t = vd["title"] as? String, !t.isEmpty { updatedTitle = t }
            if let a = vd["author"] as? String, !a.isEmpty { updatedChannelTitle = a }
            if let cid = vd["channelId"] as? String, !cid.isEmpty { updatedChannelId = cid }
            if let desc = vd["shortDescription"] as? String, !desc.isEmpty { updatedDesc = desc }
            if let live = vd["isLiveContent"] as? Bool { isLive = live }
            if let lenStr = vd["lengthSeconds"] as? String, let sec = Double(lenStr), sec > 0 {
                updatedDurationSec = sec
                updatedDurationText = Self.formatDuration(seconds: Int(sec))
            }
            if let vcStr = vd["viewCount"] as? String, let vc = Int64(vcStr) {
                updatedViews = Self.formatCompactCount(vc) + (isLive ? " spectateurs" : " vues")
            }
            if let thumbContainer = vd["thumbnail"] as? [String: Any],
               let thumbs = thumbContainer["thumbnails"] as? [[String: Any]],
               let lastURL = thumbs.last?["url"] as? String {
                updatedThumb = URL(string: lastURL)
            }
        }

        var hlsURL: URL?
        var muxed: [YTVideoStreamFormat] = []
        var adaptiveVideo: [YTVideoStreamFormat] = []
        var adaptiveAudio: [YTVideoStreamFormat] = []

        if let sd = json["streamingData"] as? [String: Any] {
            let fmts = (sd["formats"] as? [[String: Any]]) ?? []
            let rawAfmts = (sd["adaptiveFormats"] as? [[String: Any]]) ?? []

            let rawWithUrl = rawAfmts.filter { ($0["url"] as? String)?.isEmpty == false }.count
            let rawWithCipher = rawAfmts.filter { $0["signatureCipher"] != nil || $0["cipher"] != nil }.count

            // Collect all unique `n` and `sig` challenges across formats and batch-solve via yt-dlp-ejs
            var nChallenges: [String] = []
            var sigChallenges: [String] = []
            for f in fmts + rawAfmts {
                if let extracted = extractRawURLAndCipher(from: f) {
                    if let nVal = URLComponents(url: extracted.url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "n" })?.value, !nVal.isEmpty {
                        nChallenges.append(nVal)
                    }
                    if let sVal = extracted.sig, !sVal.isEmpty {
                        sigChallenges.append(sVal)
                    }
                }
            }
            let solved: (nMap: [String: String], sigMap: [String: String])
            if !nChallenges.isEmpty || !sigChallenges.isEmpty {
                solved = await YTPlayerScriptSolver.shared.solveChallenges(
                    nChallenges: nChallenges,
                    sigChallenges: sigChallenges
                )
            } else {
                solved = ([:], [:])
            }
            YTDebugLogger.shared.log(.net, tag: "InnerTube", "[\(clientLabel)] rawAdaptive=\(rawAfmts.count) url=\(rawWithUrl) cipher=\(rawWithCipher) nReq=\(Set(nChallenges).count)/\(solved.nMap.count) sigReq=\(Set(sigChallenges).count)/\(solved.sigMap.count) potLen=\(pot?.count ?? 0)")

            if let hlsStr = sd["hlsManifestUrl"] as? String, let rawHls = URL(string: hlsStr) {
                hlsURL = appendPOT(rawHls, pot: pot)
            }
            for f in fmts {
                if let parsed = parseStreamFormat(f, isMuxed: true, pot: pot, userAgent: userAgent, nMap: solved.nMap, sigMap: solved.sigMap) {
                    muxed.append(parsed)
                }
            }
            // Sort adaptive formats so H.264 (`avc1`) comes BEFORE `av01` for <=1080p, while `av01` is kept for 1440p and 2160p (4K)
            let sortedAfmts = rawAfmts.sorted { a, b in
                let mA = (a["mimeType"] as? String) ?? ""
                let mB = (b["mimeType"] as? String) ?? ""
                let isAvcA = mA.contains("avc1") ? 0 : 1
                let isAvcB = mB.contains("avc1") ? 0 : 1
                return isAvcA < isAvcB
            }
            for f in sortedAfmts {
                if let parsed = parseStreamFormat(f, isMuxed: false, pot: pot, userAgent: userAgent, nMap: solved.nMap, sigMap: solved.sigMap) {
                    // Keep all MP4 streams: H.264 (`avc1` 144p..1080p), AV1 (`av01` 144p..2160p 4K on iPhone 15 Pro / 16 Pro Max hardware decoder), and AAC (`mp4a` audio)
                    if parsed.mimeType.contains("mp4") {
                        if parsed.isAudioOnly {
                            if !adaptiveAudio.contains(where: { $0.itag == parsed.itag && $0.audioTrackId == parsed.audioTrackId }) {
                                adaptiveAudio.append(parsed)
                            }
                        } else if parsed.mimeType.contains("avc1") || parsed.mimeType.contains("av01") || parsed.mimeType.contains("hvc1") {
                            if !adaptiveVideo.contains(where: { $0.qualityLabel == parsed.qualityLabel && $0.width == parsed.width && $0.height == parsed.height }) {
                                adaptiveVideo.append(parsed)
                            }
                        }
                    }
                }
            }
        }

        var captions: [YTCaptionTrack] = []
        if let capRoot = json["captions"] as? [String: Any],
           let renderer = capRoot["playerCaptionsTracklistRenderer"] as? [String: Any],
           let tracks = renderer["captionTracks"] as? [[String: Any]] {
            for tr in tracks {
                guard let baseUrlStr = tr["baseUrl"] as? String,
                      let baseUrl = URL(string: baseUrlStr),
                      let lang = tr["languageCode"] as? String else { continue }
                var trackName = lang
                if let nameObj = tr["name"] as? [String: Any] {
                    if let simple = nameObj["simpleText"] as? String {
                        trackName = simple
                    } else if let runs = nameObj["runs"] as? [[String: Any]],
                              let firstRun = runs.first?["text"] as? String {
                        trackName = firstRun
                    }
                }
                let isAuto = (tr["kind"] as? String) == "asr"
                captions.append(YTCaptionTrack(
                    languageCode: lang,
                    name: trackName,
                    baseUrl: baseUrl,
                    isAutoGenerated: isAuto
                ))
            }
        }

        let updatedVideo = YTVideo(
            id: baseVideo.id,
            title: updatedTitle,
            channelId: updatedChannelId,
            channelTitle: updatedChannelTitle,
            channelAvatarURL: baseVideo.channelAvatarURL,
            channelSubscribers: baseVideo.channelSubscribers,
            isChannelVerified: baseVideo.isChannelVerified,
            thumbnailURL: updatedThumb ?? URL(string: "https://i.ytimg.com/vi/\(baseVideo.id)/hqdefault.jpg"),
            durationText: updatedDurationText,
            durationSeconds: updatedDurationSec,
            viewCountText: updatedViews,
            publishedTimeText: baseVideo.publishedTimeText,
            descriptionText: updatedDesc,
            hashtags: baseVideo.hashtags,
            likeCountText: baseVideo.likeCountText,
            commentCountText: baseVideo.commentCountText,
            isLive: isLive,
            isUpcoming: baseVideo.isUpcoming,
            isShort: baseVideo.isShort,
            watchProgress: baseVideo.watchProgress
        )

        return (updatedVideo, hlsURL, muxed, adaptiveVideo, adaptiveAudio, captions)
    }

    private func extractRawURLAndCipher(from dict: [String: Any]) -> (url: URL, sig: String?, sp: String)? {
        if let urlStr = dict["url"] as? String, let url = URL(string: urlStr) {
            return (url, nil, "sig")
        }
        let cipherStr = (dict["signatureCipher"] as? String) ?? (dict["cipher"] as? String)
        guard let cipherStr, !cipherStr.isEmpty else { return nil }
        var comps = URLComponents()
        comps.percentEncodedQuery = cipherStr
        let items = comps.queryItems ?? []
        guard let rawUrlStr = items.first(where: { $0.name == "url" })?.value,
              let url = URL(string: rawUrlStr) else { return nil }
        let sVal = items.first(where: { $0.name == "s" })?.value
        let spVal = items.first(where: { $0.name == "sp" })?.value ?? "sig"
        return (url, sVal, spVal)
    }

    private func parseStreamFormat(
        _ dict: [String: Any],
        isMuxed: Bool,
        pot: String? = nil,
        userAgent: String? = nil,
        nMap: [String: String] = [:],
        sigMap: [String: String] = [:]
    ) -> YTVideoStreamFormat? {
        guard let itag = dict["itag"] as? Int,
              let extracted = extractRawURLAndCipher(from: dict),
              let mimeType = dict["mimeType"] as? String else {
            return nil
        }

        var updates: [(name: String, value: String)] = []
        if let rawN = URLComponents(url: extracted.url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "n" })?.value,
           let solvedN = nMap[rawN], !solvedN.isEmpty, solvedN != rawN {
            updates.append(("n", solvedN))
        }
        if let rawSig = extracted.sig, !rawSig.isEmpty,
           let solvedSig = sigMap[rawSig], !solvedSig.isEmpty {
            updates.append((extracted.sp, solvedSig))
        }
        let solvedURL = updates.isEmpty ? extracted.url : safelyUpdateURL(extracted.url, setParams: updates)
        let url = appendPOT(solvedURL, pot: pot)
        let isAudio = mimeType.hasPrefix("audio/")
        let qualityLabel = (dict["qualityLabel"] as? String) ?? (isAudio ? "Audio AAC" : "360p")
        let width = dict["width"] as? Int
        let height = dict["height"] as? Int
        let bitrate = dict["bitrate"] as? Int
        let fps = dict["fps"] as? Int
        var videoRange: String? = nil
        if !isAudio {
            if let colorInfo = dict["colorInfo"] as? [String: Any],
               let transfer = colorInfo["transferCharacteristics"] as? String {
                if transfer.contains("SMPTEST2084") || transfer.contains("PQ") {
                    videoRange = "PQ"
                } else if transfer.contains("ARIB_STD_B67") || transfer.contains("HLG") {
                    videoRange = "HLG"
                } else {
                    videoRange = "SDR"
                }
            } else if qualityLabel.localizedCaseInsensitiveContains("HDR") {
                videoRange = "PQ"
            } else {
                videoRange = "SDR"
            }
        }
        var contentLen: Int64?
        if let clStr = dict["contentLength"] as? String {
            contentLen = Int64(clStr)
        }
        var initStart: Int64?
        var initEnd: Int64?
        if let initDict = dict["initRange"] as? [String: Any] {
            if let s = initDict["start"] as? String { initStart = Int64(s) }
            if let e = initDict["end"] as? String { initEnd = Int64(e) }
        }
        var idxStart: Int64?
        var idxEnd: Int64?
        if let idxDict = dict["indexRange"] as? [String: Any] {
            if let s = idxDict["start"] as? String { idxStart = Int64(s) }
            if let e = idxDict["end"] as? String { idxEnd = Int64(e) }
        }
        var trackId: String?
        var trackName: String?
        var isDefaultAudio = false
        if let audioTrack = dict["audioTrack"] as? [String: Any] {
            trackId = audioTrack["id"] as? String
            trackName = audioTrack["displayName"] as? String
            isDefaultAudio = (audioTrack["audioIsDefault"] as? Bool) ?? false
        }
        return YTVideoStreamFormat(
            itag: itag,
            url: url,
            mimeType: mimeType,
            qualityLabel: qualityLabel,
            width: width,
            height: height,
            bitrate: bitrate,
            isAudioOnly: isAudio,
            isMuxed: isMuxed,
            contentLength: contentLen,
            initRangeStart: initStart,
            initRangeEnd: initEnd,
            indexRangeStart: idxStart,
            indexRangeEnd: idxEnd,
            audioTrackId: trackId,
            audioTrackName: trackName,
            isAudioDefault: isDefaultAudio,
            userAgent: userAgent,
            fps: fps,
            videoRange: videoRange
        )
    }

    // Recursive parser supporting `videoRenderer`, `compactVideoRenderer`, `reelItemRenderer`, `shortsLockupViewModel`, and `lockupViewModel`
    private func parseVideosFromInnerTubeTree(_ node: Any) -> [YTVideo] {
        var results: [YTVideo] = []
        var seenIds = Set<String>()

        func walk(_ current: Any) {
            if let dict = current as? [String: Any] {
                if let vr = dict["videoRenderer"] as? [String: Any],
                   let video = parseVideoRenderer(vr),
                   !seenIds.contains(video.id) {
                    seenIds.insert(video.id)
                    results.append(video)
                } else if let cvr = dict["compactVideoRenderer"] as? [String: Any],
                          let video = parseVideoRenderer(cvr),
                          !seenIds.contains(video.id) {
                    seenIds.insert(video.id)
                    results.append(video)
                } else if let rir = dict["reelItemRenderer"] as? [String: Any],
                          let video = parseReelRenderer(rir),
                          !seenIds.contains(video.id) {
                    seenIds.insert(video.id)
                    results.append(video)
                } else if let slvm = dict["shortsLockupViewModel"] as? [String: Any],
                          let video = parseShortsLockupViewModel(slvm),
                          !seenIds.contains(video.id) {
                    seenIds.insert(video.id)
                    results.append(video)
                } else if let lvm = dict["lockupViewModel"] as? [String: Any],
                          let video = parseLockupViewModel(lvm),
                          !seenIds.contains(video.id) {
                    seenIds.insert(video.id)
                    results.append(video)
                } else {
                    for (_, val) in dict {
                        walk(val)
                    }
                }
            } else if let arr = current as? [Any] {
                for item in arr {
                    walk(item)
                }
            }
        }

        walk(node)
        return results
    }

    private func parseVideoRenderer(_ vr: [String: Any]) -> YTVideo? {
        guard let videoId = vr["videoId"] as? String, !videoId.isEmpty else { return nil }
        let title = extractText(from: vr["title"]) ?? "Vidéo YouTube"
        let channelTitle = extractText(from: vr["ownerText"]) ?? extractText(from: vr["longBylineText"]) ?? extractText(from: vr["shortBylineText"]) ?? "YouTube"
        let durationText = extractText(from: vr["lengthText"]) ?? "3:30"
        let isLive = (vr["lengthText"] == nil) && (extractText(from: vr["viewCountText"])?.contains("spectateur") == true || extractText(from: vr["viewCountText"])?.contains("watching") == true)
        let viewCountText = extractText(from: vr["shortViewCountText"]) ?? extractText(from: vr["viewCountText"]) ?? ""
        let publishedTimeText = extractText(from: vr["publishedTimeText"]) ?? ""

        var channelId = "UC_\(channelTitle.lowercased().replacingOccurrences(of: " ", with: "_"))"
        if let owner = vr["ownerText"] as? [String: Any],
           let runs = owner["runs"] as? [[String: Any]],
           let nav = runs.first?["navigationEndpoint"] as? [String: Any],
           let browse = nav["browseEndpoint"] as? [String: Any],
           let bid = browse["browseId"] as? String {
            channelId = bid
        }

        var thumbURL = URL(string: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg")
        if let thumbContainer = vr["thumbnail"] as? [String: Any],
           let thumbs = thumbContainer["thumbnails"] as? [[String: Any]],
           let uStr = thumbs.last?["url"] as? String,
           let u = URL(string: uStr) {
            thumbURL = u
        }

        var avatarURL: URL?
        if let ct = vr["channelThumbnailSupportedRenderers"] as? [String: Any],
           let ctr = ct["channelThumbnailWithLinkRenderer"] as? [String: Any],
           let t = ctr["thumbnail"] as? [String: Any],
           let thumbs = t["thumbnails"] as? [[String: Any]],
           let uStr = thumbs.first?["url"] as? String {
            avatarURL = URL(string: uStr)
        }

        let sec = Self.parseDurationSeconds(durationText)
        return YTVideo(
            id: videoId,
            title: title,
            channelId: channelId,
            channelTitle: channelTitle,
            channelAvatarURL: avatarURL,
            thumbnailURL: thumbURL,
            durationText: durationText,
            durationSeconds: sec,
            viewCountText: viewCountText,
            publishedTimeText: publishedTimeText,
            isLive: isLive,
            isShort: sec > 0 && sec <= 60 && title.lowercased().contains("#shorts")
        )
    }

    private func parseShortsLockupViewModel(_ slvm: [String: Any]) -> YTVideo? {
        var videoId: String?
        if let onTap = slvm["onTap"] as? [String: Any],
           let cmd = onTap["innertubeCommand"] as? [String: Any],
           let reel = cmd["reelWatchEndpoint"] as? [String: Any],
           let vid = reel["videoId"] as? String {
            videoId = vid
        } else if let entityId = slvm["entityId"] as? String,
                  entityId.hasPrefix("shorts-shelf-item-") {
            videoId = String(entityId.dropFirst("shorts-shelf-item-".count))
        }
        guard let vid = videoId, !vid.isEmpty else { return nil }

        var title = "YouTube Short"
        var views = "100 k vues"
        if let overlayMeta = slvm["overlayMetadata"] as? [String: Any] {
            if let pt = overlayMeta["primaryText"] as? [String: Any],
               let c = pt["content"] as? String {
                title = c
            }
            if let st = overlayMeta["secondaryText"] as? [String: Any],
               let c = st["content"] as? String {
                views = c
            }
        }

        var thumbURL = URL(string: "https://i.ytimg.com/vi/\(vid)/oar2.jpg")
        if let tvmOuter = slvm["thumbnailViewModel"] as? [String: Any],
           let tvm = tvmOuter["thumbnailViewModel"] as? [String: Any],
           let img = tvm["image"] as? [String: Any],
           let sources = img["sources"] as? [[String: Any]],
           let uStr = sources.first?["url"] as? String,
           let u = URL(string: uStr) {
            thumbURL = u
        }

        return YTVideo(
            id: vid,
            title: title,
            channelId: "UC_shorts_\(vid)",
            channelTitle: "@shorts",
            thumbnailURL: thumbURL,
            durationText: "0:45",
            durationSeconds: 45,
            viewCountText: views,
            publishedTimeText: "",
            isShort: true
        )
    }

    private func parseLockupViewModel(_ lvm: [String: Any]) -> YTVideo? {
        var videoId: String?
        if let rc = lvm["rendererContext"] as? [String: Any],
           let cc = rc["commandContext"] as? [String: Any],
           let onTap = cc["onTap"] as? [String: Any],
           let cmd = onTap["innertubeCommand"] as? [String: Any],
           let we = cmd["watchEndpoint"] as? [String: Any],
           let vid = we["videoId"] as? String {
            videoId = vid
        } else if let cid = lvm["contentId"] as? String, cid.count == 11 {
            videoId = cid
        }
        guard let vid = videoId, !vid.isEmpty else { return nil }

        var title = "Vidéo YouTube"
        var channelTitle = "YouTube"
        var channelId = "UC_\(vid)"
        var avatarURL: URL?
        var viewsText = ""
        var publishedText = ""
        var durationText = "3:45"

        if let meta = lvm["metadata"] as? [String: Any],
           let lmvm = meta["lockupMetadataViewModel"] as? [String: Any] {
            if let tObj = lmvm["title"] as? [String: Any],
               let c = tObj["content"] as? String {
                title = c
            }
            if let imgObj = lmvm["image"] as? [String: Any],
               let davm = imgObj["decoratedAvatarViewModel"] as? [String: Any] {
                if let av = davm["avatar"] as? [String: Any],
                   let avm = av["avatarViewModel"] as? [String: Any],
                   let im = avm["image"] as? [String: Any],
                   let srcs = im["sources"] as? [[String: Any]],
                   let uStr = srcs.first?["url"] as? String {
                    avatarURL = URL(string: uStr)
                }
                if let rc = davm["rendererContext"] as? [String: Any],
                   let cc = rc["commandContext"] as? [String: Any],
                   let onTap = cc["onTap"] as? [String: Any],
                   let cmd = onTap["innertubeCommand"] as? [String: Any],
                   let be = cmd["browseEndpoint"] as? [String: Any],
                   let bid = be["browseId"] as? String {
                    channelId = bid
                }
            }
            if let cm = lmvm["metadata"] as? [String: Any],
               let cmvm = cm["contentMetadataViewModel"] as? [String: Any],
               let rows = cmvm["metadataRows"] as? [[String: Any]] {
                if let firstRow = rows.first,
                   let parts = firstRow["metadataParts"] as? [[String: Any]],
                   let txt = parts.first?["text"] as? [String: Any],
                   let c = txt["content"] as? String {
                    channelTitle = c
                }
                if rows.count > 1,
                   let secondRow = rows[1]["metadataParts"] as? [[String: Any]] {
                    if let firstPart = secondRow.first?["text"] as? [String: Any],
                       let c = firstPart["content"] as? String {
                        viewsText = c.contains("vue") ? c : "\(c) vues"
                    }
                    if secondRow.count > 1,
                       let secPart = secondRow[1]["text"] as? [String: Any],
                       let c = secPart["content"] as? String {
                        publishedText = c
                    }
                }
            }
        }

        var thumbURL = URL(string: "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg")
        if let ci = lvm["contentImage"] as? [String: Any],
           let tvm = ci["thumbnailViewModel"] as? [String: Any] {
            if let im = tvm["image"] as? [String: Any],
               let srcs = im["sources"] as? [[String: Any]],
               let uStr = srcs.last?["url"] as? String,
               let u = URL(string: uStr) {
                thumbURL = u
            }
            if let overlays = tvm["overlays"] as? [[String: Any]] {
                for ov in overlays {
                    if let tbovm = ov["thumbnailBottomOverlayViewModel"] as? [String: Any],
                       let badges = tbovm["badges"] as? [[String: Any]],
                       let tbvm = badges.first?["thumbnailBadgeViewModel"] as? [String: Any],
                       let dText = tbvm["text"] as? String {
                        durationText = dText
                    }
                }
            }
        }

        return YTVideo(
            id: vid,
            title: title,
            channelId: channelId,
            channelTitle: channelTitle,
            channelAvatarURL: avatarURL,
            thumbnailURL: thumbURL,
            durationText: durationText,
            durationSeconds: Self.parseDurationSeconds(durationText),
            viewCountText: viewsText,
            publishedTimeText: publishedText
        )
    }

    private func parseReelRenderer(_ rir: [String: Any]) -> YTVideo? {
        guard let videoId = rir["videoId"] as? String, !videoId.isEmpty else { return nil }
        let title = extractText(from: rir["headline"]) ?? "YouTube Short"
        let views = extractText(from: rir["viewCountText"]) ?? "100 k vues"
        let thumbURL = URL(string: "https://i.ytimg.com/vi/\(videoId)/oar2.jpg")
        return YTVideo(
            id: videoId,
            title: title,
            channelId: "UC_shorts",
            channelTitle: "@shorts",
            thumbnailURL: thumbURL,
            durationText: "0:45",
            durationSeconds: 45,
            viewCountText: views,
            publishedTimeText: "",
            isShort: true
        )
    }

    // Extract continuation tokens for comments in `/youtubei/v1/next`
    private func extractContinuationTokens(from node: Any) -> [String] {
        var tokens: [String] = []
        func walk(_ current: Any) {
            if let dict = current as? [String: Any] {
                if let cc = dict["continuationCommand"] as? [String: Any],
                   let tok = cc["token"] as? String, !tok.isEmpty {
                    tokens.append(tok)
                }
                for (_, v) in dict {
                    walk(v)
                }
            } else if let arr = current as? [Any] {
                for item in arr {
                    walk(item)
                }
            }
        }
        walk(node)
        return tokens
    }

    // Parse real `commentEntityPayload` and `commentRenderer` from `/youtubei/v1/next` continuation
    private func parseCommentsFromInnerTubeTree(_ node: Any) -> [YTComment] {
        var comments: [YTComment] = []
        var seenIds = Set<String>()

        func walk(_ current: Any) {
            if let dict = current as? [String: Any] {
                if let cep = dict["commentEntityPayload"] as? [String: Any],
                   let props = cep["properties"] as? [String: Any],
                   let cid = props["commentId"] as? String,
                   !seenIds.contains(cid) {
                    seenIds.insert(cid)
                    let contentDict = props["content"] as? [String: Any]
                    let text = (contentDict?["content"] as? String) ?? ""
                    let published = (props["publishedTime"] as? String) ?? ""

                    let authorDict = cep["author"] as? [String: Any]
                    let handle = (authorDict?["displayName"] as? String) ?? "@user"
                    let avatarStr = (authorDict?["avatarThumbnailUrl"] as? String)
                    let isVerified = (authorDict?["isVerified"] as? Bool) ?? false

                    let toolbar = cep["toolbar"] as? [String: Any]
                    let likes = (toolbar?["likeCountNotliked"] as? String) ?? "0"
                    let repliesStr = (toolbar?["replyCount"] as? String) ?? "0"
                    let replyCount = Int(repliesStr.filter { $0.isNumber }) ?? 0
                    let isHearted = (toolbar?["heartActiveTooltip"] as? String) != nil

                    if !text.isEmpty {
                        comments.append(YTComment(
                            id: cid,
                            authorName: handle.replacingOccurrences(of: "@", with: ""),
                            authorHandle: handle,
                            authorAvatarURL: avatarStr != nil ? URL(string: avatarStr!) : nil,
                            isVerified: isVerified,
                            publishedTimeText: published,
                            text: text,
                            likeCountText: likes.isEmpty ? "0" : likes,
                            replyCount: replyCount,
                            isHeartedByCreator: isHearted
                        ))
                    }
                } else {
                    for (_, v) in dict {
                        walk(v)
                    }
                }
            } else if let arr = current as? [Any] {
                for item in arr {
                    walk(item)
                }
            }
        }

        walk(node)
        return comments
    }

    private func extractText(from obj: Any?) -> String? {
        guard let dict = obj as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String {
            return simple
        }
        if let runs = dict["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }.joined()
        }
        return nil
    }

    public static func extractTopicKeywords(from title: String) -> String {
        let stopWords: Set<String> = ["official", "video", "clip", "officiel", "lyrics", "paroles", "feat", "ft", "the", "and", "les", "des", "une", "pour", "dans", "avec", "hd", "4k", "audio"]
        let words = title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0.lowercased()) }
        return Array(words.prefix(3)).joined(separator: " ")
    }

    private func parseViewCount(_ text: String) -> Double {
        let upper = text.uppercased()
            .replacingOccurrences(of: "VUES", with: "")
            .replacingOccurrences(of: "VIEWS", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        if upper.hasSuffix("MD") || upper.hasSuffix("B") {
            return (Double(upper.dropLast(upper.hasSuffix("MD") ? 2 : 1)) ?? 0) * 1_000_000_000
        } else if upper.hasSuffix("M") {
            return (Double(upper.dropLast()) ?? 0) * 1_000_000
        } else if upper.hasSuffix("K") {
            return (Double(upper.dropLast()) ?? 0) * 1_000
        }
        return Double(upper) ?? 0
    }

    public static func formatDuration(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    public static func parseDurationSeconds(_ str: String) -> TimeInterval {
        let parts = str.split(separator: ":").compactMap { Int($0) }
        if parts.count == 3 {
            return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
        } else if parts.count == 2 {
            return TimeInterval(parts[0] * 60 + parts[1])
        }
        return 210
    }

    public static func formatCompactCount(_ count: Int64) -> String {
        if count >= 1_000_000_000 {
            return String(format: "%.1f Md", Double(count) / 1_000_000_000.0)
        } else if count >= 1_000_000 {
            return String(format: "%.1f M", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1f k", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}
