import SwiftUI
import AVKit
import WebKit

#if canImport(UIKit)
import UIKit

public final class NFPlayerUIView: UIView {
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

public struct NFAVPlayerSurfaceView: UIViewRepresentable {
    public let player: AVPlayer
    public let zoomToFill: Bool
    public let pipEnabled: Bool
    public let backgroundPlaybackEnabled: Bool

    public init(player: AVPlayer, zoomToFill: Bool, pipEnabled: Bool, backgroundPlaybackEnabled: Bool) {
        self.player = player
        self.zoomToFill = zoomToFill
        self.pipEnabled = pipEnabled
        self.backgroundPlaybackEnabled = backgroundPlaybackEnabled
    }

    public func makeUIView(context: Context) -> NFPlayerUIView {
        let v = NFPlayerUIView()
        v.backgroundColor = .black
        v.configure(player: player, zoomToFill: zoomToFill, pipEnabled: pipEnabled, backgroundPlaybackEnabled: backgroundPlaybackEnabled)
        return v
    }

    public func updateUIView(_ uiView: NFPlayerUIView, context: Context) {
        uiView.configure(player: player, zoomToFill: zoomToFill, pipEnabled: pipEnabled, backgroundPlaybackEnabled: backgroundPlaybackEnabled)
    }
}

public struct NFEmbedWebPlayerView: UIViewRepresentable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        load(url, in: webView)
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            load(url, in: uiView)
        }
    }

    private func load(_ url: URL, in webView: WKWebView) {
        var req = URLRequest(url: url)
        req.setValue("https://movix.miami/", forHTTPHeaderField: "Referer")
        webView.load(req)
    }
}
#endif

