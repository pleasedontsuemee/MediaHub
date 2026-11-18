import SwiftUI

// MARK: - 1. Dedicated Artist Page (`SPArtistDetailView`)
public struct SPArtistDetailView: View {
    @EnvironmentObject private var appVM: SPAppViewModel
    @Environment(\.dismiss) private var dismiss

    public let artistId: String
    public let initialName: String

    @State private var artistName: String
    @State private var pictureURL: String?
    @State private var nbFan: Int = 0
    @State private var topTracks: [SPTrack] = []
    @State private var albums: [SPCollection] = []
    @State private var relatedArtists: [SPCollection] = []
    @State private var isFollowing = false
    @State private var isLoading = true

    public init(artistId: String, initialName: String) {
        self.artistId = artistId
        self.initialName = initialName
        self._artistName = State(initialValue: initialName)
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            SPTheme.backgroundPrimary.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Full-bleed Artist Hero Banner
                    ZStack(alignment: .bottomLeading) {
                        SPCachedAsyncImage(url: pictureURL.flatMap { URL(string: $0) }) {
                            Rectangle().fill(SPTheme.backgroundElevated)
                        }
                        .frame(height: 310)
                        .frame(maxWidth: .infinity)
                        .clipped()

                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.45), SPTheme.backgroundPrimary],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 180)

                        Text(artistName)
                            .font(SPFontManager.mix(38, bold: true))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                            .shadow(color: .black.opacity(0.6), radius: 8)
                    }

                    // Monthly Listeners & Follow + Play Controls
                    VStack(alignment: .leading, spacing: 14) {
                        if nbFan > 0 {
                            Text("\(formatCount(nbFan)) auditeurs")
                                .font(SPFontManager.mix(13))
                                .foregroundStyle(SPTheme.textSecondary)
                        }

                        HStack(spacing: 16) {
                            Button {
                                isFollowing.toggle()
                                appVM.showToast(isFollowing ? "Vous suivez \(artistName)" : "Désabonné")
                            } label: {
                                Text(isFollowing ? "Abonné" : "Suivre")
                                    .font(SPFontManager.mix(13, bold: true))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 8)
                                    .overlay(
                                        Capsule().strokeBorder(isFollowing ? SPTheme.spotifyGreen : Color.white.opacity(0.45), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                appVM.isShuffleEnabled.toggle()
                                if let t = topTracks.randomElement() {
                                    appVM.playTrack(t, queue: topTracks, contextTitle: artistName)
                                }
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(appVM.isShuffleEnabled ? SPTheme.spotifyGreen : SPTheme.textSecondary)
                            }
                            .buttonStyle(.plain)

                            Button {
                                if let first = topTracks.first {
                                    appVM.playTrack(first, queue: topTracks, contextTitle: artistName)
                                }
                            } label: {
                                Circle()
                                    .fill(SPTheme.spotifyGreen)
                                    .frame(width: 52, height: 52)
                                    .overlay(Image(systemName: "play.fill").font(.system(size: 20)).foregroundStyle(.black))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)

                    if isLoading && topTracks.isEmpty {
                        ProgressView().tint(SPTheme.spotifyGreen).frame(maxWidth: .infinity).padding(.top, 30)
                    } else {
                        // Top Tracks ("Populaires")
                        if !topTracks.isEmpty {
                            Text("Populaires")
                                .font(SPFontManager.mix(19, bold: true))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)

                            LazyVStack(spacing: 14) {
                                ForEach(Array(topTracks.prefix(10).enumerated()), id: \.element.id) { idx, track in
                                    HStack(spacing: 12) {
                                        Text("\(idx + 1)")
                                            .font(SPFontManager.mix(14, bold: true))
                                            .foregroundStyle(SPTheme.textSecondary)
                                            .frame(width: 22, alignment: .center)

                                        SPTrackRowView(track: track, queue: topTracks, contextTitle: artistName)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        // Albums & Singles
                        if !albums.isEmpty {
                            Text("Albums et singles")
                                .font(SPFontManager.mix(19, bold: true))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 14) {
                                    ForEach(albums) { al in
                                        Button {
                                            appVM.selectedCollection = al
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                SPCachedAsyncImage(url: al.coverURL) {
                                                    Rectangle().fill(SPTheme.backgroundElevated)
                                                }
                                                .frame(width: 144, height: 144)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))

                                                Text(al.title)
                                                    .font(SPFontManager.mix(13, bold: true))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                Text(al.subtitle.isEmpty ? "Album" : al.subtitle)
                                                    .font(SPFontManager.mix(12))
                                                    .foregroundStyle(SPTheme.textSecondary)
                                            }
                                            .frame(width: 144)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        // Related Artists
                        if !relatedArtists.isEmpty {
                            Text("Les fans aiment aussi")
                                .font(SPFontManager.mix(19, bold: true))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 16) {
                                    ForEach(relatedArtists) { rel in
                                        Button {
                                            appVM.selectedCollection = rel
                                        } label: {
                                            VStack(spacing: 8) {
                                                SPCachedAsyncImage(url: rel.coverURL) {
                                                    Circle().fill(SPTheme.backgroundElevated)
                                                }
                                                .frame(width: 116, height: 116)
                                                .clipShape(Circle())
                                                Text(rel.title)
                                                    .font(SPFontManager.mix(13, bold: true))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 116)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .padding(.bottom, 80)
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
        .task(id: artistId) {
            isLoading = true
            let details = await SPMusicEngine.shared.fetchArtistDetails(artistId: artistId)
            self.artistName = details.name
            self.pictureURL = details.pictureURL
            self.nbFan = details.nbFan
            self.topTracks = details.topTracks
            self.albums = details.albums
            self.relatedArtists = details.related
            self.isLoading = false
        }
    }

    private func formatCount(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - 2. Dedicated Album Page (`SPAlbumDetailView`)
public struct SPAlbumDetailView: View {
    @EnvironmentObject private var appVM: SPAppViewModel
    @ObservedObject private var downloadManager = SPOfflineDownloadManager.shared
    @Environment(\.dismiss) private var dismiss

    public let albumId: String
    public let initialTitle: String
    public let initialCoverURL: String?

    @State private var title: String
    @State private var artistName: String = ""
    @State private var artistId: String? = nil
    @State private var artistPicURL: String? = nil
    @State private var coverURL: String?
    @State private var releaseYear: String = ""
    @State private var tracks: [SPTrack] = []
    @State private var isLoading = true

    public init(albumId: String, initialTitle: String, initialCoverURL: String? = nil) {
        self.albumId = albumId
        self.initialTitle = initialTitle
        self.initialCoverURL = initialCoverURL
        self._title = State(initialValue: initialTitle)
        self._coverURL = State(initialValue: initialCoverURL)
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            SPTheme.backgroundPrimary.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack(alignment: .top) {
                        LinearGradient(
                            colors: [Color(red: 0.24, green: 0.18, blue: 0.34), SPTheme.backgroundPrimary],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 310)

                        VStack(spacing: 16) {
                            Spacer().frame(height: 44)
                            SPCachedAsyncImage(url: coverURL.flatMap { URL(string: $0) }) {
                                RoundedRectangle(cornerRadius: 4).fill(SPTheme.backgroundElevated)
                            }
                            .frame(width: 220, height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(title)
                            .font(SPFontManager.mix(24, bold: true))
                            .foregroundStyle(.white)

                        Button {
                            appVM.openArtist(id: artistId, name: artistName)
                        } label: {
                            HStack(spacing: 8) {
                                SPCachedAsyncImage(url: artistPicURL.flatMap { URL(string: $0) }) {
                                    Circle().fill(SPTheme.backgroundElevated)
                                }
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())

                                Text(artistName)
                                    .font(SPFontManager.mix(14, bold: true))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)

                        Text("Album\(releaseYear.isEmpty ? "" : " • \(releaseYear)") • \(tracks.count) titres")
                            .font(SPFontManager.mix(12))
                            .foregroundStyle(SPTheme.textSecondary)

                        HStack(spacing: 18) {
                            Button {
                                Task {
                                    appVM.showToast("Téléchargement de l'album...")
                                    for t in tracks.prefix(20) {
                                        _ = await downloadManager.downloadTrack(t)
                                    }
                                    appVM.showToast("Album téléchargé !")
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
                                    appVM.playTrack(t, queue: tracks, contextTitle: title)
                                }
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(appVM.isShuffleEnabled ? SPTheme.spotifyGreen : SPTheme.textSecondary)
                            }
                            .buttonStyle(.plain)

                            Button {
                                if let first = tracks.first {
                                    appVM.playTrack(first, queue: tracks, contextTitle: title)
                                }
                            } label: {
                                Circle()
                                    .fill(SPTheme.spotifyGreen)
                                    .frame(width: 52, height: 52)
                                    .overlay(Image(systemName: "play.fill").font(.system(size: 20)).foregroundStyle(.black))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)

                    if isLoading && tracks.isEmpty {
                        ProgressView().tint(SPTheme.spotifyGreen).frame(maxWidth: .infinity).padding(.top, 30)
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                                HStack(spacing: 12) {
                                    Text("\(idx + 1)")
                                        .font(SPFontManager.mix(13, bold: true))
                                        .foregroundStyle(SPTheme.textSecondary)
                                        .frame(width: 22, alignment: .center)

                                    SPTrackRowView(track: track, queue: tracks, contextTitle: title)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 80)
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
        .task(id: albumId) {
            isLoading = true
            let details = await SPMusicEngine.shared.fetchAlbumDetails(albumId: albumId)
            self.title = details.title
            self.artistName = details.artistName
            self.artistId = details.artistId
            self.artistPicURL = details.artistPicURL
            self.coverURL = details.coverURL ?? coverURL
            self.releaseYear = details.releaseYear
            self.tracks = details.tracks
            self.isLoading = false
        }
    }
}

// MARK: - 3. Spotify Track Options Sheet (`...` button)
public struct SPTrackOptionsSheet: View {
    @EnvironmentObject private var appVM: SPAppViewModel
    @ObservedObject private var downloadManager = SPOfflineDownloadManager.shared
    @Environment(\.dismiss) private var dismiss

    public let track: SPTrack

    public init(track: SPTrack) {
        self.track = track
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Track Header
            HStack(spacing: 14) {
                SPCachedAsyncImage(url: track.coverURL) {
                    Rectangle().fill(SPTheme.backgroundElevated)
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(SPFontManager.mix(16, bold: true))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(track.artistName)\(track.albumTitle.isEmpty ? "" : " • \(track.albumTitle)")")
                        .font(SPFontManager.mix(13))
                        .foregroundStyle(SPTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(20)

            Rectangle().fill(SPTheme.separator).frame(height: 0.5)

            ScrollView {
                VStack(spacing: 4) {
                    optionRow(
                        icon: appVM.isLiked(track) ? "heart.fill" : "heart",
                        iconColor: appVM.isLiked(track) ? SPTheme.spotifyGreen : .white,
                        title: appVM.isLiked(track) ? "Retirer des Titres likés" : "Liker"
                    ) {
                        appVM.toggleLike(track)
                        dismiss()
                    }

                    optionRow(icon: "text.badge.plus", title: "Ajouter à une playlist") {
                        dismiss()
                        Task {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            appVM.trackToAddToPlaylist = track
                        }
                    }

                    optionRow(icon: "person.circle", title: "Voir l'artiste (\(track.artistName))") {
                        dismiss()
                        Task {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            appVM.openArtist(id: track.artistId, name: track.artistName)
                        }
                    }

                    if let alId = track.albumId, !alId.isEmpty {
                        optionRow(icon: "opticaldisc", title: "Voir l'album\(track.albumTitle.isEmpty ? "" : " (\(track.albumTitle))")") {
                            dismiss()
                            Task {
                                try? await Task.sleep(nanoseconds: 200_000_000)
                                appVM.openAlbum(id: alId, title: track.albumTitle, coverURL: track.coverURLString, artistName: track.artistName)
                            }
                        }
                    }

                    let isDl = downloadManager.isDownloaded(track.id)
                    optionRow(
                        icon: isDl ? "arrow.down.circle.fill" : "arrow.down.circle",
                        iconColor: isDl ? SPTheme.spotifyGreen : .white,
                        title: isDl ? "Téléchargé hors-ligne (Retélécharger)" : "Télécharger hors-ligne"
                    ) {
                        dismiss()
                        Task {
                            appVM.showToast("Téléchargement en cours...")
                            let ok = await downloadManager.downloadTrack(track)
                            appVM.showToast(ok ? "Téléchargé hors-ligne !" : "Échec du téléchargement")
                        }
                    }

                    optionRow(
                        icon: "radio.fill",
                        iconColor: appVM.isSkyrockMode ? SPTheme.skyrockBlue : .white,
                        title: appVM.isSkyrockMode ? "Désactiver Version Skyrock" : "Écouter en Version Skyrock (1.025x)"
                    ) {
                        dismiss()
                        appVM.toggleSkyrockMode()
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(SPTheme.backgroundCard)
    }

    private func optionRow(icon: String, iconColor: Color = .white, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
                    .frame(width: 28)
                Text(title)
                    .font(SPFontManager.mix(15, bold: true))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
