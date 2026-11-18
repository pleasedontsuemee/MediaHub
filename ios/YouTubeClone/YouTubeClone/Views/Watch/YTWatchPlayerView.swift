import SwiftUI
import AVKit

#if canImport(UIKit)
import UIKit
#endif

// MARK: - 1. Native AVPlayerLayer Surface (Supports Picture-in-Picture, Ultrawide 18:9 / 21:9 & Pinch-to-Zoom)
#if canImport(UIKit)
public final class YTPlayerUIView: UIView {
    public override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    public var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    public var pipController: AVPictureInPictureController?
    private weak var attachedPlayer: AVPlayer?
    private var backgroundPlaybackEnabled: Bool = true
    private var pipEnabled: Bool = true
    private var bgObserver: NSObjectProtocol?
    private var fgObserver: NSObjectProtocol?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupLifecycleObservers()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLifecycleObservers()
    }

    deinit {
        if let bg = bgObserver { NotificationCenter.default.removeObserver(bg) }
        if let fg = fgObserver { NotificationCenter.default.removeObserver(fg) }
    }

    private func setupLifecycleObservers() {
        bgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let pipActive = self.pipController?.isPictureInPictureActive ?? false
            // Detach AVPlayerLayer when entering background (unless PiP is active) so iOS keeps playing audio in background!
            if self.backgroundPlaybackEnabled && !self.pipEnabled && !pipActive {
                self.playerLayer.player = nil
            }
        }

        fgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if let p = self.attachedPlayer, self.playerLayer.player !== p {
                self.playerLayer.player = p
            }
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    public func configure(player: AVPlayer, zoomToFill: Bool, pipEnabled: Bool, backgroundPlaybackEnabled: Bool) {
        self.pipEnabled = pipEnabled
        self.backgroundPlaybackEnabled = backgroundPlaybackEnabled
        if attachedPlayer !== player {
            attachedPlayer = player
            playerLayer.player = player
            pipController = nil
        } else if playerLayer.player == nil && UIApplication.shared.applicationState != .background {
            playerLayer.player = player
        }
        if pipEnabled {
            if pipController == nil && AVPictureInPictureController.isPictureInPictureSupported() {
                pipController = AVPictureInPictureController(playerLayer: playerLayer)
            }
            pipController?.canStartPictureInPictureAutomaticallyFromInline = true
        } else {
            if let pip = pipController {
                pip.canStartPictureInPictureAutomaticallyFromInline = false
                if pip.isPictureInPictureActive {
                    pip.stopPictureInPicture()
                }
                pipController = nil
            }
        }
        playerLayer.videoGravity = zoomToFill ? .resizeAspectFill : .resizeAspect
    }
}

public struct YTAVPlayerSurfaceView: UIViewRepresentable {
    public let player: AVPlayer
    public let zoomToFill: Bool
    public let pipEnabled: Bool
    public let backgroundPlaybackEnabled: Bool

    public init(player: AVPlayer, zoomToFill: Bool = false, pipEnabled: Bool = true, backgroundPlaybackEnabled: Bool = true) {
        self.player = player
        self.zoomToFill = zoomToFill
        self.pipEnabled = pipEnabled
        self.backgroundPlaybackEnabled = backgroundPlaybackEnabled
    }

    public func makeUIView(context: Context) -> YTPlayerUIView {
        let view = YTPlayerUIView()
        view.backgroundColor = .black
        view.configure(player: player, zoomToFill: zoomToFill, pipEnabled: pipEnabled, backgroundPlaybackEnabled: backgroundPlaybackEnabled)
        return view
    }

    public func updateUIView(_ uiView: YTPlayerUIView, context: Context) {
        uiView.configure(player: player, zoomToFill: zoomToFill, pipEnabled: pipEnabled, backgroundPlaybackEnabled: backgroundPlaybackEnabled)
    }
}
#else
public struct YTAVPlayerSurfaceView: View {
    public let player: AVPlayer
    public let zoomToFill: Bool
    public init(player: AVPlayer, zoomToFill: Bool = false) {
        self.player = player
        self.zoomToFill = zoomToFill
    }
    public var body: some View {
        VideoPlayer(player: player)
    }
}
#endif

