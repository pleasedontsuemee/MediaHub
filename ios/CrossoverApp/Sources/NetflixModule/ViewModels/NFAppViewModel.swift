import Foundation
import SwiftUI
import AVFoundation
import MediaPlayer

#if canImport(UIKit)
import UIKit
#endif

public enum NFMainTab: Int, CaseIterable {
    case home = 0
    case newAndHot = 1
    case fastLaughs = 2
    case search = 3
    case downloads = 4
}

@MainActor
public final class NFAppViewModel: ObservableObject {
    // Splash & Profile Gate (Disabled on startup per user preference)
    @Published public var showSplash: Bool = false
    @Published public var showProfileGate: Bool = false
    @Published public var profiles: [NFProfile] = [
        NFProfile(id: "p1", name: "Mon Profil", colorHex: "#E50914", avatarName: "avatar_squid", isKids: false),
        NFProfile(id: "p2", name: "Ramy", colorHex: "#F5A818", avatarName: "avatar_yellow", isKids: false),
        NFProfile(id: "p3", name: "Rouge", colorHex: "#DA2A1C", avatarName: "avatar_red", isKids: false),
        NFProfile(id: "p4", name: "Enfants", colorHex: "#1876D2", avatarName: "avatar_blue", isKids: true)
    ]
    @Published public var activeProfile: NFProfile = NFProfile(id: "p1", name: "Mon Profil", colorHex: "#E50914", avatarName: "avatar_squid", isKids: false)

    // Navigation & Tabs
    @Published public var selectedTab: NFMainTab = .home
    @Published public var homeFilter: String = "All" // "All", "Series", "Films"
    @Published public var selectedGenreId: Int? = nil
    @Published public var selectedGenreName: String? = nil
    @Published public var isCategoriesSheetPresented: Bool = false
    @Published public var isMyListSheetPresented: Bool = false
    @Published public var isSettingsSheetPresented: Bool = false
    @Published public var selectedDetailMedia: NFMediaItem? = nil

    // Home Lolomo Data
    @Published public var heroItem: NFMediaItem? = nil
    @Published public var homeRows: [NFMediaRow] = []
    @Published public var isLoadingHome: Bool = true

    // New & Hot Data
    @Published public var comingSoonItems: [NFMediaItem] = []
    @Published public var everyoneWatchingItems: [NFMediaItem] = []
    @Published public var newHotTop10Items: [NFMediaItem] = []
    @Published public var remindedIds: Set<Int> = []

    // Search Data
    @Published public var searchQuery: String = ""
    @Published public var searchResults: [NFMediaItem] = []
    @Published public var isSearching: Bool = false

    // User Library & Watch Progress (Starts empty, updates dynamically)
    @Published public var myList: [NFMediaItem] = []
    @Published public var continueWatching: [NFMediaItem] = []
    @Published public var likedMediaIds: Set<Int> = []
    @Published public var dislikedMediaIds: Set<Int> = []

    // Settings
    @Published public var movixBaseURL: String = UserDefaults.standard.string(forKey: "nf_movix_base_url") ?? NFMovixEngine.defaultMovixBase
    @AppStorage("nf_pip_enabled") public var isPiPEnabled: Bool = true
    @AppStorage("nf_bg_playback") public var backgroundPlaybackEnabled: Bool = true
    @AppStorage("nf_wifi_only_dl") public var wifiOnlyDownloads: Bool = true
    @AppStorage("nf_autoplay_next") public var autoplayNextEpisode: Bool = true
    @AppStorage("nf_zoom_fill") public var zoomToFillScreen: Bool = false

    // Active Video Player State
    public let player = AVPlayer()
    @Published public var isPlayerPresented: Bool = false
    @Published public var playingMedia: NFMediaItem? = nil
    @Published public var playingSeason: Int? = nil
    @Published public var playingEpisode: Int? = nil
    @Published public var playingEpisodeTitle: String? = nil
    @Published public var availableStreams: [NFStreamSource] = []
    @Published public var activeStream: NFStreamSource? = nil
    @Published public var isPlaying: Bool = false
    @Published public var isBuffering: Bool = false
    @Published public var isControlsLocked: Bool = false
    @Published public var showPlayerControls: Bool = true
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 1
    @Published public var playbackSpeed: Float = 1.0

    // Toast
    @Published public var toastMessage: String? = nil
    private var toastTask: Task<Void, Never>?

    private var timeObserverToken: Any?
    private var playerStatusObserver: NSKeyValueObservation?
    private var itemStatusObserver: NSKeyValueObservation?
    private var cachedArtwork: MPMediaItemArtwork?
    private var cachedArtworkId: Int?
    private let stateURL: URL

