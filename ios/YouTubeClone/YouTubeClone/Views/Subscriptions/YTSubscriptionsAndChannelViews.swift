import SwiftUI

// MARK: - 1. Subscriptions Tab View (Empty Until User Subscribes to Channels!)
public struct YTSubscriptionsView: View {
    @EnvironmentObject private var appVM: YTAppViewModel

    public init() {}

    private var subscribedChannels: [YTChannel] {
        appVM.channels.filter { $0.isSubscribed }
    }

    private var filteredSubscriptionVideos: [YTVideo] {
        let base = appVM.subscriptionFeedVideos
        switch appVM.selectedSubscriptionsChip {
        case "Today":
            return base.filter { $0.publishedTimeText.contains("h") || $0.publishedTimeText.contains("j") || $0.publishedTimeText.contains("day") }
        case "Continue watching":
            return base.filter { $0.watchProgress > 0 }
        case "Unwatched":
            return base.filter { $0.watchProgress == 0 }
        default:
            return base
        }
    }

    public var body: some View {
        NavigationStack(path: $appVM.subscriptionsNavigationPath) {
            VStack(spacing: 0) {
                YTTopHeaderBarView()

                if subscribedChannels.isEmpty {
                    // Clean Empty State when user hasn't subscribed to any channel yet
                    VStack(spacing: 16) {
                        Spacer()
                        YTIcon("yt_outline_subscriptions_24pt", fallback: "play.square.stack", size: 64)
                            .foregroundStyle(YTTheme.textSecondary)

                        Text("Aucun abonnement")
                            .font(YTFontManager.youtubeSans(size: 20, weight: .bold))
                            .foregroundStyle(YTTheme.textPrimary)

                        Text("Abonnez-vous à des chaînes depuis une vidéo ou la recherche pour retrouver leurs dernières vidéos ici.")
                            .font(.system(size: 14))
                            .foregroundStyle(YTTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        Button {
                            appVM.isSearchOverlayPresented = true
                        } label: {
                            Text("RECHERCHER UNE CHAÎNE")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 4).fill(YTTheme.callToActionBlue))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            // Top Channel Avatars Row (`56x56 pt` circles + fixed `ALL` button on right)
                            ZStack(alignment: .trailing) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(subscribedChannels) { channel in
                                            Button {
                                                appVM.pushRoute(.channel(channel))
                                            } label: {
                                                VStack(spacing: 6) {
                                                    ZStack(alignment: .bottomTrailing) {
                                                        YTChannelAvatarView(url: channel.avatarURL, title: channel.title, size: 56)

                                                        if channel.hasUnwatchedVideos {
                                                            Circle()
                                                                .fill(YTTheme.callToActionBlue)
                                                                .frame(width: 12, height: 12)
                                                                .overlay(
                                                                    Circle().stroke(YTTheme.backgroundPrimary, lineWidth: 2)
                                                                )
                                                                .offset(x: -1, y: -1)
                                                        }
                                                    }

                                                    Text(channel.title)
                                                        .font(.system(size: 12, weight: .regular))
                                                        .foregroundStyle(YTTheme.textSecondary)
                                                        .lineLimit(1)
                                                        .frame(width: 64)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.leading, 14)
                                    .padding(.trailing, 68)
                                    .padding(.vertical, 12)
                                }

                                Button {
                                    appVM.pushRoute(.allSubscriptions)
                                } label: {
                                    Text("ALL")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(YTTheme.callToActionBlue)
                                        .frame(width: 58, height: 88)
                                        .background(YTTheme.backgroundPrimary.opacity(0.96))
                                }
                                .buttonStyle(.plain)
                            }

                            Rectangle()
                                .fill(YTTheme.separator)
                                .frame(height: 0.5)

                            // Filter Chips (`All`, `Today`, `Continue watching`, `Unwatched`)
                            YTFilterChipsBarView(
                                chips: YTCatalogData.subscriptionsFilterChips,
                                selectedChip: appVM.selectedSubscriptionsChip,
                                showExploreCompass: false
                            ) { chip in
                                appVM.selectedSubscriptionsChip = chip
                            }

                            if appVM.isLoadingSubscriptionsFeed {
                                ForEach(0..<2, id: \.self) { _ in
                                    YTVideoCardSkeletonView()
                                }
                            } else {
                                ForEach(filteredSubscriptionVideos) { video in
                                    YTVideoCardView(video: video)
                                }
                            }
                        }
                        .padding(.bottom, appVM.currentVideo != nil ? 76 : 16)
                    }
                    .refreshable {
                        await appVM.refreshSubscriptionsFeed()
                    }
                }
            }
            .background(YTTheme.backgroundPrimary)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: YTNavigationRoute.self) { route in
                YTRouteDestinationView(route: route)
            }
            .task {
                if !subscribedChannels.isEmpty && appVM.subscriptionFeedVideos.isEmpty {
                    await appVM.refreshSubscriptionsFeed()
                }
            }
        }
    }
}

