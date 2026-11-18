import SwiftUI

public struct NFContentView: View {
    @StateObject private var appVM = NFAppViewModel()

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Main 5-Tab Interface
            Group {
                switch appVM.selectedTab {
                case .home:
                    NFHomeView()
                case .newAndHot:
                    NFNewAndHotView()
                case .fastLaughs:
                    NFFastLaughsView()
                case .search:
                    NFSearchView()
                case .downloads:
                    NFDownloadsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, NFTheme.tabBarHeight)

            // Bottom Netflix Tab Bar (`#121212`, 49pt)
            HStack(spacing: 0) {
                tabButton(tab: .home, title: "Accueil", icon: "house.fill", inactiveIcon: "house")
                tabButton(tab: .newAndHot, title: "Nouveautés", icon: "play.rectangle.on.rectangle.fill", inactiveIcon: "play.rectangle.on.rectangle")
                tabButton(tab: .fastLaughs, title: "Fast Laughs", icon: "face.smiling.inverse", inactiveIcon: "face.smiling")
                tabButton(tab: .search, title: "Rechercher", icon: "magnifyingglass", inactiveIcon: "magnifyingglass")
                tabButton(tab: .downloads, title: "Télécharg.", icon: "arrow.down.circle.fill", inactiveIcon: "arrow.down.circle")
            }
            .frame(height: NFTheme.tabBarHeight)
            .background(NFTheme.backgroundSecondary.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) {
                Rectangle().fill(NFTheme.separator).frame(height: 0.5)
            }

            // Toast Notification
            if let toast = appVM.toastMessage {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white))
                    .padding(.bottom, NFTheme.tabBarHeight + 14)
                    .zIndex(50)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environmentObject(appVM)
        .preferredColorScheme(.dark)
        .sheet(item: $appVM.selectedDetailMedia) { item in
            NFMediaDetailView(media: item)
                .environmentObject(appVM)
        }
        .sheet(isPresented: $appVM.isSettingsSheetPresented) {
            NFSettingsSheetView()
                .environmentObject(appVM)
        }
        .fullScreenCover(isPresented: $appVM.isPlayerPresented) {
            NFPlayerView()
                .environmentObject(appVM)
        }
    }

    private func tabButton(tab: NFMainTab, title: String, icon: String, inactiveIcon: String) -> some View {
        let isSelected = appVM.selectedTab == tab
        return Button {
            appVM.selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? icon : inactiveIcon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : NFTheme.textMuted)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                if tab == .home {
                    NotificationCenter.default.post(name: Notification.Name("CrossoverOpenAppSwitcher"), object: nil)
                }
            }
        )
    }
}

public struct NetflixModuleEntry: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            NFContentView()
        }
    }
}
