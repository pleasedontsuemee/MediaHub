import SwiftUI

// MARK: - 1. Top Navigation Header (`YTHeaderView` / `YTNavigationBar`)
public struct YTTopHeaderBarView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    public var showBackButton: Bool = false
    public var customTitle: String? = nil
    public var onBack: (() -> Void)? = nil

    public init(showBackButton: Bool = false, customTitle: String? = nil, onBack: (() -> Void)? = nil) {
        self.showBackButton = showBackButton
        self.customTitle = customTitle
        self.onBack = onBack
    }

    public var body: some View {
        HStack(spacing: 16) {
            if showBackButton {
                Button {
                    onBack?()
                } label: {
                    YTIcon("yt_outline_arrow_left_24pt", fallback: "arrow.left", size: 24)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)

                if let title = customTitle {
                    Text(title)
                        .font(YTFontManager.youtubeSans(size: 20, weight: .bold))
                        .foregroundStyle(YTTheme.textPrimary)
                        .lineLimit(1)
                }
            } else {
                Button {
                    Task {
                        await appVM.refreshHomeFeed()
                    }
                } label: {
                    YTWordmarkLogoView(isPremium: appVM.isPremiumHeader)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            // Right action icons: Cast, Notifications, Search, User Avatar ("S")
            HStack(spacing: 18) {
                Button {
                    appVM.isCastAlertPresented = true
                } label: {
                    YTIcon("yt_outline_chromecast_24pt", fallback: "tv.badge.wifi", size: 24)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)

                if !showBackButton {
                    Button {
                        appVM.isNotificationsSheetPresented = true
                    } label: {
                        YTIcon("yt_outline_bell_24pt", fallback: "bell", size: 24)
                            .foregroundStyle(YTTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    appVM.isSearchOverlayPresented = true
                } label: {
                    YTIcon("yt_outline_search_24pt", fallback: "magnifyingglass", size: 24)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)

                if showBackButton {
                    Menu {
                        Button {
                            appVM.isHelpPresented = true
                        } label: {
                            Label("Help & feedback", systemImage: "questionmark.circle")
                        }
                        Button("Share", systemImage: "square.and.arrow.up") {
                            appVM.showToast("Link copied to clipboard")
                        }
                    } label: {
                        YTIcon("yt_outline_overflow_vertical_24pt", fallback: "ellipsis", size: 24)
                            .foregroundStyle(YTTheme.textPrimary)
                    }
                } else {
                    Button {
                        appVM.isSettingsPresented = true
                    } label: {
                        YTIcon("yt_outline_gear_24pt", fallback: "gearshape", size: 22)
                            .foregroundStyle(YTTheme.textPrimary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(YTTheme.backgroundPrimary)
    }
}

// MARK: - 2. User Avatar Circle ("S" Demo User)
public struct YTUserAvatarBadge: View {
    public let letter: String
    public let size: CGFloat
    public var backgroundHex: String = "#5C4033"

    public init(letter: String = "S", size: CGFloat = 24, backgroundHex: String = "#5C4033") {
        self.letter = letter
        self.size = size
        self.backgroundHex = backgroundHex
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(YTTheme.color(hex: backgroundHex))
                .frame(width: size, height: size)
            Text(letter)
                .font(.system(size: size * 0.54, weight: .medium))
                .foregroundStyle(Color.white)
        }
    }
}

// MARK: - 3. Horizontal Filter Chips Bar (`YTChipCloudChipView` - 32pt height, 12pt horizontal padding)
public struct YTFilterChipsBarView: View {
    public let chips: [String]
    public let selectedChip: String
    public var showExploreCompass: Bool = true
    public let onSelectChip: (String) -> Void
    public var onTapExplore: (() -> Void)? = nil

    public init(
        chips: [String],
        selectedChip: String,
        showExploreCompass: Bool = true,
        onSelectChip: @escaping (String) -> Void,
        onTapExplore: (() -> Void)? = nil
    ) {
        self.chips = chips
        self.selectedChip = selectedChip
        self.showExploreCompass = showExploreCompass
        self.onSelectChip = onSelectChip
        self.onTapExplore = onTapExplore
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if showExploreCompass {
                    Button {
                        onTapExplore?()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(YTTheme.backgroundSecondary)
                                .frame(width: 40, height: 32)
                            YTIcon("yt_outline_compass_24pt", fallback: "safari", size: 22)
                                .foregroundStyle(YTTheme.textPrimary)
                        }
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(YTTheme.separator)
                        .frame(width: 1, height: 20)
                        .padding(.horizontal, 4)
                }

                ForEach(chips, id: \.self) { chip in
                    let isSelected = (chip == selectedChip)
                    let isNewToYou = (chip == "New to you")

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            onSelectChip(chip)
                        }
                    } label: {
                        Text(chip)
                            .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(isSelected ? YTTheme.chipSelectedText : YTTheme.textPrimary)
                            .padding(.horizontal, 12) // Disassembled +[YTChipCloudChipView chipEdgePaddingX] = 12.0 pt
                            .frame(height: 32)        // Disassembled +[YTChipCloudChipView chipHeight] = 32.0 pt
                            .background(
                                Capsule(style: .continuous)
                                    .fill(
                                        isSelected
                                            ? YTTheme.chipSelectedBackground
                                            : (isNewToYou ? YTTheme.backgroundPrimary : YTTheme.backgroundSecondary)
                                    )
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        isNewToYou && !isSelected
                                            ? AnyShapeStyle(YTTheme.newToYouGradient)
                                            : AnyShapeStyle(isSelected ? Color.clear : YTTheme.separator.opacity(0.8)),
                                        lineWidth: isNewToYou && !isSelected ? 1.5 : 0.8
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(YTTheme.backgroundPrimary)
    }
}

// MARK: - 4. Full-Bleed 16:9 Video Card (`video_view_narrow.flexb`)
public struct YTVideoCardView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    public let video: YTVideo
    public var onTapVideo: (() -> Void)? = nil
    public var onTapChannel: (() -> Void)? = nil

    public init(video: YTVideo, onTapVideo: (() -> Void)? = nil, onTapChannel: (() -> Void)? = nil) {
        self.video = video
        self.onTapVideo = onTapVideo
        self.onTapChannel = onTapChannel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 16:9 Full-Bleed Thumbnail
            Button {
                if let custom = onTapVideo {
                    custom()
                } else {
                    appVM.openVideo(video)
                }
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    YTCachedAsyncImage(url: video.thumbnailURL) {
                        Rectangle()
                            .fill(YTTheme.backgroundSecondary)
                            .ytShimmer()
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipped()

                    // Duration or LIVE badge
                    if video.isLive {
                        HStack(spacing: 4) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 10, weight: .bold))
                            Text(video.isUpcoming ? "UPCOMING" : "LIVE")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(video.isUpcoming ? Color.black.opacity(0.82) : YTTheme.subscribeRed)
                        )
                        .padding(8)
                    } else if video.isShort {
                        HStack(spacing: 4) {
                            YTShortsLogoIcon(size: 14)
                            Text("SHORTS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.black)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.95))
                        )
                        .padding(8)
                    } else {
                        Text(video.durationText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.black.opacity(0.82))
                            )
                            .padding(8)
                    }

                    // Red watch progress bar along bottom edge if partially watched
                    if video.watchProgress > 0 {
                        GeometryReader { geo in
                            VStack {
                                Spacer()
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.35))
                                        .frame(height: 3)
                                    Rectangle()
                                        .fill(YTTheme.brandRed)
                                        .frame(width: geo.size.width * CGFloat(min(1.0, video.watchProgress)), height: 3)
                                }
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            // Metadata Container (`channelThumbnailView` + `titleLabel` + `subtitleView` + `actionButton`)
            HStack(alignment: .top, spacing: 12) {
                Button {
                    if let tapCh = onTapChannel {
                        tapCh()
                    } else {
                        let ch = appVM.channel(for: video.channelId, fallbackTitle: video.channelTitle, avatarURL: video.channelAvatarURL)
                        appVM.pushRoute(.channel(ch))
                    }
                } label: {
                    YTChannelAvatarView(url: video.channelAvatarURL, title: video.channelTitle, size: 36)
                }
                .buttonStyle(.plain)

                Button {
                    if let custom = onTapVideo {
                        custom()
                    } else {
                        appVM.openVideo(video)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.title)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(YTTheme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(video.subtitleLine)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(YTTheme.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                // 3-dot Contextual Menu Button (`actionButton`)
                Menu {
                    Button {
                        appVM.toggleVideo(video, inPlaylist: "WL")
                    } label: {
                        Label("Save to Watch later", systemImage: "clock")
                    }
                    Button {
                        appVM.presentSaveToPlaylist(for: video)
                    } label: {
                        Label("Save to playlist", systemImage: "plus.square.on.square")
                    }
                    Button {
                        Task {
                            let ok = await YTOfflineDownloadManager.shared.downloadVideo(video)
                            appVM.showToast(ok ? "Video downloaded for offline viewing" : "Download failed")
                        }
                    } label: {
                        Label("Download video", systemImage: "arrow.down.to.line")
                    }
                    Button {
                        appVM.showToast("Link copied to clipboard")
                    } label: {
                        Label("Share", systemImage: "arrowshape.turn.up.right")
                    }
                } label: {
                    YTIcon("yt_outline_overflow_vertical_24pt", fallback: "ellipsis", size: 20)
                        .foregroundStyle(YTTheme.textPrimary)
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(YTTheme.backgroundPrimary)
    }
}

// MARK: - 5. Channel Avatar Helper
public struct YTChannelAvatarView: View {
    public let url: URL?
    public let title: String
    public let size: CGFloat

    public init(url: URL?, title: String, size: CGFloat = 36) {
        self.url = url
        self.title = title
        self.size = size
    }

    public var body: some View {
        if let u = url {
            YTCachedAsyncImage(url: u) {
                fallbackBadge
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            fallbackBadge
        }
    }

    private var fallbackBadge: some View {
        let initial = String(title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        let colors = ["#C62828", "#00695C", "#1565C0", "#4527A0", "#EF6C00", "#2E7D32"]
        let colorHex = colors[abs(title.hashValue) % colors.count]
        return ZStack {
            Circle()
                .fill(YTTheme.color(hex: colorHex))
                .frame(width: size, height: size)
            Text(initial.isEmpty ? "Y" : initial)
                .font(YTFontManager.youtubeSans(size: size * 0.48, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - 6. Shorts Shelf Carousel (`GeneralBrowsing #01` & `#07`)
public struct YTShortsShelfView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    public let shorts: [YTVideo]

    public init(shorts: [YTVideo]) {
        self.shorts = shorts
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top thick divider
            Rectangle()
                .fill(YTTheme.backgroundSecondary)
                .frame(height: 6)

            // Header: Red Shorts icon + "Shorts"
            HStack(spacing: 8) {
                YTShortsLogoIcon(size: 24)
                Text("Shorts")
                    .font(YTFontManager.youtubeSans(size: 19, weight: .bold))
                    .foregroundStyle(YTTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)

            // Horizontal Carousel of 9:16 vertical cards (`154x256 pt`)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(shorts.enumerated()), id: \.element.id) { idx, short in
                        Button {
                            appVM.activeShortIndex = idx
                            appVM.selectedTab = .shorts
                            appVM.playShortInFeed(at: idx)
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                YTCachedAsyncImage(url: short.thumbnailURL) {
                                    Rectangle()
                                        .fill(YTTheme.backgroundSecondary)
                                        .ytShimmer()
                                }
                                .frame(width: 154, height: 256)
                                .clipped()
                                .overlay(
                                    LinearGradient(
                                        colors: [.clear, .black.opacity(0.75)],
                                        startPoint: .center,
                                        endPoint: .bottom
                                    )
                                )

                                Image(systemName: "ellipsis")
                                    .rotationEffect(.degrees(90))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(10)

                                VStack(alignment: .leading, spacing: 4) {
                                    Spacer()
                                    Text(short.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                    Text(short.viewCountText)
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                                .padding(10)
                                .frame(width: 154, height: 256, alignment: .bottomLeading)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }

            // Bottom thick divider
            Rectangle()
                .fill(YTTheme.backgroundSecondary)
                .frame(height: 6)
                .padding(.top, 4)
        }
        .background(YTTheme.backgroundPrimary)
    }
}

// MARK: - 7. Bottom Tab Bar (`YTPivotBarView` - 5 tabs)
public struct YTPivotTabBarView: View {
    @EnvironmentObject private var appVM: YTAppViewModel

    public init() {}

    private var isShortsDarkTab: Bool {
        appVM.selectedTab == .shorts && !appVM.isPlayerExpanded
    }

    public var body: some View {
        let fgColor: Color = isShortsDarkTab ? .white : YTTheme.textPrimary
        let bgColor: Color = isShortsDarkTab ? .black : YTTheme.backgroundPrimary
        let sepColor: Color = isShortsDarkTab ? Color.white.opacity(0.18) : YTTheme.separator

        VStack(spacing: 0) {
            Rectangle()
                .fill(sepColor)
                .frame(height: 0.5)

            HStack(spacing: 0) {
                // 1. Home
                pivotTabButton(
                    tab: .home,
                    title: "Home",
                    activeAsset: "yt_fill_home_24pt",
                    inactiveAsset: "yt_outline_home_24pt",
                    fallbackActive: "house.fill",
                    fallbackInactive: "house",
                    fgColor: fgColor
                )

                // 2. Shorts
                pivotTabButton(
                    tab: .shorts,
                    title: "Shorts",
                    activeAsset: "yt_fill_youtube_shorts_24pt",
                    inactiveAsset: "yt_outline_youtube_shorts_24pt",
                    fallbackActive: "bolt.fill",
                    fallbackInactive: "bolt",
                    fgColor: fgColor
                )

                // 3. Create (+) Center Circle Button (`38x38 pt`) — Inert (does nothing) as requested
                ZStack {
                    Circle()
                        .strokeBorder(fgColor, lineWidth: 1.2)
                        .frame(width: 36, height: 36)
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(fgColor)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)

                // 4. Subscriptions
                pivotTabButton(
                    tab: .subscriptions,
                    title: "Subscriptions",
                    activeAsset: "yt_fill_subscriptions_24pt",
                    inactiveAsset: "yt_outline_subscriptions_24pt",
                    fallbackActive: "play.square.stack.fill",
                    fallbackInactive: "play.square.stack",
                    fgColor: fgColor
                )

                // 5. Library
                pivotTabButton(
                    tab: .library,
                    title: "Library",
                    activeAsset: "yt_fill_library_24pt",
                    inactiveAsset: "yt_outline_library_24pt",
                    fallbackActive: "play.rectangle.on.rectangle.fill",
                    fallbackInactive: "play.rectangle.on.rectangle",
                    fgColor: fgColor
                )
            }
            .frame(height: 48) // Disassembled +[YTPivotBarView pivotBarHeight]
            .background(bgColor)
        }
        .background(bgColor.ignoresSafeArea(edges: .bottom))
    }

    private func pivotTabButton(
        tab: YTMainTab,
        title: String,
        activeAsset: String,
        inactiveAsset: String,
        fallbackActive: String,
        fallbackInactive: String,
        fgColor: Color
    ) -> some View {
        let isSelected = (appVM.selectedTab == tab)
        return Button {
            if appVM.selectedTab == tab {
                // Pop to root if already selected
                switch tab {
                case .home: appVM.homeNavigationPath.removeAll()
                case .subscriptions: appVM.subscriptionsNavigationPath.removeAll()
                case .library: appVM.libraryNavigationPath.removeAll()
                default: break
                }
            } else {
                appVM.selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                YTIcon(
                    isSelected ? activeAsset : inactiveAsset,
                    fallback: isSelected ? fallbackActive : fallbackInactive,
                    size: 24
                )
                .foregroundStyle(fgColor)

                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(fgColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 8. Docked Mini-Player (`YTWatchMiniBarView` - 56pt height above Tab Bar)
public struct YTMiniPlayerBarView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    public let video: YTVideo

    public init(video: YTVideo) {
        self.video = video
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Left 16:9 Mini Thumbnail (`100x56 pt`)
                ZStack {
                    YTCachedAsyncImage(url: video.thumbnailURL) {
                        Rectangle().fill(Color.black)
                    }
                    .frame(width: 100, height: 56)
                    .clipped()
                }

                // Title & Channel Subtitle
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(YTTheme.textPrimary)
                        .lineLimit(1)

                    Text(video.channelTitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(YTTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Play/Pause Button (`||` or `▶`)
                Button {
                    appVM.togglePlayPause()
                } label: {
                    Image(systemName: appVM.isPlaying ? "pause" : "play.fill")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(YTTheme.textPrimary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)

                // Close Button (`✕`)
                Button {
                    appVM.closeMiniPlayer()
                } label: {
                    YTIcon("yt_outline_x_24pt", fallback: "xmark", size: 22)
                        .foregroundStyle(YTTheme.textPrimary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
            .frame(height: 56)
            .background(YTTheme.backgroundPrimary)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    appVM.isPlayerExpanded = true
                }
            }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { val in
                        if val.translation.height < -25 {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                appVM.isPlayerExpanded = true
                            }
                        } else if val.translation.height > 35 {
                            appVM.closeMiniPlayer()
                        }
                    }
            )

            // Bottom red progress bar (`2 pt` height)
            GeometryReader { geo in
                let fraction = appVM.duration > 0 ? min(1.0, max(0.0, appVM.currentTime / appVM.duration)) : 0.35
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(YTTheme.separator)
                        .frame(height: 2)
                    Rectangle()
                        .fill(YTTheme.brandRed)
                        .frame(width: geo.size.width * CGFloat(fraction), height: 2)
                }
            }
            .frame(height: 2)
        }
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: -2)
    }
}

// MARK: - 9. Snackbar / Toast (`YTHUDMessageView` - matches `Subscribing #02, #06, #09` & `Watching #13`)
public struct YTSnackbarToastView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    public let message: String
    public let actionTitle: String?

    public init(message: String, actionTitle: String? = nil) {
        self.message = message
        self.actionTitle = actionTitle
    }

    public var body: some View {
        HStack {
            Text(message)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.white)
                .lineLimit(2)

            Spacer()

            if let act = actionTitle {
                Button {
                    appVM.triggerToastAction()
                } label: {
                    Text(act)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(YTTheme.color(hex: "#3EA6FF"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(YTTheme.snackbarBackground)
        )
        .padding(.horizontal, 12)
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 10. Notification Bell Popover (`All` / `Personalized` / `None` - matches `Subscribing #08` & `Watching #02`)
public struct YTNotificationBellMenuButton: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    public let channelId: String
    public let channelTitle: String

    @State private var showPopover = false

    public init(channelId: String, channelTitle: String) {
        self.channelId = channelId
        self.channelTitle = channelTitle
    }

    public var body: some View {
        let currentPref = appVM.notificationPreference(for: channelId, channelTitle: channelTitle)

        Button {
            showPopover = true
        } label: {
            YTIcon(currentPref.iconAssetName, fallback: "bell", size: 22)
                .foregroundStyle(YTTheme.textPrimary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
            VStack(spacing: 0) {
                ForEach(YTNotificationPreference.allCases, id: \.rawValue) { pref in
                    Button {
                        appVM.setNotificationPreference(pref, for: channelId, channelTitle: channelTitle)
                        showPopover = false
                    } label: {
                        HStack {
                            Text(pref.rawValue)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(YTTheme.textPrimary)
                            Spacer()
                            YTIcon(pref.iconAssetName, fallback: "bell", size: 22)
                                .foregroundStyle(YTTheme.textPrimary)
                        }
                        .padding(.horizontal, 16)
                        .frame(width: 210, height: 48)
                        .background(pref == currentPref ? YTTheme.backgroundSecondary : YTTheme.backgroundPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .presentationCompactAdaptation(.popover)
        }
    }
}
