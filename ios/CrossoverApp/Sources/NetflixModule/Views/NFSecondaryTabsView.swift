import SwiftUI

// MARK: - 1. New & Hot View (`NFNewAndHotView`)
public struct NFNewAndHotView: View {
    @EnvironmentObject private var appVM: NFAppViewModel
    @State private var selectedChip: String = "À venir"

    private let chips = ["🍿 À venir", "👀 Tout le monde regarde", "🔥 Top 10"]

    public init() {}

    private var activeList: [NFMediaItem] {
        if selectedChip.contains("Tout") { return appVM.everyoneWatchingItems }
        if selectedChip.contains("Top 10") { return appVM.newHotTop10Items }
        return appVM.comingSoonItems
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                Text("Nouveautés")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    appVM.isSettingsSheetPresented = true
                } label: {
                    NFProfileAvatarBox(profile: appVM.activeProfile, size: 26)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(chips, id: \.self) { chip in
                        let isSel = selectedChip == chip
                        Button {
                            selectedChip = chip
                        } label: {
                            Text(chip)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(isSel ? .black : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(isSel ? Color.white : NFTheme.backgroundElevated))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 24) {
                    ForEach(activeList) { item in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 2) {
                                Text(item.releaseYear.isEmpty ? "2026" : item.releaseYear)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(NFTheme.textSecondary)
                                if let rank = item.top10Rank {
                                    Text("#\(rank)")
                                        .font(.system(size: 20, weight: .black))
                                        .foregroundStyle(NFTheme.netflixRed)
                                }
                            }
                            .frame(width: 42)

                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    appVM.selectedDetailMedia = item
                                } label: {
                                    NFCachedAsyncImage(url: item.backdropURL) {
                                        Rectangle().fill(NFTheme.backgroundSecondary)
                                    }
                                    .frame(height: 190)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)

                                HStack {
                                    Text(item.title)
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)

                                    Spacer()

                                    Button {
                                        appVM.toggleRemind(item)
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: appVM.remindedIds.contains(item.id) ? "bell.fill" : "bell")
                                                .font(.system(size: 18))
                                            Text("Me rappeler")
                                                .font(.system(size: 10))
                                        }
                                        .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        appVM.selectedDetailMedia = item
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: "info.circle")
                                                .font(.system(size: 18))
                                            Text("Infos")
                                                .font(.system(size: 10))
                                        }
                                        .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.plain)
                                }

                                if !item.overview.isEmpty {
                                    Text(item.overview)
                                        .font(.system(size: 13))
                                        .foregroundStyle(NFTheme.textSecondary)
                                        .lineLimit(3)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                }
                .padding(.bottom, 80)
            }
        }
        .background(NFTheme.backgroundPrimary)
    }
}

// MARK: - 2. Fast Laughs / Clips View (`NFFastLaughsView`)
public struct NFFastLaughsView: View {
    @EnvironmentObject private var appVM: NFAppViewModel
    @State private var currentIndex: Int = 0

    public init() {}

    private var items: [NFMediaItem] {
        appVM.everyoneWatchingItems.isEmpty ? (appVM.homeRows.first?.items ?? []) : appVM.everyoneWatchingItems
    }

    public var body: some View {
        GeometryReader { geo in
            if items.isEmpty {
                ZStack {
                    NFTheme.backgroundPrimary.ignoresSafeArea()
                    ProgressView().tint(NFTheme.netflixRed)
                }
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        ZStack(alignment: .bottom) {
                            NFCachedAsyncImage(url: item.posterURL ?? item.backdropURL) {
                                Color.black
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()

                            LinearGradient(colors: [Color.clear, Color.black.opacity(0.88)], startPoint: .center, endPoint: .bottom)

                            HStack(alignment: .bottom) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.title)
                                        .font(.system(size: 24, weight: .black))
                                        .foregroundStyle(.white)
                                    Text(item.overview)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .lineLimit(3)
                                    Button {
                                        appVM.playMedia(item)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "play.fill")
                                            Text("Regarder")
                                                .fontWeight(.bold)
                                        }
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 9)
                                        .background(RoundedRectangle(cornerRadius: 4).fill(.white))
                                    }
                                    .buttonStyle(.plain)
                                }
                                Spacer()
                                VStack(spacing: 22) {
                                    Button {
                                        appVM.toggleLike(item)
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: appVM.likedMediaIds.contains(item.id) ? "hand.thumbsup.fill" : "hand.thumbsup")
                                                .font(.system(size: 26))
                                            Text("J'aime").font(.system(size: 11))
                                        }
                                        .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        appVM.toggleMyList(item)
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: appVM.isInMyList(item) ? "checkmark" : "plus")
                                                .font(.system(size: 26))
                                            Text("Ma liste").font(.system(size: 11))
                                        }
                                        .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        appVM.selectedDetailMedia = item
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: "info.circle")
                                                .font(.system(size: 26))
                                            Text("Infos").font(.system(size: 11))
                                        }
                                        .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 76)
                        }
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .background(NFTheme.backgroundPrimary)
    }
}

