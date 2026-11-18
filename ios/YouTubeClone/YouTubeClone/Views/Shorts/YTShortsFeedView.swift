import SwiftUI
import AVKit

// MARK: - Fullscreen Vertical Shorts Feed (Swipe Up to Load Next Short Beneath, Swipe Down for Previous!)
public struct YTShortsFeedView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @State private var showCommentsSheet: Bool = false
    @State private var dragTranslationY: CGFloat = 0

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let shorts = appVM.shortsShelfVideos
            let count = shorts.count
            let idx = appVM.activeShortIndex

            ZStack {
                Color.black.ignoresSafeArea()

                if shorts.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.4)
                        Text("Chargement des Shorts...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .task {
                        let fetched = await YTInnerTubeEngine.shared.fetchShortsFeed(seedKeywords: appVM.watchProfileKeywords)
                        if !fetched.isEmpty {
                            appVM.shortsShelfVideos = fetched
                            appVM.playShortInFeed(at: 0)
                        }
                    }
                } else if shorts.indices.contains(idx) {
                    ZStack {
                        // Previous Short (Above) when dragging down
                        if idx > 0 && dragTranslationY > 0 {
                            YTShortSinglePageView(
                                short: shorts[idx - 1],
                                isActive: false,
                                size: geo.size,
                                onOpenComments: {}
                            )
                            .offset(y: -geo.size.height + dragTranslationY)
                        }

                        // Next Short (Below) when dragging up (Swipe Up!)
                        if idx + 1 < count && dragTranslationY < 0 {
                            YTShortSinglePageView(
                                short: shorts[idx + 1],
                                isActive: false,
                                size: geo.size,
                                onOpenComments: {}
                            )
                            .offset(y: geo.size.height + dragTranslationY)
                        }

                        // Active Current Short
                        YTShortSinglePageView(
                            short: shorts[idx],
                            isActive: true,
                            size: geo.size,
                            onOpenComments: {
                                showCommentsSheet = true
                            }
                        )
                        .offset(y: dragTranslationY)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onChanged { val in
                                dragTranslationY = val.translation.height
                            }
                            .onEnded { val in
                                let threshold: CGFloat = 65
                                let predicted = val.predictedEndTranslation.height
                                if (val.translation.height < -threshold || predicted < -140) && idx + 1 < count {
                                    // Swipe UP -> Load Next Short from below!
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                        dragTranslationY = -geo.size.height
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                        dragTranslationY = 0
                                        appVM.playShortInFeed(at: idx + 1)
                                    }
                                } else if (val.translation.height > threshold || predicted > 140) && idx > 0 {
                                    // Swipe DOWN -> Load Previous Short from above!
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                        dragTranslationY = geo.size.height
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                        dragTranslationY = 0
                                        appVM.playShortInFeed(at: idx - 1)
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                        dragTranslationY = 0
                                    }
                                }
                            }
                    )
                }

                // Top-Right Action Icons: Search, Camera, 3-dots
                VStack {
                    HStack(spacing: 22) {
                        Spacer()
                        Button {
                            appVM.shortsPlayer.pause()
                            appVM.audioPlayer.pause()
                            appVM.isSearchOverlayPresented = true
                        } label: {
                            YTIcon("yt_outline_search_24pt", fallback: "magnifyingglass", size: 24)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        YTIcon("ic_shorts_camera_outline", fallback: "camera", size: 24)
                            .foregroundStyle(.white)

                        if shorts.indices.contains(idx) {
                            let activeShort = shorts[idx]
                            Menu {
                                Button("Enregistrer dans une playlist", systemImage: "plus.square.on.square") {
                                    appVM.presentSaveToPlaylist(for: activeShort)
                                }
                                Button("Télécharger", systemImage: "arrow.down.to.line") {
                                    Task {
                                        let ok = await YTOfflineDownloadManager.shared.downloadVideo(activeShort)
                                        appVM.showToast(ok ? "Short téléchargé" : "Erreur de téléchargement")
                                    }
                                }
                            } label: {
                                YTIcon("yt_outline_overflow_vertical_24pt", fallback: "ellipsis", size: 24)
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    Spacer()
                }
            }
            .onAppear {
                if !appVM.shortsShelfVideos.isEmpty {
                    appVM.playShortInFeed(at: appVM.activeShortIndex)
                }
            }
            .onDisappear {
                appVM.shortsPlayer.pause()
                appVM.audioPlayer.pause()
                appVM.isShortsPlaying = false
            }
            .sheet(isPresented: $showCommentsSheet) {
                if shorts.indices.contains(idx) {
                    YTShortsCommentsSheet(short: shorts[idx])
                        .presentationDetents([.medium, .large])
                }
            }
        }
    }
}

