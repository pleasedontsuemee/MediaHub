import SwiftUI

// MARK: - 1. Home Screen (`GeneralBrowsing #01, #06, #07, #21` & `Searching #01`)
public struct YTHomeView: View {
    @EnvironmentObject private var appVM: YTAppViewModel

    public init() {}

    public var body: some View {
        NavigationStack(path: $appVM.homeNavigationPath) {
            VStack(spacing: 0) {
                YTTopHeaderBarView()

                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        // Category Filter Chips Bar (`All`, `New to you`, `Mixes`, `Gaming`...)
                        YTFilterChipsBarView(
                            chips: YTCatalogData.homeFilterChips,
                            selectedChip: appVM.selectedHomeChip,
                            showExploreCompass: true,
                            onSelectChip: { chip in
                                appVM.selectHomeChip(chip)
                            },
                            onTapExplore: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                                    appVM.isExploreDrawerOpen = true
                                }
                            }
                        )

                        if appVM.isLoadingFeed {
                            ForEach(0..<3, id: \.self) { _ in
                                YTVideoCardSkeletonView()
                            }
                        } else {
                            // Shorts Shelf (`GeneralBrowsing #01` & `#07`) when "All" or "New to you" is selected
                            if appVM.selectedHomeChip == "All" || appVM.selectedHomeChip == "New to you" {
                                YTShortsShelfView(shorts: appVM.shortsShelfVideos)
                            }

                            // Sponsored Banner Card when "All" is selected in non-Premium mode (`Searching #01`)
                            if !appVM.isPremiumHeader && appVM.selectedHomeChip == "All" {
                                YTSponsoredFeedCardView()
                            }

                            // Main Video Feed Cards
                            ForEach(appVM.homeVideos) { video in
                                YTVideoCardView(video: video)
                            }
                        }
                    }
                    .padding(.bottom, appVM.currentVideo != nil ? 76 : 16)
                }
                .refreshable {
                    await appVM.refreshHomeFeed()
                }
            }
            .background(YTTheme.backgroundPrimary)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: YTNavigationRoute.self) { route in
                YTRouteDestinationView(route: route)
            }
        }
    }
}

// MARK: - Sponsored Feed Card (`Searching #01` Gulfood Ad Card)
public struct YTSponsoredFeedCardView: View {
    @EnvironmentObject private var appVM: YTAppViewModel

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [YTTheme.color(hex: "#FAFAFA"), YTTheme.color(hex: "#ECEFF1")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .aspectRatio(16.0 / 9.0, contentMode: .fit)

                VStack(spacing: 10) {
                    HStack(spacing: 16) {
                        Text("Gulfood")
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .italic()
                            .foregroundStyle(Color.black)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("20–24 FEB 2023")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.black)
                            Text("DUBAI WORLD TRADE CENTRE")
                                .font(.system(size: 7, weight: .medium))
                                .foregroundStyle(Color.gray)
                        }
                    }

                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SUPER EARLY BIRD")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(YTTheme.subscribeRed)
                            Text("OFFER")
                                .font(.system(size: 30, weight: .black))
                                .foregroundStyle(YTTheme.color(hex: "#1E293B"))
                        }

                        VStack(alignment: . center, spacing: 2) {
                            Text("AED 495")
                                .font(.system(size: 15, weight: .semibold))
                                .strikethrough(true, color: .red)
                                .foregroundStyle(.black)
                            Text("AED 195")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.black)
                        }
                    }

                    Text("REGISTER NOW")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(YTTheme.subscribeRed)
                }
            }

            // Blue CTA Strip ("VISIT SITE")
            Button {
                appVM.showToast("Opening advertiser site...")
            } label: {
                HStack {
                    Text("VISIT SITE")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(YTTheme.callToActionBlue)
                    Spacer()
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 16))
                        .foregroundStyle(YTTheme.callToActionBlue)
                }
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(YTTheme.color(hex: "#F2F8FF"))
            }
            .buttonStyle(.plain)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("20-24 February 2023")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(YTTheme.textPrimary)
                    Text("Visit Gulfood, the world's largest F&B event with 5000+ exhibitors from 120+ countries.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(YTTheme.textSecondary)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        Text("Ad")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(YTTheme.textPrimary)
                        Text("· gulfood.com")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(YTTheme.textSecondary)
                    }
                    .padding(.top, 2)
                }
                Spacer()
                YTIcon("yt_outline_overflow_vertical_24pt", fallback: "ellipsis", size: 20)
                    .foregroundStyle(YTTheme.textPrimary)
            }
            .padding(14)

            Rectangle()
                .fill(YTTheme.separator)
                .frame(height: 0.5)
        }
        .background(YTTheme.backgroundPrimary)
    }
}