// MARK: - 3. Search View (`NFSearchView` - Popular Searches + Live TMDB Grid)
public struct NFSearchView: View {
    @EnvironmentObject private var appVM: NFAppViewModel
    @State private var query: String = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(NFTheme.textSecondary)
                    TextField("Rechercher un film, une série...", text: $query)
                        .foregroundStyle(.white)
                        .autocorrectionDisabled()
                        .onChange(of: query) { _, newVal in
                            appVM.performSearch(newVal)
                        }
                    if !query.isEmpty {
                        Button {
                            query = ""
                            appVM.performSearch("")
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(NFTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 6).fill(NFTheme.searchBarFill))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            ScrollView(.vertical, showsIndicators: false) {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recherches populaires")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)

                        let popular = appVM.homeRows.first?.items ?? []
                        ForEach(popular) { item in
                            HStack(spacing: 12) {
                                Button {
                                    appVM.selectedDetailMedia = item
                                } label: {
                                    HStack(spacing: 12) {
                                        NFCachedAsyncImage(url: item.backdropURL) {
                                            Rectangle().fill(NFTheme.backgroundElevated)
                                        }
                                        .frame(width: 132, height: 74)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))

                                        Text(item.title)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)

                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)

                                Button {
                                    appVM.playMedia(item)
                                } label: {
                                    Image(systemName: "play.circle")
                                        .font(.system(size: 30))
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                    .padding(.bottom, 80)
                } else if appVM.isSearching {
                    ProgressView().tint(NFTheme.netflixRed).padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Films & Séries")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(appVM.searchResults) { item in
                                Button {
                                    appVM.selectedDetailMedia = item
                                } label: {
                                    NFCachedAsyncImage(url: item.posterURL) {
                                        Rectangle().fill(NFTheme.backgroundElevated)
                                    }
                                    .aspectRatio(2.0 / 3.0, contentMode: .fill)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                    .padding(.bottom, 80)
                }
            }
        }
        .background(NFTheme.backgroundPrimary)
    }
}

// MARK: - 4. Downloads View (`NFDownloadsView`)
public struct NFDownloadsView: View {
    @EnvironmentObject private var appVM: NFAppViewModel
    @ObservedObject private var downloadManager = NFOfflineDownloadManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Téléchargements")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    appVM.isSettingsSheetPresented = true
                } label: {
                    NFProfileAvatarBox(profile: appVM.activeProfile, size: 26)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if downloadManager.downloads.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(NFTheme.textSecondary)
                    Text("Aucun téléchargement")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Les films et épisodes que vous téléchargez apparaîtront ici pour être regardés hors-ligne.")
                        .font(.system(size: 14))
                        .foregroundStyle(NFTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)

                    Button {
                        appVM.selectedTab = .home
                    } label: {
                        Text("Découvrir le catalogue")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.white))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(downloadManager.downloads) { dl in
                            HStack(spacing: 12) {
                                Button {
                                    appVM.playMedia(dl.media, season: dl.seasonNumber, episode: dl.episodeNumber, episodeTitle: dl.episodeTitle)
                                } label: {
                                    HStack(spacing: 12) {
                                        NFCachedAsyncImage(url: dl.media.backdropURL) {
                                            Rectangle().fill(NFTheme.backgroundElevated)
                                        }
                                        .frame(width: 128, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(dl.media.title)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                            if let ep = dl.episodeTitle {
                                                Text("S\(dl.seasonNumber ?? 1):E\(dl.episodeNumber ?? 1) \(ep)")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(NFTheme.textSecondary)
                                                    .lineLimit(1)
                                            }
                                            Text("\(dl.qualityLabel) · \(dl.formattedSize)")
                                                .font(.system(size: 12))
                                                .foregroundStyle(NFTheme.accentBlue)
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)

                                Button {
                                    downloadManager.removeDownload(id: dl.id)
                                    appVM.showToast("Téléchargement supprimé")
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                        .padding(8)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                    .padding(.bottom, 80)
                }
            }
        }
        .background(NFTheme.backgroundPrimary)
    }
}

