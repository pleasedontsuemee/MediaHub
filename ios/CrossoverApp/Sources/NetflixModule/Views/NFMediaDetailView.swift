import SwiftUI

// MARK: - Media Detail View (`Lost in Space` / `Stranger Things` style sheet)
public struct NFMediaDetailView: View {
    @EnvironmentObject private var appVM: NFAppViewModel
    @ObservedObject private var downloadManager = NFOfflineDownloadManager.shared
    @Environment(\.dismiss) private var dismiss

    public let initialMedia: NFMediaItem

    @State private var media: NFMediaItem
    @State private var castLine: String = ""
    @State private var seasons: [NFSeason] = []
    @State private var selectedSeason: Int = 1
    @State private var episodes: [NFEpisode] = []
    @State private var recommendations: [NFMediaItem] = []
    @State private var activeTab: DetailTab = .episodes
    @State private var isLoadingDetails = true

    public enum DetailTab: String, CaseIterable {
        case episodes = "Épisodes"
        case moreLikeThis = "Titres similaires"
    }

    public init(media: NFMediaItem) {
        self.initialMedia = media
        self._media = State(initialValue: media)
        self._activeTab = State(initialValue: media.mediaType == .tv ? .episodes : .moreLikeThis)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            NFTheme.backgroundPrimary.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    // 1. Top 16:9 Preview Banner
                    ZStack(alignment: .topTrailing) {
                        NFCachedAsyncImage(url: media.backdropURL) {
                            Rectangle().fill(NFTheme.backgroundSecondary)
                        }
                        .frame(height: 225)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [Color.black.opacity(0.35), Color.clear, Color.black.opacity(0.65)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay {
                            Button {
                                appVM.playMedia(media, season: selectedSeason, episode: episodes.first?.episodeNumber)
                            } label: {
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                                    .frame(width: 58, height: 58)
                                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                                    .overlay(
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 24))
                                            .foregroundStyle(.white)
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 12) {
                            Button {
                                appVM.showToast("AirPlay / Cast prêt")
                            } label: {
                                Circle()
                                    .fill(Color.black.opacity(0.65))
                                    .frame(width: 34, height: 34)
                                    .overlay(Image(systemName: "airplayvideo").font(.system(size: 14)).foregroundStyle(.white))
                            }
                            .buttonStyle(.plain)

                            Button {
                                dismiss()
                            } label: {
                                Circle()
                                    .fill(Color.black.opacity(0.65))
                                    .frame(width: 34, height: 34)
                                    .overlay(Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        // 2. N SERIES / N FILM + Title + Metadata
                        HStack(spacing: 6) {
                            NFNetflixRibbonN(height: 15)
                            Text(media.mediaType.badgeLabel)
                                .font(.system(size: 11, weight: .bold))
                                .tracking(2.5)
                                .foregroundStyle(NFTheme.textSecondary)
                        }

                        Text(media.title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)

                        HStack(spacing: 8) {
                            if !media.metadataLine.isEmpty {
                                Text(media.metadataLine)
                                    .font(.system(size: 13))
                                    .foregroundStyle(NFTheme.textSecondary)
                            }

                            Text(media.maturityRating)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 2).fill(Color.orange.opacity(0.85)))

                            Text("HD")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(NFTheme.textSecondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(NFTheme.textSecondary, lineWidth: 1))
                        }

                        // 3. Full-width Play & Download Buttons
                        Button {
                            appVM.playMedia(media, season: media.mediaType == .tv ? selectedSeason : nil, episode: episodes.first?.episodeNumber, episodeTitle: episodes.first?.name)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text("Lecture")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white))
                        }
                        .buttonStyle(.plain)

                        let dlKey = downloadManager.key(for: media, season: media.mediaType == .tv ? selectedSeason : nil, episode: media.mediaType == .tv ? 1 : nil)
                        let isDownloading = downloadManager.activeProgress[dlKey] != nil
                        let isDownloaded = downloadManager.isDownloaded(media: media, season: media.mediaType == .tv ? selectedSeason : nil, episode: media.mediaType == .tv ? 1 : nil)

                        Button {
                            Task {
                                appVM.showToast("Téléchargement lancé...")
                                let ok = await downloadManager.downloadMedia(
                                    media,
                                    season: media.mediaType == .tv ? selectedSeason : nil,
                                    episode: media.mediaType == .tv ? 1 : nil,
                                    episodeTitle: episodes.first?.name
                                )
                                appVM.showToast(ok ? "Enregistré dans Téléchargements" : "Échec du téléchargement")
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.to.line")
                                Text(isDownloading ? "Téléchargement..." : (isDownloaded ? "Téléchargé" : "Télécharger"))
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 4).fill(NFTheme.backgroundElevated))
                        }
                        .buttonStyle(.plain)

                        // 4. Synopsis & Cast
                        if !media.overview.isEmpty {
                            Text(media.overview)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineSpacing(3)
                        }
                        if !castLine.isEmpty {
                            Text(castLine)
                                .font(.system(size: 12))
                                .foregroundStyle(NFTheme.textSecondary)
                        }

                        // 5. Action Row (`My List`, `Rate`, `Share`)
                        HStack(spacing: 38) {
                            Button {
                                appVM.toggleMyList(media)
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: appVM.isInMyList(media) ? "checkmark" : "plus")
                                        .font(.system(size: 22))
                                    Text("Ma liste")
                                        .font(.system(size: 12))
                                        .foregroundStyle(NFTheme.textSecondary)
                                }
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)