// MARK: - Netflix Fullscreen Landscape Player (`NFPlayerView`)
public struct NFPlayerView: View {
    @EnvironmentObject private var appVM: NFAppViewModel
    @State private var showSourcesSheet = false
    @State private var showSpeedSheet = false

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .center) {
                Color.black.ignoresSafeArea(.all)
                playerCanvas(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea(.all)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onDisappear {
            if appVM.isPlayerPresented {
                appVM.closePlayer()
            }
        }
        .sheet(isPresented: $showSourcesSheet) {
            NFStreamSourcePickerSheet()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSpeedSheet) {
            NFSpeedPickerSheet()
                .presentationDetents([.height(280)])
        }
    }

    private func playerCanvas(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.black

            #if canImport(UIKit)
            if let stream = appVM.activeStream, stream.isEmbed {
                NFEmbedWebPlayerView(url: stream.url)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                NFAVPlayerSurfaceView(
                    player: appVM.player,
                    zoomToFill: appVM.zoomToFillScreen,
                    pipEnabled: appVM.isPiPEnabled,
                    backgroundPlaybackEnabled: appVM.backgroundPlaybackEnabled
                )
                .frame(width: width, height: height)
                .clipped()
            }
            #endif

            if appVM.isBuffering {
                ProgressView()
                    .tint(NFTheme.netflixRed)
                    .scaleEffect(1.4)
            }

            if appVM.activeStream?.isEmbed == true {
                // Floating minimal top bar for WebView embed servers so user can switch servers or close
                VStack {
                    HStack(spacing: 16) {
                        Button {
                            appVM.closePlayer()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(Color.black.opacity(0.75)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Text(appVM.playingMedia?.title ?? "")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.65)))

                        Spacer()

                        Button {
                            showSourcesSheet = true
                        } label: {
                            Label("Serveurs (\(appVM.availableStreams.count))", systemImage: "server.rack")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .frame(height: 44)
                                .background(Capsule().fill(NFTheme.netflixRed))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 52)
                    .padding(.top, 20)
                    Spacer()
                }
                .zIndex(20)
            } else {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            appVM.showPlayerControls.toggle()
                        }
                    }
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onEnded { scale in
                                if scale > 1.12 { appVM.zoomToFillScreen = true }
                                else if scale < 0.9 { appVM.zoomToFillScreen = false }
                            }
                    )
                    .zIndex(1)
            }

            if appVM.showPlayerControls && appVM.activeStream?.isEmbed != true {
                Group {
                if appVM.isControlsLocked {
                    VStack {
                        Spacer()
                        Button {
                            appVM.isControlsLocked = false
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "lock.open.fill")
                                    .font(.system(size: 20))
                                Text("Déverrouiller")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.black.opacity(0.8)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 32)
                    }
                } else {
                    ZStack {
                        Color.black.opacity(0.45).allowsHitTesting(false)

                        VStack {
                            // Top Bar
                            HStack(spacing: 16) {
                                Button {
                                    appVM.closePlayer()
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 52, height: 52)
                                        .background(Circle().fill(Color.black.opacity(0.35)))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                VStack(spacing: 2) {
                                    Text(appVM.playingMedia?.title ?? "")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    if let ep = appVM.playingEpisodeTitle {
                                        Text("S\(appVM.playingSeason ?? 1):E\(appVM.playingEpisode ?? 1) \(ep)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(NFTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Button {
                                    appVM.zoomToFillScreen.toggle()
                                } label: {
                                    Image(systemName: appVM.zoomToFillScreen ? "arrow.down.right.and.arrow.up.left" : "aspectratio")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.white)
                                        .frame(width: 52, height: 52)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 52)
                            .padding(.top, 20)

                            Spacer()

                            // Center Play/Pause + 10s Skip
                            HStack(spacing: 56) {
                                Button {
                                    appVM.skipBackward()
                                } label: {
                                    Image(systemName: "gobackward.10")
                                        .font(.system(size: 32, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    appVM.togglePlayPause()
                                } label: {
                                    Image(systemName: appVM.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 46, weight: .regular))
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    appVM.skipForward()
                                } label: {
                                    Image(systemName: "goforward.10")
                                        .font(.system(size: 32, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                            }

                            Spacer()

                            // Bottom Scrubber & Netflix Action Row
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    Text(formatTime(appVM.currentTime))
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.white)

                                    GeometryReader { barGeo in
                                        let pct = appVM.duration > 0 ? min(1, max(0, appVM.currentTime / appVM.duration)) : 0
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.white.opacity(0.3)).frame(height: 3)
                                            Capsule().fill(NFTheme.netflixRed).frame(width: barGeo.size.width * CGFloat(pct), height: 3)
                                            Circle()
                                                .fill(NFTheme.netflixRed)
                                                .frame(width: 14, height: 14)
                                                .offset(x: max(0, min(barGeo.size.width - 14, barGeo.size.width * CGFloat(pct) - 7)))
                                        }
                                        .frame(height: 20)
                                        .contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { val in
                                                    let p = max(0, min(1, val.location.x / max(1, barGeo.size.width)))
                                                    appVM.seek(to: Double(p) * appVM.duration)
                                                }
                                        )
                                    }
                                    .frame(height: 20)

                                    Text(formatTime(max(0, appVM.duration - appVM.currentTime)))
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(NFTheme.textSecondary)
                                }

                                HStack(spacing: 36) {
                                    Button {
                                        showSpeedSheet = true
                                    } label: {
                                        Label("Vitesse (\(String(format: "%.2gx", appVM.playbackSpeed)))", systemImage: "speedometer")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        appVM.isControlsLocked = true
                                    } label: {
                                        Label("Verrouiller", systemImage: "lock")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        showSourcesSheet = true
                                    } label: {
                                        Label("Serveurs (\(appVM.availableStreams.count))", systemImage: "server.rack")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 52)
                            .padding(.bottom, 22)
                        }
                    }
                }
                }
                .zIndex(10)
            }
        }
        .frame(width: width, height: height)
    }

    private func formatTime(_ sec: TimeInterval) -> String {
        let total = max(0, Int(sec))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

public struct NFStreamSourcePickerSheet: View {
    @EnvironmentObject private var appVM: NFAppViewModel
    @Environment(\.dismiss) private var dismiss

    public init() {}

    private var groupedProviders: [(provider: String, sources: [NFStreamSource])] {
        let order = ["PurStream", "Links", "FStream", "Wiflix", "Movix"]
        let dict = Dictionary(grouping: appVM.availableStreams, by: { $0.provider })
        let sortedKeys = dict.keys.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? 99
            let ib = order.firstIndex(of: b) ?? 99
            return ia == ib ? a < b : ia < ib
        }
        return sortedKeys.compactMap { k in
            guard let list = dict[k] else { return nil }
            return (k, list)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Serveurs Movix (\(appVM.availableStreams.count))")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Fermer") { dismiss() }
                    .foregroundStyle(NFTheme.netflixRed)
            }
            .padding(16)

            Rectangle().fill(NFTheme.separator).frame(height: 0.5)

            if appVM.availableStreams.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text("Aucun serveur disponible")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Ce titre n'a pas encore de source sur Movix.")
                        .font(.system(size: 13))
                        .foregroundStyle(NFTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groupedProviders, id: \.provider) { group in
                            Text(group.provider.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(NFTheme.textSecondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                                .padding(.bottom, 6)

                            ForEach(group.sources) { src in
                                Button {
                                    appVM.switchStreamSource(src)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(src.name)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundStyle(.white)
                                            HStack(spacing: 6) {
                                                Text(src.isEmbed ? "LECTEUR WEB" : "DIRECT \(src.format.uppercased())")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(src.isEmbed ? NFTheme.textSecondary : Color.green)
                                                Text("• \(src.quality) • \(src.language)")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(NFTheme.textSecondary)
                                            }
                                        }
                                        Spacer()
                                        if appVM.activeStream?.id == src.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(NFTheme.netflixRed)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)
                                Rectangle().fill(NFTheme.separator).frame(height: 0.5)
                            }
                        }
                    }
                }
            }
        }
        .background(NFTheme.backgroundSecondary)
    }
}

public struct NFSpeedPickerSheet: View {
    @EnvironmentObject private var appVM: NFAppViewModel
    @Environment(\.dismiss) private var dismiss

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Text("Vitesse de lecture")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .padding(16)
            Rectangle().fill(NFTheme.separator).frame(height: 0.5)
            ForEach(speeds, id: \.self) { sp in
                Button {
                    appVM.changeSpeed(sp)
                    dismiss()
                } label: {
                    HStack {
                        Text(sp == 1.0 ? "1.0x (Normal)" : "\(String(format: "%.2g", sp))x")
                            .foregroundStyle(.white)
                        Spacer()
                        if abs(appVM.playbackSpeed - sp) < 0.01 {
                            Image(systemName: "checkmark")
                                .foregroundStyle(NFTheme.netflixRed)
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .background(NFTheme.backgroundSecondary)
    }
}
