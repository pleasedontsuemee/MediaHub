import Foundation
import SwiftUI
import AVFoundation
import MediaPlayer

#if canImport(UIKit)
import UIKit
#endif

public enum SPTab: Int, CaseIterable {
    case home = 0
    case search = 1
    case library = 2
    case premium = 3
}

@MainActor
public final class SPAppViewModel: ObservableObject {
    // Navigation
    @Published public var selectedTab: SPTab = .home
    @Published public var isNowPlayingPresented: Bool = false
    @Published public var isCreatePlaylistPresented: Bool = false
    @Published public var trackToAddToPlaylist: SPTrack? = nil
    @Published public var trackOptionsTarget: SPTrack? = nil
    @Published public var selectedCollection: SPCollection? = nil

    // Catalog Data
    @Published public var topTracks: [SPTrack] = []
    @Published public var homePlaylists: [SPCollection] = []
    @Published public var homeAlbums: [SPCollection] = []
    @Published public var homeArtists: [SPCollection] = []
    @Published public var homePodcasts: [SPCollection] = []
    @Published public var isLoadingHome: Bool = true

    // Deezer ARL Cookie
    @Published public var deezerARL: String = UserDefaults.standard.string(forKey: "sp_deezer_arl") ?? ""
    @Published public var arlStatusMessage: String = ""

    // Search
    @Published public var searchQuery: String = ""
    @Published public var searchTracks: [SPTrack] = []
    @Published public var searchAlbums: [SPCollection] = []
    @Published public var searchArtists: [SPCollection] = []
    @Published public var searchPlaylists: [SPCollection] = []
    @Published public var searchPodcasts: [SPCollection] = []
    @Published public var isSearching: Bool = false
    private var searchDebounceTask: Task<Void, Never>?

    // User Library
    @Published public var likedTracks: [SPTrack] = []
    @Published public var userPlaylists: [SPCollection] = []
    @Published public var recentlyPlayed: [SPTrack] = []

    // Player & Skyrock Mode
    public let player = AVPlayer()
    private var jinglePlayer: AVAudioPlayer?
    private var skyrockTask: Task<Void, Never>?

    @Published public var currentTrack: SPTrack? = nil
    @Published public var currentContextTitle: String = "Titres populaires"
    @Published public var queue: [SPTrack] = []
    @Published public var isPlaying: Bool = false
    @Published public var isBuffering: Bool = false
    @Published public var isShuffleEnabled: Bool = false
    @Published public var isRepeatEnabled: Bool = false
    @Published public var isSkyrockMode: Bool = false
    @Published public var isSkyrockTransitioning: Bool = false
    @Published public var currentStreamLabel: String = ""
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 1

    @Published public var toastMessage: String? = nil
    private var toastTask: Task<Void, Never>?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var itemStatusObserver: NSKeyValueObservation?
    private var cachedArtwork: MPMediaItemArtwork?
    private var cachedArtworkId: String?
    private let stateURL: URL

    public let skyRate: Float = 1.025

    private struct PersistedState: Codable {
        var likedTracks: [SPTrack]
        var userPlaylists: [SPCollection]
        var recentlyPlayed: [SPTrack]
    }

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.stateURL = docs.appendingPathComponent("sp_user_state_v1.json")

        SPFontManager.registerBundledFonts()
        configureAudioSession()
        setupRemoteCommandCenter()
        loadState()
        setupPlayerObservers()