// MARK: - 2. Explore Left Side Drawer (`GeneralBrowsing #10` - `ABCSideDrawerViewController`)
public struct YTExploreSideDrawerOverlay: View {
    @EnvironmentObject private var appVM: YTAppViewModel

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if appVM.isExploreDrawerOpen {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                appVM.isExploreDrawerOpen = false
                            }
                        }

                    VStack(alignment: .leading, spacing: 0) {
                        // Top Logo
                        HStack {
                            YTWordmarkLogoView(isPremium: appVM.isPremiumHeader)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 24)

                        // 9 Explore Categories (`Trending`, `Music`, `Movies & Shows`, `Live`, `Gaming`, `News`, `Sports`, `Learning`, `Fashion & Beauty`)
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(YTExploreCategory.allCases) { category in
                                    Button {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                            appVM.isExploreDrawerOpen = false
                                        }
                                        handleCategorySelection(category)
                                    } label: {
                                        HStack(spacing: 24) {
                                            YTIcon(category.iconAssetName, fallback: category.sfSymbolFallback, size: 24)
                                                .foregroundStyle(YTTheme.textPrimary)

                                            Text(category.rawValue)
                                                .font(.system(size: 16, weight: .regular))
                                                .foregroundStyle(YTTheme.textPrimary)

                                            Spacer()
                                        }
                                        .padding(.horizontal, 24)
                                        .frame(height: 52)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Spacer()
                    }
                    .frame(width: min(374, geo.size.width * 0.85))
                    .frame(maxHeight: .infinity)
                    .background(YTTheme.backgroundPrimary.ignoresSafeArea())
                    .transition(.move(edge: .leading))
                }
            }
        }
    }

    private func handleCategorySelection(_ category: YTExploreCategory) {
        switch category {
        case .trending:
            appVM.pushRoute(.trending(initialTab: "NOW"))
        case .music:
            appVM.pushRoute(.trending(initialTab: "MUSIC"))
        case .gaming:
            appVM.pushRoute(.trending(initialTab: "GAMING"))
        case .moviesAndShows:
            appVM.pushRoute(.trending(initialTab: "MOVIES"))
        case .live:
            appVM.pushRoute(.liveHub)
        default:
            appVM.selectHomeChip(category.rawValue)
        }
    }
}

