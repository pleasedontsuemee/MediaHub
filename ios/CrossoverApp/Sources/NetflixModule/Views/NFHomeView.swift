import SwiftUI

// MARK: - 1. Real Netflix N Ribbon Logo
public struct NFNetflixRibbonN: View {
    public let height: CGFloat

    public init(height: CGFloat = 32) {
        self.height = height
    }

    public var body: some View {
        if let uiImg = NFResourceBundle.image(named: "netflix_n_ribbon") {
            Image(uiImage: uiImg)
                .resizable()
                .scaledToFit()
                .frame(height: height)
        } else {
            Text("N")
                .font(.system(size: height, weight: .black))
                .foregroundStyle(NFTheme.netflixRed)
        }
    }
}

// MARK: - 2. Profile Gate (`Who's Watching?`)
public struct NFProfileGateView: View {
    @EnvironmentObject private var appVM: NFAppViewModel
    @State private var showAddProfile = false
    @State private var newProfileName = ""

    public init() {}

    public var body: some View {
        ZStack {
            NFTheme.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer().frame(width: 44)
                    Spacer()
                    Text("NETFLIX")
                        .font(.system(size: 24, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(NFTheme.netflixRed)
                    Spacer()
                    Button {
                        showAddProfile = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Spacer()

                Text("Qui est-ce ?")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.bottom, 28)

                LazyVGrid(columns: [GridItem(.fixed(110), spacing: 26), GridItem(.fixed(110), spacing: 26)], spacing: 26) {
                    ForEach(appVM.profiles) { profile in
                        Button {
                            appVM.activeProfile = profile
                            withAnimation(.easeInOut(duration: 0.25)) {
                                appVM.showProfileGate = false
                            }
                        } label: {
                            VStack(spacing: 10) {
                                NFProfileAvatarBox(profile: profile, size: 100)
                                Text(profile.name)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        showAddProfile = true
                    } label: {
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                                    .frame(width: 100, height: 100)
                                Image(systemName: "plus")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundStyle(.white)
                            }
                            Text("Ajouter un profil")
                                .font(.system(size: 14))
                                .foregroundStyle(NFTheme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .alert("Nouveau profil", isPresented: $showAddProfile) {
            TextField("Nom du profil", text: $newProfileName)
            Button("Ajouter") {
                appVM.addProfile(name: newProfileName)
                newProfileName = ""
            }
            Button("Annuler", role: .cancel) {
                newProfileName = ""
            }
        }
    }
}

public struct NFProfileAvatarBox: View {
    public let profile: NFProfile
    public let size: CGFloat

    public init(profile: NFProfile, size: CGFloat = 26) {
        self.profile = profile
        self.size = size
    }

    public var body: some View {
        Group {
            if let uiImg = NFResourceBundle.image(named: profile.avatarName) {
                Image(uiImage: uiImg)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.14), style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: max(4, size * 0.14), style: .continuous)
                        .fill(NFTheme.color(hex: profile.colorHex))
                        .frame(width: size, height: size)
                    if profile.isKids {
                        Text("KIDS")
                            .font(.system(size: size * 0.28, weight: .black))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }
}

// MARK: - 3. Home Lolomo View (`NFHomeView`)
public struct NFHomeView: View {
    @EnvironmentObject private var appVM: NFAppViewModel

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            NFTheme.backgroundPrimary.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    // 1. Billboard Hero
                    if let hero = appVM.heroItem {
                        NFBillboardHeroView(item: hero)
                    } else if appVM.isLoadingHome {
                        Rectangle()
                            .fill(NFTheme.backgroundSecondary)
                            .frame(height: 500)
                    }

                    // 2. Continue Watching (Populates dynamically as user watches)
                    if !appVM.continueWatching.isEmpty {
                        NFMediaRowSectionView(
                            row: NFMediaRow(
                                id: "continue_watching",
                                title: "Reprendre avec \(appVM.activeProfile.name)",
                                style: .continueWatching,
                                items: appVM.continueWatching
                            )
                        )
                    }

                    // 3. My List Row (if user added items)
                    if !appVM.myList.isEmpty {
                        NFMediaRowSectionView(
                            row: NFMediaRow(
                                id: "my_list",
                                title: "Ma liste",
                                style: .standard,
                                items: appVM.myList
                            )
                        )
                    }

                    // 4. Live TMDB / Movix Lolomo Rows
                    ForEach(appVM.homeRows) { row in
                        NFMediaRowSectionView(row: row)
                    }
                }
                .padding(.bottom, 90)
            }
            .ignoresSafeArea(edges: .top)
            .refreshable {
                await appVM.loadHomeFeed()
            }

            // Floating Netflix Top Navigation Bar
            VStack(spacing: 12) {
                HStack(spacing: 18) {
                    Button {
                        appVM.selectHomeFilter("All")
                    } label: {
                        NFNetflixRibbonN(height: 32)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        appVM.showToast("AirPlay / Cast prêt")
                    } label: {
                        Image(systemName: "airplayvideo")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        appVM.isSettingsSheetPresented = true
                    } label: {
                        NFProfileAvatarBox(profile: appVM.activeProfile, size: 26)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)

                // Sub-navigation (`Series`, `Films`, `Categories v` — matches IMG_2854 & IMG_2858)
                HStack {
                    Spacer()
                    Button {
                        appVM.selectHomeFilter(appVM.homeFilter == "Series" ? "All" : "Series")
                    } label: {
                        HStack(spacing: 4) {
                            Text("Séries")
                                .font(.system(size: 15, weight: appVM.homeFilter == "Series" ? .bold : .medium))
                            if appVM.homeFilter == "Series" {
                                Image(systemName: "arrowtriangle.down.fill")
                                    .font(.system(size: 8))
                            }
                        }
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        appVM.selectHomeFilter(appVM.homeFilter == "Films" ? "All" : "Films")
                    } label: {
                        HStack(spacing: 4) {
                            Text("Films")
                                .font(.system(size: 15, weight: appVM.homeFilter == "Films" ? .bold : .medium))
                            if appVM.homeFilter == "Films" {
                                Image(systemName: "arrowtriangle.down.fill")
                                    .font(.system(size: 8))
                            }
                        }
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        appVM.isCategoriesSheetPresented = true
                    } label: {
                        HStack(spacing: 5) {
                            Text(appVM.selectedGenreName ?? "Catégories")
                                .font(.system(size: 15, weight: appVM.selectedGenreName != nil ? .bold : .medium))
                            Image(systemName: "arrowtriangle.down.fill")
                                .font(.system(size: 8))
                        }
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 6)
            .padding(.bottom, 10)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.75), Color.black.opacity(0.35), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
            )
        }
        .sheet(isPresented: $appVM.isCategoriesSheetPresented) {
            NFCategoriesModalView()
        }
    }
}

// MARK: - 4. Full-Bleed Billboard Hero (`Stay Close` / Trending #1)
public struct NFBillboardHeroView: View {
    @EnvironmentObject private var appVM: NFAppViewModel
    public let item: NFMediaItem

    public init(item: NFMediaItem) {
        self.item = item
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            NFCachedAsyncImage(url: item.posterURL ?? item.backdropURL) {
                Rectangle().fill(NFTheme.backgroundSecondary)
            }
            .frame(height: 520)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.35),
                    Color.black.opacity(0.88),
                    NFTheme.backgroundPrimary
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 270)

            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    NFNetflixRibbonN(height: 16)
                    Text(item.mediaType.badgeLabel)
                        .font(.system(size: 12, weight: .bold))
                        .tracking(3.0)
                        .foregroundStyle(.white.opacity(0.92))
                }

                Text(item.title.uppercased())
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
                    .shadow(color: .black.opacity(0.75), radius: 6)

                if !item.genreNames.isEmpty {
                    Text(item.genreNames.prefix(3).joined(separator: " • "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }

                HStack(spacing: 0) {
                    Button {
                        appVM.toggleMyList(item)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: appVM.isInMyList(item) ? "checkmark" : "plus")
                                .font(.system(size: 20, weight: .semibold))
                            Text("Ma liste")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)

                    Button {
                        appVM.playMedia(item)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16))
                            Text("Lecture")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22)
                        .frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white))
                    }
                    .buttonStyle(.plain)