// MARK: - 2. All Subscriptions Screen (`MANAGE` + Swipe-left `UNSUBSCRIBE` + Bell Popover)
public struct YTAllSubscriptionsView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isManaging: Bool = false
    @State private var sortOrder: String = "Most relevant"
    @State private var swipedChannelId: String? = nil

    public init() {}

    private var sortedChannels: [YTChannel] {
        switch sortOrder {
        case "A-Z":
            return appVM.channels.sorted { $0.title < $1.title }
        default:
            return appVM.channels
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            YTTopHeaderBarView(showBackButton: true, customTitle: "All subscriptions") {
                dismiss()
            }

            HStack {
                Menu {
                    ForEach(["Most relevant", "A-Z"], id: \.self) { opt in
                        Button(opt) {
                            sortOrder = opt
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(sortOrder)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(YTTheme.textPrimary)
                        YTIcon("yt_outline_chevron_down_24pt", fallback: "chevron.down", size: 16)
                            .foregroundStyle(YTTheme.textSecondary)
                    }
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isManaging.toggle()
                        swipedChannelId = nil
                    }
                } label: {
                    Text(isManaging ? "DONE" : "MANAGE")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(YTTheme.callToActionBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    ForEach(sortedChannels) { channel in
                        YTAllSubscriptionChannelRow(
                            channel: channel,
                            isManaging: isManaging,
                            isSwiped: swipedChannelId == channel.id,
                            onSetSwiped: { open in
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                    swipedChannelId = open ? channel.id : nil
                                }
                            },
                            onTapChannel: {
                                appVM.pushRoute(.channel(channel))
                            }
                        )
                    }
                }
                .padding(.bottom, appVM.currentVideo != nil ? 76 : 16)
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct YTAllSubscriptionChannelRow: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    let channel: YTChannel
    let isManaging: Bool
    let isSwiped: Bool
    let onSetSwiped: (Bool) -> Void
    let onTapChannel: () -> Void

    @State private var dragX: CGFloat = 0

    var body: some View {
        let isSub = channel.isSubscribed

        ZStack(alignment: .trailing) {
            if isManaging && isSub {
                Button {
                    onSetSwiped(false)
                    appVM.toggleSubscription(for: channel.id, channelTitle: channel.title, avatarURL: channel.avatarURL)
                } label: {
                    Text("UNSUBSCRIBE")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 136, height: 60)
                        .background(YTTheme.color(hex: "#DC1414"))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 16) {
                Button(action: onTapChannel) {
                    HStack(spacing: 16) {
                        YTChannelAvatarView(url: channel.avatarURL, title: channel.title, size: 40)
                            .opacity(isSub ? 1.0 : 0.45)

                        Text(channel.title)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(isSub ? YTTheme.textPrimary : YTTheme.textDisabled)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if isManaging {
                    if isSub {
                        YTNotificationBellMenuButton(channelId: channel.id, channelTitle: channel.title)
                    } else {
                        Button {
                            appVM.toggleSubscription(for: channel.id, channelTitle: channel.title, avatarURL: channel.avatarURL)
                        } label: {
                            Text("SUBSCRIBE")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(YTTheme.subscribeRed)
                        }
                        .buttonStyle(.plain)
                    }
                } else if channel.hasUnwatchedVideos && isSub {
                    Circle()
                        .fill(YTTheme.callToActionBlue)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            .background(YTTheme.backgroundPrimary)
            .offset(x: (isManaging && isSwiped && isSub) ? -136 : min(0, dragX))
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { val in
                        guard isManaging && isSub else { return }
                        if val.translation.width < 0 {
                            dragX = max(-144, val.translation.width)
                        } else if isSwiped {
                            dragX = min(0, -136 + val.translation.width)
                        }
                    }
                    .onEnded { val in
                        guard isManaging && isSub else { return }
                        if val.translation.width < -40 {
                            onSetSwiped(true)
                        } else {
                            onSetSwiped(false)
                        }
                        dragX = 0
                    }
            )
        }
        .clipped()
    }
}

// MARK: - 3. Channel Page (Dynamically Loads the Channel's Videos from YouTube InnerTube!)
public struct YTChannelPageView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss
    public let initialChannel: YTChannel

    @State private var selectedTab: String = "HOME"
    @State private var channelVideos: [YTVideo] = []
    @State private var isLoadingChannelVideos: Bool = true
    private let tabs = ["HOME", "VIDEOS", "SHORTS", "LIVE", "PLAYLISTS"]

    public init(channel: YTChannel) {
        self.initialChannel = channel
    }

    private var isSub: Bool {
        appVM.isSubscribed(to: initialChannel.id, channelTitle: initialChannel.title)
    }

    public var body: some View {
        VStack(spacing: 0) {
            YTTopHeaderBarView(showBackButton: true, customTitle: initialChannel.title) {
                dismiss()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 28) {
                    ForEach(tabs, id: \.self) { tab in
                        let active = (tab == selectedTab)
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedTab = tab
                            }
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
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(YTTheme.separator).frame(height: 0.5)
            }
            .background(YTTheme.backgroundPrimary)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    if selectedTab == "HOME" {
                        if let bannerURL = initialChannel.bannerURL ?? channelVideos.first?.thumbnailURL {
                            YTCachedAsyncImage(url: bannerURL) {
                                Rectangle().fill(YTTheme.backgroundSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 104)
                            .clipped()
                        }

                        VStack(spacing: 10) {
                            YTChannelAvatarView(url: initialChannel.avatarURL, title: initialChannel.title, size: 72)
                                .padding(.top, 16)

                            Text(initialChannel.title)
                                .font(YTFontManager.youtubeSans(size: 24, weight: .bold))
                                .foregroundStyle(YTTheme.textPrimary)

                            HStack(spacing: 14) {
                                Button {
                                    appVM.toggleSubscription(
                                        for: initialChannel.id,
                                        channelTitle: initialChannel.title,
                                        avatarURL: initialChannel.avatarURL
                                    )
                                } label: {
                                    Text(isSub ? "SUBSCRIBED" : "SUBSCRIBE")
                                        .font(.system(size: 14, weight: .medium))
                                        .tracking(0.3)
                                        .foregroundStyle(isSub ? YTTheme.textSecondary : YTTheme.subscribeRed)
                                }
                                .buttonStyle(.plain)

                                if isSub {
                                    YTNotificationBellMenuButton(channelId: initialChannel.id, channelTitle: initialChannel.title)
                                }
                            }
                            .padding(.vertical, 2)

                            Text("\(initialChannel.handle) · \(initialChannel.subscribersText)")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(YTTheme.textPrimary)

                            Text(initialChannel.descriptionText)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(YTTheme.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 16)
                        }
                    }

                    if isLoadingChannelVideos {
                        ForEach(0..<2, id: \.self) { _ in
                            YTVideoCardSkeletonView()
                        }
                    } else {
                        let filtered: [YTVideo] = {
                            if selectedTab == "SHORTS" {
                                return channelVideos.filter { $0.isShort }
                            } else if selectedTab == "LIVE" {
                                return channelVideos.filter { $0.isLive }
                            }
                            return channelVideos
                        }()
                        ForEach(filtered.isEmpty ? channelVideos : filtered) { video in
                            YTVideoCardView(video: video)
                        }
                    }
                }
                .padding(.bottom, appVM.currentVideo != nil ? 76 : 16)
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            isLoadingChannelVideos = true
            let fetched = await YTInnerTubeEngine.shared.fetchChannelVideos(
                channelTitle: initialChannel.title,
                channelId: initialChannel.id
            )
            channelVideos = fetched.isEmpty ? initialChannel.videos : fetched
            isLoadingChannelVideos = false
        }
    }
}
