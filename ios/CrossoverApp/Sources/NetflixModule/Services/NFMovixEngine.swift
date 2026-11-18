import Foundation

// MARK: - 100% Embedded In-App Movix + TMDB Engine (`https://api.movix.miami` + `https://api.themoviedb.org/3`)
public actor NFMovixEngine {
    public static let shared = NFMovixEngine()

    private let tmdbAPIKey = "YOUR_TMDB_API_KEY"
    private let tmdbBase = "https://api.themoviedb.org/3"
    public static let defaultMovixBase = "https://api.movix.miami"
    private var movixBase: String = UserDefaults.standard.string(forKey: "nf_movix_base_url") ?? defaultMovixBase
    private let session: URLSession

    private var streamCache: [String: [NFStreamSource]] = [:]

    public func currentBaseURL() -> String {
        movixBase
    }

    public func updateBaseURL(_ raw: String) {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix("/") { cleaned.removeLast() }
        if !cleaned.isEmpty && !cleaned.hasPrefix("http://") && !cleaned.hasPrefix("https://") {
            cleaned = "https://" + cleaned
        }
        if cleaned.isEmpty {
            cleaned = Self.defaultMovixBase
        }
        self.movixBase = cleaned
        self.streamCache.removeAll()
        UserDefaults.standard.set(cleaned, forKey: "nf_movix_base_url")
        NFDebugLogger.shared.log(.net, tag: "MovixConfig", "Updated Movix base URL -> \(cleaned)")
    }

    private let movieGenres: [Int: String] = [
        28: "Action", 12: "Aventure", 16: "Animation", 35: "Comédie",
        80: "Crime", 99: "Documentaire", 18: "Drame", 10751: "Famille",
        14: "Fantastique", 36: "Histoire", 27: "Horreur", 10402: "Musique",
        9648: "Mystère", 10749: "Romance", 878: "Science-Fiction",
        53: "Thriller", 10752: "Guerre", 37: "Western"
    ]

    private let tvGenres: [Int: String] = [
        10759: "Action & Aventure", 16: "Animation", 35: "Comédie",
        80: "Crime", 99: "Documentaire", 18: "Drame", 10751: "Famille",
        10762: "Enfants", 9648: "Mystère", 10765: "Sci-Fi & Fantastique",
        10768: "Guerre & Politique", 37: "Western"
    ]

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 30
        config.urlCache = URLCache(memoryCapacity: 40 * 1024 * 1024, diskCapacity: 150 * 1024 * 1024)
        self.session = URLSession(configuration: config)
    }

    // MARK: - 1. Fetch Full Home Lolomo Feed (Hero + Top 10 + Movies + Series + Genres)
    public func fetchHomeFeed(filter: String = "All", genreId: Int? = nil) async -> (hero: NFMediaItem?, rows: [NFMediaRow]) {
        if let gid = genreId {
            async let mTask = fetchTMDBList(endpoint: "discover/movie", extra: ["with_genres": "\(gid)", "sort_by": "popularity.desc"], forceType: .movie)
            async let tTask = fetchTMDBList(endpoint: "discover/tv", extra: ["with_genres": "\(gid)", "sort_by": "popularity.desc"], forceType: .tv)
            let (movies, series) = await (mTask, tTask)
            var rows: [NFMediaRow] = []
            if !movies.isEmpty { rows.append(NFMediaRow(title: "Films populaires", items: movies)) }
            if !series.isEmpty { rows.append(NFMediaRow(title: "Séries populaires", items: series)) }
            return (movies.first ?? series.first, rows)
        }

        if filter == "Series" {
            async let trendingTV = fetchTMDBList(endpoint: "trending/tv/week", forceType: .tv)
            async let topTV = fetchTMDBList(endpoint: "tv/top_rated", forceType: .tv)
            async let popTV = fetchTMDBList(endpoint: "tv/popular", forceType: .tv)
            async let sciFiTV = fetchTMDBList(endpoint: "discover/tv", extra: ["with_genres": "10765"], forceType: .tv)
            let (t, top, pop, sf) = await (trendingTV, topTV, popTV, sciFiTV)
            let top10 = Array(t.prefix(10)).enumerated().map { idx, item in
                var copy = item; copy.top10Rank = idx + 1; return copy
            }
            var rows: [NFMediaRow] = []
            if !top10.isEmpty { rows.append(NFMediaRow(title: "Top 10 des séries aujourd'hui", style: .top10, items: top10)) }
            if !pop.isEmpty { rows.append(NFMediaRow(title: "Séries populaires", items: pop)) }
            if !top.isEmpty { rows.append(NFMediaRow(title: "Séries les mieux notées", items: top)) }
            if !sf.isEmpty { rows.append(NFMediaRow(title: "Science-Fiction & Fantastique", items: sf)) }
            return (t.first, rows)
        }

        if filter == "Films" {
            async let trendingM = fetchTMDBList(endpoint: "trending/movie/week", forceType: .movie)
            async let popM = fetchTMDBList(endpoint: "movie/popular", forceType: .movie)
            async let topM = fetchTMDBList(endpoint: "movie/top_rated", forceType: .movie)
            async let actionM = fetchTMDBList(endpoint: "discover/movie", extra: ["with_genres": "28"], forceType: .movie)
            let (t, pop, top, act) = await (trendingM, popM, topM, actionM)
            let top10 = Array(t.prefix(10)).enumerated().map { idx, item in
                var copy = item; copy.top10Rank = idx + 1; return copy
            }
            var rows: [NFMediaRow] = []
            if !top10.isEmpty { rows.append(NFMediaRow(title: "Top 10 des films aujourd'hui", style: .top10, items: top10)) }
            if !pop.isEmpty { rows.append(NFMediaRow(title: "Films populaires", items: pop)) }
            if !top.isEmpty { rows.append(NFMediaRow(title: "Films cultes", items: top)) }
            if !act.isEmpty { rows.append(NFMediaRow(title: "Action & Aventure", items: act)) }
            return (t.first, rows)
        }

        // Default "All" Home Lolomo
        async let trendingAll = fetchTMDBList(endpoint: "trending/all/day")
        async let popMovies = fetchTMDBList(endpoint: "movie/popular", forceType: .movie)
        async let popTV = fetchTMDBList(endpoint: "tv/popular", forceType: .tv)
        async let actionMovies = fetchTMDBList(endpoint: "discover/movie", extra: ["with_genres": "28"], forceType: .movie)
        async let anime = fetchTMDBList(endpoint: "discover/tv", extra: ["with_genres": "16", "with_original_language": "ja"], forceType: .tv)
        async let thriller = fetchTMDBList(endpoint: "discover/movie", extra: ["with_genres": "53"], forceType: .movie)

        let (trend, movies, tv, action, ani, thr) = await (trendingAll, popMovies, popTV, actionMovies, anime, thriller)

        let top10Items = Array(trend.prefix(10)).enumerated().map { idx, item in
            var copy = item
            copy.top10Rank = idx + 1
            return copy
        }

        var rows: [NFMediaRow] = []
        if !top10Items.isEmpty {
            rows.append(NFMediaRow(title: "Top 10 en France aujourd'hui", style: .top10, items: top10Items))
        }
        if !movies.isEmpty {
            rows.append(NFMediaRow(title: "Tendances Films", items: movies))
        }
        if !tv.isEmpty {
            rows.append(NFMediaRow(title: "Séries du moment", items: tv))
        }
        if !action.isEmpty {
            rows.append(NFMediaRow(title: "Action & Adrénaline", items: action))
        }
        if !ani.isEmpty {
            rows.append(NFMediaRow(title: "Animés & Séries japonaises", items: ani))
        }
        if !thr.isEmpty {
            rows.append(NFMediaRow(title: "Thrillers & Suspense", items: thr))
        }

        NFDebugLogger.shared.log(.net, tag: "MovixCatalog", "Loaded Home feed: \(rows.count) rows, hero=\(trend.first?.title ?? "none")")
        return (trend.first, rows)
    }

    // MARK: - 2. Fetch New & Hot (Upcoming Movies & Popular Series)
    public func fetchNewAndHot() async -> (comingSoon: [NFMediaItem], everyoneWatching: [NFMediaItem], top10: [NFMediaItem]) {
        async let upcoming = fetchTMDBList(endpoint: "movie/upcoming", forceType: .movie)
        async let trending = fetchTMDBList(endpoint: "trending/all/week")
        let (up, tr) = await (upcoming, trending)
        let top10 = Array(tr.prefix(10)).enumerated().map { idx, item in
            var copy = item; copy.top10Rank = idx + 1; return copy
        }
        return (up, Array(tr.dropFirst(2)), top10)
    }

    // MARK: - 3. Live Search (/search/multi)
    public func search(query: String) async -> [NFMediaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let items = await fetchTMDBList(endpoint: "search/multi", extra: ["query": trimmed])
        NFDebugLogger.shared.log(.net, tag: "Search", "Query \"\(trimmed)\" -> \(items.count) results")
        return items
    }

    // MARK: - 4. Fetch Full Details, Cast, Recommendations & Seasons/Episodes
    public func fetchMediaDetails(for item: NFMediaItem) async -> (
        updated: NFMediaItem,
        castLine: String,
        seasons: [NFSeason],
        recommendations: [NFMediaItem],
        trailerKey: String?
    ) {
        let ep = "\(item.mediaType.rawValue)/\(item.id)"
        guard let data = await getTMDB(endpoint: ep, extra: ["append_to_response": "credits,recommendations,videos"]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (item, "", [], [], nil)
        }

        var copy = item
        if let rt = json["runtime"] as? Int, rt > 0 {
            copy.runtimeMinutes = rt
        }
        if let ns = json["number_of_seasons"] as? Int, ns > 0 {
            copy.numberOfSeasons = ns
        }
        if let genresArr = json["genres"] as? [[String: Any]] {
            copy.genreNames = genresArr.compactMap { $0["name"] as? String }
        }
        if let overview = json["overview"] as? String, !overview.isEmpty {
            copy = NFMediaItem(
                id: copy.id,
                mediaType: copy.mediaType,
                title: copy.title,
                originalTitle: copy.originalTitle,
                overview: overview,
                posterPath: copy.posterPath,
                backdropPath: copy.backdropPath,
                releaseDate: copy.releaseDate,
                voteAverage: copy.voteAverage,
                genreIds: copy.genreIds,
                genreNames: copy.genreNames,
                runtimeMinutes: copy.runtimeMinutes,
                numberOfSeasons: copy.numberOfSeasons,
                maturityRating: copy.maturityRating,
                badgeText: copy.badgeText,
                top10Rank: copy.top10Rank,
                watchProgress: copy.watchProgress
            )
        }

        // Cast
        var castNames: [String] = []
        if let credits = json["credits"] as? [String: Any],
           let cast = credits["cast"] as? [[String: Any]] {
            castNames = cast.prefix(5).compactMap { $0["name"] as? String }
        }
        let castLine = castNames.isEmpty ? "" : "Avec : " + castNames.joined(separator: ", ")

        // Seasons
        var seasons: [NFSeason] = []
        if let sArr = json["seasons"] as? [[String: Any]] {
            for s in sArr {
                guard let sn = s["season_number"] as? Int, sn > 0 else { continue }
                let sName = (s["name"] as? String) ?? "Saison \(sn)"
                let epCount = (s["episode_count"] as? Int) ?? 0
                seasons.append(NFSeason(seasonNumber: sn, name: sName, episodeCount: epCount))
            }
        }

        // Recommendations
        var recs: [NFMediaItem] = []
        if let recRoot = json["recommendations"] as? [String: Any],
           let results = recRoot["results"] as? [[String: Any]] {
            recs = results.compactMap { parseTMDBItem($0, forceType: item.mediaType) }
        }

        // YouTube Trailer key
        var trailerKey: String?
        if let videosRoot = json["videos"] as? [String: Any],
           let results = videosRoot["results"] as? [[String: Any]] {
            let yt = results.first { ($0["site"] as? String) == "YouTube" && ($0["type"] as? String) == "Trailer" }
                ?? results.first { ($0["site"] as? String) == "YouTube" }
            trailerKey = yt?["key"] as? String
        }

        return (copy, castLine, seasons, recs, trailerKey)
    }

    public func fetchEpisodes(tvId: Int, season: Int) async -> [NFEpisode] {
        guard let data = await getTMDB(endpoint: "tv/\(tvId)/season/\(season)"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eps = json["episodes"] as? [[String: Any]] else {
            return []
        }

        return eps.compactMap { e in
            guard let id = e["id"] as? Int,
                  let epNum = e["episode_number"] as? Int else { return nil }
            return NFEpisode(
                id: id,
                seasonNumber: season,
                episodeNumber: epNum,
                name: (e["name"] as? String) ?? "Épisode \(epNum)",
                overview: (e["overview"] as? String) ?? "",
                runtime: (e["runtime"] as? Int) ?? 45,
                stillPath: e["still_path"] as? String
            )
        }
    }

    // MARK: - 5. Resolve All Movix Servers & Streams (`PurStream`, `FStream`, `Links`, `Wiflix`)
    public func resolveMovixStreams(
        for item: NFMediaItem,
        season: Int? = nil,
        episode: Int? = nil
    ) async -> [NFStreamSource] {
        let sNum = season ?? 1
        let eNum = episode ?? 1
        let cacheKey = item.mediaType == .movie ? "movie_\(item.id)" : "tv_\(item.id)_s\(sNum)_e\(eNum)"

        if let cached = streamCache[cacheKey], !cached.isEmpty {
            return cached
        }

        async let purTask = fetchPurStreamSources(item: item, season: sNum, episode: eNum)
        async let fstreamTask = fetchFStreamSources(item: item, season: sNum, episode: eNum)
        async let linksTask = fetchLinksSources(item: item, season: sNum, episode: eNum)
        async let wiflixTask = fetchWiflixSources(item: item)

        let (pur, fs, lnk, wf) = await (purTask, fstreamTask, linksTask, wiflixTask)

        var combined: [NFStreamSource] = []
        var seenURLs: Set<String> = []

        func appendUnique(_ list: [NFStreamSource]) {
            for s in list {
                if seenURLs.insert(s.url.absoluteString).inserted {
                    combined.append(s)
                }
            }
        }

        // Direct streams (.m3u8 / .mp4) first, then embed servers
        let all = pur + lnk + fs + wf
        appendUnique(all.filter { !$0.isEmbed })
        appendUnique(all.filter { $0.isEmbed })

        NFDebugLogger.shared.log(
            .stream,
            tag: "MovixAll",
            "\(cacheKey) -> total=\(combined.count) (pur=\(pur.count), fstream=\(fs.count), links=\(lnk.count), wiflix=\(wf.count))"
        )

        if !combined.isEmpty {
            streamCache[cacheKey] = combined
        }
        return combined
    }

    private func fetchPurStreamSources(item: NFMediaItem, season: Int, episode: Int) async -> [NFStreamSource] {
        let urlStr = item.mediaType == .movie
            ? "\(movixBase)/api/purstream/movie/\(item.id)/stream"
            : "\(movixBase)/api/purstream/tv/\(item.id)/stream?season=\(season)&episode=\(episode)"

        guard let data = await fetchMovixJSON(urlString: urlStr),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["sources"] as? [[String: Any]] else {
            return []
        }

        return arr.compactMap { s in
            guard let uStr = s["url"] as? String, let url = URL(string: uStr) else { return nil }
            let name = (s["name"] as? String) ?? "PurStream HLS"
            let fmt = (s["format"] as? String) ?? (uStr.contains(".m3u8") ? "m3u8" : "mp4")
            return NFStreamSource(
                url: url,
                name: name,
                provider: "PurStream",
                format: fmt,
                quality: name.contains("1080") ? "1080p" : "HD",
                language: name.contains("MULTI") ? "MULTI" : (name.contains("VF") ? "VF" : "MULTI"),
                isEmbed: false
            )
        }
    }

    private func fetchFStreamSources(item: NFMediaItem, season: Int, episode: Int) async -> [NFStreamSource] {
        let urlStr = item.mediaType == .movie
            ? "\(movixBase)/api/fstream/movie/\(item.id)"
            : "\(movixBase)/api/fstream/tv/\(item.id)/season/\(season)"

        guard let data = await fetchMovixJSON(urlString: urlStr),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var langDict: [String: Any] = [:]
        if item.mediaType == .movie {
            langDict = (json["players"] as? [String: Any]) ?? [:]
        } else if let episodes = json["episodes"] as? [String: Any],
                  let epObj = episodes["\(episode)"] as? [String: Any],
                  let langs = epObj["languages"] as? [String: Any] {
            langDict = langs
        }

        var out: [NFStreamSource] = []
        for (lang, val) in langDict.sorted(by: { $0.key < $1.key }) {
            guard let arr = val as? [[String: Any]] else { continue }
            for entry in arr {
                guard let uStr = entry["url"] as? String, let url = URL(string: uStr) else { continue }
                let playerName = (entry["player"] as? String) ?? (url.host ?? "Serveur")
                let quality = (entry["quality"] as? String) ?? "HD"
                let isDirect = uStr.contains(".m3u8") || uStr.contains(".mp4")
                let fmt = uStr.contains(".m3u8") ? "m3u8" : (uStr.contains(".mp4") ? "mp4" : "embed")
                out.append(NFStreamSource(
                    url: url,
                    name: "\(playerName) (\(lang))",
                    provider: "FStream",
                    format: fmt,
                    quality: quality,
                    language: lang,
                    isEmbed: !isDirect
                ))
            }
        }
        return out
    }

    private func fetchLinksSources(item: NFMediaItem, season: Int, episode: Int) async -> [NFStreamSource] {
        let urlStr = item.mediaType == .movie
            ? "\(movixBase)/api/links/movie/\(item.id)"
            : "\(movixBase)/api/links/tv/\(item.id)"

        guard let data = await fetchMovixJSON(urlString: urlStr),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var rawLinks: [Any] = []
        if item.mediaType == .movie {
            if let dataObj = json["data"] as? [String: Any],
               let links = dataObj["links"] as? [Any] {
                rawLinks = links
            }
        } else if let dataArr = json["data"] as? [[String: Any]] {
            if let match = dataArr.first(where: {
                ($0["season_number"] as? Int) == season && ($0["episode_number"] as? Int) == episode
            }), let links = match["links"] as? [Any] {
                rawLinks = links
            }
        }

        var out: [NFStreamSource] = []
        for entry in rawLinks {
            let uStr: String?
            if let s = entry as? String {
                uStr = s
            } else if let dict = entry as? [String: Any] {
                uStr = dict["url"] as? String
            } else {
                uStr = nil
            }
            guard let rawU = uStr, let url = URL(string: rawU) else { continue }
            let isDirect = rawU.contains(".m3u8") || rawU.contains(".mp4")
            let fmt = rawU.contains(".m3u8") ? "m3u8" : (rawU.contains(".mp4") ? "mp4" : "embed")
            let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? "Movix Link"
            out.append(NFStreamSource(
                url: url,
                name: isDirect ? "Direct \(fmt.uppercased()) (\(host))" : host,
                provider: "Links",
                format: fmt,
                quality: "HD",
                language: "MULTI",
                isEmbed: !isDirect
            ))
        }
        return out
    }

    private func fetchWiflixSources(item: NFMediaItem) async -> [NFStreamSource] {
        guard item.mediaType == .movie else { return [] }
        let urlStr = "\(movixBase)/api/wiflix/movie/\(item.id)"
        guard let data = await fetchMovixJSON(urlString: urlStr),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let players = json["players"] as? [String: Any] else {
            return []
        }

        var out: [NFStreamSource] = []
        for (lang, val) in players.sorted(by: { $0.key < $1.key }) {
            guard let arr = val as? [[String: Any]] else { continue }
            for entry in arr {
                guard let uStr = entry["url"] as? String, let url = URL(string: uStr) else { continue }
                let host = (entry["name"] as? String) ?? (url.host ?? "Wiflix")
                let typeLabel = (entry["type"] as? String) ?? lang.uppercased()
                let isDirect = uStr.contains(".m3u8") || uStr.contains(".mp4")
                let fmt = uStr.contains(".m3u8") ? "m3u8" : (uStr.contains(".mp4") ? "mp4" : "embed")
                out.append(NFStreamSource(
                    url: url,
                    name: "\(host) (\(typeLabel))",
                    provider: "Wiflix",
                    format: fmt,
                    quality: "HD",
                    language: typeLabel,
                    isEmbed: !isDirect
                ))
            }
        }
        return out
    }

    // MARK: - Private HTTP Helpers
    private func fetchMovixJSON(urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        let originURL = movixBase.replacingOccurrences(of: "://api.", with: "://")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue(originURL, forHTTPHeaderField: "Origin")
        req.setValue(originURL + "/", forHTTPHeaderField: "Referer")
        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse {
                NFDebugLogger.shared.log(.net, tag: "MovixAPI", "GET \(url.path) -> \(http.statusCode)")
                if (200..<300).contains(http.statusCode) {
                    return data
                }
            }
        } catch {
            NFDebugLogger.shared.log(.error, tag: "MovixAPI", "GET \(urlString) error: \(error.localizedDescription)")
        }
        return nil
    }

    private func getTMDB(endpoint: String, extra: [String: String] = [:]) async -> Data? {
        guard var comps = URLComponents(string: "\(tmdbBase)/\(endpoint)") else { return nil }
        var items = [
            URLQueryItem(name: "api_key", value: tmdbAPIKey),
            URLQueryItem(name: "language", value: "fr-FR")
        ]
        for (k, v) in extra {
            items.append(URLQueryItem(name: k, value: v))
        }
        comps.queryItems = items
        guard let url = comps.url else { return nil }
        do {
            let (data, resp) = try await session.data(from: url)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                return data
            }
        } catch {
            NFDebugLogger.shared.log(.error, tag: "TMDB", "\(endpoint) error: \(error.localizedDescription)")
        }
        return nil
    }

    private func fetchTMDBList(endpoint: String, extra: [String: String] = [:], forceType: NFMediaType? = nil) async -> [NFMediaItem] {
        guard let data = await getTMDB(endpoint: endpoint, extra: extra),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }
        return results.compactMap { parseTMDBItem($0, forceType: forceType) }
    }

    private func parseTMDBItem(_ dict: [String: Any], forceType: NFMediaType? = nil) -> NFMediaItem? {
        guard let id = dict["id"] as? Int else { return nil }
        let rawType = (dict["media_type"] as? String) ?? forceType?.rawValue ?? (dict["first_air_date"] != nil ? "tv" : "movie")
        guard rawType == "movie" || rawType == "tv" else { return nil }
        let mType: NFMediaType = rawType == "tv" ? .tv : .movie

        let title = (dict["title"] as? String) ?? (dict["name"] as? String) ?? "Titre"
        let origTitle = (dict["original_title"] as? String) ?? (dict["original_name"] as? String) ?? title
        let overview = (dict["overview"] as? String) ?? ""
        let poster = dict["poster_path"] as? String
        let backdrop = dict["backdrop_path"] as? String
        guard poster != nil || backdrop != nil else { return nil }

        let releaseDate = (dict["release_date"] as? String) ?? (dict["first_air_date"] as? String) ?? ""
        let voteAvg = (dict["vote_average"] as? Double) ?? 7.5
        let gIds = (dict["genre_ids"] as? [Int]) ?? []
        let genreMap = mType == .tv ? tvGenres : movieGenres
        let gNames = gIds.compactMap { genreMap[$0] }

        return NFMediaItem(
            id: id,
            mediaType: mType,
            title: title,
            originalTitle: origTitle,
            overview: overview,
            posterPath: poster,
            backdropPath: backdrop,
            releaseDate: releaseDate,
            voteAverage: voteAvg,
            genreIds: gIds,
            genreNames: gNames
        )
    }

    // MARK: - 6. Real-time Direct Stream Extractor (Dumps .m3u8 / .mp4 from Embed Hosters)
    public func extractDirectStream(from source: NFStreamSource) async -> NFStreamSource? {
        guard source.isEmbed else { return source }

        var req = URLRequest(url: source.url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("https://french-stream.net/", forHTTPHeaderField: "Referer")

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return nil
            }

            let unpacked = Self.unpackPackerBlocks(in: html)
            let combinedText = html + "\n" + unpacked
            let candidates = Self.extractDirectMediaURLs(from: combinedText).filter { u in
                let s = u.absoluteString.lowercased()
                return !s.contains("/troll/") && !s.contains("favicon") && !s.contains("preview")
            }

            if let best = candidates.first(where: { $0.absoluteString.contains(".m3u8") }) ?? candidates.first {
                let hostOrigin: String?
                if let scheme = source.url.scheme, let host = source.url.host {
                    hostOrigin = "\(scheme)://\(host)/"
                } else {
                    hostOrigin = nil
                }
                let fmt = best.absoluteString.contains(".m3u8") ? "m3u8" : "mp4"
                NFDebugLogger.shared.log(.stream, tag: "Extractor", "Dumped \(fmt.uppercased()) from \(source.url.host ?? "embed") -> \(best.absoluteString)")
                return NFStreamSource(
                    url: best,
                    name: source.name,
                    provider: source.provider,
                    format: fmt,
                    quality: source.quality,
                    language: source.language,
                    isEmbed: false,
                    referer: hostOrigin
                )
            }
        } catch {
            NFDebugLogger.shared.log(.error, tag: "Extractor", "Failed \(source.url.absoluteString): \(error.localizedDescription)")
        }
        return nil
    }

    private static func unpackPackerBlocks(in html: String) -> String {
        // Matches eval(function(p,a,c,k,e,d){...}('payload',base,count,'sym1|sym2|...'.split('|'),0,{}))
        let pattern = #"eval\(function\(p,a,c,k,e,[dr]\)\{.*?\}\('(.*?)',(\d+),(\d+),'(.*?)'\.split\('\|'\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return ""
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var result = ""
        for m in matches {
            guard m.numberOfRanges >= 5 else { continue }
            let payload = ns.substring(with: m.range(at: 1))
            let base = Int(ns.substring(with: m.range(at: 2))) ?? 36
            let count = Int(ns.substring(with: m.range(at: 3))) ?? 0
            let symtab = ns.substring(with: m.range(at: 4)).components(separatedBy: "|")
            result += "\n" + unpackSinglePacker(payload: payload, base: base, count: count, symtab: symtab)
        }
        return result
    }

    private static func unpackSinglePacker(payload: String, base: Int, count: Int, symtab: [String]) -> String {
        func baseEncode(_ val: Int, radix: Int) -> String {
            let digits = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
            let arr = Array(digits)
            if val == 0 { return "0" }
            var n = val
            var out = ""
            while n > 0 {
                let rem = n % radix
                out = String(arr[min(rem, arr.count - 1)]) + out
                n /= radix
            }
            return out
        }

        var lookup: [String: String] = [:]
        for i in 0..<min(count, symtab.count) {
            let word = symtab[i]
            if !word.isEmpty {
                lookup[baseEncode(i, radix: max(2, base))] = word
            }
        }

        guard let wordRegex = try? NSRegularExpression(pattern: #"\b\w+\b"#) else { return payload }
        let ns = payload as NSString
        let matches = wordRegex.matches(in: payload, range: NSRange(location: 0, length: ns.length))
        var out = ""
        var lastLoc = 0
        for m in matches {
            if m.range.location > lastLoc {
                out += ns.substring(with: NSRange(location: lastLoc, length: m.range.location - lastLoc))
            }
            let token = ns.substring(with: m.range)
            out += lookup[token] ?? token
            lastLoc = m.range.location + m.range.length
        }
        if lastLoc < ns.length {
            out += ns.substring(from: lastLoc)
        }
        return out.replacingOccurrences(of: "\\'", with: "'").replacingOccurrences(of: "\\\"", with: "\"")
    }

    private static func extractDirectMediaURLs(from raw: String) -> [URL] {
        let pattern = #"https?:\\?/\\?/[^"'\s<>\\]+\.(?:m3u8|mp4)(?:\?[^"'\s<>\\]*)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        var urls: [URL] = []
        for m in regex.matches(in: raw, range: range) {
            if let r = Range(m.range, in: raw) {
                let cleaned = String(raw[r]).replacingOccurrences(of: "\\/", with: "/")
                if let u = URL(string: cleaned), !urls.contains(u) {
                    urls.append(u)
                }
            }
        }
        return urls
    }
}
