import Foundation
import SwiftUI
import AVFoundation
import AVKit
import Network
import MediaPlayer

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Navigation Destination Enum
public enum YTNavigationRoute: Hashable {
    case channel(YTChannel)
    case allSubscriptions
    case trending(initialTab: String)
    case liveHub
    case yourVideos
    case downloads
    case playlistDetail(YTPlaylist)
    case timeWatched
    case searchResults(query: String)
}

// MARK: - Main Tab Enum (`YTPivotBarView` 5 items)
public enum YTMainTab: Int, CaseIterable {
    case home = 0
    case shorts = 1
    case create = 2
    case subscriptions = 3
    case library = 4
}

// MARK: - Global App & Player ViewModel
@MainActor
public final class YTAppViewModel: ObservableObject {

    // Navigation & Tabs
    @Published public var selectedTab: YTMainTab = .home
    @Published public var homeNavigationPath: [YTNavigationRoute] = []
    @Published public var subscriptionsNavigationPath: [YTNavigationRoute] = []
    @Published public var libraryNavigationPath: [YTNavigationRoute] = []

    // Drawers, Sheets & Overlays
    @Published public var isExploreDrawerOpen: Bool = false
    @Published public var isSearchOverlayPresented: Bool = false
    @Published public var isCreateSheetPresented: Bool = false
    @Published public var isAccountSheetPresented: Bool = false
    @Published public var isSettingsPresented: Bool = false
    @Published public var isHelpPresented: Bool = false
    @Published public var isHelpArticlePresented: Bool = false
    @Published public var isSaveToPlaylistSheetPresented: Bool = false
    @Published public var videoToSave: YTVideo?
    @Published public var isCastAlertPresented: Bool = false
    @Published public var isNotificationsSheetPresented: Bool = false

    // Appearance & Settings (`Settings > General`)
    @AppStorage("yt_appearance_mode") public var appearanceMode: String = "Light theme"
    @AppStorage("yt_is_premium_header") public var isPremiumHeader: Bool = true
    @AppStorage("yt_is_incognito") public var isIncognito: Bool = false
    @AppStorage("yt_autoplay_enabled") public var isAutoplayEnabled: Bool = true
    @AppStorage("yt_pip_enabled") public var isPiPEnabled: Bool = true
    @AppStorage("yt_skip_seconds") public var skipSeconds: Int = 10
    @AppStorage("yt_zoom_to_fill") public var zoomToFillScreen: Bool = false
    @AppStorage("yt_show_info_cards") public var showInVideoInfoCards: Bool = true
    @AppStorage("yt_restricted_mode") public var restrictedMode: Bool = false
    @AppStorage("yt_bedtime_reminder") public var bedtimeReminderEnabled: Bool = false
    @AppStorage("yt_break_reminder") public var breakReminderEnabled: Bool = false
    @AppStorage("yt_break_reminder_hours") public var breakReminderHours: Int = 0
    @AppStorage("yt_break_reminder_minutes") public var breakReminderMinutes: Int = 15
    @AppStorage("yt_stats_for_nerds") public var statsForNerdsEnabled: Bool = false
    @AppStorage("yt_custom_piped_url") public var customPipedInstanceURL: String = ""
    @AppStorage("yt_user_display_name") public var userDisplayName: String = "Mon compte"
    @AppStorage("yt_user_handle") public var userHandle: String = "@utilisateur"
    @AppStorage("yt_wifi_default_quality") public var wifiDefaultQuality: String = "Auto (recommended)"
    @AppStorage("yt_cellular_default_quality") public var cellularDefaultQuality: String = "720p"
    @AppStorage("yt_background_playback") public var backgroundPlaybackEnabled: Bool = true
    @AppStorage("yt_inline_feed_playback") public var inlineFeedPlayback: Bool = true
    @AppStorage("yt_offline_quality") public var offlineDownloadQuality: String = "1080p"
    @Published public var isOnWiFi: Bool = true
    private let pathMonitor = NWPathMonitor()

    // Feed Data & Filter Chips (Dynamic & Personalized)
    @Published public var selectedHomeChip: String = "All"
    @Published public var selectedSubscriptionsChip: String = "All"
    @Published public var homeVideos: [YTVideo] = []
    @Published public var shortsShelfVideos: [YTVideo] = []
    @Published public var subscriptionFeedVideos: [YTVideo] = []
    @Published public var isLoadingFeed: Bool = true
    @Published public var isLoadingShorts: Bool = false
    @Published public var isLoadingSubscriptionsFeed: Bool = false

    // User Watch Profile Keywords (Builds dynamically as the user watches/searches videos)
    @Published public var watchProfileKeywords: [String] = []

    // Channels & Subscriptions — Starts EMPTY until the user subscribes to channels!
    @Published public var channels: [YTChannel] = []
    @Published public var lastUnsubscribedChannel: YTChannel?

    // Library: Watch History & Your Videos — Starts EMPTY until the user watches videos!
    @Published public var watchHistory: [YTVideo] = []
    @Published public var playlists: [YTPlaylist] = [
        YTPlaylist(
            id: "WL",
            title: "Watch later",
            isPrivate: true,
            videos: [],
            isSystemPlaylist: true
        )
    ]

    // Search State & History
    @Published public var searchQuery: String = ""
    @Published public var activeSubmittedQuery: String = ""
    @Published public var searchHistory: [String] = []
    @Published public var searchSuggestions: [String] = []
    @Published public var searchResults: [YTVideo] = []
    @Published public var isSearching: Bool = false
    @Published public var searchFilters: YTSearchFilters = YTSearchFilters()
    @Published public var selectedSearchChip: String = "All"

    // Watch / Mini-Player / Fullscreen Player State (`YTWatchView`)
    @Published public var currentVideo: YTVideo? = nil
    @Published public var isPlayerExpanded: Bool = false
    @Published public var isFullscreenLandscape: Bool = false
    @Published public var playerDragOffset: CGFloat = 0

    // Main AVPlayer (for Watch View & Mini-Player) + Synchronized Audio Player (for Adaptive 144p..4K 2160p streams) + Shorts AVPlayer
    public let player = AVPlayer()
    public let audioPlayer = AVPlayer()
    public var hasSeparateAudioTrack: Bool = false
    @Published public var activeVideoAspectRatio: CGFloat = 16.0 / 9.0
    @Published public var activeResolutionDimensionsText: String = ""
    public let shortsPlayer = AVPlayer()
    @Published public var activeShortIndex: Int = 0
    @Published public var isShortsPlaying: Bool = false

