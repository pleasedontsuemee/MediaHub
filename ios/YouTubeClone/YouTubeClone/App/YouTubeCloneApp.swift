import SwiftUI

// MARK: - Route Destination Resolver
public struct YTRouteDestinationView: View {
    public let route: YTNavigationRoute

    public init(route: YTNavigationRoute) {
        self.route = route
    }

    public var body: some View {
        switch route {
        case .channel(let channel):
            YTChannelPageView(channel: channel)
        case .allSubscriptions:
            YTAllSubscriptionsView()
        case .trending(let initialTab):
            YTTrendingView(initialTab: initialTab)
        case .liveHub:
            YTLiveHubView()
        case .yourVideos:
            YTYourVideosView()
        case .downloads:
            YTDownloadsView()
        case .playlistDetail(let playlist):
            YTPlaylistDetailView(playlist: playlist)
        case .timeWatched:
            YTTimeWatchedView()
        case .searchResults(let query):
            YTSearchResultsView(query: query)
        }
    }
}

// MARK: - Root Container View (`YTRootViewController` + `YTWatchView` + `YTPivotBarView`)
public struct ContentView: View {
    @StateObject private var appVM = YTAppViewModel()

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            // 1. Main Tab Content (`Home`, `Shorts`, `Subscriptions`, `Library`)
            Group {
                switch appVM.selectedTab {
                case .home:
                    YTHomeView()
                case .shorts:
                    YTShortsFeedView()
                case .create:
                    YTHomeView()
                case .subscriptions:
                    YTSubscriptionsView()
                case .library:
                    YTLibraryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 48) // Space for YTPivotTabBarView

            // 2. Docked Mini-Player (`56pt` height above Tab Bar when a video is active and not expanded)
            if let activeVideo = appVM.currentVideo,
               !appVM.isPlayerExpanded,
               appVM.selectedTab != .shorts {
                YTMiniPlayerBarView(video: activeVideo)
                    .padding(.bottom, 48)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 3. Bottom Tab Bar (`YTPivotBarView`)
            if !appVM.isPlayerExpanded {
                YTPivotTabBarView()
            }

            // 4. Fullscreen / Portrait Watch Player (`YTWatchView`)
            if let activeVideo = appVM.currentVideo, appVM.isPlayerExpanded {
                YTWatchFullPlayerView(video: activeVideo)
                    .ignoresSafeArea(.all, edges: appVM.isFullscreenLandscape ? .all : [])
                    .zIndex(20)
                    .transition(.move(edge: .bottom))
            }

            // 5. Explore Left Side Drawer (`ABCSideDrawerViewController`)
            if appVM.isExploreDrawerOpen {
                YTExploreSideDrawerOverlay()
                    .zIndex(30)
            }

            // 6. Active Search & Autocomplete Overlay (`Search YouTube`)
            if appVM.isSearchOverlayPresented {
                YTSearchOverlayView()
                    .zIndex(35)
                    .transition(.opacity)
            }

            // 7. Snackbar / Toast (`YTHUDMessageView` - Subscription added / Unsubscribed UNDO / Notifications)
            if let toast = appVM.toastMessage {
                YTSnackbarToastView(message: toast, actionTitle: appVM.toastActionTitle)
                    .padding(.bottom, appVM.isPlayerExpanded ? 16 : (appVM.currentVideo != nil ? 114 : 58))
                    .zIndex(50)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environmentObject(appVM)
        .preferredColorScheme(appVM.preferredColorScheme)
        // Create (+) Bottom Sheet (`GeneralBrowsing #23`)
        .sheet(isPresented: $appVM.isCreateSheetPresented) {
            YTCreateBottomSheetView()
                .environmentObject(appVM)
                .presentationDetents([.height(380)])
                .presentationCornerRadius(16)
        }
        // Save Video to Playlist Modal (`GeneralBrowsing #05`)
        .sheet(isPresented: $appVM.isSaveToPlaylistSheetPresented) {
            YTSaveToPlaylistModalView()
                .environmentObject(appVM)
                .presentationDetents([.height(275)])
                .presentationCornerRadius(12)
        }
        // Account Menu Fullscreen Sheet (`GeneralBrowsing #26, #28, #29`)
        .fullScreenCover(isPresented: $appVM.isAccountSheetPresented) {
            YTAccountMenuSheetView()
                .environmentObject(appVM)
        }
        // Settings Fullscreen Sheet (`GeneralBrowsing #36 & #38`)
        .fullScreenCover(isPresented: $appVM.isSettingsPresented) {
            YTSettingsModalView()
                .environmentObject(appVM)
        }
        // Help & Help Article Fullscreen Sheet (`GeneralBrowsing #16 & #17`)
        .fullScreenCover(isPresented: $appVM.isHelpPresented) {
            YTHelpModalView()
                .environmentObject(appVM)
        }
        // Cast Device Dialog
        .confirmationDialog("Connect to a device", isPresented: $appVM.isCastAlertPresented, titleVisibility: .visible) {
            Button("AirPlay & Bluetooth devices") {
                appVM.showToast("Searching for AirPlay devices...")
            }
            Button("Link with TV code") {
                appVM.showToast("Enter TV code in Settings > Watch on TV")
            }
            Button("Learn more") {
                appVM.isHelpPresented = true
            }
            Button("Cancel", role: .cancel) {}
        }
        // Notifications Sheet
        .sheet(isPresented: $appVM.isNotificationsSheetPresented) {
            YTNotificationsSheetView()
                .environmentObject(appVM)
        }
    }
}

// MARK: - Notifications Inbox Sheet
public struct YTNotificationsSheetView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notifications")
                    .font(YTFontManager.youtubeSans(size: 20, weight: .bold))
                    .foregroundStyle(YTTheme.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    YTIcon("yt_outline_x_24pt", fallback: "xmark", size: 22)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Rectangle().fill(YTTheme.separator).frame(height: 0.5)

            ScrollView {
                VStack(spacing: 16) {
                    ForEach([YTCatalogData.videoAdamSandlerHustle, YTCatalogData.videoOndaraTheCurrent, YTCatalogData.videoJennaOrtegaCosplayer]) { video in
                        Button {
                            dismiss()
                            appVM.openVideo(video)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .fill(YTTheme.callToActionBlue)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 16)

                                YTChannelAvatarView(url: video.channelAvatarURL, title: video.channelTitle, size: 36)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(video.channelTitle) uploaded: \(video.title)")
                                        .font(.system(size: 14))
                                        .foregroundStyle(YTTheme.textPrimary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)

                                    Text(video.publishedTimeText)
                                        .font(.system(size: 12))
                                        .foregroundStyle(YTTheme.textSecondary)
                                }

                                Spacer()

                                YTCachedAsyncImage(url: video.thumbnailURL) {
                                    Rectangle().fill(YTTheme.backgroundSecondary)
                                }
                                .frame(width: 86, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .background(YTTheme.backgroundPrimary)
    }
}

// MARK: - Main App Entry Point (`@main`)
@main
public struct YouTubeCloneApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
