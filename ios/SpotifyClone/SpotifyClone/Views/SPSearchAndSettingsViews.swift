import SwiftUI

// MARK: - 1. Spotify Search View
public struct SPSearchView: View {
    @EnvironmentObject private var appVM: SPAppViewModel
    @State private var query: String = ""

    private let browseCategories: [(title: String, query: String, color: Color)] = [
        ("Pop", "pop hits", Color(red: 0.85, green: 0.25, blue: 0.50)),
        ("Hip-Hop / Rap", "rap fr", Color(red: 0.72, green: 0.35, blue: 0.12)),
        ("Électro / Dance", "electro dance", Color(red: 0.10, green: 0.55, blue: 0.65)),
        ("Rock", "rock classics", Color(red: 0.78, green: 0.14, blue: 0.20)),
        ("R&B", "rnb soul", Color(red: 0.55, green: 0.20, blue: 0.72)),
        ("Chill", "lofi chill", Color(red: 0.20, green: 0.48, blue: 0.38)),
        ("Latino", "reggaeton latino", Color(red: 0.88, green: 0.45, blue: 0.10)),
        ("Skyrock Classics", "skyrock rap", Color(red: 0.0, green: 0.52, blue: 0.88))
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rechercher")
                    .font(SPFontManager.mix(24, bold: true))
                    .foregroundStyle(.white)

                // Classic White Spotify Search Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.8))

                    TextField("Que souhaitez-vous écouter ?", text: $query)
                        .font(SPFontManager.mix(15, bold: true))
                        .foregroundStyle(.black)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit {
                            appVM.performSearch(query, immediate: true)
                        }
                        .onChange(of: query) { _, newVal in
                            appVM.performSearch(newVal)
                        }

                    if !query.isEmpty {
                        Button {
                            query = ""
                            appVM.performSearch("")
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.black.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Parcourir tout")
                            .font(SPFontManager.mix(16, bold: true))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(browseCategories, id: \.title) { cat in
                                Button {
                                    query = cat.query
                                    appVM.performSearch(cat.query)
                                } label: {
                                    ZStack(alignment: .topLeading) {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(cat.color)
                                            .frame(height: 94)

                                        Text(cat.title)
                                            .font(SPFontManager.mix(16, bold: true))
                                            .foregroundStyle(.white)
                                            .padding(12)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 130)
                } else if appVM.isSearching {
                    ProgressView().tint(SPTheme.spotifyGreen).padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        if !appVM.searchTracks.isEmpty {
                            Text("Titres")
                                .font(SPFontManager.mix(18, bold: true))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)

                            LazyVStack(spacing: 12) {
                                ForEach(appVM.searchTracks) { track in
                                    SPTrackRowView(track: track, queue: appVM.searchTracks, contextTitle: "Recherche")
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        if !appVM.searchArtists.isEmpty {
                            Text("Artistes")
                                .font(SPFontManager.mix(18, bold: true))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(appVM.searchArtists) { artist in
                                        Button {
                                            appVM.selectedCollection = artist
                                        } label: {
                                            VStack(spacing: 6) {
                                                SPCachedAsyncImage(url: artist.coverURL) {
                                                    Circle().fill(SPTheme.backgroundElevated)
                                                }
                                                .frame(width: 100, height: 100)
                                                .clipShape(Circle())
                                                Text(artist.title)
                                                    .font(SPFontManager.mix(13, bold: true))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 100)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        if !appVM.searchAlbums.isEmpty {
                            Text("Albums")
                                .font(SPFontManager.mix(18, bold: true))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(appVM.searchAlbums) { album in
                                        Button {
                                            appVM.selectedCollection = album
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                SPCachedAsyncImage(url: album.coverURL) {
                                                    Rectangle().fill(SPTheme.backgroundElevated)
                                                }
                                                .frame(width: 120, height: 120)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                                Text(album.title)
                                                    .font(SPFontManager.mix(13, bold: true))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 120)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        if !appVM.searchPlaylists.isEmpty {
                            Text("Playlists")
                                .font(SPFontManager.mix(18, bold: true))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(appVM.searchPlaylists) { pl in
                                        Button {
                                            appVM.selectedCollection = pl
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                SPCachedAsyncImage(url: pl.coverURL) {
                                                    Rectangle().fill(SPTheme.backgroundElevated)
                                                }
                                                .frame(width: 120, height: 120)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                                Text(pl.title)
                                                    .font(SPFontManager.mix(13, bold: true))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 120)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        if !appVM.searchPodcasts.isEmpty {
                            Text("Podcasts")
                                .font(SPFontManager.mix(18, bold: true))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(appVM.searchPodcasts) { pod in
                                        Button {
                                            appVM.selectedCollection = pod
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                SPCachedAsyncImage(url: pod.coverURL) {
                                                    Rectangle().fill(SPTheme.backgroundElevated)
                                                }
                                                .frame(width: 120, height: 120)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                Text(pod.title)
                                                    .font(SPFontManager.mix(13, bold: true))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 120)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.bottom, 130)
                }
            }
        }
        .background(SPTheme.backgroundPrimary)
    }
}

// MARK: - 2. Premium / Settings View
public struct SPPremiumAndSettingsView: View {
    @EnvironmentObject private var appVM: SPAppViewModel
    @ObservedObject private var downloadManager = SPOfflineDownloadManager.shared
    @State private var arlDraft: String = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("Compte & ARL OpenDeezer") {
                    TextField("Collez votre cookie ARL Deezer ici", text: $arlDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 13, design: .monospaced))
                        .submitLabel(.done)
                        .onSubmit {
                            appVM.saveAndValidateARL(arlDraft)
                        }

                    Button("Enregistrer & Tester l'ARL") {
                        appVM.saveAndValidateARL(arlDraft)
                    }
                    .foregroundStyle(SPTheme.spotifyGreen)
                    .fontWeight(.semibold)

                    if !appVM.arlStatusMessage.isEmpty {
                        Text(appVM.arlStatusMessage)
                            .font(SPFontManager.mix(12))
                            .foregroundStyle(appVM.arlStatusMessage.contains("Connecté") ? SPTheme.spotifyGreen : .orange)
                    }
                }

                Section("Mode Radio Skyrock") {
                    Toggle(isOn: Binding(
                        get: { appVM.isSkyrockMode },
                        set: { _ in appVM.toggleSkyrockMode() }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Version Skyrock (Jingle + 1.025x)")
                                .font(SPFontManager.mix(15, bold: true))
                            Text("Lance skyRock.mp3 puis enchaîne en fondu avec pitch/vitesse 1.025x.")
                                .font(SPFontManager.mix(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(SPTheme.skyrockBlue)
                }

                Section("Moteur Audio & Hors-ligne") {
                    LabeledContent("Catalogue & Podcasts", value: "OpenDeezer API")
                    LabeledContent("Streaming & Download", value: appVM.deezerARL.isEmpty ? "OpenAudio HLS / Teaser" : "OpenDeezer ARL")
                    LabeledContent("Titres téléchargés", value: "\(downloadManager.downloads.count)")
                    LabeledContent("Titres likés", value: "\(appVM.likedTracks.count)")
                }

                Section("À propos") {
                    LabeledContent("Version", value: "9.2.0")
                    LabeledContent("Bundle ID", value: "com.skyrock.spotifyclone")
                }
            }
            .navigationTitle("Réglages & Premium")
        }
        .preferredColorScheme(.dark)
        .onAppear {
            arlDraft = appVM.deezerARL
        }
    }
}