// MARK: - 5. Settings & Debug Console (`NFSettingsSheetView`)
public struct NFSettingsSheetView: View {
    @EnvironmentObject private var appVM: NFAppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var movixURLDraft: String = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("Profils") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(appVM.profiles) { p in
                                let isActive = p.id == appVM.activeProfile.id
                                Button {
                                    appVM.activeProfile = p
                                    appVM.saveState()
                                    appVM.showToast("Profil : \(p.name)")
                                } label: {
                                    VStack(spacing: 6) {
                                        NFProfileAvatarBox(profile: p, size: 54)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .strokeBorder(isActive ? Color.white : Color.clear, lineWidth: 2)
                                            )
                                        Text(p.name)
                                            .font(.system(size: 12, weight: isActive ? .bold : .regular))
                                            .foregroundStyle(isActive ? .white : NFTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section("Serveur & URL Movix") {
                    TextField("https://api.movix.miami", text: $movixURLDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(size: 14, design: .monospaced))

                    Button("Appliquer & Actualiser les données") {
                        appVM.updateMovixURL(movixURLDraft)
                        dismiss()
                    }
                    .foregroundStyle(NFTheme.netflixRed)
                    .fontWeight(.semibold)

                    Button("Réinitialiser (api.movix.miami)") {
                        movixURLDraft = NFMovixEngine.defaultMovixBase
                        appVM.updateMovixURL(NFMovixEngine.defaultMovixBase)
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }

                Section("Lecture & PiP") {
                    Toggle("Picture-in-Picture (PiP)", isOn: $appVM.isPiPEnabled)
                    Toggle("Lecture en arrière-plan (audio)", isOn: $appVM.backgroundPlaybackEnabled)
                    Toggle("Lecture auto épisode suivant", isOn: $appVM.autoplayNextEpisode)
                    Toggle("Zoom plein écran par défaut", isOn: $appVM.zoomToFillScreen)
                }

                Section("Téléchargements & Données") {
                    Toggle("Télécharger uniquement en Wi-Fi", isOn: $appVM.wifiOnlyDownloads)
                    Button("Vider Reprendre la lecture (\(appVM.continueWatching.count))") {
                        appVM.continueWatching.removeAll()
                        appVM.saveState()
                    }
                    .foregroundStyle(.red)
                }

                Section("Diagnostic") {
                    NavigationLink {
                        NFDebugConsoleView()
                    } label: {
                        Label("Debug (Logs & Diagnostics Movix)", systemImage: "ladybug.fill")
                            .foregroundStyle(NFTheme.netflixRed)
                    }
                }

                Section("À propos") {
                    LabeledContent("Version", value: "26.6.0 (Movix)")
                    LabeledContent("Bundle ID", value: "com.movix.netflixclone")
                }
            }
            .navigationTitle("Paramètres")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            movixURLDraft = appVM.movixBaseURL
        }
    }
}

public struct NFDebugConsoleView: View {
    @ObservedObject private var logger = NFDebugLogger.shared
    @State private var selectedFilter = "ALL"
    @State private var copied = false

    private let filters = ["ALL", "ERROR", "PLAYER", "STREAM", "NET"]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Text(logger.livePlayerSummary)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(NFTheme.backgroundSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters, id: \.self) { f in
                        Button(f) { selectedFilter = f }
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(selectedFilter == f ? NFTheme.netflixRed : NFTheme.backgroundElevated))
                            .foregroundStyle(.white)
                    }
                    Button(copied ? "Copié !" : "Copier") {
                        logger.copyAllToClipboard()
                        copied = true
                    }
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(NFTheme.accentBlue))
                    .foregroundStyle(.white)
                }
                .padding(10)
            }

            List {
                let items = (selectedFilter == "ALL" ? logger.entries : logger.entries.filter { $0.level.rawValue == selectedFilter }).reversed()
                ForEach(Array(items)) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("[\(entry.formattedTime)] [\(entry.level.rawValue)] [\(entry.tag)]")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(entry.level == .error ? .red : .secondary)
                        Text(entry.message)
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Debug Logs")
    }
}
