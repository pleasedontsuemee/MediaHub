import SwiftUI

// MARK: - 1. Library Tab View (History Starts Empty, Your Videos = Watched Videos, Interactive Playlists!)
public struct YTLibraryView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @ObservedObject private var downloadManager = YTOfflineDownloadManager.shared

    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistTitle = ""
    @State private var playlistSortOrder = "Recently added"

    public init() {}

    public var body: some View {
        NavigationStack(path: $appVM.libraryNavigationPath) {
            VStack(spacing: 0) {
                YTTopHeaderBarView()

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Section 1: History Header + Dynamic Watch History Carousel
                        HStack(spacing: 14) {
                            YTIcon("ic_history", fallback: "clock.arrow.circlepath", size: 24)
                                .foregroundStyle(YTTheme.textPrimary)

                            Text("History")
                                .font(YTFontManager.youtubeSans(size: 18, weight: .bold))
                                .foregroundStyle(YTTheme.textPrimary)

                            Spacer()

                            if !appVM.watchHistory.isEmpty {
                                Button {
                                    appVM.pushRoute(.yourVideos)
                                } label: {
                                    Text("VIEW ALL")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(YTTheme.callToActionBlue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 12)

                        if appVM.watchHistory.isEmpty {
                            Text("Aucune vidéo regardée pour le moment. Les vidéos que vous regardez apparaîtront ici.")
                                .font(.system(size: 13))
                                .foregroundStyle(YTTheme.textSecondary)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 18)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 14) {
                                    ForEach(appVM.watchHistory) { item in
                                        Button {
                                            appVM.openVideo(item)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 8) {
                                                ZStack(alignment: .bottomTrailing) {
                                                    YTCachedAsyncImage(url: item.thumbnailURL) {
                                                        Rectangle().fill(YTTheme.backgroundSecondary)
                                                    }
                                                    .frame(width: 154, height: 86)
                                                    .clipped()

                                                    if !item.isLive {
                                                        Text(item.durationText)
                                                            .font(.system(size: 11, weight: .medium))
                                                            .foregroundStyle(.white)
                                                            .padding(.horizontal, 4)
                                                            .padding(.vertical, 2)
                                                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.82)))
                                                            .padding(6)
                                                    }

                                                    VStack {
                                                        Spacer()
                                                        ZStack(alignment: .leading) {
                                                            Rectangle().fill(Color.white.opacity(0.35)).frame(height: 3)
                                                            Rectangle().fill(YTTheme.brandRed).frame(width: 154 * CGFloat(max(0.15, item.watchProgress)), height: 3)
                                                        }
                                                    }
                                                }
                                                .frame(width: 154, height: 86)

                                                HStack(alignment: .top, spacing: 4) {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(item.title)
                                                            .font(.system(size: 14, weight: .regular))
                                                            .foregroundStyle(YTTheme.textPrimary)
                                                            .lineLimit(2)
                                                            .multilineTextAlignment(.leading)

                                                        Text(item.channelTitle)
                                                            .font(.system(size: 12))
                                                            .foregroundStyle(YTTheme.textSecondary)
                                                            .lineLimit(1)
                                                    }
                                                    Spacer(minLength: 0)
                                                    Menu {
                                                        Button("Supprimer de l'historique", role: .destructive) {
                                                            appVM.watchHistory.removeAll { $0.id == item.id }
                                                            appVM.savePersistedUserState()
                                                        }
                                                        Button("Enregistrer dans une playlist") {
                                                            appVM.presentSaveToPlaylist(for: item)
                                                        }
                                                    } label: {
                                                        YTIcon("yt_outline_overflow_vertical_24pt", fallback: "ellipsis", size: 16)
                                                            .foregroundStyle(YTTheme.textPrimary)
                                                    }
                                                }
                                            }
                                            .frame(width: 154)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 18)
                            }
                        }

                        Rectangle()
                            .fill(YTTheme.separator)
                            .frame(height: 0.5)

                        // Section 2: Library Action Rows (`Your videos` = watched videos, `Downloads`, `Your movies and shows`)
                        VStack(spacing: 0) {
                            Button {
                                appVM.pushRoute(.yourVideos)
                            } label: {
                                libraryMenuRow(
                                    asset: "yt_outline_my_videos_24pt",
                                    fallback: "play.rectangle",
                                    title: "Your videos",
                                    subtitle: appVM.watchHistory.isEmpty ? "Aucune vidéo regardée" : "\(appVM.watchHistory.count) \(appVM.watchHistory.count == 1 ? "vidéo regardée" : "vidéos regardées")"
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                appVM.pushRoute(.downloads)
                            } label: {
                                libraryMenuRow(
                                    asset: "yt_outline_download_24pt",
                                    fallback: "arrow.down.to.line",
                                    title: "Downloads",
                                    subtitle: downloadManager.downloads.isEmpty ? "No videos" : "\(downloadManager.downloads.count) videos"
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                appVM.pushRoute(.trending(initialTab: "MOVIES"))
                            } label: {
                                libraryMenuRow(
                                    asset: "yt_outline_film_strip_24pt",
                                    fallback: "film",
                                    title: "Your movies and shows",
                                    subtitle: nil
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)

                        Rectangle()
                            .fill(YTTheme.separator)
                            .frame(height: 0.5)

                        // Section 3: Playlists (`+ New playlist`, `Watch later`, User Playlists)
                        HStack {
                            Text("Playlists")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(YTTheme.textPrimary)

                            Spacer()

                            Menu {
                                Button("Recently added") { playlistSortOrder = "Recently added" }
                                Button("A-Z") { playlistSortOrder = "A-Z" }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(playlistSortOrder)
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(YTTheme.textPrimary)
                                    YTIcon("yt_outline_chevron_down_24pt", fallback: "chevron.down", size: 16)
                                        .foregroundStyle(YTTheme.textSecondary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                        // `+ New playlist` row in blue
                        Button {
                            newPlaylistTitle = ""
                            showNewPlaylistAlert = true
                        } label: {
                            HStack(spacing: 20) {
                                Image(systemName: "plus")
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundStyle(YTTheme.callToActionBlue)
                                    .frame(width: 44, height: 44)

                                Text("New playlist")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(YTTheme.callToActionBlue)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 54)
                        }
                        .buttonStyle(.plain)

                        // Playlist rows
                        ForEach(appVM.playlists) { playlist in
                            Button {
                                appVM.pushRoute(.playlistDetail(playlist))
                            } label: {
                                HStack(spacing: 20) {
                                    if playlist.id == "WL" {
                                        ZStack {
                                            YTIcon("yt_outline_clock_24pt", fallback: "clock", size: 24)
                                                .foregroundStyle(YTTheme.textPrimary)
                                        }
                                        .frame(width: 44, height: 44)
                                    } else {
                                        YTCachedAsyncImage(url: playlist.videos.first?.thumbnailURL) {
                                            RoundedRectangle(cornerRadius: 4).fill(YTTheme.backgroundSecondary)
                                        }
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.title)
                                            .font(.system(size: 16, weight: .regular))
                                            .foregroundStyle(YTTheme.textPrimary)
                                        Text("\(playlist.videos.count) \(playlist.videos.count == 1 ? "video" : "videos")")
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundStyle(YTTheme.textSecondary)
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 58)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, appVM.currentVideo != nil ? 76 : 24)
                }
            }
            .background(YTTheme.backgroundPrimary)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: YTNavigationRoute.self) { route in
                YTRouteDestinationView(route: route)
            }
            .alert("New playlist", isPresented: $showNewPlaylistAlert) {
                TextField("Title", text: $newPlaylistTitle)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    appVM.createPlaylist(title: newPlaylistTitle)
                }
            }
        }
    }

    private func libraryMenuRow(asset: String, fallback: String, title: String, subtitle: String?) -> some View {
        HStack(spacing: 20) {
            YTIcon(asset, fallback: fallback, size: 24)
                .foregroundStyle(YTTheme.textPrimary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(YTTheme.textPrimary)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(YTTheme.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .contentShape(Rectangle())
    }
}

// MARK: - 2. Your Videos Screen (Displays Only the Videos Watched by the User!)
public struct YTYourVideosView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilter = "All"

    public init() {}

    private var filteredWatchedVideos: [YTVideo] {
        switch selectedFilter {
        case "Shorts":
            return appVM.watchHistory.filter { $0.isShort }
        case "Videos":
            return appVM.watchHistory.filter { !$0.isShort }
        default:
            return appVM.watchHistory
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            YTTopHeaderBarView(showBackButton: true, customTitle: "Your videos") {
                dismiss()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["All", "Videos", "Shorts"], id: \.self) { chip in
                        let active = (chip == selectedFilter)
                        Button {
                            selectedFilter = chip
                        } label: {
                            Text(chip)
                                .font(.system(size: 14, weight: active ? .medium : .regular))
                                .foregroundStyle(active ? YTTheme.chipSelectedText : YTTheme.textPrimary)
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .background(Capsule().fill(active ? YTTheme.chipSelectedBackground : YTTheme.backgroundSecondary))
                        }
                        .buttonStyle(.plain)
                    }

                    if !appVM.watchHistory.isEmpty {
                        Button {
                            appVM.watchHistory.removeAll()
                            appVM.savePersistedUserState()
                            appVM.showToast("Historique effacé")
                        } label: {
                            Text("Effacer tout")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(Capsule().fill(YTTheme.backgroundSecondary))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            if filteredWatchedVideos.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    YTIcon("yt_outline_my_videos_24pt", fallback: "play.rectangle", size: 56)
                        .foregroundStyle(YTTheme.textSecondary)
                    Text("Aucune vidéo regardée")
                        .font(YTFontManager.youtubeSans(size: 18, weight: .bold))
                        .foregroundStyle(YTTheme.textPrimary)
                    Text("Les vidéos et Shorts que vous regardez s'afficheront automatiquement ici.")
                        .font(.system(size: 14))
                        .foregroundStyle(YTTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(filteredWatchedVideos) { v in
                            HStack(alignment: .top, spacing: 8) {
                                YTCompactHorizontalVideoRow(video: v)
                                Button {
                                    appVM.watchHistory.removeAll { $0.id == v.id }
                                    appVM.savePersistedUserState()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 15))
                                        .foregroundStyle(YTTheme.textSecondary)
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.bottom, appVM.currentVideo != nil ? 76 : 20)
                }
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - 3. Offline Downloads Screen
public struct YTDownloadsView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @ObservedObject private var downloadManager = YTOfflineDownloadManager.shared
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            YTTopHeaderBarView(showBackButton: true, customTitle: "Downloads") {
                dismiss()
            }

            if downloadManager.downloads.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    YTIcon("yt_outline_download_24pt", fallback: "arrow.down.circle", size: 64)
                        .foregroundStyle(YTTheme.textSecondary)
                    Text("No downloaded videos")
                        .font(YTFontManager.youtubeSans(size: 18, weight: .bold))
                        .foregroundStyle(YTTheme.textPrimary)
                    Text("Téléchargez n'importe quelle vidéo depuis le bouton Download sous le lecteur pour la regarder hors-ligne.")
                        .font(.system(size: 14))
                        .foregroundStyle(YTTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(downloadManager.downloads) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top, spacing: 12) {
                                    YTCompactHorizontalVideoRow(video: item.video)
                                    Button {
                                        downloadManager.removeDownload(videoId: item.id)
                                        appVM.showToast("Supprimé des téléchargements")
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                            .padding(8)
                                    }
                                    .buttonStyle(.plain)
                                }

                                HStack(spacing: 8) {
                                    Image(systemName: item.qualityLabel.contains("Audio") ? "music.note" : "arrow.down.circle.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(YTTheme.callToActionBlue)
                                    Text("\(item.qualityLabel) · \(item.formattedFileSize)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(YTTheme.callToActionBlue)
                                }
                                .padding(.leading, 4)
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - 4. Playlist Detail View (Supports Searching & Adding Any Music/Video Directly Inside the Playlist!)
public struct YTPlaylistDetailView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss
    public let playlist: YTPlaylist

    @State private var showAddMusicSheet: Bool = false

    public init(playlist: YTPlaylist) {
        self.playlist = playlist
    }

    private var currentPlaylist: YTPlaylist {
        appVM.playlists.first(where: { $0.id == playlist.id }) ?? playlist
    }

    public var body: some View {
        let pl = currentPlaylist

        VStack(spacing: 0) {
            YTTopHeaderBarView(showBackButton: true, customTitle: pl.title) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Playlist Header Banner
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(pl.title)
                                .font(YTFontManager.youtubeSans(size: 22, weight: .bold))
                                .foregroundStyle(YTTheme.textPrimary)
                            HStack(spacing: 6) {
                                Text("\(pl.videos.count) \(pl.videos.count == 1 ? "vidéo" : "vidéos")")
                                if pl.isPrivate {
                                    Image(systemName: "lock.fill").font(.system(size: 11))
                                }
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(YTTheme.textSecondary)

                            // `+ Ajouter une musique / vidéo` Button directly in the playlist!
                            Button {
                                showAddMusicSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Ajouter une musique / vidéo")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(YTTheme.callToActionBlue))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                        Spacer()
                        if let first = pl.videos.first {
                            Button {
                                appVM.openVideo(first)
                            } label: {
                                ZStack {
                                    Circle().fill(YTTheme.brandRed).frame(width: 48, height: 48)
                                    Image(systemName: "play.fill").foregroundStyle(.white)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .background(YTTheme.backgroundSecondary)

                    if pl.videos.isEmpty {
                        VStack(spacing: 12) {
                            Text("Cette playlist est vide.")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(YTTheme.textSecondary)
                            Button {
                                showAddMusicSheet = true
                            } label: {
                                Text("RECHERCHER ET AJOUTER UN TITRE")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(YTTheme.callToActionBlue)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(pl.videos) { video in
                            HStack(alignment: .top, spacing: 8) {
                                YTCompactHorizontalVideoRow(video: video)
                                Button {
                                    appVM.toggleVideo(video, inPlaylist: pl.id)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                }
                .padding(.bottom, appVM.currentVideo != nil ? 76 : 20)
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAddMusicSheet) {
            YTAddMusicToPlaylistSheet(playlistId: pl.id, playlistTitle: pl.title)
                .environmentObject(appVM)
        }
    }
}

// MARK: - Search & Add Music/Video to Playlist Modal Sheet
private struct YTAddMusicToPlaylistSheet: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss
    let playlistId: String
    let playlistTitle: String

    @State private var query: String = ""
    @State private var results: [YTVideo] = []
    @State private var isSearching: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    YTIcon("yt_outline_search_24pt", fallback: "magnifyingglass", size: 20)
                        .foregroundStyle(YTTheme.textSecondary)

                    TextField("Rechercher une musique, un clip, un artiste...", text: $query)
                        .font(.system(size: 15))
                        .submitLabel(.search)
                        .onSubmit {
                            performSearch()
                        }

                    if !query.isEmpty {
                        Button("Chercher") {
                            performSearch()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(YTTheme.callToActionBlue)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 8).fill(YTTheme.backgroundSecondary))
                .padding(12)

                Divider()

                if isSearching {
                    Spacer()
                    ProgressView("Recherche sur YouTube...")
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            let list = results.isEmpty ? appVM.homeVideos : results
                            ForEach(list) { video in
                                let alreadyIn = appVM.isVideo(video.id, inPlaylist: playlistId)
                                HStack(alignment: .center, spacing: 12) {
                                    YTCachedAsyncImage(url: video.thumbnailURL) {
                                        Rectangle().fill(YTTheme.backgroundSecondary)
                                    }
                                    .frame(width: 110, height: 62)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(video.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(YTTheme.textPrimary)
                                            .lineLimit(2)
                                        Text(video.channelTitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(YTTheme.textSecondary)
                                    }

                                    Spacer()

                                    Button {
                                        appVM.toggleVideo(video, inPlaylist: playlistId)
                                    } label: {
                                        Image(systemName: alreadyIn ? "checkmark.circle.fill" : "plus.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundStyle(alreadyIn ? .green : YTTheme.callToActionBlue)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 14)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(YTTheme.backgroundPrimary)
            .navigationTitle("Ajouter à \(playlistTitle)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        Task {
            results = await YTInnerTubeEngine.shared.searchVideos(query: q)
            isSearching = false
        }
    }
}

// MARK: - 5. User Personal Channel View
public struct YTUserPersonalChannelView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        YTYourVideosView()
    }
}