    @Published public var isPlaying: Bool = false
    @Published public var isBuffering: Bool = false
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 1
    @Published public var showPlayerControlsOverlay: Bool = false
    @Published public var selectedQuality: String = "Auto (recommended)"
    @Published public var availableQualities: [String] = ["Auto (recommended)", "1080p", "720p", "480p", "360p"]
    @Published public var playbackSpeed: Float = 1.0
    @Published public var isLoopVideoEnabled: Bool = false
    @Published public var availableCaptionTracks: [YTCaptionTrack] = []
    @Published public var selectedCaptionLanguage: String = "Off"
    @Published public var captionCues: [YTCaptionCue] = []
    @Published public var currentCaptionText: String?

    // Watch Page Engagement State
    @Published public var likedVideoIds: Set<String> = []
    @Published public var dislikedVideoIds: Set<String> = []
    @Published public var relatedVideos: [YTVideo] = []
    @Published public var currentComments: [YTComment] = []
    @Published public var isLoadingCommentsAndRelated: Bool = false
    @Published public var liveChatMessages: [YTLiveChatMessage] = YTCatalogData.liveChatMessages

    // Engagement Panels (Sheets inside Watch View under the 16:9 player)
    public enum ActiveEngagementPanel: Equatable {
        case none
        case description
        case comments
        case liveChat
    }
    @Published public var activeEngagementPanel: ActiveEngagementPanel = .none
    @Published public var isPlayerOptionsSheetPresented: Bool = false
    @Published public var isQualityPickerSheetPresented: Bool = false
    @Published public var isCaptionsPickerSheetPresented: Bool = false
    @Published public var isSpeedPickerSheetPresented: Bool = false

    // Snackbar / Toast (`YTHUDMessageView`)
    @Published public var toastMessage: String?
    @Published public var toastActionTitle: String?
    private var toastActionHandler: (() -> Void)?
    private var toastTask: Task<Void, Never>?

    private var timeObserverToken: Any?
    private var playerStatusObserver: NSKeyValueObservation?
    private var shortsStatusObserver: NSKeyValueObservation?
    private var itemStatusObserver: NSKeyValueObservation?
    private var didDisableIdleTimer: Bool = false
    private var currentPlaybackBundle: YTResolvedVideoPlayback?
    private var controlsAutoHideTask: Task<Void, Never>?
    private let stateStorageURL: URL

    private struct PersistedUserState: Codable {
        var channels: [YTChannel]
        var watchHistory: [YTVideo]
        var playlists: [YTPlaylist]
        var searchHistory: [String]
        var watchProfileKeywords: [String]
        var likedVideoIds: [String]
    }

    private var pendingQualitySeekTime: Double?
    private var pendingQualityShouldPlay: Bool = false
    private var streamRecoveryCounts: [String: Int] = [:]
    private var itemFailureFallbackStage: [String: Int] = [:]
    private var isRecoveringStream: Bool = false

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.stateStorageURL = docs.appendingPathComponent("yt_user_state_v2.json")

        // Standard HLS buffering with 5s forward buffer so AVPlayer starts as soon as the first 5s chunk arrives and never drops to .paused!
        player.automaticallyWaitsToMinimizeStalling = true
        player.preventsDisplaySleepDuringVideoPlayback = true
        audioPlayer.automaticallyWaitsToMinimizeStalling = true
        shortsPlayer.automaticallyWaitsToMinimizeStalling = true
        shortsPlayer.preventsDisplaySleepDuringVideoPlayback = true

        YTFontManager.registerBundledFonts()
        configureAudioSessionForBackgroundAndPiP()
        setupRemoteCommandCenter()
        loadPersistedUserState()
        setupPlayerTimeObserver()

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let wifi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
            Task { @MainActor [weak self] in
                self?.isOnWiFi = wifi
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.ytmine.netmonitor"))

        // Fetch live initial Home feed & Shorts from YouTube InnerTube
        Task {
            await refreshHomeFeed()
        }
    }

    // MARK: - Persistence of User History, Subscriptions, Playlists & Profile Keywords
    private func loadPersistedUserState() {
        guard let data = try? Data(contentsOf: stateStorageURL),
              let decoded = try? JSONDecoder().decode(PersistedUserState.self, from: data) else {
            return
        }
        self.channels = decoded.channels
        self.watchHistory = decoded.watchHistory
        if !decoded.playlists.isEmpty {
            self.playlists = decoded.playlists
        }
        self.searchHistory = decoded.searchHistory
        self.watchProfileKeywords = decoded.watchProfileKeywords
        self.likedVideoIds = Set(decoded.likedVideoIds)
    }