        Task {
            await loadHomeFeed()
        }
    }

    // MARK: - Persistence
    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL),
              let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        self.likedTracks = decoded.likedTracks
        self.userPlaylists = decoded.userPlaylists
        self.recentlyPlayed = decoded.recentlyPlayed
    }

    public func saveState() {
        let s = PersistedState(likedTracks: likedTracks, userPlaylists: userPlaylists, recentlyPlayed: recentlyPlayed)
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    // MARK: - Catalog, ARL & Search
    public func saveAndValidateARL(_ raw: String) {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        self.deezerARL = cleaned
        self.arlStatusMessage = "Vérification..."
        Task {
            await SPMusicEngine.shared.updateARL(cleaned)
            if cleaned.isEmpty {
                self.arlStatusMessage = "Aucun ARL configuré"
                self.showToast("ARL supprimé")
                return
            }
            let res = await SPMusicEngine.shared.validateARL()
            if res.ok {
                self.arlStatusMessage = "Connecté (\(res.userName ?? "Deezer"))"
                self.showToast("ARL valide : \(res.userName ?? "Connecté")")
            } else {
                self.arlStatusMessage = "ARL invalide ou expiré"
                self.showToast("ARL invalide ou expiré")
            }
        }
    }

    public func loadHomeFeed() async {
        isLoadingHome = true
        let (tracks, playlists, albums, artists, podcasts) = await SPMusicEngine.shared.fetchHomeFeed()
        self.topTracks = tracks
        self.homePlaylists = playlists
        self.homeAlbums = albums
        self.homeArtists = artists
        self.homePodcasts = podcasts
        self.isLoadingHome = false
    }

    public func performSearch(_ q: String, immediate: Bool = false) {
        searchQuery = q
        searchDebounceTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchTracks = []
            searchAlbums = []
            searchArtists = []
            searchPlaylists = []
            searchPodcasts = []
            isSearching = false
            return
        }
        isSearching = true
        searchDebounceTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            guard !Task.isCancelled else { return }
            let (t, a, ar, p, pod) = await SPMusicEngine.shared.search(query: trimmed)
            if self.searchQuery == q {
                self.searchTracks = t
                self.searchAlbums = a
                self.searchArtists = ar
                self.searchPlaylists = p
                self.searchPodcasts = pod
                self.isSearching = false
            }
        }
    }

    // MARK: - Library & Playlists
    public func isLiked(_ track: SPTrack) -> Bool {
        likedTracks.contains { $0.id == track.id }
    }

    public func toggleLike(_ track: SPTrack) {
        if isLiked(track) {
            likedTracks.removeAll { $0.id == track.id }
            showToast("Retiré des Titres likés")
        } else {
            likedTracks.insert(track, at: 0)
            showToast("Ajouté aux Titres likés")
        }
        saveState()
    }

    public func createPlaylist(name: String, initialTrack: SPTrack? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let tracks = initialTrack.map { [$0] } ?? []
        let pl = SPCollection(
            id: UUID().uuidString,
            kind: .playlist,
            title: trimmed,
            subtitle: "Playlist • Vous",
            coverURLString: initialTrack?.coverURLString,
            tracks: tracks,
            isUserCreated: true
        )
        userPlaylists.insert(pl, at: 0)
        saveState()
        showToast("Playlist « \(trimmed) » créée")
    }

    public func addTrack(_ track: SPTrack, toPlaylist playlistId: String) {
        guard let idx = userPlaylists.firstIndex(where: { $0.id == playlistId }) else { return }
        if !userPlaylists[idx].tracks.contains(where: { $0.id == track.id }) {
            userPlaylists[idx].tracks.append(track)
            if userPlaylists[idx].coverURLString == nil {
                userPlaylists[idx] = SPCollection(
                    id: userPlaylists[idx].id,
                    kind: .playlist,
                    title: userPlaylists[idx].title,
                    subtitle: userPlaylists[idx].subtitle,
                    coverURLString: track.coverURLString,
                    tracks: userPlaylists[idx].tracks,
                    isUserCreated: true
                )
            }
            saveState()
            showToast("Ajouté à \(userPlaylists[idx].title)")
        } else {
            showToast("Déjà dans \(userPlaylists[idx].title)")
        }
    }

    public func openArtist(id: String?, name: String) {
        guard let aid = id, !aid.isEmpty else {
            showToast("Page artiste indisponible")
            return
        }
        let col = SPCollection(id: aid, kind: .artist, title: name, subtitle: "Artiste")
        if isNowPlayingPresented {
            isNowPlayingPresented = false
            Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                self.selectedCollection = col
            }
        } else {
            selectedCollection = col
        }
    }

    public func openAlbum(id: String?, title: String, coverURL: String? = nil, artistName: String = "") {
        guard let alId = id, !alId.isEmpty else {
            showToast("Page album indisponible")
            return
        }
        let col = SPCollection(id: alId, kind: .album, title: title.isEmpty ? "Album" : title, subtitle: artistName, coverURLString: coverURL)
        if isNowPlayingPresented {
            isNowPlayingPresented = false
            Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                self.selectedCollection = col
            }
        } else {
            selectedCollection = col
        }
    }

    // MARK: - Audio Playback + Skyrock Radio Jingle & 1.025x Pitch
    public func playTrack(_ track: SPTrack, queue newQueue: [SPTrack]? = nil, contextTitle: String? = nil) {
        skyrockTask?.cancel()
        stopJingle()

        if let q = newQueue {
            self.queue = q
        } else if self.queue.isEmpty {
            self.queue = topTracks
        }
        if let ctx = contextTitle {
            self.currentContextTitle = ctx
        }

        self.currentTrack = track
        self.isBuffering = true
        self.currentTime = 0
        self.duration = TimeInterval(max(1, track.durationSeconds))
        self.isPlaying = true

        recentlyPlayed.removeAll { $0.id == track.id }
        recentlyPlayed.insert(track, at: 0)
        if recentlyPlayed.count > 20 { recentlyPlayed = Array(recentlyPlayed.prefix(20)) }
        saveState()

        if isSkyrockMode {
            playWithSkyrockTransition(track: track)
        } else {
            Task { await loadAndPlayTrack(track, fadeIn: false) }
        }
    }

    public func toggleSkyrockMode() {
        isSkyrockMode.toggle()
        if isSkyrockMode {
            showToast("Mode Skyrock activé (Jingle + 1.025x)")
            if let track = currentTrack {
                playWithSkyrockTransition(track: track)
            }
        } else {
            skyrockTask?.cancel()
            stopJingle()
            isSkyrockTransitioning = false
            player.volume = 1.0
            player.currentItem?.audioTimePitchAlgorithm = .timeDomain
            if isPlaying {
                player.rate = 1.0
            }
            showToast("Mode Skyrock désactivé")
        }
        updateNowPlayingInfo()
    }

    private func playWithSkyrockTransition(track: SPTrack) {
        skyrockTask?.cancel()
        stopJingle()

        guard let jingleURL = SPResourceBundle.url(forResource: "skyrock", withExtension: "mp3"),
              let jp = try? AVAudioPlayer(contentsOf: jingleURL) else {
            Task { await loadAndPlayTrack(track, fadeIn: false) }
            return
        }

        isSkyrockTransitioning = true
        player.pause()
        player.volume = 0.0

        jp.volume = 1.0
        jp.prepareToPlay()
        jp.play()
        self.jinglePlayer = jp

        let jingleDuration = jp.duration
        let crossfadeDuration: TimeInterval = min(0.65, jingleDuration * 0.35)
        let waitBeforeCrossfade = max(0.1, jingleDuration - crossfadeDuration)

        skyrockTask = Task { [weak self] in
            guard let self = self else { return }

            // Resolve & prepare the main track silently while jingle plays
            async let streamTask: Void = self.prepareTrackWithoutPlaying(track)
            try? await Task.sleep(nanoseconds: UInt64(waitBeforeCrossfade * 1_000_000_000))
            _ = await streamTask
            guard !Task.isCancelled else { return }

            // Smooth 0.65s crossfade at the very end of the Skyrock jingle to introduce the track
            self.player.volume = 0.0
            if let item = self.player.currentItem {
                item.audioTimePitchAlgorithm = .varispeed
            }
            self.player.play()
            self.player.rate = self.skyRate
            self.isPlaying = true

            let steps = 16
            let stepNs = UInt64((crossfadeDuration / Double(steps)) * 1_000_000_000)
            for i in 1...steps {
                guard !Task.isCancelled else { return }
                let progress = Float(i) / Float(steps)
                self.jinglePlayer?.volume = max(0, 1.0 - progress)
                self.player.volume = min(1.0, progress)
                try? await Task.sleep(nanoseconds: stepNs)
            }

            self.stopJingle()
            self.player.volume = 1.0
            self.isSkyrockTransitioning = false
            self.updateNowPlayingInfo(fetchArtwork: true)
        }
    }

    private func stopJingle() {
        jinglePlayer?.stop()
        jinglePlayer = nil
    }

    private func prepareTrackWithoutPlaying(_ track: SPTrack) async {
        guard let item = await buildPlayerItem(for: track) else { return }
        item.audioTimePitchAlgorithm = isSkyrockMode ? .varispeed : .timeDomain
        observePlayerItem(item, trackId: track.id)
        player.replaceCurrentItem(with: item)
    }

    private func loadAndPlayTrack(_ track: SPTrack, fadeIn: Bool) async {
        guard let item = await buildPlayerItem(for: track) else {
            self.isBuffering = false
            self.isPlaying = false
            self.showToast("Impossible de charger ce titre")
            return
        }
        item.audioTimePitchAlgorithm = isSkyrockMode ? .varispeed : .timeDomain
        observePlayerItem(item, trackId: track.id)
        player.replaceCurrentItem(with: item)
        player.volume = fadeIn ? 0.0 : 1.0
        player.play()
        player.rate = isSkyrockMode ? skyRate : 1.0
        isPlaying = true
        updateNowPlayingInfo(fetchArtwork: true)
    }

    private func buildPlayerItem(for track: SPTrack) async -> AVPlayerItem? {
        if let localURL = SPOfflineDownloadManager.localFileURL(for: track.id) {
            self.currentStreamLabel = "Hors-ligne"
            return AVPlayerItem(url: localURL)
        }
        guard let stream = await SPMusicEngine.shared.resolveAudioStream(for: track) else {
            return nil
        }
        self.currentStreamLabel = stream.sourceName
        let headers = ["User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X)"]
        let asset = AVURLAsset(url: stream.url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 5.0
        return item
    }

    public func togglePlayPause() {
        if isPlaying {
            player.pause()
            jinglePlayer?.pause()
            isPlaying = false
        } else {
            player.play()
            player.rate = isSkyrockMode ? skyRate : 1.0
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

    public func nextTrack() {
        guard !queue.isEmpty else { return }
        if isShuffleEnabled {
            if let next = queue.randomElement() {
                playTrack(next)
            }
            return
        }
        guard let cur = currentTrack, let idx = queue.firstIndex(where: { $0.id == cur.id }) else {
            if let first = queue.first { playTrack(first) }
            return
        }
        let nextIdx = (idx + 1) % queue.count
        playTrack(queue[nextIdx])
    }

    public func previousTrack() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty, let cur = currentTrack, let idx = queue.firstIndex(where: { $0.id == cur.id }) else {
            seek(to: 0)
            return
        }
        let prevIdx = (idx - 1 + queue.count) % queue.count
        playTrack(queue[prevIdx])
    }

    // MARK: - Audio Session & Lock Screen / Dynamic Island
    private func configureAudioSession() {
        #if canImport(UIKit)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
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
                if self?.isPlaying == false { self?.togglePlayPause() }
            }
            return .success
        }
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                if self?.isPlaying == true { self?.togglePlayPause() }
            }
            return .success
        }
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.nextTrack() }
            return .success
        }
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.previousTrack() }
            return .success
        }
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] ev in
            guard let pe = ev as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in self?.seek(to: pe.positionTime) }
            return .success
        }
    }

    public func updateNowPlayingInfo(fetchArtwork: Bool = false) {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: isSkyrockMode ? "\(track.title) (Skyrock)" : track.title,
            MPMediaItemPropertyArtist: track.artistName,
            MPMediaItemPropertyAlbumTitle: track.albumTitle,
            MPMediaItemPropertyPlaybackDuration: max(1, duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(isSkyrockMode ? skyRate : 1.0) : 0.0
        ]
        if cachedArtworkId == track.id, let art = cachedArtwork {
            info[MPMediaItemPropertyArtwork] = art
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if fetchArtwork, cachedArtworkId != track.id, let url = track.coverURL {
            let tid = track.id
            Task {
                #if canImport(UIKit)
                if let img = await SPImageCache.shared.image(for: url) {
                    let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                    await MainActor.run {
                        self.cachedArtworkId = tid
                        self.cachedArtwork = art
                        self.updateNowPlayingInfo(fetchArtwork: false)
                    }
                }
                #endif
            }
        }
    }

    private func setupPlayerObservers() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let sec = CMTimeGetSeconds(t)
                if sec.isFinite && sec >= 0 { self.currentTime = sec }
                if let item = self.player.currentItem {
                    let dur = CMTimeGetSeconds(item.duration)
                    if dur.isFinite && dur > 0 { self.duration = dur }
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.isRepeatEnabled {
                    self.seek(to: 0)
                    self.player.play()
                    self.player.rate = self.isSkyrockMode ? self.skyRate : 1.0
                } else {
                    self.nextTrack()
                }
            }
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem, trackId: String) {
        itemStatusObserver?.invalidate()
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if observed.status == .readyToPlay {
                    self.isBuffering = false
                } else if observed.status == .failed {
                    self.isBuffering = false
                    self.isPlaying = false
                    self.showToast("Erreur de lecture du flux audio")
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
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { self.toastMessage = nil }
        }
    }
}