// MARK: - Single Vertical Short Page (Live AVPlayer Video Stream + Right Actions + Bottom Info)
private struct YTShortSinglePageView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    let short: YTVideo
    let isActive: Bool
    let size: CGSize
    let onOpenComments: () -> Void

    @State private var showDoubleTapHeart: Bool = false
    @State private var showPlayPauseIcon: Bool = false

    var body: some View {
        let isLiked = appVM.isVideoLiked(short.id)
        let isSub = appVM.isSubscribed(to: short.channelId, channelTitle: short.channelTitle)

        ZStack {
            // Fallback thumbnail while the Short stream is buffering
            YTCachedAsyncImage(url: short.thumbnailURL) {
                Rectangle().fill(Color.black)
            }
            .frame(width: size.width, height: size.height)
            .clipped()

            // Live Vertical AVPlayer when this Short page is active!
            if isActive {
                YTAVPlayerSurfaceView(player: appVM.shortsPlayer, zoomToFill: true)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }

            // Top & Bottom subtle gradient for legibility
            LinearGradient(
                colors: [
                    Color.black.opacity(0.32),
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if !isLiked {
                    appVM.toggleLike(for: short.id)
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    showDoubleTapHeart = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        showDoubleTapHeart = false
                    }
                }
            }
            .onTapGesture(count: 1) {
                appVM.toggleShortsPlayPause()
                withAnimation(.easeInOut(duration: 0.15)) {
                    showPlayPauseIcon = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showPlayPauseIcon = false
                    }
                }
            }

            if showDoubleTapHeart {
                Image(systemName: "hand.thumbsup.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(.white)
                    .shadow(radius: 12)
                    .transition(.scale.combined(with: .opacity))
            }

            if showPlayPauseIcon {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 68, height: 68)
                    Image(systemName: appVM.isShortsPlaying ? "play.fill" : "pause.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
                .transition(.opacity)
            }

            // Bottom Metadata + Right Vertical Action Column
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    // Bottom-Left: Title + Channel Handle + Red SUBSCRIBE Button
                    VStack(alignment: .leading, spacing: 12) {
                        Text(short.title)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 10) {
                            YTChannelAvatarView(url: short.channelAvatarURL, title: short.channelTitle, size: 32)

                            Text(short.channelTitle.hasPrefix("@") ? short.channelTitle : "@\(short.channelTitle.lowercased().replacingOccurrences(of: " ", with: ""))")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Button {
                                appVM.toggleSubscription(
                                    for: short.channelId,
                                    channelTitle: short.channelTitle,
                                    avatarURL: short.channelAvatarURL
                                )
                            } label: {
                                Text(isSub ? "ABONNÉ" : "S'ABONNER")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(isSub ? Color.white.opacity(0.25) : YTTheme.subscribeRed)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.bottom, 18)

                    Spacer(minLength: 8)

                    // Right Action Column: Like, Dislike, Comments, Share, Remix, Audio Square
                    VStack(spacing: 20) {
                        shortsActionButton(
                            asset: isLiked ? "ic_shorts_like_fill_32dp" : "ic_shorts_like_outline_32dp",
                            fallback: "hand.thumbsup.fill",
                            label: isLiked ? "Aimé" : short.likeCountText,
                            tint: isLiked ? YTTheme.callToActionBlue : .white
                        ) {
                            appVM.toggleLike(for: short.id)
                        }

                        shortsActionButton(
                            asset: "ic_shorts_dislike_fill_32dp",
                            fallback: "hand.thumbsdown.fill",
                            label: "Je n'aime pas",
                            tint: .white
                        ) {
                            appVM.toggleDislike(for: short.id)
                        }

                        shortsActionButton(
                            asset: "ic_shorts_comment_filled_style_c",
                            fallback: "text.bubble.fill",
                            label: "\(appVM.currentComments.count)",
                            tint: .white
                        ) {
                            onOpenComments()
                        }

                        shortsActionButton(
                            asset: "ic_shorts_share_filled_style_c",
                            fallback: "arrowshape.turn.up.right.fill",
                            label: "Partager",
                            tint: .white
                        ) {
                            appVM.showToast("Lien copié")
                        }

                        shortsActionButton(
                            asset: "ic_shorts_remix_outline_32dp",
                            fallback: "arrow.triangle.2.circlepath",
                            label: "Remixer",
                            tint: .white
                        ) {}

                        // Audio Album Art Square (`36x36 pt`)
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.black)
                                .frame(width: 36, height: 36)
                            YTCachedAsyncImage(url: short.thumbnailURL) {
                                Color.gray
                            }
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.white, lineWidth: 1.5)
                        )
                    }
                    .padding(.trailing, 14)
                    .padding(.bottom, 18)
                }
            }
        }
    }

    private func shortsActionButton(
        asset: String,
        fallback: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                YTIcon(asset, fallback: fallback, size: 28)
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shorts Comments Sheet
private struct YTShortsCommentsSheet: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss
    let short: YTVideo
    @State private var commentInput = ""

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            HStack {
                Text("Commentaires")
                    .font(YTFontManager.youtubeSans(size: 20, weight: .bold))
                Text("\(appVM.currentComments.count)")
                    .font(.system(size: 15))
                    .foregroundStyle(YTTheme.textSecondary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    YTIcon("yt_outline_x_24pt", fallback: "xmark", size: 22)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                if appVM.currentComments.isEmpty {
                    Text("Aucun commentaire pour le moment.")
                        .font(.system(size: 14))
                        .foregroundStyle(YTTheme.textSecondary)
                        .padding(32)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(appVM.currentComments) { comment in
                            YTCommentRowView(comment: comment)
                        }
                    }
                    .padding(16)
                }
            }

            Divider()

            HStack(spacing: 12) {
                YTUserAvatarBadge(letter: "S", size: 28)
                TextField("Ajouter un commentaire...", text: $commentInput)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 4).fill(YTTheme.backgroundSecondary))
                    .onSubmit {
                        appVM.addComment(commentInput)
                        commentInput = ""
                    }
            }
            .padding(12)
        }
        .background(YTTheme.backgroundPrimary)
    }
}