// MARK: - 3. Trending Screen (`GeneralBrowsing #12, #13, #27, #34` - NOW / MUSIC / GAMING / MOVIES)
public struct YTTrendingView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: String

    private let tabs = ["NOW", "MUSIC", "GAMING", "MOVIES"]

    public init(initialTab: String = "NOW") {
        _selectedTab = State(initialValue: initialTab)
    }

    public var body: some View {
        VStack(spacing: 0) {
            YTTopHeaderBarView(showBackButton: true, customTitle: "Trending") {
                dismiss()
            }

            // Tab Strip (`NOW`, `MUSIC`, `GAMING`, `MOVIES`)
            HStack(spacing: 0) {
                ForEach(tabs, id: \.self) { tab in
                    let isSelected = (tab == selectedTab)
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 10) {
                            Text(tab)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(isSelected ? YTTheme.textPrimary : YTTheme.textSecondary)
                                .padding(.top, 12)

                            Rectangle()
                                .fill(isSelected ? YTTheme.textPrimary : Color.clear)
                                .frame(height: 2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(YTTheme.separator).frame(height: 0.5)
            }
            .background(YTTheme.backgroundPrimary)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    // Featured Event Shelf (`FIFA World Cup Qatar 2022™` in `GeneralBrowsing #13`) when on `NOW`
                    if selectedTab == "NOW" {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(YTTheme.backgroundSecondary)
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "trophy.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(YTTheme.subscribeRed)
                                }
                                Text("FIFA World Cup Qatar 2022™")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(YTTheme.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 14)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(YTCatalogData.worldCupHighlights) { wcVideo in
                                        Button {
                                            appVM.openVideo(wcVideo)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 8) {
                                                ZStack(alignment: .bottomTrailing) {
                                                    YTCachedAsyncImage(url: wcVideo.thumbnailURL) {
                                                        Rectangle().fill(YTTheme.backgroundSecondary)
                                                    }
                                                    .frame(width: 280, height: 158)
                                                    .clipped()

                                                    Text(wcVideo.durationText)
                                                        .font(.system(size: 12, weight: .medium))
                                                        .foregroundStyle(.white)
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 2)
                                                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.82)))
                                                        .padding(8)
                                                }

                                                HStack(alignment: .top) {
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text(wcVideo.title)
                                                            .font(.system(size: 14, weight: .regular))
                                                            .foregroundStyle(YTTheme.textPrimary)
                                                            .lineLimit(2)
                                                            .multilineTextAlignment(.leading)
                                                        Text(wcVideo.channelTitle)
                                                            .font(.system(size: 12))
                                                            .foregroundStyle(YTTheme.textSecondary)
                                                        Text("\(wcVideo.viewCountText) · \(wcVideo.publishedTimeText)")
                                                            .font(.system(size: 12))
                                                            .foregroundStyle(YTTheme.textSecondary)
                                                    }
                                                    Spacer()
                                                    YTIcon("yt_outline_overflow_vertical_24pt", fallback: "ellipsis", size: 18)
                                                        .foregroundStyle(YTTheme.textPrimary)
                                                }
                                            }
                                            .frame(width: 280)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 14)
                            }
                            .padding(.bottom, 14)

                            Rectangle()
                                .fill(YTTheme.backgroundSecondary)
                                .frame(height: 6)
                        }
                    }

                    Text("Trending videos")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(YTTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)

                    ForEach(YTCatalogData.trendingVideos(for: selectedTab)) { video in
                        YTVideoCardView(video: video)
                    }
                }
                .padding(.bottom, appVM.currentVideo != nil ? 76 : 16)
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - 4. Live Channel Hub (`GeneralBrowsing #22 & #37`)
public struct YTLiveHubView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = "HOME"

    public init() {}

    public var body: some View {
        let isSub = appVM.isSubscribed(to: "UC_live_hub", channelTitle: "Live")

        VStack(spacing: 0) {
            YTTopHeaderBarView(showBackButton: true, customTitle: "Live") {
                dismiss()
            }

            HStack(spacing: 0) {
                ForEach(["HOME", "ABOUT"], id: \.self) { tab in
                    let active = (tab == selectedTab)
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 10) {
                            Text(tab)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(active ? YTTheme.textPrimary : YTTheme.textSecondary)
                                .padding(.top, 12)
                            Rectangle()
                                .fill(active ? YTTheme.textPrimary : Color.clear)
                                .frame(height: 2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(YTTheme.separator).frame(height: 0.5)
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    // Live Hub Header (`GeneralBrowsing #37`)
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(YTTheme.color(hex: "#0D5C63"))
                                .frame(width: 72, height: 72)
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(YTTheme.color(hex: "#BAFF39"))
                        }
                        .padding(.top, 18)

                        Text("Live")
                            .font(YTFontManager.youtubeSans(size: 24, weight: .bold))
                            .foregroundStyle(YTTheme.textPrimary)

                        Button {
                            appVM.toggleSubscription(for: "UC_live_hub", channelTitle: "Live")
                        } label: {
                            Text(isSub ? "SUBSCRIBED" : "SUBSCRIBE")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(isSub ? YTTheme.textSecondary : YTTheme.subscribeRed)
                        }
                        .buttonStyle(.plain)

                        Text("@live · 15.6M subscribers · No videos")
                            .font(.system(size: 12))
                            .foregroundStyle(YTTheme.textPrimary)

                        HStack {
                            Text("YouTube Live - Watch great live streams, such as live gaming, live music, live sports, and live news.")
                                .font(.system(size: 12))
                                .foregroundStyle(YTTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(YTTheme.textSecondary)
                        }
                        .padding(.horizontal, 24)
                    }

                    // Sections: `Featured Live Streams` and `Live Now` (`GeneralBrowsing #22`)
                    VStack(alignment: .leading, spacing: 18) {
                        liveSectionHeader(title: "Featured Live Streams")
                        if let first = YTCatalogData.liveHubStreams.first {
                            YTCompactHorizontalVideoRow(video: first)
                        }

                        liveSectionHeader(title: "Live Now")
                        ForEach(YTCatalogData.liveHubStreams.dropFirst()) { stream in
                            YTCompactHorizontalVideoRow(video: stream)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }
                .padding(.bottom, appVM.currentVideo != nil ? 76 : 20)
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func liveSectionHeader(title: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(YTTheme.color(hex: "#0D5C63"))
                    .frame(width: 36, height: 36)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(YTTheme.color(hex: "#BAFF39"))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(YTTheme.textPrimary)
                Text("by Live")
                    .font(.system(size: 12))
                    .foregroundStyle(YTTheme.textSecondary)
            }
            Spacer()
        }
    }
}

// MARK: - Compact Horizontal Video Row (`GeneralBrowsing #11, #22, #37`)
public struct YTCompactHorizontalVideoRow: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    public let video: YTVideo

    public init(video: YTVideo) {
        self.video = video
    }

    public var body: some View {
        Button {
            appVM.openVideo(video)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    YTCachedAsyncImage(url: video.thumbnailURL) {
                        Rectangle().fill(YTTheme.backgroundSecondary)
                    }
                    .frame(width: 160, height: 90)
                    .clipped()

                    if video.isLive {
                        HStack(spacing: 4) {
                            if !video.isUpcoming {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            Text(video.isUpcoming ? "UPCOMING" : "LIVE")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(video.isUpcoming ? Color.black.opacity(0.82) : YTTheme.subscribeRed)
                        )
                        .padding(6)
                    } else {
                        Text(video.durationText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.82)))
                            .padding(6)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(YTTheme.textPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    Text(video.channelTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(YTTheme.textSecondary)

                    Text(video.viewCountText)
                        .font(.system(size: 12))
                        .foregroundStyle(YTTheme.textSecondary)
                }

                Spacer(minLength: 2)

                YTIcon("yt_outline_overflow_vertical_24pt", fallback: "ellipsis", size: 18)
                    .foregroundStyle(YTTheme.textPrimary)
            }
        }
        .buttonStyle(.plain)
    }
}
