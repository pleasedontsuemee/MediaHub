import SwiftUI

// MARK: - 1. Below-Player Engagement Panel Container (`YTEngagementPanelContainerView`)
public struct YTEngagementPanelDrawerView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    public let video: YTVideo

    @State private var commentInput: String = ""
    @State private var liveChatInput: String = ""

    public init(video: YTVideo) {
        self.video = video
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Drag Handle (`36x4 pt`)
            Capsule()
                .fill(Color.secondary.opacity(0.32))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 6)

            switch appVM.activeEngagementPanel {
            case .comments:
                commentsPanelContent
            case .liveChat:
                liveChatPanelContent
            case .description:
                descriptionPanelContent
            case .none:
                EmptyView()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(YTTheme.backgroundPrimary)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: -4)
        )
    }

    // MARK: - A. Comments Panel (`Watching #10`)
    private var commentsPanelContent: some View {
        VStack(spacing: 0) {
            // Header: `Comments 1.6K` on left, Sort sliders + `✕` on right
            HStack(spacing: 8) {
                Text("Comments")
                    .font(YTFontManager.youtubeSans(size: 20, weight: .bold))
                    .foregroundStyle(YTTheme.textPrimary)

                Text(video.commentCountText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(YTTheme.textSecondary)

                Spacer()

                Menu {
                    Button("Top comments") {}
                    Button("Newest first") {}
                } label: {
                    YTIcon("yt_outline_menu_filter_24pt", fallback: "slider.horizontal.3", size: 22)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .padding(.trailing, 8)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        appVM.activeEngagementPanel = .none
                    }
                } label: {
                    YTIcon("yt_outline_x_24pt", fallback: "xmark", size: 22)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Rectangle().fill(YTTheme.separator).frame(height: 0.5)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(appVM.currentComments) { comment in
                        YTCommentRowView(comment: comment)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                        Rectangle().fill(YTTheme.separator).frame(height: 0.5)
                    }
                }
            }

            Rectangle().fill(YTTheme.separator).frame(height: 0.5)

            // Bottom Comment Input Bar (`Avatar S` + `"Add a comment..."` on `#F2F2F2`)
            HStack(spacing: 12) {
                YTUserAvatarBadge(letter: "S", size: 28, backgroundHex: "#00695C")

                TextField("Add a comment...", text: $commentInput)
                    .font(.system(size: 14, weight: .regular))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(YTTheme.backgroundSecondary)
                    )
                    .submitLabel(.send)
                    .onSubmit {
                        appVM.addComment(commentInput)
                        commentInput = ""
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(YTTheme.backgroundPrimary)
        }
    }

    // MARK: - B. Live Chat / Live Chat Replay Panel (`GeneralBrowsing #24` & `Watching #14`)
    private var liveChatPanelContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.isLive ? "Live chat" : "Live chat replay")
                        .font(YTFontManager.youtubeSans(size: 20, weight: .bold))
                        .foregroundStyle(YTTheme.textPrimary)

                    HStack(spacing: 6) {
                        Text(video.isLive ? "Top chat" : "Top chat replay")
                            .font(.system(size: 13))
                            .foregroundStyle(YTTheme.textSecondary)

                        if video.isLive {
                            Image(systemName: "person.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(YTTheme.textPrimary)
                            Text("44K")
                                .font(.system(size: 13))
                                .foregroundStyle(YTTheme.textSecondary)
                        }
                    }
                }

                Spacer()

                if video.isLive {
                    Button {
                        appVM.showToast("Clip editor opened")
                    } label: {
                        YTIcon("yt_outline_scissors_24pt", fallback: "scissors", size: 22)
                            .foregroundStyle(YTTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }

                YTIcon("yt_outline_menu_filter_24pt", fallback: "slider.horizontal.3", size: 22)
                    .foregroundStyle(YTTheme.textPrimary)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        appVM.activeEngagementPanel = .none
                    }
                } label: {
                    YTIcon("yt_outline_x_24pt", fallback: "xmark", size: 22)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Rectangle().fill(YTTheme.separator).frame(height: 0.5)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(appVM.liveChatMessages) { msg in
                        HStack(alignment: .top, spacing: 10) {
                            YTUserAvatarBadge(
                                letter: String(msg.authorName.prefix(1)).uppercased(),
                                size: 24,
                                backgroundHex: msg.authorAvatarColorHex
                            )

                            (
                                Text(msg.authorName + "  ")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(YTTheme.textSecondary)
                                +
                                Text(msg.message)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(YTTheme.textPrimary)
                            )
                            .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)
                        }
                    }

                    // Community Guidelines Welcome Card (`GeneralBrowsing #24`)
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.red)
                                .frame(width: 28, height: 20)
                            TrianglePlayShape()
                                .fill(Color.white)
                                .frame(width: 8, height: 9)
                        }
                        .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Welcome to live chat! Remember to guard your privacy and abide by our community guidelines.")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(YTTheme.textPrimary)

                            Button {
                                appVM.isHelpPresented = true
                            } label: {
                                Text("LEARN MORE")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(YTTheme.callToActionBlue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(YTTheme.backgroundPrimary)
                            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)
                    )
                }
                .padding(16)
            }

            Rectangle().fill(YTTheme.separator).frame(height: 0.5)

            // Bottom Chat Input Bar (`Avatar S` + `"Chat publicly as Demo User... (slow..."` + `$` Super Chat icon)
            HStack(spacing: 12) {
                YTUserAvatarBadge(letter: "S", size: 32, backgroundHex: "#5C4033")

                TextField("Chat publicly as \(appVM.userDisplayName)...", text: $liveChatInput)
                    .font(.system(size: 14))
                    .foregroundStyle(YTTheme.textPrimary)
                    .submitLabel(.send)
                    .onSubmit {
                        appVM.addLiveChatMessage(liveChatInput)
                        liveChatInput = ""
                    }

                Button {
                    appVM.showToast("Super Chat & Super Stickers")
                } label: {
                    YTIcon("yt_outline_super_chat_24pt", fallback: "dollarsign.square", size: 24)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - C. Video Description Panel
    private var descriptionPanelContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Description")
                    .font(YTFontManager.youtubeSans(size: 20, weight: .bold))
                    .foregroundStyle(YTTheme.textPrimary)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        appVM.activeEngagementPanel = .none
                    }
                } label: {
                    YTIcon("yt_outline_x_24pt", fallback: "xmark", size: 22)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Rectangle().fill(YTTheme.separator).frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(video.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(YTTheme.textPrimary)

                    HStack(spacing: 10) {
                        YTChannelAvatarView(url: video.channelAvatarURL, title: video.channelTitle, size: 28)
                        Text(video.channelTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(YTTheme.textPrimary)
                    }

                    // 3-Factoid Counters (Likes, Views, Date)
                    HStack(spacing: 0) {
                        factoidBox(value: video.likeCountText, label: "Likes")
                        factoidBox(value: video.viewCountText.replacingOccurrences(of: " views", with: ""), label: "Views")
                        factoidBox(value: video.publishedTimeText, label: "Published")
                    }
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(YTTheme.backgroundSecondary))

                    Text(video.descriptionText.isEmpty ? "Official video uploaded by \(video.channelTitle)." : video.descriptionText)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(YTTheme.textPrimary)

                    if !video.hashtags.isEmpty {
                        Text(video.hashtags.joined(separator: " "))
                            .font(.system(size: 14))
                            .foregroundStyle(YTTheme.callToActionBlue)
                    }
                }
                .padding(16)
            }
        }
    }

    private func factoidBox(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(YTFontManager.youtubeSans(size: 18, weight: .bold))
                .foregroundStyle(YTTheme.textPrimary)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(YTTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 2. Single Comment Row (`Watching #10` - Supports Clickable Timestamp Pills `0:00`, `3:38` & Creator Heart)
public struct YTCommentRowView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    public let comment: YTComment
    @State private var isLikedLocal: Bool = false

    public init(comment: YTComment) {
        self.comment = comment
        _isLikedLocal = State(initialValue: comment.isLiked)
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            YTChannelAvatarView(url: comment.authorAvatarURL, title: comment.authorName, size: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("\(comment.authorHandle) · \(comment.publishedTimeText)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(YTTheme.textSecondary)

                    if comment.isVerified {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(YTTheme.textSecondary)
                    }

                    Spacer()

                    YTIcon("yt_outline_overflow_vertical_24pt", fallback: "ellipsis", size: 16)
                        .foregroundStyle(YTTheme.textPrimary)
                }

                // Comment body with interactive blue timestamp pills (`0:00`, `3:38` in `Watching #10`)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(comment.text.components(separatedBy: "\n"), id: \.self) { line in
                        if line.hasPrefix("0:00") || line.hasPrefix("3:38") || line.hasPrefix("0:08") {
                            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
                            let ts = parts.first ?? "0:00"
                            let rest = parts.count > 1 ? parts[1] : ""
                            HStack(spacing: 6) {
                                Button {
                                    let sec = YTInnerTubeEngine.parseDurationSeconds(ts)
                                    appVM.seek(to: sec)
                                } label: {
                                    Text(ts)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(YTTheme.callToActionBlue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(YTTheme.color(hex: "#DEF1FF"))
                                        )
                                }
                                .buttonStyle(.plain)

                                Text(rest)
                                    .font(.system(size: 14))
                                    .foregroundStyle(YTTheme.textPrimary)
                            }
                        } else {
                            Text(line)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(YTTheme.textPrimary)
                        }
                    }
                }

                // Comment Actions Row: Thumbs up + count, Thumbs down, Reply icon, Creator Heart
                HStack(spacing: 18) {
                    Button {
                        isLikedLocal.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            YTIcon(isLikedLocal ? "yt_fill_thumb_up_24pt" : "yt_outline_thumb_up_24pt", fallback: "hand.thumbsup", size: 16)
                            Text(comment.likeCountText)
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(YTTheme.textPrimary)
                    }
                    .buttonStyle(.plain)

                    YTIcon("yt_outline_thumb_down_24pt", fallback: "hand.thumbsdown", size: 16)
                        .foregroundStyle(YTTheme.textPrimary)

                    YTIcon("yt_outline_message_bubble_right_24pt", fallback: "text.bubble", size: 16)
                        .foregroundStyle(YTTheme.textPrimary)

                    if comment.isHeartedByCreator {
                        ZStack(alignment: .bottomTrailing) {
                            Circle()
                                .fill(YTTheme.subscribeRed)
                                .frame(width: 18, height: 18)
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(YTTheme.subscribeRed)
                                .offset(x: 4, y: 3)
                        }
                    }
                }
                .padding(.top, 4)

                // Replies Button (`18 REPLIES` / `• 39 REPLIES` in `Watching #10`)
                if comment.replyCount > 0 {
                    Button {
                        appVM.showToast("Showing \(comment.replyCount) replies")
                    } label: {
                        HStack(spacing: 8) {
                            if comment.replyCount > 25 {
                                Circle()
                                    .fill(YTTheme.subscribeRed)
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Text("the\ncurrent")
                                            .font(.system(size: 4, weight: .bold))
                                            .foregroundStyle(.white)
                                    )
                                Text("• \(comment.replyCount) REPLIES")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(YTTheme.callToActionBlue)
                            } else {
                                Text("\(comment.replyCount) REPLIES")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(YTTheme.callToActionBlue)
                            }
                        }
                        .padding(.top, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 3. Player Options Bottom Sheet (`GeneralBrowsing #32` & `Watching #11`)
public struct YTPlayerSettingsBottomSheet: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                // 1. Quality
                optionRow(
                    asset: "yt_outline_gear_24pt",
                    fallback: "gearshape",
                    title: "Quality",
                    value: appVM.selectedQuality
                ) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        appVM.isQualityPickerSheetPresented = true
                    }
                }

                // 2. Captions
                optionRow(
                    asset: "yt_outline_closed_caption_24pt",
                    fallback: "captions.bubble",
                    title: "Captions",
                    value: appVM.selectedCaptionLanguage
                ) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        appVM.isCaptionsPickerSheetPresented = true
                    }
                }

                // 3. Loop video
                optionRow(
                    asset: "yt_outline_arrow_repeat_1_24pt",
                    fallback: "repeat.1",
                    title: "Loop video",
                    value: appVM.isLoopVideoEnabled ? "On" : "Off"
                ) {
                    appVM.isLoopVideoEnabled.toggle()
                    dismiss()
                    appVM.showToast(appVM.isLoopVideoEnabled ? "Video loop is on" : "Video loop is off")
                }

                // 4. Report
                optionRow(
                    asset: "yt_outline_flag_24pt",
                    fallback: "flag",
                    title: "Report",
                    value: nil
                ) {
                    dismiss()
                    appVM.showToast("Report submitted")
                }

                // 5. Help & feedback
                optionRow(
                    asset: "yt_outline_question_circle_24pt",
                    fallback: "questionmark.circle",
                    title: "Help & feedback",
                    value: nil
                ) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        appVM.isHelpPresented = true
                    }
                }

                // 6. Playback speed
                optionRow(
                    asset: "yt_outline_clock_24pt",
                    fallback: "speedometer",
                    title: "Playback speed",
                    value: appVM.playbackSpeed == 1.0 ? "Normal" : "\(appVM.playbackSpeed)x"
                ) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        appVM.isSpeedPickerSheetPresented = true
                    }
                }

                // 7. Listening controls
                optionRow(
                    asset: "yt_outline_menu_filter_24pt",
                    fallback: "slider.horizontal.3",
                    title: "Listening controls",
                    value: nil
                ) {
                    dismiss()
                    appVM.showToast("Listening controls active")
                }
            }

            Rectangle().fill(YTTheme.separator).frame(height: 0.5)

            // Cancel Row (`✕ Cancel`)
            Button {
                dismiss()
            } label: {
                HStack(spacing: 22) {
                    YTIcon("yt_outline_x_24pt", fallback: "xmark", size: 24)
                        .foregroundStyle(YTTheme.textPrimary)
                    Text("Cancel")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(YTTheme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .frame(height: 52)
            }
            .buttonStyle(.plain)
        }
        .background(YTTheme.backgroundPrimary)
    }

    private func optionRow(
        asset: String,
        fallback: String,
        title: String,
        value: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 22) {
                YTIcon(asset, fallback: fallback, size: 24)
                    .foregroundStyle(YTTheme.textPrimary)

                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(YTTheme.textPrimary)

                    if let val = value {
                        Text("· \(val)")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(YTTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 4. Captions Picker Sheet (Dynamically Lists Real Caption Tracks from the Video!)
public struct YTCaptionsSelectionBottomSheet: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss

    public init() {}

    private var trackOptions: [String] {
        var opts = ["Off"]
        for t in appVM.availableCaptionTracks {
            if !opts.contains(t.name) {
                opts.append(t.name)
            }
        }
        return opts
    }

    public var body: some View {
        VStack(spacing: 0) {
            if appVM.availableCaptionTracks.isEmpty {
                HStack {
                    Text("Aucune piste de sous-titres disponible pour cette vidéo")
                        .font(.system(size: 14))
                        .foregroundStyle(YTTheme.textSecondary)
                    Spacer()
                }
                .padding(18)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(trackOptions, id: \.self) { opt in
                        Button {
                            appVM.selectCaptionTrack(opt)
                            dismiss()
                        } label: {
                            HStack(spacing: 22) {
                                if appVM.selectedCaptionLanguage == opt {
                                    YTIcon("yt_outline_check_24pt", fallback: "checkmark", size: 22)
                                        .foregroundStyle(YTTheme.textPrimary)
                                } else {
                                    Color.clear.frame(width: 22, height: 22)
                                }

                                Text(opt)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(YTTheme.textPrimary)

                                Spacer()
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 48)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Rectangle().fill(YTTheme.separator).frame(height: 0.5)

            Button {
                dismiss()
            } label: {
                HStack(spacing: 22) {
                    YTIcon("yt_outline_x_24pt", fallback: "xmark", size: 22)
                        .foregroundStyle(YTTheme.textPrimary)
                    Text("Cancel")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(YTTheme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .frame(height: 52)
            }
            .buttonStyle(.plain)
        }
        .background(YTTheme.backgroundPrimary)
    }
}

// MARK: - 5. Quality Picker Sheet (Scrollable list supporting 144p, 240p, 360p, 480p, 720p, 1080p, 1440p QHD, 2160p 4K & 2:1 / 21:9 resolutions)
public struct YTQualitySelectionBottomSheet: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.32))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            HStack {
                Text("Qualité de la vidéo · \(appVM.activeResolutionDimensionsText.isEmpty ? appVM.selectedQuality : appVM.activeResolutionDimensionsText)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(YTTheme.textSecondary)
                Spacer()
            }
            .padding(16)

            Rectangle().fill(YTTheme.separator).frame(height: 0.5)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    ForEach(appVM.availableQualities, id: \.self) { q in
                        Button {
                            appVM.changeQuality(q)
                            dismiss()
                        } label: {
                            HStack(spacing: 20) {
                                if appVM.selectedQuality == q {
                                    YTIcon("yt_outline_check_24pt", fallback: "checkmark", size: 22)
                                        .foregroundStyle(YTTheme.callToActionBlue)
                                } else {
                                    Color.clear.frame(width: 22, height: 22)
                                }
                                Text(q)
                                    .font(.system(size: 16, weight: appVM.selectedQuality == q ? .semibold : .regular))
                                    .foregroundStyle(YTTheme.textPrimary)
                                Spacer()
                                if q.contains("4K") || q.contains("2160") {
                                    Text("4K")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(RoundedRectangle(cornerRadius: 3).fill(YTTheme.subscribeRed))
                                } else if q.contains("1440") || q.contains("QHD") {
                                    Text("QHD")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(RoundedRectangle(cornerRadius: 3).fill(YTTheme.callToActionBlue))
                                } else if q.contains("1080") {
                                    Text("HD")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(YTTheme.textSecondary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(YTTheme.separator, lineWidth: 1))
                                }
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 48)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(YTTheme.backgroundPrimary)
    }
}

// MARK: - 6. Playback Speed Picker Sheet
public struct YTSpeedSelectionBottomSheet: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss

    private let speeds: [(Float, String)] = [
        (0.25, "0.25x"),
        (0.5, "0.5x"),
        (0.75, "0.75x"),
        (1.0, "Normal"),
        (1.25, "1.25x"),
        (1.5, "1.5x"),
        (2.0, "2x")
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(speeds, id: \.0) { speed, label in
                Button {
                    appVM.changePlaybackSpeed(speed)
                    dismiss()
                } label: {
                    HStack(spacing: 22) {
                        if abs(appVM.playbackSpeed - speed) < 0.01 {
                            YTIcon("yt_outline_check_24pt", fallback: "checkmark", size: 22)
                                .foregroundStyle(YTTheme.textPrimary)
                        } else {
                            Color.clear.frame(width: 22, height: 22)
                        }
                        Text(label)
                            .font(.system(size: 16))
                            .foregroundStyle(YTTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                }
                .buttonStyle(.plain)
            }
        }
        .background(YTTheme.backgroundPrimary)
    }
}