                            Button {
                                appVM.toggleLike(media)
                                appVM.showToast(appVM.likedMediaIds.contains(media.id) ? "Aimé !" : "Note retirée")
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: appVM.likedMediaIds.contains(media.id) ? "hand.thumbsup.fill" : "hand.thumbsup")
                                        .font(.system(size: 22))
                                    Text("Évaluer")
                                        .font(.system(size: 12))
                                        .foregroundStyle(NFTheme.textSecondary)
                                }
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)

                            Button {
                                appVM.showToast("Lien copié !")
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "paperplane")
                                        .font(.system(size: 22))
                                    Text("Partager")
                                        .font(.system(size: 12))
                                        .foregroundStyle(NFTheme.textSecondary)
                                }
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }
                        .padding(.vertical, 8)

                        // 6. Tabs (`Episodes` / `More Like This`)
                        Rectangle().fill(NFTheme.separator).frame(height: 0.5)

                        HStack(spacing: 24) {
                            if media.mediaType == .tv {
                                tabHeader(.episodes)
                            }
                            tabHeader(.moreLikeThis)
                            Spacer()
                        }

                        if activeTab == .episodes && media.mediaType == .tv {
                            if !seasons.isEmpty {
                                Menu {
                                    ForEach(seasons) { s in
                                        Button(s.name) {
                                            selectedSeason = s.seasonNumber
                                            Task {
                                                episodes = await NFMovixEngine.shared.fetchEpisodes(tvId: media.id, season: s.seasonNumber)
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("Saison \(selectedSeason)")
                                            .font(.system(size: 15, weight: .semibold))
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 12))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(NFTheme.backgroundElevated))
                                }
                            }

                            ForEach(episodes) { ep in
                                episodeRow(ep)
                            }
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                                ForEach(recommendations) { rec in
                                    Button {
                                        appVM.selectedDetailMedia = rec
                                    } label: {
                                        NFCachedAsyncImage(url: rec.posterURL) {
                                            Rectangle().fill(NFTheme.backgroundElevated)
                                        }
                                        .aspectRatio(2.0 / 3.0, contentMode: .fill)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 32)
                }
            }
        }
        .task(id: initialMedia.id) {
            isLoadingDetails = true
            let details = await NFMovixEngine.shared.fetchMediaDetails(for: initialMedia)
            self.media = details.updated
            self.castLine = details.castLine
            self.seasons = details.seasons
            self.recommendations = details.recommendations
            if initialMedia.mediaType == .tv {
                let s1 = details.seasons.first?.seasonNumber ?? 1
                self.selectedSeason = s1
                self.episodes = await NFMovixEngine.shared.fetchEpisodes(tvId: initialMedia.id, season: s1)
            }
            isLoadingDetails = false
        }
    }

    private func tabHeader(_ tab: DetailTab) -> some View {
        Button {
            activeTab = tab
        } label: {
            VStack(spacing: 8) {
                Rectangle()
                    .fill(activeTab == tab ? NFTheme.netflixRed : Color.clear)
                    .frame(height: 3)
                Text(tab.rawValue)
                    .font(.system(size: 14, weight: activeTab == tab ? .bold : .medium))
                    .foregroundStyle(activeTab == tab ? .white : NFTheme.textSecondary)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    private func episodeRow(_ ep: NFEpisode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button {
                    appVM.playMedia(media, season: ep.seasonNumber, episode: ep.episodeNumber, episodeTitle: "\(ep.episodeNumber). \(ep.name)")
                } label: {
                    ZStack {
                        NFCachedAsyncImage(url: ep.stillURL ?? media.backdropURL) {
                            Rectangle().fill(NFTheme.backgroundElevated)
                        }
                        .frame(width: 124, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        Circle()
                            .fill(Color.black.opacity(0.55))
                            .frame(width: 32, height: 32)
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 1))
                            .overlay(Image(systemName: "play.fill").font(.system(size: 12)).foregroundStyle(.white))
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(ep.episodeNumber). \(ep.name)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text("\(ep.runtime)m")
                        .font(.system(size: 12))
                        .foregroundStyle(NFTheme.textSecondary)
                }

                Spacer()

                let isEpDl = downloadManager.isDownloaded(media: media, season: ep.seasonNumber, episode: ep.episodeNumber)
                Button {
                    Task {
                        appVM.showToast("Téléchargement Épisode \(ep.episodeNumber)...")
                        let ok = await downloadManager.downloadMedia(media, season: ep.seasonNumber, episode: ep.episodeNumber, episodeTitle: "\(ep.episodeNumber). \(ep.name)")
                        appVM.showToast(ok ? "Épisode téléchargé" : "Échec")
                    }
                } label: {
                    Image(systemName: isEpDl ? "checkmark.circle.fill" : "arrow.down.to.line")
                        .font(.system(size: 18))
                        .foregroundStyle(isEpDl ? NFTheme.accentBlue : .white)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }

            if !ep.overview.isEmpty {
                Text(ep.overview)
                    .font(.system(size: 12))
                    .foregroundStyle(NFTheme.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 6)
    }
}