                    Button {
                        appVM.selectedDetailMedia = item
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 20, weight: .semibold))
                            Text("Infos")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
            .padding(.bottom, 16)
        }
    }
}

// MARK: - 5. Lolomo Horizontal Carousel Row (`Standard`, `Top 10`, `Continue Watching`)
public struct NFMediaRowSectionView: View {
    @EnvironmentObject private var appVM: NFAppViewModel
    public let row: NFMediaRow

    public init(row: NFMediaRow) {
        self.row = row
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(row.title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: row.style == .top10 ? 18 : 8) {
                    ForEach(row.items) { item in
                        switch row.style {
                        case .top10:
                            NFTop10CardView(item: item)
                        case .continueWatching:
                            NFContinueWatchingCardView(item: item)
                        case .standard:
                            NFPosterCardView(item: item)
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }
}

public struct NFPosterCardView: View {
    @EnvironmentObject private var appVM: NFAppViewModel
    public let item: NFMediaItem

    public init(item: NFMediaItem) {
        self.item = item
    }

    public var body: some View {
        Button {
            appVM.selectedDetailMedia = item
        } label: {
            ZStack(alignment: .topLeading) {
                NFCachedAsyncImage(url: item.posterURL) {
                    Rectangle().fill(NFTheme.backgroundElevated)
                }
                .frame(width: 110, height: 158)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                NFNetflixRibbonN(height: 16)
                    .padding(6)
                    .shadow(color: .black.opacity(0.8), radius: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

public struct NFTop10CardView: View {
    @EnvironmentObject private var appVM: NFAppViewModel
    public let item: NFMediaItem

    public init(item: NFMediaItem) {
        self.item = item
    }

    public var body: some View {
        Button {
            appVM.selectedDetailMedia = item
        } label: {
            HStack(alignment: .bottom, spacing: -14) {
                ZStack {
                    let rankStr = "\(item.top10Rank ?? 1)"
                    ForEach([-1.5, 1.5], id: \.self) { dx in
                        ForEach([-1.5, 1.5], id: \.self) { dy in
                            Text(rankStr)
                                .font(.system(size: 92, weight: .black))
                                .foregroundStyle(Color.white.opacity(0.72))
                                .offset(x: dx, y: dy)
                        }
                    }
                    Text(rankStr)
                        .font(.system(size: 92, weight: .black))
                        .foregroundStyle(Color.black)
                }
                .offset(y: 12)
                .zIndex(1)

                ZStack(alignment: .topTrailing) {
                    NFCachedAsyncImage(url: item.posterURL) {
                        Rectangle().fill(NFTheme.backgroundElevated)
                    }
                    .frame(width: 108, height: 156)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    VStack(spacing: 0) {
                        Text("TOP")
                            .font(.system(size: 7, weight: .black))
                        Text("10")
                            .font(.system(size: 11, weight: .black))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(NFTheme.netflixRed)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

public struct NFContinueWatchingCardView: View {
    @EnvironmentObject private var appVM: NFAppViewModel
    public let item: NFMediaItem

    public init(item: NFMediaItem) {
        self.item = item
    }

    public var body: some View {
        VStack(spacing: 0) {
            Button {
                appVM.playMedia(item)
            } label: {
                ZStack {
                    NFCachedAsyncImage(url: item.posterURL) {
                        Rectangle().fill(NFTheme.backgroundElevated)
                    }
                    .frame(width: 114, height: 150)
                    .clipped()

                    Circle()
                        .fill(Color.black.opacity(0.65))
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                        )
                }
            }
            .buttonStyle(.plain)

            // Red Progress Bar
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.28))
                    Rectangle()
                        .fill(NFTheme.netflixRed)
                        .frame(width: g.size.width * CGFloat(max(0.05, min(1.0, item.watchProgress))))
                }
            }
            .frame(width: 114, height: 3)

            // Info Footer
            HStack {
                Button {
                    appVM.selectedDetailMedia = item
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(NFTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(item.mediaType == .tv ? "S\(item.lastSeasonNumber ?? 1):E\(item.lastEpisodeNumber ?? 1)" : item.releaseYear)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NFTheme.textSecondary)
            }
            .padding(.horizontal, 8)
            .frame(width: 114, height: 32)
            .background(NFTheme.backgroundSecondary)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - 6. Categories Modal
public struct NFCategoriesModalView: View {
    @EnvironmentObject private var appVM: NFAppViewModel
    @Environment(\.dismiss) private var dismiss

    private let genres: [(id: Int?, name: String)] = [
        (nil, "Tout le catalogue"),
        (28, "Action"),
        (16, "Animation & Animés"),
        (35, "Comédies"),
        (80, "Policier & Crime"),
        (99, "Documentaires"),
        (18, "Drames"),
        (14, "Fantastique"),
        (27, "Horreur"),
        (10749, "Romance"),
        (878, "Science-Fiction"),
        (53, "Thrillers")
    ]

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.95).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 30)
                    ForEach(genres, id: \.name) { g in
                        Button {
                            appVM.selectGenre(id: g.id, name: g.id == nil ? nil : g.name)
                            dismiss()
                        } label: {
                            Text(g.name)
                                .font(.system(size: 20, weight: appVM.selectedGenreId == g.id ? .bold : .regular))
                                .foregroundStyle(appVM.selectedGenreId == g.id ? .white : NFTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer().frame(height: 80)
                }
                .frame(maxWidth: .infinity)
            }

            Button {
                dismiss()
            } label: {
                ZStack {
                    Circle().fill(Color.white).frame(width: 52, height: 52)
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.black)
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
    }
}