    private struct PersistedState: Codable {
        var profiles: [NFProfile]
        var myList: [NFMediaItem]
        var continueWatching: [NFMediaItem]
        var likedIds: [Int]
        var remindedIds: [Int]
    }

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.stateURL = docs.appendingPathComponent("nf_user_state_v1.json")

        NFFontManager.registerBundledFonts()
        configureAudioSession()
        setupRemoteCommandCenter()
        loadState()
        setupPlayerObservers()

        Task {
            await loadHomeFeed()
            await loadNewAndHot()
        }
    }

    public func updateMovixURL(_ newURL: String) {
        Task {
            await NFMovixEngine.shared.updateBaseURL(newURL)
            let updated = await NFMovixEngine.shared.currentBaseURL()
            self.movixBaseURL = updated
            self.showToast("URL Movix mise à jour : \(updated)")
            await loadHomeFeed()
            await loadNewAndHot()
        }
    }

    // MARK: - Persistence
    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL),
              let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        if !decoded.profiles.isEmpty {
            self.profiles = decoded.profiles
            self.activeProfile = decoded.profiles[0]
        }
        self.myList = decoded.myList
        self.continueWatching = decoded.continueWatching
        self.likedMediaIds = Set(decoded.likedIds)
        self.remindedIds = Set(decoded.remindedIds)
    }

    public func saveState() {
        let state = PersistedState(
            profiles: profiles,
            myList: myList,
            continueWatching: continueWatching,
            likedIds: Array(likedMediaIds),
            remindedIds: Array(remindedIds)
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    // MARK: - Catalog Loading
    public func loadHomeFeed() async {
        isLoadingHome = true
        let (hero, rows) = await NFMovixEngine.shared.fetchHomeFeed(filter: homeFilter, genreId: selectedGenreId)
        self.heroItem = hero
        self.homeRows = rows
        self.isLoadingHome = false
    }

    public func loadNewAndHot() async {
        let (coming, watching, top10) = await NFMovixEngine.shared.fetchNewAndHot()
        self.comingSoonItems = coming
        self.everyoneWatchingItems = watching
        self.newHotTop10Items = top10
    }

    public func selectHomeFilter(_ filter: String) {
        homeFilter = filter
        selectedGenreId = nil
        selectedGenreName = nil
        Task { await loadHomeFeed() }
    }

    public func selectGenre(id: Int?, name: String?) {
        selectedGenreId = id
        selectedGenreName = name
        Task { await loadHomeFeed() }
    }

    public func performSearch(_ query: String) {
        searchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        Task {
            let results = await NFMovixEngine.shared.search(query: trimmed)
            if self.searchQuery == query {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }

    // MARK: - My List, Ratings & Profiles
    public func isInMyList(_ item: NFMediaItem) -> Bool {
        myList.contains { $0.id == item.id && $0.mediaType == item.mediaType }
    }

    public func toggleMyList(_ item: NFMediaItem) {
        if isInMyList(item) {
            myList.removeAll { $0.id == item.id && $0.mediaType == item.mediaType }
            showToast("Retiré de Ma liste")
        } else {
            myList.insert(item, at: 0)
            showToast("Ajouté à Ma liste")
        }
        saveState()
    }

    public func toggleLike(_ item: NFMediaItem) {
        if likedMediaIds.contains(item.id) {
            likedMediaIds.remove(item.id)
        } else {
            likedMediaIds.insert(item.id)
            dislikedMediaIds.remove(item.id)
        }
        saveState()
    }

    public func toggleRemind(_ item: NFMediaItem) {
        if remindedIds.contains(item.id) {
            remindedIds.remove(item.id)
            showToast("Rappel annulé")
        } else {
            remindedIds.insert(item.id)
            showToast("Rappel activé pour \(item.title)")
        }
        saveState()
    }

    public func addProfile(name: String, isKids: Bool = false) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let colors = ["#E50914", "#1876D2", "#F5A818", "#DA2A1C"]
        let avatars = ["avatar_squid", "avatar_blue", "avatar_yellow", "avatar_red"]
        let idx = profiles.count % colors.count
        let p = NFProfile(name: trimmed, colorHex: colors[idx], avatarName: avatars[idx], isKids: isKids)
        profiles.append(p)
        activeProfile = p
        saveState()
    }

    // MARK: - Play Movie / Episode via Movix Engine (or Offline Local File)
    public func playMedia(_ media: NFMediaItem, season: Int? = nil, episode: Int? = nil, episodeTitle: String? = nil) {
        let sNum = media.mediaType == .tv ? (season ?? media.lastSeasonNumber ?? 1) : nil
        let eNum = media.mediaType == .tv ? (episode ?? media.lastEpisodeNumber ?? 1) : nil

        NFDebugLogger.shared.log(.ui, tag: "Player", "playMedia id=\(media.id) type=\(media.mediaType.rawValue) title=\"\(media.title)\" S\(sNum ?? 0)E\(eNum ?? 0)")

        let hadDetailSheet = (self.selectedDetailMedia != nil)
        self.selectedDetailMedia = nil

        self.playingMedia = media
        self.playingSeason = sNum
        self.playingEpisode = eNum
        self.playingEpisodeTitle = episodeTitle
        self.activeStream = nil
        self.availableStreams = []
        self.isBuffering = true
        self.showPlayerControls = true
        self.isControlsLocked = false
        self.currentTime = 0
        self.duration = 1

        // Record in Continue Watching
        var cwCopy = media
        cwCopy.watchProgress = max(0.05, media.watchProgress)
        cwCopy.lastSeasonNumber = sNum
        cwCopy.lastEpisodeNumber = eNum
        continueWatching.removeAll { $0.id == media.id && $0.mediaType == media.mediaType }
        continueWatching.insert(cwCopy, at: 0)
        saveState()

        Task {
            if hadDetailSheet {
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
            self.isPlayerPresented = true

            #if canImport(UIKit)
            NotificationCenter.default.post(name: Notification.Name("CrossoverAllowLandscapeChanged"), object: true)
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let ws = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                for win in ws.windows {
                    win.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
                ws.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
            }
            #endif

            let dlKey = NFOfflineDownloadManager.shared.key(for: media, season: sNum, episode: eNum)
            if let localURL = NFOfflineDownloadManager.localFileURL(for: dlKey) {
                NFDebugLogger.shared.log(.stream, tag: "Player", "Playing offline file \(localURL.lastPathComponent)")
                let item = AVPlayerItem(url: localURL)
                self.startPlayback(with: item, media: media)
                return
            }

            let sources = await NFMovixEngine.shared.resolveMovixStreams(for: media, season: sNum, episode: eNum)
            self.availableStreams = sources
            guard let first = sources.first else {
                self.isBuffering = false
                self.showToast("Aucun serveur Movix trouvé pour ce titre")
                return
            }
            await self.activateStreamSource(first, media: media, seekTime: nil)
        }
    }

    public func switchStreamSource(_ source: NFStreamSource) {
        guard let media = playingMedia else { return }
        let savedTime = currentTime
        isBuffering = true
        Task {
            await activateStreamSource(source, media: media, seekTime: savedTime)
        }
    }

    private func activateStreamSource(_ source: NFStreamSource, media: NFMediaItem, seekTime: TimeInterval?) async {
        // Attempt real-time direct .m3u8 / .mp4 extraction if this is an embed server
        let resolved: NFStreamSource
        if source.isEmbed, let dumped = await NFMovixEngine.shared.extractDirectStream(from: source) {
            resolved = dumped
        } else {
            resolved = source
        }

        self.activeStream = resolved

        if resolved.isEmbed {
            self.player.pause()
            self.player.replaceCurrentItem(with: nil)
            self.isBuffering = false
            self.isPlaying = true
            self.showToast("Serveur Web : \(resolved.provider) · \(resolved.name)")
            return
        }

        var headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) AppleWebKit/605.1.15"
        ]
        if let ref = resolved.referer {
            headers["Referer"] = ref
        }
        let asset = AVURLAsset(url: resolved.url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 5.0
        if let t = seekTime, t > 1 {
            await item.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        self.startPlayback(with: item, media: media)
        if seekTime != nil {
            self.showToast("Source : \(resolved.provider) · \(resolved.name)")
        }
    }

    private func startPlayback(with item: AVPlayerItem, media: NFMediaItem) {
        observePlayerItem(item, mediaId: media.id)
        player.replaceCurrentItem(with: item)
        player.play()
        player.rate = playbackSpeed
        isPlaying = true
        updateNowPlayingInfo(fetchArtwork: true)
    }

    public func closePlayer() {
        player.pause()
        isPlaying = false
        isPlayerPresented = false
        updateNowPlayingInfo()
        #if canImport(UIKit)
        NotificationCenter.default.post(name: Notification.Name("CrossoverAllowLandscapeChanged"), object: false)
        if let ws = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            for win in ws.windows {
                win.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            ws.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
        }
        #endif
    }

    public func togglePlayPause() {
        if player.timeControlStatus != .paused {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            player.rate = playbackSpeed
            isPlaying = true
        }
        updateNowPlayingInfo()
    }

    public func seek(to seconds: TimeInterval) {
        let clamped = max(0, min(seconds, duration))
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlayingInfo()
    }

    public func skipForward() { seek(to: currentTime + 10) }
    public func skipBackward() { seek(to: currentTime - 10) }

    public func changeSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying {
            player.rate = speed
        }
    }

    // MARK: - Audio Session, Background Playback & Dynamic Island (`MPNowPlayingInfoCenter`)
    private func configureAudioSession() {
        #if canImport(UIKit)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothA2DP])
            try session.setActive(true)
            UIApplication.shared.beginReceivingRemoteControlEvents()
        } catch {}
        #endif
    }

    private func setupRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                if self?.player.timeControlStatus == .paused { self?.togglePlayPause() }
            }
            return .success
        }
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                if self?.player.timeControlStatus != .paused { self?.togglePlayPause() }
            }
            return .success
        }
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.togglePlayPause() }
            return .success
        }
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] ev in
            guard let pe = ev as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in self?.seek(to: pe.positionTime) }
            return .success
        }
        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.skipForward() }
            return .success
        }
        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.skipBackward() }
            return .success
        }
    }

    public func updateNowPlayingInfo(fetchArtwork: Bool = false) {
        guard isPlayerPresented, let media = playingMedia else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let subtitle = playingEpisodeTitle ?? media.mediaType.badgeLabel
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: media.title,
            MPMediaItemPropertyArtist: subtitle,
            MPMediaItemPropertyPlaybackDuration: max(1, duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackSpeed) : 0.0
        ]
        if cachedArtworkId == media.id, let art = cachedArtwork {
            info[MPMediaItemPropertyArtwork] = art
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if fetchArtwork, cachedArtworkId != media.id, let url = media.posterURL ?? media.backdropURL {
            let mid = media.id
            Task {
                #if canImport(UIKit)
                if let img = await NFImageCache.shared.image(for: url) {
                    let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                    await MainActor.run {
                        self.cachedArtworkId = mid
                        self.cachedArtwork = art
                        self.updateNowPlayingInfo(fetchArtwork: false)
                    }
                }
                #endif
            }
        }
    }

    private func setupPlayerObservers() {
        playerStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch p.timeControlStatus {
                case .playing:
                    self.isBuffering = false
                    NFDebugLogger.shared.updatePlayerSummary("Playing | \(self.activeStream?.name ?? "Local")")
                case .waitingToPlayAtSpecifiedRate:
                    self.isBuffering = true
                    NFDebugLogger.shared.updatePlayerSummary("Buffering (\(p.reasonForWaitingToPlay?.rawValue ?? ""))")
                case .paused:
                    NFDebugLogger.shared.updatePlayerSummary("Paused")
                @unknown default:
                    break
                }
            }
        }

        timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let sec = CMTimeGetSeconds(time)
                if sec.isFinite && sec >= 0 { self.currentTime = sec }
                if let item = self.player.currentItem {
                    let dur = CMTimeGetSeconds(item.duration)
                    if dur.isFinite && dur > 0 { self.duration = dur }
                }
                if let cur = self.playingMedia, self.duration > 1 {
                    let prog = min(1.0, max(0.05, self.currentTime / self.duration))
                    if let idx = self.continueWatching.firstIndex(where: { $0.id == cur.id && $0.mediaType == cur.mediaType }) {
                        self.continueWatching[idx].watchProgress = prog
                    }
                }
            }
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem, mediaId: Int) {
        itemStatusObserver?.invalidate()
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if observed.status == .readyToPlay {
                    self.isBuffering = false
                    if self.isPlaying && self.player.timeControlStatus == .paused {
                        self.player.play()
                        self.player.rate = self.playbackSpeed
                    }
                    NFDebugLogger.shared.log(.player, tag: "ItemStatus", "media \(mediaId) readyToPlay (\(Int(observed.presentationSize.width))x\(Int(observed.presentationSize.height)))")
                } else if observed.status == .failed {
                    let err = observed.error?.localizedDescription ?? "Unknown error"
                    NFDebugLogger.shared.log(.error, tag: "ItemStatus", "media \(mediaId) FAILED: \(err)")
                    self.isBuffering = false
                }
            }
        }
    }

    public func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            self.toastMessage = message
        }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { self.toastMessage = nil }
        }
    }
}
