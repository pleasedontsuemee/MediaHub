import SwiftUI

// MARK: - 1. Spotify Home View
public struct SPHomeView: View {
    @EnvironmentObject private var appVM: SPAppViewModel

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            SPTheme.backgroundPrimary.ignoresSafeArea()

            // Subtle Spotify top-left ambient gradient
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.25, blue: 0.18).opacity(0.65), SPTheme.backgroundPrimary],
                startPoint: .topLeading,
                endPoint: .center
            )
            .frame(height: 280)
            .ignoresSafeArea(edges: .top)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    HStack(spacing: 18) {
                        Text("Écoutés récemment")
                            .font(SPFontManager.mix(22, bold: true))
                            .foregroundStyle(.white)
                        Spacer()
                        Button { appVM.showToast("Nouveautés à jour") } label: {
                            Image(systemName: "bell")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        Button { appVM.selectedTab = .library } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        Button { appVM.selectedTab = .premium } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    // 2-Column Quick-Pick Grid
                    let quickItems = Array(appVM.homePlaylists.prefix(5))
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        Button {
                            let likedCol = SPCollection(
                                id: "liked_songs",
                                kind: .playlist,
                                title: "Titres likés",
                                subtitle: "\(appVM.likedTracks.count) titres",
                                tracks: appVM.likedTracks,
                                isUserCreated: true
                            )
                            appVM.selectedCollection = likedCol
                        } label: {
                            HStack(spacing: 10) {
                                LinearGradient(
                                    colors: [Color(red: 0.28, green: 0.16, blue: 0.92), Color(red: 0.72, green: 0.88, blue: 0.96)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .frame(width: 54, height: 54)
                                .overlay(Image(systemName: "heart.fill").foregroundStyle(.white).font(.system(size: 18)))

                                Text("Titres likés")
                                    .font(SPFontManager.mix(13, bold: true))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                Spacer(minLength: 4)
                            }
                            .background(SPTheme.backgroundElevated.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)

                        ForEach(quickItems) { col in
                            Button {
                                appVM.selectedCollection = col
                            } label: {
                                HStack(spacing: 10) {
                                    SPCachedAsyncImage(url: col.coverURL) {
                                        Rectangle().fill(SPTheme.backgroundElevated)
                                    }
                                    .frame(width: 54, height: 54)
                                    .clipped()

                                    Text(col.title)
                                        .font(SPFontManager.mix(13, bold: true))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 4)
                                }
                                .background(SPTheme.backgroundElevated.opacity(0.75))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Top Tracks Carousel
                    if !appVM.topTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Titres du moment")
                                .font(SPFontManager.mix(21, bold: true))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 14) {
                                    ForEach(appVM.topTracks) { track in
                                        Button {
                                            appVM.playTrack(track, queue: appVM.topTracks, contextTitle: "Titres du moment")
                                        } label: {
                                            VStack(alignment: .leading, spacing: 8) {
                                                SPCachedAsyncImage(url: track.coverURL) {
                                                    Rectangle().fill(SPTheme.backgroundElevated)
                                                }
                                                .frame(width: 148, height: 148)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))

                                                Text(track.title)
                                                    .font(SPFontManager.mix(13, bold: true))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                Text(track.artistName)
                                                    .font(SPFontManager.mix(12))
                                                    .foregroundStyle(SPTheme.textSecondary)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 148)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    // Popular Playlists Carousel
                    if !appVM.homePlaylists.isEmpty {
                        collectionCarousel(title: "Pour commencer", items: appVM.homePlaylists)
                    }

                    // Popular Albums Carousel
                    if !appVM.homeAlbums.isEmpty {
                        collectionCarousel(title: "Albums populaires", items: appVM.homeAlbums)
                    }

                    // Popular Podcasts Carousel
                    if !appVM.homePodcasts.isEmpty {
                        collectionCarousel(title: "Podcasts populaires", items: appVM.homePodcasts)
                    }

                    // Artists Circular Carousel
                    if !appVM.homeArtists.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Artistes à découvrir")
                                .font(SPFontManager.mix(21, bold: true))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 16) {
                                    ForEach(appVM.homeArtists) { artist in
                                        Button {
                                            appVM.selectedCollection = artist
                                        } label: {
                                            VStack(spacing: 8) {
                                                SPCachedAsyncImage(url: artist.coverURL) {
                                                    Circle().fill(SPTheme.backgroundElevated)
                                                }
                                                .frame(width: 130, height: 130)
                                                .clipShape(Circle())

                                                Text(artist.title)
                                                    .font(SPFontManager.mix(13, bold: true))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 130)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .padding(.bottom, 130)
            }
            .refreshable {
                await appVM.loadHomeFeed()
            }
        }
    }

    private func collectionCarousel(title: String, items: [SPCollection]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(SPFontManager.mix(21, bold: true))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(items) { col in
                        Button {
                            appVM.selectedCollection = col
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                SPCachedAsyncImage(url: col.coverURL) {
                                    Rectangle().fill(SPTheme.backgroundElevated)
                                }
                                .frame(width: 148, height: 148)
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                                Text(col.title)
                                    .font(SPFontManager.mix(13, bold: true))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(col.subtitle)
                                    .font(SPFontManager.mix(12))
                                    .foregroundStyle(SPTheme.textSecondary)
                                    .lineLimit(2)
                            }
                            .frame(width: 148)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - 2. Your Library View
public struct SPLibraryView: View {
    @EnvironmentObject private var appVM: SPAppViewModel
    @ObservedObject private var downloadManager = SPOfflineDownloadManager.shared
    @State private var selectedFilter: String = "Tout"

    private let filters = ["Tout", "Playlists", "Téléchargés"]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                Circle()
                    .fill(SPTheme.spotifyGreen)
                    .frame(width: 30, height: 30)
                    .overlay(Text("S").font(SPFontManager.mix(15, bold: true)).foregroundStyle(.black))

                Text("Bibliothèque")
                    .font(SPFontManager.mix(22, bold: true))
                    .foregroundStyle(.white)

                Spacer()

                Button { appVM.selectedTab = .search } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button { appVM.isCreatePlaylistPresented = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters, id: \.self) { f in
                        let isSel = selectedFilter == f
                        Button {
                            selectedFilter = f
                        } label: {
                            Text(f)
                                .font(SPFontManager.mix(13, bold: isSel))
                                .foregroundStyle(isSel ? .black : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(isSel ? SPTheme.spotifyGreen : SPTheme.backgroundElevated))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            Rectangle().fill(SPTheme.separator).frame(height: 0.5)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    if selectedFilter != "Téléchargés" {
                        // Liked Songs Row
                        Button {
                            appVM.selectedCollection = SPCollection(
                                id: "liked_songs",
                                kind: .playlist,
                                title: "Titres likés",
                                subtitle: "Playlist • \(appVM.likedTracks.count) titres",
                                tracks: appVM.likedTracks,
                                isUserCreated: true
                            )
                        } label: {
                            HStack(spacing: 12) {
                                LinearGradient(
                                    colors: [Color(red: 0.28, green: 0.16, blue: 0.92), Color(red: 0.72, green: 0.88, blue: 0.96)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .frame(width: 62, height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(Image(systemName: "heart.fill").foregroundStyle(.white).font(.system(size: 22)))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Titres likés")
                                        .font(SPFontManager.mix(16, bold: true))
                                        .foregroundStyle(.white)
                                    Text("Playlist • \(appVM.likedTracks.count) titres")
                                        .font(SPFontManager.mix(13))
                                        .foregroundStyle(SPTheme.textSecondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Offline Downloads Row
                    Button {
                        appVM.selectedCollection = SPCollection(
                            id: "offline_downloads",
                            kind: .playlist,
                            title: "Titres téléchargés",
                            subtitle: "Hors-ligne • \(downloadManager.downloads.count) titres",
                            tracks: downloadManager.downloads.map { $0.track },
                            isUserCreated: true
                        )
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(red: 0.08, green: 0.42, blue: 0.24))
                                .frame(width: 62, height: 62)
                                .overlay(Image(systemName: "arrow.down.circle.fill").foregroundStyle(SPTheme.spotifyGreen).font(.system(size: 24)))

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Titres téléchargés")
                                    .font(SPFontManager.mix(16, bold: true))
                                    .foregroundStyle(.white)
                                Text("Hors-ligne • \(downloadManager.downloads.count) titres")
                                    .font(SPFontManager.mix(13))
                                    .foregroundStyle(SPTheme.textSecondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    if selectedFilter != "Téléchargés" {
                        ForEach(appVM.userPlaylists) { pl in
                            Button {
                                appVM.selectedCollection = pl
                            } label: {
                                HStack(spacing: 12) {
                                    SPCachedAsyncImage(url: pl.coverURL) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(SPTheme.backgroundElevated)
                                            .overlay(Image(systemName: "music.note").foregroundStyle(SPTheme.textSecondary))
                                    }
                                    .frame(width: 62, height: 62)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(pl.title)
                                            .font(SPFontManager.mix(16, bold: true))
                                            .foregroundStyle(.white)
                                        Text("Playlist • \(pl.tracks.count) titres")
                                            .font(SPFontManager.mix(13))
                                            .foregroundStyle(SPTheme.textSecondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 130)
            }
        }
        .background(SPTheme.backgroundPrimary)
    }
}

// MARK: - 3. Collection Detail View (Playlist / Album / Artist)
public struct SPCollectionDetailView: View {
    @EnvironmentObject private var appVM: SPAppViewModel
    @ObservedObject private var downloadManager = SPOfflineDownloadManager.shared
    @Environment(\.dismiss) private var dismiss

    public let collection: SPCollection
    @State private var tracks: [SPTrack] = []
    @State private var isLoading = true

    public init(collection: SPCollection) {
        self.collection = collection
        self._tracks = State(initialValue: collection.tracks)
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            SPTheme.backgroundPrimary.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Artwork Header
                    ZStack(alignment: .top) {
                        LinearGradient(
                            colors: [Color(red: 0.16, green: 0.34, blue: 0.25), SPTheme.backgroundPrimary],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 310)

                        VStack(spacing: 16) {
                            Spacer().frame(height: 44)
                            SPCachedAsyncImage(url: collection.coverURL ?? tracks.first?.coverURL) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(SPTheme.backgroundElevated)
                                    .overlay(Image(systemName: "music.note.list").font(.system(size: 48)).foregroundStyle(SPTheme.textSecondary))
                            }
                            .frame(width: 210, height: 210)
                            .clipShape(collection.kind == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 4)))
                            .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(collection.title)
                            .font(SPFontManager.mix(24, bold: true))
                            .foregroundStyle(.white)
                        Text(collection.subtitle)
                            .font(SPFontManager.mix(13))
                            .foregroundStyle(SPTheme.textSecondary)

                        HStack(spacing: 18) {
                            Button {
                                Task {
                                    appVM.showToast("Téléchargement de la liste...")
                                    for t in tracks.prefix(15) {
                                        _ = await downloadManager.downloadTrack(t)
                                    }
                                    appVM.showToast("Téléchargement terminé")
                                }
                            } label: {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 24))
                                    .foregroundStyle(SPTheme.textSecondary)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                appVM.isShuffleEnabled.toggle()
                                if let t = tracks.randomElement() {
                                    appVM.playTrack(t, queue: tracks, contextTitle: collection.title)
                                }
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(appVM.isShuffleEnabled ? SPTheme.spotifyGreen : SPTheme.textSecondary)
                            }
                            .buttonStyle(.plain)

                            Button {
                                if let first = tracks.first {
                                    appVM.playTrack(first, queue: tracks, contextTitle: collection.title)
                                }
                            } label: {
                                Circle()
                                    .fill(SPTheme.spotifyGreen)
                                    .frame(width: 52, height: 52)
                                    .overlay(Image(systemName: "play.fill").font(.system(size: 20)).foregroundStyle(.black))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)

                    if isLoading && tracks.isEmpty {
                        ProgressView().tint(SPTheme.spotifyGreen).frame(maxWidth: .infinity).padding(.top, 30)
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(tracks) { track in
                                SPTrackRowView(track: track, queue: tracks, contextTitle: collection.title)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 120)
            }
            .ignoresSafeArea(edges: .top)

            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.55)))
            }
            .buttonStyle(.plain)
            .padding(.leading, 14)
            .padding(.top, 10)
        }
        .task {
            let fetched = await SPMusicEngine.shared.fetchTracks(for: collection)
            self.tracks = fetched
            self.isLoading = false
        }
    }
}

public struct SPTrackRowView: View {
    @EnvironmentObject private var appVM: SPAppViewModel
    @ObservedObject private var downloadManager = SPOfflineDownloadManager.shared

    public let track: SPTrack
    public let queue: [SPTrack]
    public let contextTitle: String

    public init(track: SPTrack, queue: [SPTrack], contextTitle: String) {
        self.track = track
        self.queue = queue
        self.contextTitle = contextTitle
    }

    public var body: some View {
        let isCurrent = appVM.currentTrack?.id == track.id
        let isDownloaded = downloadManager.isDownloaded(track.id)
        let isDownloading = downloadManager.activeDownloads.contains(track.id)

        HStack(spacing: 12) {
            Button {
                appVM.playTrack(track, queue: queue, contextTitle: contextTitle)
            } label: {
                HStack(spacing: 12) {
                    SPCachedAsyncImage(url: track.coverURL) {
                        Rectangle().fill(SPTheme.backgroundElevated)
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(SPFontManager.mix(15, bold: isCurrent))
                            .foregroundStyle(isCurrent ? SPTheme.spotifyGreen : .white)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            if isDownloaded {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SPTheme.spotifyGreen)
                            }
                            Text(track.artistName)
                                .font(SPFontManager.mix(13))
                                .foregroundStyle(SPTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isDownloading {
                ProgressView().tint(SPTheme.spotifyGreen).scaleEffect(0.8)
            }

            Button {
                appVM.trackOptionsTarget = track
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18))
                    .foregroundStyle(SPTheme.textSecondary)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - 4. Create Playlist & Add to Playlist Modals
public struct SPCreatePlaylistSheet: View {
    @EnvironmentObject private var appVM: SPAppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.22), SPTheme.backgroundPrimary], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                Text("Donnez un nom à votre playlist")
                    .font(SPFontManager.mix(20, bold: true))
                    .foregroundStyle(.white)

                TextField("Ma playlist", text: $name)
                    .font(SPFontManager.mix(26, bold: true))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.white.opacity(0.4)).frame(height: 1)
                    }
                    .padding(.horizontal, 40)

                HStack(spacing: 18) {
                    Button("Annuler") { dismiss() }
                        .font(SPFontManager.mix(15, bold: true))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))

                    Button("Créer") {
                        appVM.createPlaylist(name: name.isEmpty ? "Ma playlist" : name)
                        dismiss()
                    }
                    .font(SPFontManager.mix(15, bold: true))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(SPTheme.spotifyGreen))
                }
            }
        }
    }
}

public struct SPAddToPlaylistSheet: View {
    @EnvironmentObject private var appVM: SPAppViewModel
    @Environment(\.dismiss) private var dismiss
    public let track: SPTrack

    public init(track: SPTrack) {
        self.track = track
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Button {
                    dismiss()
                    appVM.isCreatePlaylistPresented = true
                } label: {
                    Text("Nouvelle playlist")
                        .font(SPFontManager.mix(15, bold: true))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(.white))
                }
                .padding(.top, 12)

                List(appVM.userPlaylists) { pl in
                    Button {
                        appVM.addTrack(track, toPlaylist: pl.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            SPCachedAsyncImage(url: pl.coverURL) {
                                Rectangle().fill(SPTheme.backgroundElevated)
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            VStack(alignment: .leading) {
                                Text(pl.title).font(SPFontManager.mix(15, bold: true)).foregroundStyle(.white)
                                Text("\(pl.tracks.count) titres").font(SPFontManager.mix(12)).foregroundStyle(SPTheme.textSecondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .background(SPTheme.backgroundPrimary)
            .navigationTitle("Ajouter à une playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