// MARK: - 2. Full Watch Page (`YTWatchView` - True Edge-to-Edge Fullscreen, 1-Tap Fullscreen Button, 144p..4K 2160p Resolution Switcher)
public struct YTWatchFullPlayerView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @ObservedObject private var downloadManager = YTOfflineDownloadManager.shared
    public let video: YTVideo

    @State private var doubleTapSeekDirection: Int = 0 // -1 = backward, +1 = forward
    @State private var pinchZoomScale: CGFloat = 1.0
    @State private var isDownloadSheetPresented: Bool = false

    public init(video: YTVideo) {
        self.video = video
    }

    public var body: some View {
        GeometryReader { geo in
            let isLandscape = appVM.isFullscreenLandscape || (geo.size.width > geo.size.height)
            let screenW = geo.size.width
            let screenH = geo.size.height

            ZStack(alignment: .center) {
                if isLandscape {
                    Color.black.ignoresSafeArea(.all)

                    // TRUE Edge-to-Edge Centered Fullscreen Player (Adapts automatically to every iPhone screen size!)
                    let fullWidth = max(screenW, screenH)
                    let fullHeight = min(screenW, screenH)

                    if screenH > screenW {
                        // Portrait-locked device: rotate 90° around exact center and fill physical screen bounds
                        playerVideoCanvas(width: fullWidth, height: fullHeight, isFullscreen: true)
                            .frame(width: fullWidth, height: fullHeight)
                            .rotationEffect(.degrees(90))
                            .position(x: screenW / 2, y: screenH / 2)
                    } else {
                        // Landscape orientation: centered edge-to-edge
                        playerVideoCanvas(width: fullWidth, height: fullHeight, isFullscreen: true)
                            .frame(width: fullWidth, height: fullHeight)
                            .position(x: screenW / 2, y: screenH / 2)
                    }
                } else {
                    YTTheme.backgroundPrimary.ignoresSafeArea()

                    // Portrait Watch Layout (Dynamic aspect ratio: 16:9 or 18:9/2:1 ultrawide + Metadata / Engagement Panel / Suggestions below)
                    let clampedRatio = max(16.0 / 9.0, min(2.2, appVM.activeVideoAspectRatio))
                    let playerHeight = screenW / clampedRatio

                    VStack(spacing: 0) {
                        playerVideoCanvas(
                            width: screenW,
                            height: playerHeight,
                            isFullscreen: false
                        )
                        .gesture(
                            DragGesture(minimumDistance: 14)
                                .onChanged { val in
                                    if val.translation.height > 0 {
                                        appVM.playerDragOffset = val.translation.height
                                    }
                                }
                                .onEnded { val in
                                    if val.translation.height > 75 {
                                        appVM.minimizePlayerToMiniBar()
                                    } else {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                            appVM.playerDragOffset = 0
                                        }
                                    }
                                }
                        )

                        // Below-player area: either Active Engagement Panel (`Comments`, `Live chat`, `Description`) or Watch Next ScrollView
                        ZStack {
                            watchMetadataAndSuggestionsScrollView

                            if appVM.activeEngagementPanel != .none {
                                YTEngagementPanelDrawerView(video: video)
                                    .transition(.move(edge: .bottom))
                            }
                        }
                    }
                    .offset(y: max(0, appVM.playerDragOffset * 0.45))
                }
            }
            .frame(width: screenW, height: screenH)
            .statusBarHidden(isLandscape)
            .persistentSystemOverlays(isLandscape ? .hidden : .automatic)
            .sheet(isPresented: $appVM.isPlayerOptionsSheetPresented) {
                YTPlayerSettingsBottomSheet()
                    .presentationDetents([.height(430)])
            }
            .sheet(isPresented: $appVM.isCaptionsPickerSheetPresented) {
                YTCaptionsSelectionBottomSheet()
                    .presentationDetents([.height(250)])
            }
            .sheet(isPresented: $appVM.isQualityPickerSheetPresented) {
                YTQualitySelectionBottomSheet()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $appVM.isSpeedPickerSheetPresented) {
                YTSpeedSelectionBottomSheet()
                    .presentationDetents([.height(380)])
            }
            .sheet(isPresented: $isDownloadSheetPresented) {
                YTDownloadQualitySheet(video: video)
                    .presentationDetents([.medium, .large])
            }
        }
        .ignoresSafeArea(appVM.isFullscreenLandscape ? .all : [])
    }

    // MARK: - Player Video Surface + Instant 1-Tap Fullscreen Button + Resolution Badge + Captions + Red Scrubber
    private func playerVideoCanvas(width: CGFloat, height: CGFloat, isFullscreen: Bool) -> some View {
        ZStack(alignment: .bottom) {
            Color.black

            // Fallback thumbnail behind AVPlayer while buffering
            YTCachedAsyncImage(url: video.thumbnailURL) {
                Color.black
            }
            .frame(width: width, height: height)
            .clipped()
            .opacity(appVM.isPlaying ? 0.0 : 0.85)

            // Live AVPlayer Surface (Supports 16:9, 18:9 / 2:1 MKBHD Univisium, 21:9 Ultrawide, and Pinch-to-Zoom to Fill!)
            YTAVPlayerSurfaceView(
                player: appVM.player,
                zoomToFill: appVM.zoomToFillScreen,
                pipEnabled: appVM.isPiPEnabled,
                backgroundPlaybackEnabled: appVM.backgroundPlaybackEnabled
            )
                .frame(width: width, height: height)
                .clipped()

            if appVM.isBuffering {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Stats for Nerds Overlay
            if appVM.statsForNerdsEnabled {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Video ID: \(video.id)")
                    Text("Resolution: \(appVM.activeResolutionDimensionsText)")
                    Text("Aspect Ratio: \(String(format: "%.2f:1", appVM.activeVideoAspectRatio)) | ZoomToFill: \(appVM.zoomToFillScreen ? "ON" : "OFF")")
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .padding(8)
                .background(Color.black.opacity(0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
            }

            // Double-Tap Seek Feedback (-10s / +10s)
            if doubleTapSeekDirection != 0 {
                HStack {
                    if doubleTapSeekDirection > 0 { Spacer() }
                    VStack(spacing: 6) {
                        Image(systemName: doubleTapSeekDirection < 0 ? "gobackward.10" : "goforward.10")
                            .font(.system(size: 28, weight: .bold))
                        Text("\(appVM.skipSeconds) seconds")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 120, height: 120)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .padding(.horizontal, 28)
                    if doubleTapSeekDirection < 0 { Spacer() }
                }
                .frame(width: width, height: height)
            }

            // Tap, Double-Tap & Pinch-to-Zoom Gesture Catcher
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        appVM.skipBackward()
                        triggerDoubleTapFeedback(-1)
                    }
                    .onTapGesture(count: 1) {
                        appVM.togglePlayerControls()
                    }

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        appVM.skipForward()
                        triggerDoubleTapFeedback(1)
                    }
                    .onTapGesture(count: 1) {
                        appVM.togglePlayerControls()
                    }
            }
            .frame(width: width, height: height)
            .simultaneousGesture(
                MagnificationGesture()
                    .onEnded { scale in
                        if scale > 1.12 && !appVM.zoomToFillScreen {
                            appVM.zoomToFillScreen = true
                            appVM.showToast("Zoom to fill screen (Plein écran étiré)")
                        } else if scale < 0.9 && appVM.zoomToFillScreen {
                            appVM.zoomToFillScreen = false
                            appVM.showToast("Original aspect ratio (Format original)")
                        }
                    }
            )

            // Subtitles / Closed Captions Overlay
            if let capText = appVM.currentCaptionText, appVM.selectedCaptionLanguage != "Off" {
                Text(capText)
                    .font(.system(size: isFullscreen ? 16 : 13, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.72))
                    )
                    .padding(.bottom, appVM.showPlayerControlsOverlay ? 46 : 20)
            }

            // Player Controls Overlay
            if appVM.showPlayerControlsOverlay {
                ZStack {
                    Color.black.opacity(0.48)
                        .allowsHitTesting(false)

                    VStack {
                        // Top Row: Minimize Chevron `v` on left; Resolution Pill (`4K`/`1080p`), Zoom-to-Fill button, Cast, CC, 3-dots `⋮` on right
                        HStack(spacing: 14) {
                            Button {
                                if isFullscreen {
                                    appVM.toggleFullscreen()
                                } else {
                                    appVM.minimizePlayerToMiniBar()
                                }
                            } label: {
                                YTIcon("yt_outline_chevron_down_24pt", fallback: "chevron.down", size: 24)
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if isFullscreen {
                                Text(video.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }

                            Spacer()

                            // Direct 1-Tap Resolution Picker Pill (`Auto`, `2160p 4K`, `1440p`, `1080p`, etc.)
                            Button {
                                appVM.isQualityPickerSheetPresented = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles.tv")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(appVM.selectedQuality == "Auto (recommended)" ? "Auto" : appVM.selectedQuality)
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.black.opacity(0.65)))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(.plain)

                            // 1-Tap Aspect Ratio / Zoom-to-Fill Toggle (Ideal for 18:9 / 21:9 MKBHD videos)
                            Button {
                                appVM.zoomToFillScreen.toggle()
                                appVM.showToast(appVM.zoomToFillScreen ? "Zoom plein écran activé" : "Format original (\(String(format: "%.1f:9", appVM.activeVideoAspectRatio * 9)))")
                            } label: {
                                Image(systemName: appVM.zoomToFillScreen ? "arrow.down.right.and.arrow.up.left" : "aspectratio")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            // CC (Closed Captions)
                            Button {
                                if appVM.selectedCaptionLanguage == "Off" {
                                    if let firstTrack = appVM.availableCaptionTracks.first {
                                        appVM.selectCaptionTrack(firstTrack.name)
                                        appVM.showToast("Sous-titres : \(firstTrack.name)")
                                    } else {
                                        appVM.isCaptionsPickerSheetPresented = true
                                    }
                                } else {
                                    appVM.selectCaptionTrack("Off")
                                    appVM.showToast("Sous-titres désactivés")
                                }
                            } label: {
                                YTIcon(
                                    appVM.selectedCaptionLanguage == "Off" ? "yt_outline_closed_caption_24pt" : "yt_fill_closed_caption_24pt",
                                    fallback: "captions.bubble",
                                    size: 22
                                )
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            // 3-dot Player Options
                            Button {
                                appVM.isPlayerOptionsSheetPresented = true
                            } label: {
                                YTIcon("yt_outline_overflow_vertical_24pt", fallback: "gearshape", size: 22)
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, isFullscreen ? 42 : 10)
                        .padding(.top, isFullscreen ? 14 : 6)

                        Spacer()

                        // Center Row: Previous `|◀`, Large Play/Pause `||`, Next `▶|`
                        HStack(spacing: 56) {
                            Button {
                                appVM.seek(to: 0)
                            } label: {
                                YTIcon("yt_fill_skip_previous_24pt", fallback: "backward.end.fill", size: 28)
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                appVM.togglePlayPause()
                            } label: {
                                Image(systemName: appVM.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 38, weight: .regular))
                                    .foregroundStyle(.white)
                                    .frame(width: 64, height: 64)
                                    .background(Circle().fill(Color.black.opacity(0.35)))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                if let next = appVM.relatedVideos.first {
                                    appVM.openVideo(next)
                                }
                            } label: {
                                YTIcon("yt_fill_skip_next_24pt", fallback: "forward.end.fill", size: 28)
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        // Bottom Row: Current Time / Duration (`0:27 / 12:08`) on left, Spacer, and dedicated Fullscreen space on right
                        HStack {
                            HStack(spacing: 0) {
                                Text(YTInnerTubeEngine.formatDuration(seconds: Int(appVM.currentTime)))
                                    .foregroundStyle(.white)
                                Text(" / \(video.durationText)")
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            .font(.system(size: 12, weight: .medium))

                            Spacer()
                            // Reserve space for the always-responsive Fullscreen button on bottom-right
                            Color.clear.frame(width: 48, height: 44)
                        }
                        .padding(.horizontal, isFullscreen ? 42 : 14)
                        .padding(.bottom, isFullscreen ? 24 : 10)
                    }
                }
                .frame(width: width, height: height)
            }

            // Fullscreen Button `[ ]`: Always 1-tap accessible in Portrait, and cleanly hidden in Fullscreen when controls fade out!
            if !isFullscreen || appVM.showPlayerControlsOverlay {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            appVM.toggleFullscreen()
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.black.opacity(appVM.showPlayerControlsOverlay ? 0.55 : 0.35))
                                    .frame(width: 38, height: 38)

                                YTIcon(
                                    isFullscreen ? "yt_outline_screen_full_exit_24pt" : "yt_outline_screen_full_24pt",
                                    fallback: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "viewfinder",
                                    size: 22
                                )
                                .foregroundStyle(.white)
                            }
                            .frame(width: 52, height: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, isFullscreen ? 36 : 6)
                        .padding(.bottom, isFullscreen ? 18 : 6)
                    }
                }
                .frame(width: width, height: height)
            }

            // Bottom Red Scrubber Bar + Red Thumb Circle (hidden in fullscreen when controls are hidden!)
            if !isFullscreen || appVM.showPlayerControlsOverlay {
                GeometryReader { barGeo in
                    let fraction = appVM.duration > 0 ? min(1.0, max(0.0, appVM.currentTime / appVM.duration)) : 0.0
                    let xPos = barGeo.size.width * CGFloat(fraction)

                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.32))
                            .frame(height: 3)

                        Rectangle()
                            .fill(YTTheme.brandRed)
                            .frame(width: xPos, height: 3)

                        if appVM.showPlayerControlsOverlay {
                            Circle()
                                .fill(YTTheme.brandRed)
                                .frame(width: 13, height: 13)
                                .offset(x: max(0, min(barGeo.size.width - 13, xPos - 6.5)))
                        }
                    }
                    .frame(height: 14, alignment: .bottom)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                let pct = max(0, min(1, val.location.x / max(1, barGeo.size.width)))
                                appVM.seek(to: Double(pct) * appVM.duration)
                            }
                    )
                }
                .frame(height: 14)
                .padding(.horizontal, isFullscreen ? 42 : 0)
                .padding(.bottom, isFullscreen ? 12 : 0)
            }
        }
        .frame(width: width, height: height)
    }

    private func triggerDoubleTapFeedback(_ dir: Int) {
        withAnimation(.easeInOut(duration: 0.15)) {
            doubleTapSeekDirection = dir
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(.easeOut(duration: 0.2)) {
                doubleTapSeekDirection = 0
            }
        }
    }

    // MARK: - Below-Player ScrollView: Metadata, Action Row, Channel Bar, Comments Teaser, Related Videos
    private var watchMetadataAndSuggestionsScrollView: some View {
        let isLiked = appVM.isVideoLiked(video.id)
        let isDisliked = appVM.dislikedVideoIds.contains(video.id)
        let isSub = appVM.isSubscribed(to: video.channelId, channelTitle: video.channelTitle)

        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // 1. Video Title + Downward Disclosure Chevron + Views/Date/Hashtags (`slim_video_metadata_cell.flexb`)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        appVM.activeEngagementPanel = .description
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(video.title)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(YTTheme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 4)

                            YTIcon("yt_outline_chevron_down_24pt", fallback: "chevron.down", size: 18)
                                .foregroundStyle(YTTheme.textPrimary)
                                .padding(.top, 2)
                        }

                        HStack(spacing: 4) {
                            Text("\(video.viewCountText) · \(video.publishedTimeText)")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(YTTheme.textSecondary)

                            if !appVM.activeResolutionDimensionsText.isEmpty {
                                Text("· \(appVM.activeResolutionDimensionsText)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(YTTheme.callToActionBlue)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                }
                .buttonStyle(.plain)

                // 2. Horizontal Action Bar (`Like`, `Dislike`, `Quality`, `Share`, `Download`, `Save`)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 28) {
                        // Like
                        watchActionButton(
                            asset: isLiked ? "yt_fill_thumb_up_24pt" : "yt_outline_thumb_up_24pt",
                            fallback: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                            label: video.likeCountText
                        ) {
                            appVM.toggleLike(for: video.id)
                        }

                        // Dislike
                        watchActionButton(
                            asset: isDisliked ? "yt_fill_thumb_down_24pt" : "yt_outline_thumb_down_24pt",
                            fallback: isDisliked ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                            label: "Dislike"
                        ) {
                            appVM.toggleDislike(for: video.id)
                        }

                        // Direct Resolution Switcher Button (`144p` .. `2160p 4K`)
                        watchActionButton(
                            asset: "yt_outline_gear_24pt",
                            fallback: "sparkles.tv",
                            label: appVM.selectedQuality == "Auto (recommended)" ? "Qualité" : appVM.selectedQuality.components(separatedBy: " ").first ?? "Qualité"
                        ) {
                            appVM.isQualityPickerSheetPresented = true
                        }

                        // Share
                        watchActionButton(
                            asset: "yt_outline_share_24pt",
                            fallback: "arrowshape.turn.up.right",
                            label: "Share"
                        ) {
                            appVM.showToast("Link copied to clipboard")
                        }

                        // Download (Opens Quality & Audio-Only Download Picker)
                        let isDownloaded = downloadManager.isDownloaded(video.id)
                        let isDownloading = downloadManager.activeDownloadProgress[video.id] != nil
                        watchActionButton(
                            asset: isDownloaded ? "yt_fill_downloaded_24pt" : "yt_outline_download_24pt",
                            fallback: isDownloaded ? "checkmark.circle.fill" : (isDownloading ? "arrow.down.circle.dotted" : "arrow.down.to.line"),
                            label: isDownloading ? "..." : (isDownloaded ? "Téléchargé" : "Download")
                        ) {
                            isDownloadSheetPresented = true
                        }

                        // Save (Opens `Save video to...` modal)
                        watchActionButton(
                            asset: "yt_outline_library_add_24pt",
                            fallback: "plus.square.on.square",
                            label: "Save"
                        ) {
                            appVM.presentSaveToPlaylist(for: video)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                }

                Rectangle()
                    .fill(YTTheme.separator)
                    .frame(height: 0.5)

                // 3. Compact Channel Bar (`Avatar`, `Channel Name`, `Subscribers`, `SUBSCRIBE` / `SUBSCRIBED` + Bell)
                HStack(spacing: 12) {
                    Button {
                        let ch = appVM.channel(for: video.channelId, fallbackTitle: video.channelTitle, avatarURL: video.channelAvatarURL)
                        appVM.minimizePlayerToMiniBar()
                        appVM.pushRoute(.channel(ch))
                    } label: {
                        HStack(spacing: 12) {
                            YTChannelAvatarView(url: video.channelAvatarURL, title: video.channelTitle, size: 36)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(video.channelTitle)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(YTTheme.textPrimary)
                                    .lineLimit(1)

                                Text(video.channelSubscribers)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(YTTheme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        appVM.toggleSubscription(
                            for: video.channelId,
                            channelTitle: video.channelTitle,
                            avatarURL: video.channelAvatarURL
                        )
                    } label: {
                        Text(isSub ? "SUBSCRIBED" : "SUBSCRIBE")
                            .font(.system(size: 14, weight: .medium))
                            .tracking(0.3)
                            .foregroundStyle(isSub ? YTTheme.textSecondary : YTTheme.subscribeRed)
                    }
                    .buttonStyle(.plain)

                    if isSub {
                        YTNotificationBellMenuButton(channelId: video.channelId, channelTitle: video.channelTitle)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 56)

                Rectangle()
                    .fill(YTTheme.separator)
                    .frame(height: 0.5)

                // 4. Comments Entry Point Teaser
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        appVM.activeEngagementPanel = .comments
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("Comments")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(YTTheme.textPrimary)

                            Text(video.commentCountText)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(YTTheme.textSecondary)

                            Spacer()

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(YTTheme.textPrimary)
                        }

                        if let firstComment = appVM.currentComments.first {
                            HStack(alignment: .top, spacing: 10) {
                                YTChannelAvatarView(url: firstComment.authorAvatarURL, title: firstComment.authorName, size: 24)

                                Text(firstComment.text)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(YTTheme.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        } else if appVM.isLoadingCommentsAndRelated {
                            Text("Chargement des commentaires...")
                                .font(.system(size: 12))
                                .foregroundStyle(YTTheme.textSecondary)
                        } else {
                            Text("Appuyez pour voir ou ajouter un commentaire...")
                                .font(.system(size: 12))
                                .foregroundStyle(YTTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(YTTheme.backgroundSecondary)
                    .frame(height: 6)

                // 5. Related / Suggested Videos (`watchNextWrapperView` - dynamically matched to the watched video's topic)
                if appVM.isLoadingCommentsAndRelated && appVM.relatedVideos.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        YTVideoCardSkeletonView()
                    }
                } else {
                    ForEach(appVM.relatedVideos) { related in
                        YTVideoCardView(video: related)
                    }
                }
            }
            .padding(.bottom, 32)
        }
    }

    private func watchActionButton(
        asset: String,
        fallback: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                YTIcon(asset, fallback: fallback, size: 24)
                    .foregroundStyle(YTTheme.textPrimary)
                Text(label)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(YTTheme.textPrimary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 3. Download Quality & Audio-Only Picker Sheet
public struct YTDownloadQualitySheet: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @ObservedObject private var downloadManager = YTOfflineDownloadManager.shared
    @Environment(\.dismiss) private var dismiss
    public let video: YTVideo

    public init(video: YTVideo) {
        self.video = video
    }

    private var downloadableQualities: [String] {
        let filtered = appVM.availableQualities.filter { $0 != "Auto (recommended)" }
        return filtered.isEmpty ? ["1080p", "720p", "480p", "360p"] : filtered
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Télécharger pour hors-ligne")
                        .font(YTFontManager.youtubeSans(size: 18, weight: .bold))
                        .foregroundStyle(YTTheme.textPrimary)
                    Text(video.title)
                        .font(.system(size: 12))
                        .foregroundStyle(YTTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    YTIcon("yt_outline_x_24pt", fallback: "xmark", size: 20)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Rectangle().fill(YTTheme.separator).frame(height: 0.5)

            ScrollView {
                VStack(spacing: 0) {
                    // Option 1: Audio Only (M4A Music / Podcast)
                    Button {
                        startDownload(quality: "Audio uniquement (M4A)")
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "music.note")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(YTTheme.callToActionBlue)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Audio uniquement (M4A)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(YTTheme.textPrimary)
                                Text("Idéal pour la musique et les podcasts · Piste originale AAC")
                                    .font(.system(size: 12))
                                    .foregroundStyle(YTTheme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(YTTheme.callToActionBlue)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 62)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Rectangle().fill(YTTheme.separator).frame(height: 0.5)

                    // Option 2: All Video Resolutions (`2160p 4K` down to `144p`)
                    ForEach(downloadableQualities, id: \.self) { q in
                        Button {
                            startDownload(quality: q)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: q.contains("4K") || q.contains("2160") ? "4k.tv" : "film")
                                    .font(.system(size: 17))
                                    .foregroundStyle(YTTheme.textPrimary)
                                    .frame(width: 28)

                                Text("Vidéo · \(q)")
                                    .font(.system(size: 16))
                                    .foregroundStyle(YTTheme.textPrimary)

                                Spacer()

                                if q == appVM.offlineDownloadQuality {
                                    Text("Recommandé")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(YTTheme.callToActionBlue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(YTTheme.callToActionBlue.opacity(0.14)))
                                }

                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 19))
                                    .foregroundStyle(YTTheme.textSecondary)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if downloadManager.isDownloaded(video.id) {
                        Rectangle().fill(YTTheme.separator).frame(height: 0.5)
                        Button {
                            downloadManager.removeDownload(videoId: video.id)
                            appVM.showToast("Supprimé des téléchargements")
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                                Text("Supprimer le téléchargement existant")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            .padding(16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(YTTheme.backgroundPrimary)
    }

    private func startDownload(quality: String) {
        dismiss()
        appVM.showToast("Téléchargement lancé (\(quality))...")
        Task {
            let ok = await downloadManager.downloadVideo(video, quality: quality)
            appVM.showToast(ok ? "Enregistré dans Bibliothèque > Downloads (\(quality))" : "Échec du téléchargement")
        }
    }
}
