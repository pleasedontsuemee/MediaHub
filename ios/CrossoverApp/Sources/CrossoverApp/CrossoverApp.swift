import SwiftUI
import YouTubeModule
import NetflixModule
import SpotifyModule

#if canImport(UIKit)
import UIKit

public final class CrossoverAppDelegate: NSObject, UIApplicationDelegate {
    public static var allowLandscape: Bool = false

    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("CrossoverAllowLandscapeChanged"),
            object: nil,
            queue: .main
        ) { note in
            if let allow = note.object as? Bool {
                CrossoverAppDelegate.allowLandscape = allow
            }
        }
        return true
    }

    public func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        CrossoverAppDelegate.allowLandscape ? [.landscapeLeft, .landscapeRight] : [.portrait]
    }
}
#endif

public enum CrossoverAppMode: String, CaseIterable, Identifiable {
    case youtube = "youtube"
    case netflix = "netflix"
    case spotify = "spotify"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .youtube: return "YouTube"
        case .netflix: return "Netflix"
        case .spotify: return "Spotify"
        }
    }

    public var subtitle: String {
        switch self {
        case .youtube: return "Vidéos, Shorts & Abonnements"
        case .netflix: return "Films & Séries (Movix)"
        case .spotify: return "Musique, Podcasts & Skyrock"
        }
    }

    public var accentColor: Color {
        switch self {
        case .youtube: return Color(red: 1.0, green: 0.0, blue: 0.0)
        case .netflix: return Color(red: 0.898, green: 0.035, blue: 0.078)
        case .spotify: return Color(red: 0.118, green: 0.843, blue: 0.376)
        }
    }

    public var iconName: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .netflix: return "film.fill"
        case .spotify: return "music.note.list"
        }
    }

    public var logoResourceName: String {
        switch self {
        case .youtube: return "logo_youtube"
        case .netflix: return "logo_netflix"
        case .spotify: return "logo_spotify"
        }
    }
}

public struct CrossoverRootView: View {
    @AppStorage("crossover_active_app") private var activeAppRaw: String = CrossoverAppMode.youtube.rawValue
    @State private var showSwitcher: Bool = false

    private var activeApp: CrossoverAppMode {
        CrossoverAppMode(rawValue: activeAppRaw) ?? .youtube
    }

    public init() {}

    public var body: some View {
        ZStack {
            Group {
                switch activeApp {
                case .youtube:
                    YouTubeModule.ContentView()
                case .netflix:
                    NetflixModule.NFContentView()
                case .spotify:
                    SpotifyModule.SPContentView()
                }
            }
            .id(activeApp.rawValue)

            if showSwitcher {
                ZStack {
                    Color.black.opacity(0.78)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showSwitcher = false
                            }
                        }

                    VStack(spacing: 18) {
                        Text("Changer d'application")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Appui long sur Accueil à tout moment")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.65))

                        VStack(spacing: 12) {
                            ForEach(CrossoverAppMode.allCases) { mode in
                                let isCurrent = (mode == activeApp)
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        activeAppRaw = mode.rawValue
                                        showSwitcher = false
                                    }
                                } label: {
                                    HStack(spacing: 16) {
                                        Group {
                                            #if canImport(UIKit)
                                            if let url = Bundle.module.url(forResource: mode.logoResourceName, withExtension: "png"),
                                               let uiImg = UIImage(contentsOfFile: url.path) {
                                                Image(uiImage: uiImg)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 48, height: 48)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            } else {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .fill(mode.accentColor)
                                                        .frame(width: 48, height: 48)
                                                    Image(systemName: mode.iconName)
                                                        .font(.system(size: 22, weight: .bold))
                                                        .foregroundStyle(mode == .spotify ? .black : .white)
                                                }
                                            }
                                            #endif
                                        }

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(mode.title)
                                                .font(.system(size: 17, weight: .bold))
                                                .foregroundStyle(.white)
                                            Text(mode.subtitle)
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color.white.opacity(0.7))
                                        }

                                        Spacer()

                                        if isCurrent {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 22))
                                                .foregroundStyle(mode.accentColor)
                                        }
                                    }
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color(white: isCurrent ? 0.20 : 0.13))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .strokeBorder(isCurrent ? mode.accentColor.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1.5)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button("Fermer") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showSwitcher = false
                            }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .padding(.top, 6)
                    }
                    .padding(22)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color(white: 0.08))
                            .shadow(color: .black.opacity(0.6), radius: 24)
                    )
                    .padding(.horizontal, 24)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                .zIndex(999)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CrossoverOpenAppSwitcher"))) { _ in
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showSwitcher = true
            }
        }
    }
}

@main
public struct CrossoverApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(CrossoverAppDelegate.self) var appDelegate
    #endif

    public init() {}

    public var body: some Scene {
        WindowGroup {
            CrossoverRootView()
        }
    }
}
