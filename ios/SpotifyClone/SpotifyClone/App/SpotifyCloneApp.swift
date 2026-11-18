import SwiftUI

#if canImport(UIKit)
import UIKit

public final class SPAppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        [.portrait]
    }
}
#endif

public struct SPContentView: View {
    @StateObject private var appVM = SPAppViewModel()

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch appVM.selectedTab {
                case .home:
                    SPHomeView()
                case .search:
                    SPSearchView()
                case .library:
                    SPLibraryView()
                case .premium:
                    SPPremiumAndSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, SPTheme.tabBarHeight)

            VStack(spacing: 0) {
                SPMiniPlayerBar()

                // Spotify Bottom Tab Bar
                HStack(spacing: 0) {
                    tabButton(tab: .home, title: "Accueil", icon: "house.fill", inactive: "house")
                    tabButton(tab: .search, title: "Rechercher", icon: "magnifyingglass", inactive: "magnifyingglass")
                    tabButton(tab: .library, title: "Bibliothèque", icon: "books.vertical.fill", inactive: "books.vertical")
                    tabButton(tab: .premium, title: "Réglages", icon: "gearshape.fill", inactive: "gearshape")
                }
                .frame(height: SPTheme.tabBarHeight)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.85), Color.black.opacity(0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
            }

            if let toast = appVM.toastMessage {
                Text(toast)
                    .font(SPFontManager.mix(13, bold: true))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white))
                    .padding(.bottom, SPTheme.tabBarHeight + (appVM.currentTrack != nil ? SPTheme.miniPlayerHeight + 12 : 12))
                    .zIndex(50)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environmentObject(appVM)
        .preferredColorScheme(.dark)
        .sheet(item: $appVM.selectedCollection) { col in
            Group {
                switch col.kind {
                case .artist:
                    SPArtistDetailView(artistId: col.id, initialName: col.title)
                case .album:
                    SPAlbumDetailView(albumId: col.id, initialTitle: col.title, initialCoverURL: col.coverURLString)
                case .playlist, .podcast:
                    SPCollectionDetailView(collection: col)
                }
            }
            .environmentObject(appVM)
        }
        .sheet(item: $appVM.trackOptionsTarget) { track in
            SPTrackOptionsSheet(track: track)
                .environmentObject(appVM)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $appVM.isCreatePlaylistPresented) {
            SPCreatePlaylistSheet()
                .environmentObject(appVM)
        }
        .sheet(item: $appVM.trackToAddToPlaylist) { track in
            SPAddToPlaylistSheet(track: track)
                .environmentObject(appVM)
        }
        .fullScreenCover(isPresented: $appVM.isNowPlayingPresented) {
            SPNowPlayingView()
                .environmentObject(appVM)
        }
    }

    private func tabButton(tab: SPTab, title: String, icon: String, inactive: String) -> some View {
        let isSelected = appVM.selectedTab == tab
        return Button {
            appVM.selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? icon : inactive)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                Text(title)
                    .font(SPFontManager.mix(10, bold: isSelected))
            }
            .foregroundStyle(isSelected ? .white : SPTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@main
public struct SpotifyCloneApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(SPAppDelegate.self) var appDelegate
    #endif

    public init() {}

    public var body: some Scene {
        WindowGroup {
            SPContentView()
        }
    }
}
