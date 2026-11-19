import Foundation

// MARK: - 100% Embedded In-App OpenDeezer Backend (Catalog + Podcasts + ARL Full-Track Streaming)
public actor SPMusicEngine {
    public static let shared = SPMusicEngine()

    private let deezerBase = "https://api.deezer.com"
    private let session: URLSession
    private var streamCache: [String: (timestamp: Date, stream: SPAudioStream)] = [:]
    private let streamCacheTTL: TimeInterval = 900 // 15 minutes

    private var arlCookie: String = UserDefaults.standard.string(forKey: "sp_deezer_arl") ?? ""

    public init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 30
        cfg.urlCache = URLCache(memoryCapacity: 40 * 1024 * 1024, diskCapacity: 150 * 1024 * 1024)
        self.session = URLSession(configuration: cfg)
    }

    public func currentARL() -> String {
        arlCookie
    }

    private func applyARLCookie(_ arl: String) {
        let storage = session.configuration.httpCookieStorage ?? HTTPCookieStorage.shared
        // Remove old arl/sid cookies so a fresh session is negotiated
        if let existing = storage.cookies(for: URL(string: "https://www.deezer.com")!) {
            for c in existing where c.name == "arl" || c.name == "sid" {
                storage.deleteCookie(c)
            }
        }
        guard !arl.isEmpty else { return }
        let props: [HTTPCookiePropertyKey: Any] = [
            .domain: ".deezer.com",
            .path: "/",
            .name: "arl",
            .value: arl,
            .secure: true
        ]
        if let cookie = HTTPCookie(properties: props) {
            storage.setCookie(cookie)
        }
    }

    public func updateARL(_ raw: String) {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        self.arlCookie = cleaned
        self.streamCache.removeAll()
        applyARLCookie(cleaned)
        UserDefaults.standard.set(cleaned, forKey: "sp_deezer_arl")
    }

    public func validateARL() async -> (ok: Bool, userName: String?) {
        guard !arlCookie.isEmpty,
              let (_, _, userId, userName) = await fetchDeezerSession(arl: arlCookie) else {
            return (false, nil)
        }
        return (userId > 0, userName)
    }

    // MARK: - 1. Home Feed (Top Tracks, Playlists, Albums, Artists, Podcasts)
    public func fetchHomeFeed() async -> (
        topTracks: [SPTrack],
        playlists: [SPCollection],
        albums: [SPCollection],
        artists: [SPCollection],
        podcasts: [SPCollection]
    ) {
        async let tracksTask = fetchChartTracks()
        async let playlistsTask = fetchChartPlaylists()
        async let albumsTask = fetchChartAlbums()
        async let artistsTask = fetchChartArtists()
        async let podcastsTask = fetchChartPodcasts()
        return await (tracksTask, playlistsTask, albumsTask, artistsTask, podcastsTask)
    }

    private func fetchChartTracks() async -> [SPTrack] {
        guard let data = await getJSON("\(deezerBase)/chart/0/tracks?limit=25"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else {
            return []
        }
        return arr.compactMap(parseDeezerTrack)
    }

    private func fetchChartPlaylists() async -> [SPCollection] {
        guard let data = await getJSON("\(deezerBase)/chart/0/playlists?limit=15"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { d in
            guard let id = d["id"] as? Int, let title = d["title"] as? String else { return nil }
            let cover = (d["picture_xl"] as? String) ?? (d["picture_big"] as? String) ?? (d["picture_medium"] as? String)
            let user = (d["user"] as? [String: Any])?["name"] as? String ?? "Deezer"
            return SPCollection(id: "\(id)", kind: .playlist, title: title, subtitle: "Playlist • \(user)", coverURLString: cover)
        }
    }

    private func fetchChartAlbums() async -> [SPCollection] {
        guard let data = await getJSON("\(deezerBase)/chart/0/albums?limit=15"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { d in
            guard let id = d["id"] as? Int, let title = d["title"] as? String else { return nil }
            let cover = (d["cover_xl"] as? String) ?? (d["cover_big"] as? String) ?? (d["cover_medium"] as? String)
            let artist = (d["artist"] as? [String: Any])?["name"] as? String ?? "Artiste"
            return SPCollection(id: "\(id)", kind: .album, title: title, subtitle: "Album • \(artist)", coverURLString: cover)
        }
    }

    private func fetchChartArtists() async -> [SPCollection] {
        guard let data = await getJSON("\(deezerBase)/chart/0/artists?limit=15"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { d in
            guard let id = d["id"] as? Int, let name = d["name"] as? String else { return nil }
            let pic = (d["picture_xl"] as? String) ?? (d["picture_big"] as? String) ?? (d["picture_medium"] as? String)
            return SPCollection(id: "\(id)", kind: .artist, title: name, subtitle: "Artiste", coverURLString: pic)
        }
    }

    private func fetchChartPodcasts() async -> [SPCollection] {
        guard let data = await getJSON("\(deezerBase)/chart/0/podcasts?limit=15"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { d in
            guard let id = d["id"] as? Int, let title = d["title"] as? String else { return nil }
            let pic = (d["picture_xl"] as? String) ?? (d["picture_big"] as? String) ?? (d["picture_medium"] as? String)
            return SPCollection(id: "\(id)", kind: .podcast, title: title, subtitle: "Podcast", coverURLString: pic)
        }
    }

    // MARK: - 2. Search (Tracks, Albums, Artists, Playlists, Podcasts)
    public func search(query: String) async -> (
        tracks: [SPTrack],
        albums: [SPCollection],
        artists: [SPCollection],
        playlists: [SPCollection],
        podcasts: [SPCollection]
    ) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return ([], [], [], [], [])
        }

        async let tTask = getJSON("\(deezerBase)/search/track?q=\(encoded)&limit=25")
        async let aTask = getJSON("\(deezerBase)/search/album?q=\(encoded)&limit=12")
        async let arTask = getJSON("\(deezerBase)/search/artist?q=\(encoded)&limit=10")
        async let pTask = getJSON("\(deezerBase)/search/playlist?q=\(encoded)&limit=10")
        async let podTask = getJSON("\(deezerBase)/search/podcast?q=\(encoded)&limit=10")

        let (tData, aData, arData, pData, podData) = await (tTask, aTask, arTask, pTask, podTask)

        var tracks: [SPTrack] = []
        if let d = tData,
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let arr = j["data"] as? [[String: Any]] {
            tracks = arr.compactMap(parseDeezerTrack)
        }

        var albums: [SPCollection] = []
        if let d = aData,
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let arr = j["data"] as? [[String: Any]] {
            albums = arr.compactMap { x in
                guard let id = x["id"] as? Int, let title = x["title"] as? String else { return nil }
                let cover = (x["cover_xl"] as? String) ?? (x["cover_big"] as? String) ?? (x["cover_medium"] as? String)
                let artist = (x["artist"] as? [String: Any])?["name"] as? String ?? "Album"
                return SPCollection(id: "\(id)", kind: .album, title: title, subtitle: "Album • \(artist)", coverURLString: cover)
            }
        }

        var artists: [SPCollection] = []
        if let d = arData,
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let arr = j["data"] as? [[String: Any]] {
            artists = arr.compactMap { x in
                guard let id = x["id"] as? Int, let name = x["name"] as? String else { return nil }
                let pic = (x["picture_xl"] as? String) ?? (x["picture_big"] as? String) ?? (x["picture_medium"] as? String)
                return SPCollection(id: "\(id)", kind: .artist, title: name, subtitle: "Artiste", coverURLString: pic)
            }
        }

        var playlists: [SPCollection] = []
        if let d = pData,
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let arr = j["data"] as? [[String: Any]] {
            playlists = arr.compactMap { x in
                guard let id = x["id"] as? Int, let title = x["title"] as? String else { return nil }
                let cover = (x["picture_xl"] as? String) ?? (x["picture_big"] as? String) ?? (x["picture_medium"] as? String)
                let user = (x["user"] as? [String: Any])?["name"] as? String ?? "Playlist"
                return SPCollection(id: "\(id)", kind: .playlist, title: title, subtitle: "Playlist • \(user)", coverURLString: cover)
            }
        }

        var podcasts: [SPCollection] = []
        if let d = podData,
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let arr = j["data"] as? [[String: Any]] {
            podcasts = arr.compactMap { x in
                guard let id = x["id"] as? Int, let title = x["title"] as? String else { return nil }
                let pic = (x["picture_xl"] as? String) ?? (x["picture_big"] as? String) ?? (x["picture_medium"] as? String)
                return SPCollection(id: "\(id)", kind: .podcast, title: title, subtitle: "Podcast", coverURLString: pic)
            }
        }

        return (tracks, albums, artists, playlists, podcasts)
    }

    // MARK: - 3. Fetch Collection Tracks (Playlist / Album / Artist / Podcast)
    public func fetchTracks(for collection: SPCollection) async -> [SPTrack] {
        if collection.isUserCreated { return collection.tracks }

        let urlStr: String
        switch collection.kind {
        case .playlist:
            urlStr = "\(deezerBase)/playlist/\(collection.id)/tracks?limit=50"
        case .album:
            urlStr = "\(deezerBase)/album/\(collection.id)/tracks?limit=50"
        case .artist:
            urlStr = "\(deezerBase)/artist/\(collection.id)/top?limit=30"
        case .podcast:
            urlStr = "\(deezerBase)/podcast/\(collection.id)/episodes?limit=50"
        }

        guard let data = await getJSON(urlStr),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else {
            return collection.tracks
        }

        if collection.kind == .podcast {
            return arr.compactMap { ep in
                guard let id = ep["id"] as? Int, let title = ep["title"] as? String else { return nil }
                let dur = (ep["duration"] as? Int) ?? 1800
                let mp3 = ep["mp3"] as? String
                let pic = (ep["picture_xl"] as? String) ?? (ep["picture_big"] as? String) ?? collection.coverURLString
                return SPTrack(
                    id: "ep_\(id)",
                    title: title,
                    artistName: collection.title,
                    albumTitle: "Podcast",
                    coverURLString: pic,
                    durationSeconds: dur,
                    previewURLString: mp3,
                    directAudioURLString: mp3
                )
            }
        }

        return arr.compactMap { dict in
            var copy = dict
            if copy["album"] == nil, collection.kind == .album {
                copy["album"] = [
                    "id": Int(collection.id) ?? 0,
                    "title": collection.title,
                    "cover_xl": collection.coverURLString ?? ""
                ]
            }
            return parseDeezerTrack(copy)
        }
    }

    // MARK: - 3b. Full Artist & Album Details
    public func fetchArtistDetails(artistId: String) async -> (
        name: String,
        pictureURL: String?,
        nbFan: Int,
        topTracks: [SPTrack],
        albums: [SPCollection],
        related: [SPCollection]
    ) {
        async let infoData = getJSON("\(deezerBase)/artist/\(artistId)")
        async let topData = getJSON("\(deezerBase)/artist/\(artistId)/top?limit=25")
        async let albumsData = getJSON("\(deezerBase)/artist/\(artistId)/albums?limit=20")
        async let relData = getJSON("\(deezerBase)/artist/\(artistId)/related?limit=12")

        let (iD, tD, aD, rD) = await (infoData, topData, albumsData, relData)

        var name = "Artiste"
        var pic: String? = nil
        var nbFan = 0
        if let d = iD, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            name = (j["name"] as? String) ?? name
            pic = (j["picture_xl"] as? String) ?? (j["picture_big"] as? String) ?? (j["picture_medium"] as? String)
            nbFan = (j["nb_fan"] as? Int) ?? 0
        }

        var topTracks: [SPTrack] = []
        if let d = tD,
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let arr = j["data"] as? [[String: Any]] {
            topTracks = arr.compactMap(parseDeezerTrack)
        }

        var albums: [SPCollection] = []
        if let d = aD,
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let arr = j["data"] as? [[String: Any]] {
            albums = arr.compactMap { x in
                guard let id = x["id"] as? Int, let title = x["title"] as? String else { return nil }
                let cover = (x["cover_xl"] as? String) ?? (x["cover_big"] as? String) ?? (x["cover_medium"] as? String)
                let release = (x["release_date"] as? String) ?? ""
                return SPCollection(id: "\(id)", kind: .album, title: title, subtitle: String(release.prefix(4)), coverURLString: cover)
            }
        }

        var related: [SPCollection] = []
        if let d = rD,
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let arr = j["data"] as? [[String: Any]] {
            related = arr.compactMap { x in
                guard let id = x["id"] as? Int, let rname = x["name"] as? String else { return nil }
                let rpic = (x["picture_xl"] as? String) ?? (x["picture_big"] as? String) ?? (x["picture_medium"] as? String)
                return SPCollection(id: "\(id)", kind: .artist, title: rname, subtitle: "Artiste", coverURLString: rpic)
            }
        }

        return (name, pic, nbFan, topTracks, albums, related)
    }

    public func fetchAlbumDetails(albumId: String) async -> (
        title: String,
        artistName: String,
        artistId: String?,
        artistPicURL: String?,
        coverURL: String?,
        releaseYear: String,
        tracks: [SPTrack]
    ) {
        guard let data = await getJSON("\(deezerBase)/album/\(albumId)"),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ("Album", "Artiste", nil, nil, nil, "", [])
        }
        let title = (j["title"] as? String) ?? "Album"
        let cover = (j["cover_xl"] as? String) ?? (j["cover_big"] as? String) ?? (j["cover_medium"] as? String)
        let release = String(((j["release_date"] as? String) ?? "").prefix(4))
        let artistObj = j["artist"] as? [String: Any]
        let artistName = (artistObj?["name"] as? String) ?? "Artiste"
        let artistId = (artistObj?["id"] as? Int).map { "\($0)" }
        let artistPic = (artistObj?["picture_medium"] as? String) ?? (artistObj?["picture_small"] as? String)

        var tracks: [SPTrack] = []
        if let tracksObj = j["tracks"] as? [String: Any],
           let arr = tracksObj["data"] as? [[String: Any]] {
            tracks = arr.compactMap { dict in
                var copy = dict
                if copy["album"] == nil {
                    copy["album"] = ["id": Int(albumId) ?? 0, "title": title, "cover_xl": cover ?? ""]
                }
                return parseDeezerTrack(copy)
            }
        }
        return (title, artistName, artistId, artistPic, cover, release, tracks)
    }

    public func invalidateStreamCache(for trackId: String) {
        streamCache.removeValue(forKey: trackId)
    }

    // MARK: - 4. Full-Length Audio Stream Resolver (Direct Podcast -> OpenDeezer ARL + Local Decrypt Proxy -> Teaser)
    public func resolveAudioStream(for track: SPTrack, forceRefresh: Bool = false) async -> SPAudioStream? {
        if let direct = track.directAudioURL {
            return SPAudioStream(url: direct, format: "mp3", sourceName: "Podcast Direct (MP3)", isFullLength: true)
        }

        if !forceRefresh, let cached = streamCache[track.id], Date().timeIntervalSince(cached.timestamp) < streamCacheTTL {
            return cached.stream
        }
        if forceRefresh {
            streamCache.removeValue(forKey: track.id)
        }

        // 1. OpenDeezer ARL authenticated full-track stream via on-device Blowfish proxy
        if !arlCookie.isEmpty, let dzStream = await resolveDeezerARLStream(trackId: track.id, arl: arlCookie) {
            streamCache[track.id] = (Date(), dzStream)
            return dzStream
        }

        // 2. Official Deezer 30s teaser (exact track, never a wrong song)
        if let preview = track.previewURL {
            return SPAudioStream(url: preview, format: "mp3", sourceName: "Deezer Teaser 30s (Configurez ARL)", isFullLength: false)
        }

        return nil
    }

    private func fetchDeezerSession(arl: String) async -> (apiToken: String, licenseToken: String, userId: Int, userName: String)? {
        applyARLCookie(arl)
        guard let url = URL(string: "https://www.deezer.com/ajax/gw-light.php?method=deezer.getUserData&input=3&api_version=1.0&api_token=null") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpShouldHandleCookies = true
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await session.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [String: Any],
                  let checkForm = results["checkForm"] as? String,
                  let user = results["USER"] as? [String: Any],
                  let userId = user["USER_ID"] as? Int, userId > 0,
                  let options = user["OPTIONS"] as? [String: Any],
                  let licenseToken = options["license_token"] as? String else {
                return nil
            }
            let blogName = (user["BLOG_NAME"] as? String) ?? "Deezer"
            return (checkForm, licenseToken, userId, blogName)
        } catch {
            return nil
        }
    }

    private func resolveDeezerARLStream(trackId: String, arl: String) async -> SPAudioStream? {
        guard let sessionInfo = await fetchDeezerSession(arl: arl) else { return nil }

        guard let gwURL = URL(string: "https://www.deezer.com/ajax/gw-light.php?method=song.getData&input=3&api_version=1.0&api_token=\(sessionInfo.apiToken)") else {
            return nil
        }
        var songReq = URLRequest(url: gwURL)
        songReq.httpMethod = "POST"
        songReq.httpShouldHandleCookies = true
        songReq.httpBody = try? JSONSerialization.data(withJSONObject: ["sng_id": trackId])
        songReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        songReq.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        guard let (sData, _) = try? await session.data(for: songReq),
              let sJson = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
              let sRes = sJson["results"] as? [String: Any],
              let trackToken = sRes["TRACK_TOKEN"] as? String else {
            return nil
        }

        let effectiveId: String
        if let sngInt = sRes["SNG_ID"] as? Int {
            effectiveId = "\(sngInt)"
        } else if let sngStr = sRes["SNG_ID"] as? String {
            effectiveId = sngStr
        } else {
            effectiveId = trackId
        }

        guard let mediaURL = URL(string: "https://media.deezer.com/v1/get_url") else { return nil }
        let body: [String: Any] = [
            "license_token": sessionInfo.licenseToken,
            "media": [[
                "type": "FULL",
                "formats": [
                    ["cipher": "BF_CBC_STRIPE", "format": "MP3_320"],
                    ["cipher": "BF_CBC_STRIPE", "format": "MP3_128"],
                    ["cipher": "NONE", "format": "MP3_MISC"]
                ]
            ]],
            "track_tokens": [trackToken]
        ]
        var mReq = URLRequest(url: mediaURL)
        mReq.httpMethod = "POST"
        mReq.httpBody = try? JSONSerialization.data(withJSONObject: body)
        mReq.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let (mData, _) = try? await session.data(for: mReq),
              let mJson = try? JSONSerialization.jsonObject(with: mData) as? [String: Any],
              let dataArr = mJson["data"] as? [[String: Any]],
              let mediaArr = dataArr.first?["media"] as? [[String: Any]],
              let firstMedia = mediaArr.first,
              let sources = firstMedia["sources"] as? [[String: Any]],
              let uStr = sources.first?["url"] as? String,
              let cdnURL = URL(string: uStr) else {
            return nil
        }

        let fmt = (firstMedia["format"] as? String) ?? "MP3"
        let cipher = (firstMedia["cipher"] as? [String: Any])?["type"] as? String ?? "BF_CBC_STRIPE"

        if cipher == "NONE" || fmt == "MP3_MISC" {
            return SPAudioStream(url: cdnURL, format: "mp3", sourceName: "OpenDeezer (\(fmt))", isFullLength: true)
        }

        // Register encrypted stream in local on-device Blowfish-CBC decrypting proxy
        guard let localProxyURL = await SPDeezerStreamProxy.shared.register(trackId: effectiveId, encryptedURL: cdnURL) else {
            return nil
        }
        return SPAudioStream(url: localProxyURL, format: "mp3", sourceName: "OpenDeezer ARL (\(fmt))", isFullLength: true)
    }

    // MARK: - Helpers
    private func getJSON(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, resp) = try await session.data(from: url)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                return data
            }
        } catch {}
        return nil
    }

    private func parseDeezerTrack(_ dict: [String: Any]) -> SPTrack? {
        guard let idVal = dict["id"] as? Int,
              let title = (dict["title_short"] as? String) ?? (dict["title"] as? String) else {
            return nil
        }
        let artistObj = dict["artist"] as? [String: Any]
        let artistName = (artistObj?["name"] as? String) ?? "Artiste inconnu"
        let artistId = (artistObj?["id"] as? Int).map { "\($0)" }

        let albumObj = dict["album"] as? [String: Any]
        let albumTitle = (albumObj?["title"] as? String) ?? ""
        let albumId = (albumObj?["id"] as? Int).map { "\($0)" }
        let cover = (albumObj?["cover_xl"] as? String)
            ?? (albumObj?["cover_big"] as? String)
            ?? (albumObj?["cover_medium"] as? String)
            ?? (artistObj?["picture_xl"] as? String)

        let dur = (dict["duration"] as? Int) ?? 180
        let preview = dict["preview"] as? String
        let explicit = (dict["explicit_lyrics"] as? Bool) ?? false

        return SPTrack(
            id: "\(idVal)",
            title: title,
            artistName: artistName,
            artistId: artistId,
            albumTitle: albumTitle,
            albumId: albumId,
            coverURLString: cover,
            durationSeconds: dur,
            previewURLString: preview,
            isExplicit: explicit
        )
    }
}