    public func savePersistedUserState() {
        let state = PersistedUserState(
            channels: channels,
            watchHistory: watchHistory,
            playlists: playlists,
            searchHistory: searchHistory,
            watchProfileKeywords: watchProfileKeywords,
            likedVideoIds: Array(likedVideoIds)
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateStorageURL, options: .atomic)
        }
    }

    private func recordInterest(from video: YTVideo) {
        let extracted = YTInnerTubeEngine.extractTopicKeywords(from: video.title)
        let topic = "\(video.channelTitle) \(extracted)".trimmingCharacters(in: .whitespaces)
        guard !topic.isEmpty else { return }
        watchProfileKeywords.removeAll { $0.lowercased() == topic.lowercased() }
        watchProfileKeywords.insert(topic, at: 0)
        if watchProfileKeywords.count > 10 {
            watchProfileKeywords = Array(watchProfileKeywords.prefix(10))
        }
        savePersistedUserState()
    }

    // MARK: - Color Scheme Resolution
    public var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "Light theme": return .light
        case "Dark theme": return .dark
        default: return nil
        }
    }

    // MARK: - Audio Session & Now Playing Info (Background Audio, Dynamic Island, Lock Screen & Control Center)
    private var cachedNowPlayingArtwork: MPMediaItemArtwork?
    private var cachedArtworkVideoId: String?

    private func configureAudioSessionForBackgroundAndPiP() {
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
                guard let self = self else { return }
                if self.player.timeControlStatus == .paused {
                    self.togglePlayPause()
                }
            }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.player.timeControlStatus != .paused {
                    self.togglePlayPause()
                }
            }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.togglePlayPause()
            }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.seek(to: posEvent.positionTime)
            }
            return .success
        }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipSeconds)]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skipForward()
            }
            return .success
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipSeconds)]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skipBackward()
            }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                if let next = self?.relatedVideos.first {
                    self?.openVideo(next)
                }
            }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.seek(to: 0)
            }
            return .success
        }
    }

    public func updateNowPlayingInfo(fetchArtwork: Bool = false) {
        guard let video = currentVideo else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: video.title,
            MPMediaItemPropertyArtist: video.channelTitle,
            MPMediaItemPropertyPlaybackDuration: max(1, duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackSpeed) : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue
        ]

        if cachedArtworkVideoId == video.id, let art = cachedNowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = art
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if fetchArtwork, cachedArtworkVideoId != video.id, let thumbURL = video.thumbnailURL {
            let vid = video.id
            Task {
                #if canImport(UIKit)
                if let img = await YTImageCache.shared.image(for: thumbURL) {
                    let artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                    await MainActor.run {
                        self.cachedArtworkVideoId = vid
                        self.cachedNowPlayingArtwork = artwork
                        self.updateNowPlayingInfo(fetchArtwork: false)
                    }
                }
                #endif
            }
        }
    }

    private func updateIdleTimer() {
        #if canImport(UIKit)
        let isForeground = UIApplication.shared.applicationState == .active
        let mainActive = (currentVideo != nil) && (player.timeControlStatus == .playing || (isPlaying && player.timeControlStatus == .waitingToPlayAtSpecifiedRate))
        let shortsActive = (selectedTab == .shorts) && isShortsPlaying && (shortsPlayer.timeControlStatus != .paused)
        let keepAwake = isForeground && (mainActive || shortsActive)
        if keepAwake {
            if !UIApplication.shared.isIdleTimerDisabled {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            didDisableIdleTimer = true
        } else if didDisableIdleTimer {
            UIApplication.shared.isIdleTimerDisabled = false
            didDisableIdleTimer = false
        }
        #endif
    }

    private func setupPlayerTimeObserver() {
        playerStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let stateStr: String
                switch p.timeControlStatus {
                case .paused:
                    stateStr = "paused"
                case .waitingToPlayAtSpecifiedRate:
                    let reason = p.reasonForWaitingToPlay?.rawValue ?? "unknown"
                    stateStr = "waiting(\(reason))"
                case .playing:
                    stateStr = "playing"
                    self.isBuffering = false
                @unknown default:
                    stateStr = "unknown"
                }
                self.updateIdleTimer()
                YTDebugLogger.shared.log(.player, tag: "AVPlayer", "timeControlStatus -> \(stateStr)")
                YTDebugLogger.shared.updatePlayerSummary("State: \(stateStr) | Quality: \(self.activeResolutionDimensionsText) | HLS Port: \(YTSequentialStreamServer.shared.listeningPort)")
            }
        }

        shortsStatusObserver = shortsPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updateIdleTimer()
            }
        }

        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateIdleTimer()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.didDisableIdleTimer {
                    UIApplication.shared.isIdleTimerDisabled = false
                    self.didDisableIdleTimer = false
                }
            }
        }
        #endif

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let sec = CMTimeGetSeconds(time)
                if sec.isFinite && sec >= 0 {
                    self.currentTime = sec
                }
                if let item = self.player.currentItem {
                    let dur = CMTimeGetSeconds(item.duration)
                    if dur.isFinite && dur > 0 {
                        self.duration = dur
                    }
                }
                // Update watch progress in watchHistory
                if let cur = self.currentVideo, self.duration > 1 {
                    let prog = min(1.0, max(0.05, self.currentTime / self.duration))
                    if let idx = self.watchHistory.firstIndex(where: { $0.id == cur.id }) {
                        self.watchHistory[idx].watchProgress = prog
                    }
                }
                // Keep separate adaptive audio track synchronized within 0.15s of video player
                if self.hasSeparateAudioTrack && self.isPlaying {
                    let aSec = CMTimeGetSeconds(self.audioPlayer.currentTime())
                    if aSec.isFinite && abs(aSec - self.currentTime) > 0.25 {
                        self.audioPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                    if self.audioPlayer.rate == 0 {
                        self.audioPlayer.play()
                        self.audioPlayer.rate = self.playbackSpeed
                    }
                }
                self.updateActiveCaptionCue()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let item = note.object as? AVPlayerItem,
                      item === self.player.currentItem,
                      let vid = self.currentVideo?.id else { return }
                YTDebugLogger.shared.log(.stream, tag: "AVPlayer", "PlaybackStalled for \(vid) at \(String(format: "%.1fs", self.currentTime))")
                self.isBuffering = true
                // Give AVPlayer 3.5s to resume; if still stuck, refresh stream URLs at current timestamp
                let stalledAt = self.currentTime
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                if self.currentVideo?.id == vid && self.isPlaying && self.player.timeControlStatus != .playing && abs(self.currentTime - stalledAt) < 0.5 {
                    await self.recoverStreamAtCurrentPosition(for: vid)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let item = note.object as? AVPlayerItem,
                      item === self.player.currentItem,
                      let vid = self.currentVideo?.id else { return }
                YTDebugLogger.shared.log(.error, tag: "AVPlayer", "FailedToPlayToEndTime for \(vid) at \(String(format: "%.1fs", self.currentTime))")
                await self.recoverStreamAtCurrentPosition(for: vid)
            }
        }

        NotificationCenter.default.addObserver(
            forName: YTSequentialStreamServer.streamNeedsRefreshNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let vid = note.userInfo?["videoId"] as? String,
                      vid == self.currentVideo?.id else { return }
                let segIdx = (note.userInfo?["segIndex"] as? Int) ?? -1
                let isAudio = (note.userInfo?["isAudio"] as? Bool) ?? false
                let approxSegTime = Double(max(0, segIdx)) * (isAudio ? 10.0 : 5.2)
                // Never interrupt smooth active playback for a far-ahead lookahead segment (>25s ahead)
                if self.player.timeControlStatus == .playing && segIdx >= 0 && (approxSegTime - self.currentTime) > 25.0 {
                    YTDebugLogger.shared.log(.stream, tag: "Recovery", "Deferred refresh for \(vid) seg=\(segIdx) (~\(Int(approxSegTime))s) while playing at \(String(format: "%.1fs", self.currentTime))")
                    return
                }
                await self.recoverStreamAtCurrentPosition(for: vid)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let item = note.object as? AVPlayerItem, item === self.shortsPlayer.currentItem {
                    // Loop active Short automatically
                    await self.shortsPlayer.seek(to: .zero)
                    self.shortsPlayer.play()
                    return
                }
                guard let endedItem = note.object as? AVPlayerItem, endedItem === self.player.currentItem else {
                    return
                }
                // Guard against premature end-of-stream from HTTP drop mid-video
                if self.duration > 15 && self.currentTime < self.duration - 5.0 {
                    if let vid = self.currentVideo?.id {
                        YTDebugLogger.shared.log(.stream, tag: "AVPlayer", "Premature DidPlayToEndTime at \(String(format: "%.1fs", self.currentTime))/\(String(format: "%.1fs", self.duration)) — recovering")
                        await self.recoverStreamAtCurrentPosition(for: vid)
                        return
                    }
                }
                if self.isLoopVideoEnabled {
                    self.seek(to: 0)
                    self.player.play()
                } else if self.isAutoplayEnabled, let nextVideo = self.relatedVideos.first {
                    self.openVideo(nextVideo)
                } else {
                    self.isPlaying = false
                }
            }
        }
    }

    private func updateActiveCaptionCue() {
        guard selectedCaptionLanguage != "Off", !captionCues.isEmpty else {
            currentCaptionText = nil
            return
        }
        if let cue = captionCues.first(where: { currentTime >= $0.startTime && currentTime <= $0.endTime }) {
            currentCaptionText = cue.text
        } else {
            currentCaptionText = nil
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem, videoId: String) {
        itemStatusObserver?.invalidate()
        itemStatusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch observedItem.status {
                case .unknown:
                    YTDebugLogger.shared.log(.player, tag: "ItemStatus", "\(videoId) -> unknown")
                case .readyToPlay:
                    let dur = CMTimeGetSeconds(observedItem.duration)
                    let presSize = observedItem.presentationSize
                    YTDebugLogger.shared.log(.player, tag: "ItemStatus", "\(videoId) -> readyToPlay (duration: \(dur.isFinite ? String(format: "%.1fs", dur) : "live/unknown"), presentationSize: \(Int(presSize.width))x\(Int(presSize.height)))")
                    self.isBuffering = false
                    if presSize.height > 0 && self.selectedQuality == "Auto (recommended)" {
                        self.activeResolutionDimensionsText = "Auto · \(Int(presSize.height))p"
                    }
                    if let seekTarget = self.pendingQualitySeekTime {
                        self.pendingQualitySeekTime = nil
                        let shouldPlay = self.pendingQualityShouldPlay || self.isPlaying
                        self.pendingQualityShouldPlay = false
                        let cmTime = CMTime(seconds: seekTarget, preferredTimescale: 600)
                        self.player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                            Task { @MainActor [weak self] in
                                guard let self = self else { return }
                                if shouldPlay {
                                    self.player.play()
                                    self.player.rate = self.playbackSpeed
                                }
                            }
                        }
                        if self.hasSeparateAudioTrack {
                            self.audioPlayer.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                                Task { @MainActor [weak self] in
                                    guard let self = self else { return }
                                    if shouldPlay {
                                        self.audioPlayer.play()
                                        self.audioPlayer.rate = self.playbackSpeed
                                    }
                                }
                            }
                        }
                    } else if self.isPlaying && self.player.timeControlStatus == .paused {
                        self.player.play()
                        self.player.rate = self.playbackSpeed
                    }
                    self.updateNowPlayingInfo(fetchArtwork: true)
                case .failed:
                    let errMsg = observedItem.error?.localizedDescription ?? "Unknown AVPlayerItem error"
                    let nsErr = observedItem.error as NSError?
                    var logDetails = ""
                    if let events = observedItem.errorLog()?.events {
                        logDetails = events.map { "status=\($0.errorStatusCode) domain=\($0.errorDomain) comment=\($0.errorComment ?? "")" }.joined(separator: " | ")
                    }
                    YTDebugLogger.shared.log(.error, tag: "ItemStatus", "\(videoId) -> FAILED: \(errMsg) [code=\(nsErr?.code ?? -1), domain=\(nsErr?.domain ?? "")] \(logDetails)")
                    await self.handlePlayerItemFailureFallback(for: videoId)
                @unknown default:
                    break
                }
            }
        }
    }

    /// Automatic codec/HDR fallback ladder when AVPlayerItem fails (e.g., CoreMedia -12927 on 10-bit AV1 HDR or 8K):
    /// Stage 0 -> 1: Native YouTube VISIONOS HLS pinned to requested resolution + HDR (vp09.02 PQ HDR)
    /// Stage 1 -> 2: Native YouTube VISIONOS HLS pinned to requested resolution SDR (4K/1080p SDR)
    /// Stage 2 -> 3: Local sequential H.264 (`avc1`) 1080p60/720p (guaranteed hardware decode on all iPhones)
    /// Stage 3 -> 4: Muxed progressive fallback (`itag 18`)
    private func handlePlayerItemFailureFallback(for videoId: String) async {
        guard let bundle = self.currentPlaybackBundle,
              bundle.video.id == videoId,
              self.currentVideo?.id == videoId else { return }

        let stage = itemFailureFallbackStage[videoId, default: 0]
        itemFailureFallbackStage[videoId] = stage + 1
        let resumeTime = currentTime
        let shouldPlay = isPlaying
        let requestedH = YTResolvedVideoPlayback.targetHeight(for: selectedQuality) ?? 2160
        let wantsHDR = activeResolutionDimensionsText.localizedCaseInsensitiveContains("HDR")
            || selectedQuality.localizedCaseInsensitiveContains("HDR")

        var nextItem: AVPlayerItem?
        var nextLabel: String?

        if stage == 0, let hls = bundle.hlsManifestURL {
            YTDebugLogger.shared.log(.stream, tag: "Fallback", "Stage 1: Switching \(videoId) to VISIONOS HLS (target=\(requestedH)p hdr=\(wantsHDR))")
            let pinned = await YTSequentialStreamServer.shared.makeQualityPinnedHLSPlayerItem(
                from: hls,
                targetHeight: min(requestedH, 2160),
                videoId: videoId,
                preferHDR: wantsHDR
            )
            nextItem = pinned.item
            if let w = pinned.width, let h = pinned.height {
                nextLabel = wantsHDR ? "\(h)p HDR (\(w)×\(h))" : "\(h)p (\(w)×\(h))"
            }
        } else if stage == 1, let hls = bundle.hlsManifestURL {
            YTDebugLogger.shared.log(.stream, tag: "Fallback", "Stage 2: Switching \(videoId) to VISIONOS HLS SDR (target=\(min(requestedH, 2160))p)")
            let pinned = await YTSequentialStreamServer.shared.makeQualityPinnedHLSPlayerItem(
                from: hls,
                targetHeight: min(requestedH, 2160),
                videoId: videoId,
                preferHDR: false
            )
            nextItem = pinned.item
            if let w = pinned.width, let h = pinned.height {
                nextLabel = "\(h)p SDR (\(w)×\(h))"
            }
        } else if stage <= 2,
                  let avcFmt = bundle.adaptiveVideoFormats
                    .filter({ $0.mimeType.contains("avc1") })
                    .sorted(by: { ($0.height ?? 0) > ($1.height ?? 0) })
                    .first {
            YTDebugLogger.shared.log(.stream, tag: "Fallback", "Stage 3: Switching \(videoId) to H.264 \(avcFmt.qualityLabel) (itag \(avcFmt.itag))")
            nextItem = await YTSequentialStreamServer.shared.makeSequentialHLSPlayerItem(
                videoFormat: avcFmt,
                audioFormat: bundle.bestAudioFormat,
                videoId: videoId
            )
            if let w = avcFmt.width, let h = avcFmt.height {
                nextLabel = "\(avcFmt.qualityLabel) (\(w)×\(h))"
            }
        } else if stage <= 3, let muxed = bundle.muxedFormats.first {
            YTDebugLogger.shared.log(.stream, tag: "Fallback", "Stage 4: Switching \(videoId) to progressive muxed itag \(muxed.itag)")
            nextItem = YTSequentialStreamServer.shared.makeFastProgressivePlayerItem(format: muxed)
            nextLabel = muxed.qualityLabel
        }

        guard let item = nextItem, self.currentVideo?.id == videoId else { return }
        if let lbl = nextLabel {
            self.activeResolutionDimensionsText = lbl
        }
        self.pendingQualitySeekTime = resumeTime > 1.0 ? resumeTime : nil
        self.pendingQualityShouldPlay = shouldPlay
        self.hasSeparateAudioTrack = false
        self.audioPlayer.pause()
        self.audioPlayer.replaceCurrentItem(with: nil)
        self.observePlayerItem(item, videoId: videoId)
        self.player.replaceCurrentItem(with: item)
        if shouldPlay {
            self.player.play()
            self.player.rate = self.playbackSpeed
        }
    }

    // MARK: - Open & Play Video (Main Watch Player)
    public func openVideo(_ video: YTVideo, expandPlayer: Bool = true) {
        YTDebugLogger.shared.log(.ui, tag: "Watch", "openVideo id=\(video.id) title=\"\(video.title)\"")
        // Immediately stop all background downloads/prefetchers from any previously playing video
        YTSequentialStreamServer.shared.cancelAllWork(exceptVideoId: video.id)
        // Pause Shorts player if active
        shortsPlayer.pause()
        isShortsPlaying = false
        self.selectedQuality = isOnWiFi ? wifiDefaultQuality : cellularDefaultQuality

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            self.currentVideo = video
            self.isPlayerExpanded = expandPlayer
            self.activeEngagementPanel = .none
            self.playerDragOffset = 0
        }

        // Record in Watch History & update Personalized Recommendation Profile (unless Incognito)
        if !isIncognito {
            watchHistory.removeAll { $0.id == video.id }
            var withProgress = video
            withProgress.watchProgress = max(0.08, video.watchProgress)
            watchHistory.insert(withProgress, at: 0)
            recordInterest(from: video)
        }

        Task {
            streamRecoveryCounts[video.id] = 0
            itemFailureFallbackStage[video.id] = 0
            await prepareStream(for: video, autoPlay: true)
        }
    }

    public func recoverStreamAtCurrentPosition(for videoId: String) async {
        guard !isRecoveringStream,
              let video = currentVideo,
              video.id == videoId else { return }
        let attempts = streamRecoveryCounts[videoId, default: 0]
        guard attempts < 3 else {
            YTDebugLogger.shared.log(.error, tag: "Recovery", "Max stream recovery attempts reached for \(videoId)")
            isBuffering = false
            return
        }

        isRecoveringStream = true
        streamRecoveryCounts[videoId] = attempts + 1
        let resumeTime = max(0, currentTime)
        let shouldPlay = isPlaying
        isBuffering = true
        YTDebugLogger.shared.log(.stream, tag: "Recovery", "Refreshing stream for \(videoId) at \(String(format: "%.1fs", resumeTime)) (attempt \(attempts + 1))")

        let resolved = await YTInnerTubeEngine.shared.resolveVideoPlayback(
            for: video,
            userProfileKeywords: watchProfileKeywords,
            customPipedInstance: customPipedInstanceURL,
            forceRefresh: true
        )
        guard currentVideo?.id == videoId else {
            isRecoveringStream = false
            return
        }
        self.currentPlaybackBundle = resolved
        self.pendingQualitySeekTime = resumeTime
        self.pendingQualityShouldPlay = shouldPlay

        let (videoItem, audioItem, _) = await YTInnerTubeEngine.shared.makeAVPlayerItems(
            for: resolved,
            preferredQuality: selectedQuality
        )
        guard currentVideo?.id == videoId else {
            isRecoveringStream = false
            return
        }
        observePlayerItem(videoItem, videoId: videoId)
        player.replaceCurrentItem(with: videoItem)
        if let aItem = audioItem {
            hasSeparateAudioTrack = true
            audioPlayer.replaceCurrentItem(with: aItem)
        } else {
            hasSeparateAudioTrack = false
            audioPlayer.pause()
            audioPlayer.replaceCurrentItem(with: nil)
        }
        isRecoveringStream = false
    }

    public func prepareStream(for video: YTVideo, autoPlay: Bool) async {
        isBuffering = true
        isLoadingCommentsAndRelated = true
        self.duration = max(1, video.durationSeconds)
        self.currentTime = 0
        self.captionCues = []
        self.currentCaptionText = nil

        // 1. Resolve stream URLs immediately (~250ms, without waiting on comments/related)
        let resolved = await YTInnerTubeEngine.shared.resolveVideoPlayback(
            for: video,
            userProfileKeywords: watchProfileKeywords,
            customPipedInstance: customPipedInstanceURL
        )

        self.currentPlaybackBundle = resolved
        self.currentVideo = resolved.video
        self.duration = max(1, resolved.video.durationSeconds)
        self.availableQualities = resolved.availableQualityLabels
        self.availableCaptionTracks = resolved.captionTracks

        // 2. Build the 5-second sequential HLS `AVPlayerItem` and start playback immediately!
        let (videoItem, audioItem, chosenFmt) = await YTInnerTubeEngine.shared.makeAVPlayerItems(
            for: resolved,
            preferredQuality: selectedQuality
        )

        if let fmt = chosenFmt, let w = fmt.width, let h = fmt.height, h > 0 {
            self.activeVideoAspectRatio = CGFloat(w) / CGFloat(h)
            self.activeResolutionDimensionsText = "\(fmt.qualityLabel) (\(w)×\(h))"
        } else {
            self.activeVideoAspectRatio = 16.0 / 9.0
            self.activeResolutionDimensionsText = selectedQuality
        }

        observePlayerItem(videoItem, videoId: video.id)
        player.replaceCurrentItem(with: videoItem)
        if let aItem = audioItem {
            hasSeparateAudioTrack = true
            audioPlayer.replaceCurrentItem(with: aItem)
        } else {
            hasSeparateAudioTrack = false
            audioPlayer.pause()
            audioPlayer.replaceCurrentItem(with: nil)
        }

        if autoPlay {
            player.play()
            player.rate = playbackSpeed
            if hasSeparateAudioTrack {
                audioPlayer.play()
                audioPlayer.rate = playbackSpeed
            }
        }
        isPlaying = autoPlay
        isBuffering = false
        updateIdleTimer()
        updateNowPlayingInfo(fetchArtwork: true)

        // 3. Load subtitles, related videos, and real comments in the background without blocking video startup!
        Task { @MainActor in
            if let track = resolved.captionTracks.first(where: { $0.languageCode.hasPrefix("fr") }) ?? resolved.captionTracks.first {
                let fetchedCues = await YTInnerTubeEngine.shared.fetchCaptionCues(from: track)
                if self.currentVideo?.id == video.id {
                    self.captionCues = fetchedCues
                    if self.selectedCaptionLanguage != "Off" {
                        self.selectedCaptionLanguage = track.name
                    }
                }
            }
        }

        Task { @MainActor in
            let (related, comments) = await YTInnerTubeEngine.shared.fetchRelatedAndComments(for: resolved.video)
            if self.currentVideo?.id == video.id {
                self.relatedVideos = related
                self.currentComments = comments
                self.isLoadingCommentsAndRelated = false
            }
        }
    }

    // MARK: - Play Real Vertical Short Video in Shorts Tab
    public func playShortInFeed(at index: Int) {
        guard shortsShelfVideos.indices.contains(index) else { return }
        activeShortIndex = index
        let shortVideo = shortsShelfVideos[index]

        // Pause main player if playing
        player.pause()
        audioPlayer.pause()
        isPlaying = false

        // Record in Watch History & Profile
        if !isIncognito {
            watchHistory.removeAll { $0.id == shortVideo.id }
            var copy = shortVideo
            copy.watchProgress = 1.0
            watchHistory.insert(copy, at: 0)
            savePersistedUserState()
        }

        Task {
            let resolved = await YTInnerTubeEngine.shared.resolveVideoPlayback(for: shortVideo)
            guard activeShortIndex == index, selectedTab == .shorts else { return }
            let (vItem, aItem, _) = await YTInnerTubeEngine.shared.makeAVPlayerItems(for: resolved)
            shortsPlayer.replaceCurrentItem(with: vItem)
            if let aItem = aItem {
                audioPlayer.replaceCurrentItem(with: aItem)
                audioPlayer.playImmediately(atRate: 1.0)
            } else {
                audioPlayer.pause()
                audioPlayer.replaceCurrentItem(with: nil)
            }
            shortsPlayer.playImmediately(atRate: 1.0)
            isShortsPlaying = true

            // Fetch real comments for the Short in the background
            Task { @MainActor in
                let (_, comments) = await YTInnerTubeEngine.shared.fetchRelatedAndComments(for: resolved.video)
                if self.activeShortIndex == index {
                    self.currentComments = comments
                }
            }

            // Preload more shorts when reaching near the end of the feed
            if index >= shortsShelfVideos.count - 2 {
                let moreShorts = await YTInnerTubeEngine.shared.fetchShortsFeed(seedKeywords: watchProfileKeywords)
                for s in moreShorts where !shortsShelfVideos.contains(where: { $0.id == s.id }) {
                    shortsShelfVideos.append(s)
                }
            }
        }
    }

    public func toggleShortsPlayPause() {
        if isShortsPlaying {
            shortsPlayer.pause()
            isShortsPlaying = false
        } else {
            shortsPlayer.play()
            isShortsPlaying = true
        }
        updateIdleTimer()
    }

    // MARK: - Main Player Controls & True Fullscreen Orientation
    public func togglePlayPause() {
        let actuallyActive = (player.timeControlStatus != .paused)
        if actuallyActive {
            player.pause()
            audioPlayer.pause()
            isPlaying = false
        } else {
            player.play()
            player.rate = playbackSpeed
            if hasSeparateAudioTrack {
                audioPlayer.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
                audioPlayer.play()
                audioPlayer.rate = playbackSpeed
            }
            isPlaying = true
        }
        updateIdleTimer()
        updateNowPlayingInfo()
    }

    public func toggleFullscreen() {
        let targetLandscape = !isFullscreenLandscape
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            isFullscreenLandscape = targetLandscape
        }
        #if canImport(UIKit)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let orientations: UIInterfaceOrientationMask = targetLandscape ? .landscapeRight : .portrait
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
        }
        #endif
    }

    public func seek(to seconds: TimeInterval) {
        let clamped = max(0, min(seconds, duration))
        currentTime = clamped
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        if hasSeparateAudioTrack {
            audioPlayer.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        updateActiveCaptionCue()
        updateNowPlayingInfo()
    }

    public func skipForward() {
        seek(to: currentTime + Double(skipSeconds))
    }

    public func skipBackward() {
        seek(to: currentTime - Double(skipSeconds))
    }

    public func togglePlayerControls() {
        withAnimation(.easeInOut(duration: 0.16)) {
            showPlayerControlsOverlay.toggle()
        }
        if showPlayerControlsOverlay && isPlaying {
            scheduleControlsAutoHide()
        } else {
            controlsAutoHideTask?.cancel()
        }
    }

    public func scheduleControlsAutoHide() {
        controlsAutoHideTask?.cancel()
        controlsAutoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled, self.isPlaying else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                self.showPlayerControlsOverlay = false
            }
        }
    }

    public func changeQuality(_ quality: String) {
        selectedQuality = quality
        guard let video = currentVideo else { return }
        itemFailureFallbackStage[video.id] = 0
        let savedTime = currentTime
        let wasPlaying = isPlaying

        Task {
            isBuffering = true
            // Use cached resolved bundle (0 network calls) + pre-warmed sidx (0ms) for instant resolution switch!
            let bundle: YTResolvedVideoPlayback
            if let cached = self.currentPlaybackBundle, cached.video.id == video.id {
                bundle = cached
            } else {
                bundle = await YTInnerTubeEngine.shared.resolveVideoPlayback(
                    for: video,
                    userProfileKeywords: watchProfileKeywords,
                    customPipedInstance: customPipedInstanceURL
                )
                self.currentPlaybackBundle = bundle
            }

            let (videoItem, audioItem, chosenFmt) = await YTInnerTubeEngine.shared.makeAVPlayerItems(
                for: bundle,
                preferredQuality: quality
            )

            // Guard against stale async completion if user switched videos or picked another quality
            guard self.currentVideo?.id == video.id, self.selectedQuality == quality else { return }

            if let fmt = chosenFmt, let w = fmt.width, let h = fmt.height, h > 0 {
                self.activeVideoAspectRatio = CGFloat(w) / CGFloat(h)
                self.activeResolutionDimensionsText = "\(fmt.qualityLabel) (\(w)×\(h))"
            } else {
                self.activeResolutionDimensionsText = quality
            }

            self.pendingQualitySeekTime = savedTime > 0.5 ? savedTime : nil
            self.pendingQualityShouldPlay = wasPlaying

            observePlayerItem(videoItem, videoId: video.id)
            player.replaceCurrentItem(with: videoItem)

            if let aItem = audioItem {
                hasSeparateAudioTrack = true
                audioPlayer.replaceCurrentItem(with: aItem)
            } else {
                hasSeparateAudioTrack = false
                audioPlayer.pause()
                audioPlayer.replaceCurrentItem(with: nil)
            }

            if wasPlaying {
                isPlaying = true
                player.play()
                player.rate = playbackSpeed
                if hasSeparateAudioTrack {
                    audioPlayer.play()
                    audioPlayer.rate = playbackSpeed
                }
            }
            showToast("Qualité : \(quality)")
        }
    }

    public func selectCaptionTrack(_ trackName: String) {
        selectedCaptionLanguage = trackName
        if trackName == "Off" {
            currentCaptionText = nil
            return
        }
        if let track = availableCaptionTracks.first(where: { $0.name == trackName }) ?? availableCaptionTracks.first {
            Task {
                let cues = await YTInnerTubeEngine.shared.fetchCaptionCues(from: track)
                self.captionCues = cues
                self.updateActiveCaptionCue()
            }
        }
    }

    public func changePlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying {
            player.rate = speed
            if hasSeparateAudioTrack {
                audioPlayer.rate = speed
            }
        }
    }

    public func minimizePlayerToMiniBar() {
        if isFullscreenLandscape {
            toggleFullscreen()
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            activeEngagementPanel = .none
            isPlayerExpanded = false
            playerDragOffset = 0
        }
    }

    public func closeMiniPlayer() {
        YTSequentialStreamServer.shared.cancelAllWork(exceptVideoId: nil)
        player.pause()
        audioPlayer.pause()
        isPlaying = false
        withAnimation(.easeInOut(duration: 0.2)) {
            currentVideo = nil
            isPlayerExpanded = false
        }
        updateIdleTimer()
        updateNowPlayingInfo()
    }

    // MARK: - Personalized Home Feed & Category Filtering
    public func selectHomeChip(_ chip: String) {
        selectedHomeChip = chip
        Task {
            await refreshHomeFeed(forChip: chip)
        }
    }

    public func refreshHomeFeed(forChip chip: String? = nil) async {
        let activeChip = chip ?? selectedHomeChip
        isLoadingFeed = true

        let subNames = channels.filter { $0.isSubscribed }.map(\.title)
        let watchedIds = Set(watchHistory.map(\.id))
        let (fetchedVideos, fetchedShorts) = await YTInnerTubeEngine.shared.fetchPersonalizedHomeFeed(
            chip: activeChip,
            watchKeywords: watchProfileKeywords,
            subscribedChannels: subNames,
            watchedVideoIds: watchedIds
        )

        if !fetchedVideos.isEmpty {
            self.homeVideos = fetchedVideos
        } else if self.homeVideos.isEmpty {
            self.homeVideos = YTCatalogData.homeFeedVideos
        }

        if !fetchedShorts.isEmpty {
            self.shortsShelfVideos = fetchedShorts
        } else if self.shortsShelfVideos.isEmpty {
            self.shortsShelfVideos = YTCatalogData.homeShortsShelf
        }

        isLoadingFeed = false
    }

    // MARK: - Refresh Subscriptions Feed from User's Subscribed Channels
    public func refreshSubscriptionsFeed() async {
        let activeSubs = channels.filter { $0.isSubscribed }
        guard !activeSubs.isEmpty else {
            subscriptionFeedVideos = []
            return
        }
        isLoadingSubscriptionsFeed = true
        var combined: [YTVideo] = []
        for ch in activeSubs.prefix(5) {
            let vids = await YTInnerTubeEngine.shared.fetchChannelVideos(channelTitle: ch.title, channelId: ch.id)
            for v in vids.prefix(4) where !combined.contains(where: { $0.id == v.id }) {
                combined.append(v)
            }
        }
        subscriptionFeedVideos = combined
        isLoadingSubscriptionsFeed = false
    }

    // MARK: - Search & Suggestions
    public func updateSearchSuggestions(for text: String) {
        Task {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                self.searchSuggestions = []
            } else {
                self.searchSuggestions = await YTInnerTubeEngine.shared.fetchSearchSuggestions(query: trimmed)
            }
        }
    }

    public func submitSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        searchQuery = trimmed
        activeSubmittedQuery = trimmed
        isSearchOverlayPresented = false

        searchHistory.removeAll { $0.lowercased() == trimmed.lowercased() }
        searchHistory.insert(trimmed, at: 0)

        // Add search query to user profile keywords so future Home/Shorts feeds adapt!
        watchProfileKeywords.removeAll { $0.lowercased() == trimmed.lowercased() }
        watchProfileKeywords.insert(trimmed, at: 0)
        savePersistedUserState()

        pushRoute(.searchResults(query: trimmed))

        Task {
            await executeSearch(query: trimmed)
        }
    }

    public func executeSearch(query: String) async {
        isSearching = true
        let results = await YTInnerTubeEngine.shared.searchVideos(query: query, filters: searchFilters)
        self.searchResults = results
        isSearching = false
    }

    public func deleteSearchHistoryItem(_ item: String) {
        withAnimation(.easeInOut(duration: 0.22)) {
            searchHistory.removeAll { $0 == item }
            savePersistedUserState()
        }
    }

    // MARK: - Subscriptions & Notification Bell
    public func channel(for id: String, fallbackTitle: String, avatarURL: URL? = nil) -> YTChannel {
        if let found = channels.first(where: { $0.id == id || $0.title.lowercased() == fallbackTitle.lowercased() }) {
            return found
        }
        return YTChannel(
            id: id,
            title: fallbackTitle,
            handle: "@\(fallbackTitle.replacingOccurrences(of: " ", with: "").lowercased())",
            avatarURL: avatarURL,
            subscribersText: "Chaîne YouTube",
            videosCountText: "Vidéos",
            descriptionText: "Chaîne officielle de \(fallbackTitle).",
            isSubscribed: false,
            videos: []
        )
    }

    public func isSubscribed(to channelId: String, channelTitle: String = "") -> Bool {
        channels.first(where: { $0.id == channelId || (!channelTitle.isEmpty && $0.title.lowercased() == channelTitle.lowercased()) })?.isSubscribed ?? false
    }

    public func notificationPreference(for channelId: String, channelTitle: String = "") -> YTNotificationPreference {
        channels.first(where: { $0.id == channelId || (!channelTitle.isEmpty && $0.title.lowercased() == channelTitle.lowercased()) })?.notificationPreference ?? .personalized
    }

    public func toggleSubscription(for channelId: String, channelTitle: String, avatarURL: URL? = nil) {
        if let idx = channels.firstIndex(where: { $0.id == channelId || (!channelTitle.isEmpty && $0.title.lowercased() == channelTitle.lowercased()) }) {
            channels[idx].isSubscribed.toggle()
            let nowSub = channels[idx].isSubscribed
            let chCopy = channels[idx]
            if nowSub {
                showToast("Abonnement ajouté")
                Task { await refreshSubscriptionsFeed() }
            } else {
                lastUnsubscribedChannel = chCopy
                channels.remove(at: idx)
                showToast("Désabonné de \(chCopy.title)", actionTitle: "ANNULER") { [weak self] in
                    guard let self = self else { return }
                    var restored = chCopy
                    restored.isSubscribed = true
                    self.channels.append(restored)
                    self.savePersistedUserState()
                    Task { await self.refreshSubscriptionsFeed() }
                }
                Task { await refreshSubscriptionsFeed() }
            }
        } else {
            let newCh = YTChannel(
                id: channelId,
                title: channelTitle,
                handle: "@\(channelTitle.replacingOccurrences(of: " ", with: "").lowercased())",
                avatarURL: avatarURL,
                subscribersText: "Abonné",
                videosCountText: "",
                descriptionText: "Chaîne officielle de \(channelTitle).",
                isSubscribed: true,
                notificationPreference: .personalized,
                videos: []
            )
            channels.insert(newCh, at: 0)
            showToast("Abonnement ajouté")
            Task { await refreshSubscriptionsFeed() }
        }
        savePersistedUserState()
    }

    public func setNotificationPreference(_ pref: YTNotificationPreference, for channelId: String, channelTitle: String = "") {
        if let idx = channels.firstIndex(where: { $0.id == channelId || (!channelTitle.isEmpty && $0.title.lowercased() == channelTitle.lowercased()) }) {
            channels[idx].notificationPreference = pref
            savePersistedUserState()
            showToast(pref.toastMessage)
        }
    }

    // MARK: - Likes, Comments & Playlists
    public func isVideoLiked(_ videoId: String) -> Bool {
        likedVideoIds.contains(videoId)
    }

    public func toggleLike(for videoId: String) {
        if likedVideoIds.contains(videoId) {
            likedVideoIds.remove(videoId)
        } else {
            likedVideoIds.insert(videoId)
            dislikedVideoIds.remove(videoId)
            if let cur = currentVideo, cur.id == videoId {
                recordInterest(from: cur)
            }
        }
        savePersistedUserState()
    }

    public func toggleDislike(for videoId: String) {
        if dislikedVideoIds.contains(videoId) {
            dislikedVideoIds.remove(videoId)
        } else {
            dislikedVideoIds.insert(videoId)
            likedVideoIds.remove(videoId)
        }
        savePersistedUserState()
    }

    public func addComment(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newComment = YTComment(
            authorName: "Vous",
            authorHandle: "@vous",
            publishedTimeText: "À l'instant",
            text: trimmed,
            likeCountText: "1",
            isLiked: true,
            replyCount: 0
        )
        currentComments.insert(newComment, at: 0)
    }

    public func addLiveChatMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let msg = YTLiveChatMessage(
            authorName: "Vous",
            authorAvatarColorHex: "#5C4033",
            message: trimmed
        )
        liveChatMessages.append(msg)
    }

    public func presentSaveToPlaylist(for video: YTVideo) {
        self.videoToSave = video
        self.isSaveToPlaylistSheetPresented = true
    }

    public func isVideo(_ videoId: String, inPlaylist playlistId: String) -> Bool {
        guard let pl = playlists.first(where: { $0.id == playlistId }) else { return false }
        return pl.videos.contains { $0.id == videoId }
    }

    public func toggleVideo(_ video: YTVideo, inPlaylist playlistId: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        if playlists[idx].videos.contains(where: { $0.id == video.id }) {
            playlists[idx].videos.removeAll { $0.id == video.id }
            showToast("Retiré de \(playlists[idx].title)")
        } else {
            playlists[idx].videos.insert(video, at: 0)
            showToast("Enregistré dans \(playlists[idx].title)")
        }
        savePersistedUserState()
    }

    public func createPlaylist(title: String, isPrivate: Bool = true) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var vids: [YTVideo] = []
        if let v = videoToSave {
            vids.append(v)
        }
        let pl = YTPlaylist(title: trimmed, isPrivate: isPrivate, videos: vids)
        playlists.append(pl)
        savePersistedUserState()
        showToast("Playlist \"\(trimmed)\" créée")
    }

    // MARK: - Navigation Helper
    public func pushRoute(_ route: YTNavigationRoute) {
        if isPlayerExpanded {
            minimizePlayerToMiniBar()
        }
        switch selectedTab {
        case .home:
            homeNavigationPath.append(route)
        case .subscriptions:
            subscriptionsNavigationPath.append(route)
        case .library:
            libraryNavigationPath.append(route)
        default:
            selectedTab = .home
            homeNavigationPath.append(route)
        }
    }

    // MARK: - Snackbar / Toast
    public func showToast(_ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            self.toastMessage = message
            self.toastActionTitle = actionTitle
            self.toastActionHandler = action
        }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                self.toastMessage = nil
                self.toastActionTitle = nil
                self.toastActionHandler = nil
            }
        }
    }

    public func triggerToastAction() {
        toastActionHandler?()
        withAnimation(.easeOut(duration: 0.2)) {
            self.toastMessage = nil
            self.toastActionTitle = nil
            self.toastActionHandler = nil
        }
    }
}
