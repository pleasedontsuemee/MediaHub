import SwiftUI

// MARK: - 1. Create Bottom Sheet (`GeneralBrowsing #23`)
public struct YTCreateBottomSheetView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (`Create` + `✕`)
            HStack {
                Text("Create")
                    .font(YTFontManager.youtubeSans(size: 20, weight: .bold))
                    .foregroundStyle(YTTheme.textPrimary)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    YTIcon("yt_outline_x_24pt", fallback: "xmark", size: 22)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            // 5 Action Rows (`Create a Short`, `Upload a video`, `Go live`, `Go Live Together [New]`, `Create a post`)
            VStack(spacing: 6) {
                createRow(
                    asset: "yt_outline_youtube_shorts_24pt",
                    fallback: "bolt",
                    title: "Create a Short",
                    badgeText: nil
                ) {
                    dismiss()
                    appVM.showToast("Shorts camera opened")
                }

                createRow(
                    asset: "yt_outline_upload_24pt",
                    fallback: "arrow.up.to.line",
                    title: "Upload a video",
                    badgeText: nil
                ) {
                    dismiss()
                    appVM.showToast("Photo library picker opened")
                }

                createRow(
                    asset: "yt_outline_radar_live_24pt",
                    fallback: "dot.radiowaves.left.and.right",
                    title: "Go live",
                    badgeText: nil
                ) {
                    dismiss()
                    appVM.showToast("Live streaming setup opened")
                }

                createRow(
                    asset: "yt_outline_person_box_24pt",
                    fallback: "person.2.square.stack",
                    title: "Go Live Together",
                    badgeText: "New"
                ) {
                    dismiss()
                    appVM.showToast("Go Live Together co-stream setup opened")
                }

                createRow(
                    asset: "yt_outline_pencil_24pt",
                    fallback: "square.and.pencil",
                    title: "Create a post",
                    badgeText: nil
                ) {
                    dismiss()
                    appVM.showToast("Community post composer opened")
                }
            }
            .padding(.bottom, 20)
        }
        .background(YTTheme.backgroundPrimary)
    }

    private func createRow(
        asset: String,
        fallback: String,
        title: String,
        badgeText: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(YTTheme.backgroundSecondary)
                        .frame(width: 48, height: 48)
                    YTIcon(asset, fallback: fallback, size: 24)
                        .foregroundStyle(YTTheme.textPrimary)
                }

                Text(title)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(YTTheme.textPrimary)

                Spacer()

                if let badge = badgeText {
                    Text(badge)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(YTTheme.callToActionBlue)
                        )
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 2. Save Video to Playlist Modal Card (`GeneralBrowsing #05`)
public struct YTSaveToPlaylistModalView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCreatePlaylistAlert = false
    @State private var newPlaylistName = ""

    public init() {}

    public var body: some View {
        let video = appVM.videoToSave ?? YTCatalogData.videoJennaOrtegaCosplayer

        VStack(spacing: 0) {
            // Top Handle (`36x4 pt`)
            Capsule()
                .fill(Color.secondary.opacity(0.32))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 12)

            // Header (`Save video to...` + `+ NEW PLAYLIST` in blue `#065FD4`)
            HStack {
                Text("Save video to...")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(YTTheme.textPrimary)

                Spacer()

                Button {
                    newPlaylistName = ""
                    showCreatePlaylistAlert = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                        Text("NEW PLAYLIST")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(YTTheme.callToActionBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            Rectangle().fill(YTTheme.separator).frame(height: 0.5)

            // Playlist Checkboxes (`Watch later`, `Interesting` + Lock icon on right)
            VStack(spacing: 0) {
                ForEach(appVM.playlists) { playlist in
                    let isChecked = appVM.isVideo(video.id, inPlaylist: playlist.id)

                    Button {
                        appVM.toggleVideo(video, inPlaylist: playlist.id)
                    } label: {
                        HStack(spacing: 20) {
                            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                .font(.system(size: 20))
                                .foregroundStyle(isChecked ? YTTheme.callToActionBlue : YTTheme.textSecondary)

                            Text(playlist.title)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(YTTheme.textPrimary)

                            Spacer()

                            Image(systemName: playlist.isPrivate ? "lock.fill" : "globe")
                                .font(.system(size: 16))
                                .foregroundStyle(YTTheme.textPrimary)
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)

            Rectangle().fill(YTTheme.separator).frame(height: 0.5)

            // Footer (`✓ Done`)
            Button {
                dismiss()
            } label: {
                HStack(spacing: 20) {
                    YTIcon("yt_outline_check_24pt", fallback: "checkmark", size: 20)
                        .foregroundStyle(YTTheme.textPrimary)
                    Text("Done")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(YTTheme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .frame(height: 50)
            }
            .buttonStyle(.plain)
        }
        .background(YTTheme.backgroundPrimary)
        .alert("New playlist", isPresented: $showCreatePlaylistAlert) {
            TextField("Title", text: $newPlaylistName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                appVM.createPlaylist(title: newPlaylistName)
            }
        }
    }
}

// MARK: - 3. Account Menu Modal (`GeneralBrowsing #26, #28, #29`)
public struct YTAccountMenuSheetView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showUserChannelSheet = false
    @State private var showTimeWatchedSheet = false

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Close Button (`✕`)
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        YTIcon("yt_outline_x_24pt", fallback: "xmark", size: 22)
                            .foregroundStyle(YTTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 48)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        // User Profile Header (`S` Avatar `44pt`, `Demo User`, `@demouser`, `>`, `Manage your Google Account`)
                        HStack(alignment: .top, spacing: 16) {
                            YTUserAvatarBadge(letter: "S", size: 42, backgroundHex: "#5C4033")

                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Demo User")
                                            .font(.system(size: 16, weight: .regular))
                                            .foregroundStyle(YTTheme.textPrimary)
                                        Text("@demouser")
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundStyle(YTTheme.textPrimary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 15))
                                        .foregroundStyle(YTTheme.textPrimary)
                                }

                                Button {
                                    appVM.showToast("Google Account settings")
                                } label: {
                                    Text("Manage your Google Account")
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundStyle(YTTheme.callToActionBlue)
                                        .padding(.top, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)

                        Rectangle().fill(YTTheme.separator).frame(height: 0.5)

                        // Group 1: `Your channel`, `Turn on Incognito`, `Add account`
                        VStack(spacing: 0) {
                            accountRow(asset: "yt_outline_person_box_24pt", fallback: "person.crop.square", title: "Your channel") {
                                showUserChannelSheet = true
                            }
                            accountRow(
                                asset: "yt_outline_incognito_24pt",
                                fallback: "eyeglasses",
                                title: appVM.isIncognito ? "Turn off Incognito" : "Turn on Incognito"
                            ) {
                                appVM.isIncognito.toggle()
                                dismiss()
                                appVM.showToast(appVM.isIncognito ? "You're Incognito" : "Incognito turned off")
                            }
                            accountRow(asset: "yt_outline_person_add_24pt", fallback: "person.badge.plus", title: "Add account") {
                                appVM.showToast("Add Google Account")
                            }
                        }
                        .padding(.vertical, 6)

                        Rectangle().fill(YTTheme.separator).frame(height: 0.5)

                        // Group 2: `Your Premium benefits`, `Purchases and memberships`, `Time watched`, `Your data in YouTube`
                        VStack(spacing: 0) {
                            Button {
                                appVM.isPremiumHeader.toggle()
                                appVM.showToast(appVM.isPremiumHeader ? "YouTube Premium header active" : "Standard YouTube header active")
                            } label: {
                                HStack(spacing: 20) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(YTTheme.subscribeRed)
                                            .frame(width: 22, height: 22)
                                        Text("P")
                                            .font(YTFontManager.youtubeSans(size: 14, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                    .frame(width: 24, height: 24)

                                    Text("Your Premium benefits")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundStyle(YTTheme.textPrimary)

                                    Spacer()
                                }
                                .padding(.horizontal, 18)
                                .frame(height: 48)
                            }
                            .buttonStyle(.plain)

                            accountRow(asset: "yt_outline_dollar_sign_circle_24pt", fallback: "dollarsign.circle", title: "Purchases and memberships") {
                                appVM.showToast("No active purchases")
                            }

                            accountRow(asset: "yt_outline_bar_graph_box_vertical_24pt", fallback: "chart.bar.xaxis", title: "Time watched") {
                                showTimeWatchedSheet = true
                            }

                            accountRow(asset: "yt_outline_person_shield_24pt", fallback: "checkmark.shield", title: "Your data in YouTube") {
                                appVM.showToast("Your data in YouTube")
                            }
                        }
                        .padding(.vertical, 6)

                        Rectangle().fill(YTTheme.separator).frame(height: 0.5)

                        // Group 3: `Settings`, `Help & feedback`
                        VStack(spacing: 0) {
                            accountRow(asset: "yt_outline_gear_24pt", fallback: "gearshape", title: "Settings") {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    appVM.isSettingsPresented = true
                                }
                            }

                            accountRow(asset: "yt_outline_question_circle_24pt", fallback: "questionmark.circle", title: "Help & feedback") {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    appVM.isHelpPresented = true
                                }
                            }
                        }
                        .padding(.vertical, 6)

                        Rectangle().fill(YTTheme.separator).frame(height: 0.5)

                        // Group 4: `YouTube Studio`, `YouTube Music` (with official red icons)
                        VStack(spacing: 0) {
                            accountRow(
                                asset: "yt_studio_color_logo",
                                fallback: "play.square.fill",
                                title: "YouTube Studio",
                                renderOriginal: true
                            ) {
                                appVM.showToast("Opening YouTube Studio...")
                            }

                            accountRow(
                                asset: "yt_music_color_logo",
                                fallback: "play.circle.fill",
                                title: "YouTube Music",
                                renderOriginal: true
                            ) {
                                appVM.showToast("Opening YouTube Music...")
                            }
                        }
                        .padding(.vertical, 6)

                        // Footer (`Privacy Policy · Terms of Service`)
                        HStack {
                            Spacer()
                            Text("Privacy Policy  ·  Terms of Service")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(YTTheme.textSecondary)
                            Spacer()
                        }
                        .padding(.vertical, 18)
                    }
                }
            }
            .background(YTTheme.backgroundPrimary)
            .navigationDestination(isPresented: $showUserChannelSheet) {
                YTUserPersonalChannelView()
            }
            .navigationDestination(isPresented: $showTimeWatchedSheet) {
                YTTimeWatchedView()
            }
        }
    }

    private func accountRow(
        asset: String,
        fallback: String,
        title: String,
        renderOriginal: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 20) {
                YTIcon(asset, fallback: fallback, size: 24, renderOriginal: renderOriginal)
                    .foregroundStyle(renderOriginal ? YTTheme.subscribeRed : YTTheme.textPrimary)

                Text(title)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(YTTheme.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 4. Time Watched Screen + Reminder Frequency Modal (`GeneralBrowsing #19 & #31`)
public struct YTTimeWatchedView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showReminderPickerModal = false

    private let days = ["Wed", "Thu", "Fri", "Sat", "Sun", "Mon", "Today"]

    public init() {}

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                YTTopHeaderBarView(showBackButton: true, customTitle: "Time watched") {
                    dismiss()
                }

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("1 min daily average")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(YTTheme.textPrimary)
                            .padding(.top, 12)

                        // 7-Day Bar Chart (`Wed` ... `Today` with `#065FD4` bar for `Today` at `4 min`)
                        VStack(spacing: 6) {
                            ForEach([15, 10, 5, 0], id: \.self) { yVal in
                                HStack(spacing: 8) {
                                    ZStack(alignment: .bottom) {
                                        Rectangle()
                                            .fill(YTTheme.separator)
                                            .frame(height: 1)

                                        if yVal == 0 {
                                            HStack(alignment: .bottom, spacing: 0) {
                                                ForEach(days, id: \.self) { d in
                                                    VStack {
                                                        if d == "Today" {
                                                            RoundedRectangle(cornerRadius: 2)
                                                                .fill(YTTheme.callToActionBlue)
                                                                .frame(width: 36, height: 42)
                                                        } else {
                                                            Color.clear.frame(width: 36, height: 1)
                                                        }
                                                    }
                                                    .frame(maxWidth: .infinity)
                                                }
                                            }
                                        }
                                    }
                                    .frame(height: 36, alignment: .bottom)

                                    Text(yVal == 0 ? "0" : "\(yVal) min")
                                        .font(.system(size: 12))
                                        .foregroundStyle(YTTheme.textSecondary)
                                        .frame(width: 44, alignment: .leading)
                                }
                            }

                            HStack(spacing: 0) {
                                ForEach(days, id: \.self) { d in
                                    Text(d)
                                        .font(.system(size: 12))
                                        .foregroundStyle(YTTheme.textSecondary)
                                        .frame(maxWidth: .infinity)
                                }
                                Spacer().frame(width: 52)
                            }
                        }

                        // Today & Last 7 days rows
                        HStack {
                            Text("Today").font(.system(size: 16)).foregroundStyle(YTTheme.textPrimary)
                            Spacer()
                            Text("4 min").font(.system(size: 16)).foregroundStyle(YTTheme.textSecondary)
                        }
                        .padding(.top, 6)

                        HStack {
                            Text("Last 7 days").font(.system(size: 16)).foregroundStyle(YTTheme.textPrimary)
                            Spacer()
                            Text("4 min").font(.system(size: 16)).foregroundStyle(YTTheme.textSecondary)
                        }

                        Text("Stats are based on your watch history across YouTube products (except YouTube Music and YouTube TV).")
                            .font(.system(size: 13))
                            .foregroundStyle(YTTheme.textSecondary)

                        Button {
                            appVM.isHelpPresented = true
                        } label: {
                            Text("LEARN MORE")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(YTTheme.callToActionBlue)
                        }
                        .buttonStyle(.plain)

                        Rectangle().fill(YTTheme.separator).frame(height: 0.5).padding(.vertical, 4)

                        Text("Tools to manage your YouTube time")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(YTTheme.textSecondary)

                        // Remind me to take a break (opens `Reminder frequency` modal in `GeneralBrowsing #19`)
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Remind me to take a break")
                                    .font(.system(size: 16))
                                    .foregroundStyle(YTTheme.textPrimary)
                                Text(appVM.breakReminderEnabled ? "Every \(appVM.breakReminderHours) hr \(appVM.breakReminderMinutes) min" : "Off")
                                    .font(.system(size: 13))
                                    .foregroundStyle(YTTheme.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { appVM.breakReminderEnabled },
                                set: { newVal in
                                    appVM.breakReminderEnabled = newVal
                                    if newVal {
                                        showReminderPickerModal = true
                                    }
                                }
                            ))
                            .labelsHidden()
                            .tint(YTTheme.callToActionBlue)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showReminderPickerModal = true
                        }

                        // Remind me when it's bedtime
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Remind me when it’s bedtime")
                                    .font(.system(size: 16))
                                    .foregroundStyle(YTTheme.textPrimary)
                                Text(appVM.bedtimeReminderEnabled ? "11:00 PM - 7:00 AM" : "Off")
                                    .font(.system(size: 13))
                                    .foregroundStyle(YTTheme.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $appVM.bedtimeReminderEnabled)
                                .labelsHidden()
                                .tint(YTTheme.callToActionBlue)
                        }

                        // Autoplay on mobile/tablet
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Autoplay on mobile/tablet")
                                    .font(.system(size: 16))
                                    .foregroundStyle(YTTheme.textPrimary)
                                Text("When autoplay is enabled, a suggested video will automatically play next.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(YTTheme.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $appVM.isAutoplayEnabled)
                                .labelsHidden()
                                .tint(YTTheme.callToActionBlue)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }

            // Centered `Reminder frequency` Picker Modal (`GeneralBrowsing #19`)
            if showReminderPickerModal {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showReminderPickerModal = false
                    }

                VStack(alignment: .leading, spacing: 18) {
                    Text("Reminder frequency")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(YTTheme.textPrimary)
                        .padding(.top, 6)

                    HStack(spacing: 0) {
                        Picker("Hours", selection: $appVM.breakReminderHours) {
                            ForEach(0..<12, id: \.self) { h in
                                Text("\(h) hr").tag(h)
                            }
                        }
                        #if os(iOS)
                        .pickerStyle(.wheel)
                        #endif
                        .frame(maxWidth: .infinity)

                        Picker("Minutes", selection: $appVM.breakReminderMinutes) {
                            ForEach([0, 5, 10, 15, 20, 30, 45], id: \.self) { m in
                                Text("\(m) min").tag(m)
                            }
                        }
                        #if os(iOS)
                        .pickerStyle(.wheel)
                        #endif
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 160)

                    HStack(spacing: 28) {
                        Spacer()
                        Button("CANCEL") {
                            showReminderPickerModal = false
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(YTTheme.callToActionBlue)

                        Button("OK") {
                            appVM.breakReminderEnabled = true
                            showReminderPickerModal = false
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(YTTheme.callToActionBlue)
                    }
                }
                .padding(24)
                .frame(width: 332)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(YTTheme.backgroundPrimary)
                        .shadow(radius: 16)
                )
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - 5. Settings & Dedicated Sub-Menus
public struct YTSettingsModalView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case videoQuality = "Préférences de qualité vidéo"
        case autoplayAndPip = "Lecture, PiP & Apparence"
        case accountProfile = "Compte & Nom affiché"
        case historyPrivacy = "Historique et confidentialité"
        case downloads = "Lecture en arrière-plan & téléchargements"
        case about = "À propos"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .videoQuality: return "sparkles.tv"
            case .autoplayAndPip: return "pip"
            case .accountProfile: return "person.crop.circle"
            case .historyPrivacy: return "clock.arrow.circlepath"
            case .downloads: return "arrow.down.circle"
            case .about: return "info.circle"
            }
        }
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Button {
                        dismiss()
                    } label: {
                        YTIcon("yt_outline_x_24pt", fallback: "xmark", size: 22)
                            .foregroundStyle(YTTheme.textPrimary)
                    }
                    .buttonStyle(.plain)

                    Text("Paramètres")
                        .font(YTFontManager.youtubeSans(size: 20, weight: .bold))
                        .foregroundStyle(YTTheme.textPrimary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(YTTheme.separator).frame(height: 0.5)
                }

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Quick Inline Toggles & Profile Summary
                        VStack(spacing: 0) {
                            Toggle(isOn: $appVM.isPiPEnabled) {
                                HStack(spacing: 12) {
                                    Image(systemName: "pip.enter")
                                        .font(.system(size: 16))
                                        .foregroundStyle(YTTheme.textPrimary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Picture-in-Picture (PiP)")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(YTTheme.textPrimary)
                                        Text("Continuer en mini-fenêtre flottante")
                                            .font(.system(size: 12))
                                            .foregroundStyle(YTTheme.textSecondary)
                                    }
                                }
                            }
                            .tint(YTTheme.callToActionBlue)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)

                            Rectangle().fill(YTTheme.separator).frame(height: 0.5).padding(.leading, 18)
                        }

                        ForEach(SettingsSection.allCases) { section in
                            NavigationLink {
                                destinationView(for: section)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: section.icon)
                                        .font(.system(size: 17))
                                        .foregroundStyle(YTTheme.textPrimary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(section.rawValue)
                                            .font(.system(size: 16, weight: .regular))
                                            .foregroundStyle(YTTheme.textPrimary)
                                        if let subtitle = subtitle(for: section) {
                                            Text(subtitle)
                                                .font(.system(size: 12))
                                                .foregroundStyle(YTTheme.textSecondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13))
                                        .foregroundStyle(YTTheme.textSecondary)
                                }
                                .padding(.horizontal, 18)
                                .frame(height: 58)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        Rectangle().fill(YTTheme.separator).frame(height: 0.5).padding(.vertical, 6)

                        NavigationLink {
                            YTDebugConsoleView()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "ladybug.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(YTTheme.brandRed)
                                Text("Debug (Logs & Diagnostics)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(YTTheme.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(YTTheme.textSecondary)
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 54)
                            .background(YTTheme.backgroundSecondary.opacity(0.6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(YTTheme.backgroundPrimary)
        }
    }

    private func subtitle(for section: SettingsSection) -> String? {
        switch section {
        case .videoQuality:
            return "Wi-Fi : \(appVM.wifiDefaultQuality) · Mobile : \(appVM.cellularDefaultQuality)"
        case .accountProfile:
            return "\(appVM.userDisplayName) (\(appVM.userHandle))"
        case .autoplayAndPip:
            return appVM.isAutoplayEnabled ? "Lecture auto activée" : "Lecture auto désactivée"
        default:
            return nil
        }
    }

    @ViewBuilder
    private func destinationView(for section: SettingsSection) -> some View {
        switch section {
        case .videoQuality:
            YTVideoQualitySettingsView()
        case .autoplayAndPip:
            YTAutoplayAndPiPSettingsView()
        case .accountProfile:
            YTAccountProfileSettingsView()
        case .historyPrivacy:
            YTHistoryPrivacySettingsView()
        case .downloads:
            YTDownloadsSettingsView()
        case .about:
            YTAboutSettingsView()
        }
    }
}

// MARK: - Settings > Préférences de qualité vidéo (Wi-Fi & Données mobiles jusqu'à 4K)
public struct YTVideoQualitySettingsView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss

    private let wifiOptions = ["Auto (recommended)", "2160p (4K)", "1440p (QHD)", "1080p", "720p", "480p", "360p"]
    private let cellularOptions = ["Auto (recommended)", "2160p (4K)", "1440p (QHD)", "1080p", "720p", "480p", "360p", "240p", "144p"]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            settingsHeader(title: "Qualité vidéo", dismiss: dismiss)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 8) {
                        Image(systemName: appVM.isOnWiFi ? "wifi" : "antenna.radiowaves.left.and.right")
                            .foregroundStyle(YTTheme.callToActionBlue)
                        Text("Réseau actuel : \(appVM.isOnWiFi ? "Wi-Fi" : "Données mobiles")")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(YTTheme.textSecondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("EN WI-FI")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(YTTheme.textSecondary)
                            .padding(.horizontal, 18)

                        ForEach(wifiOptions, id: \.self) { opt in
                            qualityRadioRow(title: opt, isSelected: appVM.wifiDefaultQuality == opt) {
                                appVM.wifiDefaultQuality = opt
                            }
                        }
                    }

                    Rectangle().fill(YTTheme.separator).frame(height: 0.5)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("SUR RÉSEAU MOBILE (4G / 5G)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(YTTheme.textSecondary)
                            .padding(.horizontal, 18)

                        ForEach(cellularOptions, id: \.self) { opt in
                            qualityRadioRow(title: opt, isSelected: appVM.cellularDefaultQuality == opt) {
                                appVM.cellularDefaultQuality = opt
                            }
                        }
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func qualityRadioRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(YTTheme.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(YTTheme.callToActionBlue)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings > Lecture, PiP & Apparence
public struct YTAutoplayAndPiPSettingsView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss

    private let themes = ["Use device theme", "Light theme", "Dark theme"]
    private let skipDurations = [5, 10, 15, 20, 30]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            settingsHeader(title: "Lecture, PiP & Apparence", dismiss: dismiss)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Toggle("Lecture automatique de la vidéo suivante", isOn: $appVM.isAutoplayEnabled)
                        .tint(YTTheme.callToActionBlue)
                        .padding(18)
                    Rectangle().fill(YTTheme.separator).frame(height: 0.5)
                    Toggle("Picture-in-Picture (PiP)", isOn: $appVM.isPiPEnabled)
                        .tint(YTTheme.callToActionBlue)
                        .padding(18)
                    Rectangle().fill(YTTheme.separator).frame(height: 0.5)
                    Toggle("Lecture en arrière-plan (audio)", isOn: $appVM.backgroundPlaybackEnabled)
                        .tint(YTTheme.callToActionBlue)
                        .padding(18)
                    Rectangle().fill(YTTheme.separator).frame(height: 0.5)
                    Toggle("Zoom plein écran par défaut (18:9 / 21:9)", isOn: $appVM.zoomToFillScreen)
                        .tint(YTTheme.callToActionBlue)
                        .padding(18)
                    Rectangle().fill(YTTheme.separator).frame(height: 0.5)
                    Toggle("Lire les vidéos en boucle", isOn: $appVM.isLoopVideoEnabled)
                        .tint(YTTheme.callToActionBlue)
                        .padding(18)
                    Rectangle().fill(YTTheme.separator).frame(height: 0.5)
                    Toggle("Statistiques pour les nerds", isOn: $appVM.statsForNerdsEnabled)
                        .tint(YTTheme.callToActionBlue)
                        .padding(18)

                    Rectangle().fill(YTTheme.separator).frame(height: 0.5)

                    HStack {
                        Text("Thème")
                            .foregroundStyle(YTTheme.textPrimary)
                        Spacer()
                        Picker("Thème", selection: $appVM.appearanceMode) {
                            ForEach(themes, id: \.self) { t in
                                Text(t).tag(t)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(18)

                    Rectangle().fill(YTTheme.separator).frame(height: 0.5)

                    HStack {
                        Text("Double-tap avance/retour")
                            .foregroundStyle(YTTheme.textPrimary)
                        Spacer()
                        Picker("Secondes", selection: $appVM.skipSeconds) {
                            ForEach(skipDurations, id: \.self) { s in
                                Text("\(s)s").tag(s)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(18)
                }
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Settings > Compte & Nom affiché
public struct YTAccountProfileSettingsView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            settingsHeader(title: "Compte & Profil", dismiss: dismiss)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOM AFFICHÉ")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(YTTheme.textSecondary)
                        TextField("Votre nom", text: $appVM.userDisplayName)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("IDENTIFIANT (@HANDLE)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(YTTheme.textSecondary)
                        TextField("@identifiant", text: $appVM.userHandle)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(18)
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Settings > Historique et confidentialité
public struct YTHistoryPrivacySettingsView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            settingsHeader(title: "Historique & confidentialité", dismiss: dismiss)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Toggle("Mode navigation privée (Incognito)", isOn: $appVM.isIncognito)
                        .tint(YTTheme.callToActionBlue)
                        .padding(18)
                    Rectangle().fill(YTTheme.separator).frame(height: 0.5)

                    Button {
                        appVM.watchHistory.removeAll()
                        appVM.savePersistedUserState()
                        appVM.showToast("Historique de visionnage effacé")
                    } label: {
                        HStack {
                            Text("Effacer l'historique de visionnage")
                                .foregroundStyle(YTTheme.textPrimary)
                            Spacer()
                            Text("\(appVM.watchHistory.count)")
                                .foregroundStyle(YTTheme.textSecondary)
                        }
                        .padding(18)
                    }
                    .buttonStyle(.plain)

                    Rectangle().fill(YTTheme.separator).frame(height: 0.5)

                    Button {
                        appVM.searchHistory.removeAll()
                        appVM.savePersistedUserState()
                        appVM.showToast("Historique de recherche effacé")
                    } label: {
                        HStack {
                            Text("Effacer l'historique de recherche")
                                .foregroundStyle(YTTheme.textPrimary)
                            Spacer()
                            Text("\(appVM.searchHistory.count)")
                                .foregroundStyle(YTTheme.textSecondary)
                        }
                        .padding(18)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Settings > Téléchargements
public struct YTDownloadsSettingsView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss

    private let options = ["1080p", "720p", "360p"]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            settingsHeader(title: "Téléchargements", dismiss: dismiss)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("QUALITÉ DE TÉLÉCHARGEMENT")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(YTTheme.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.top, 14)

                    ForEach(options, id: \.self) { opt in
                        Button {
                            appVM.offlineDownloadQuality = opt
                        } label: {
                            HStack {
                                Text(opt)
                                    .foregroundStyle(YTTheme.textPrimary)
                                Spacer()
                                if appVM.offlineDownloadQuality == opt {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(YTTheme.callToActionBlue)
                                }
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 46)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Settings > À propos
public struct YTAboutSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            settingsHeader(title: "À propos", dismiss: dismiss)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    infoRow("Application", "YouTube Clone")
                    infoRow("Identifiant", "com.ytmine.app")
                    infoRow("Version", "21.46.3")
                    infoRow("Moteur vidéo", "InnerTube natif + Serveur HLS Localhost")
                    infoRow("Audio par défaut", "Piste originale de la vidéo")
                }
                .padding(18)
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(YTTheme.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(YTTheme.textPrimary)
                .fontWeight(.medium)
        }
    }
}

private func settingsHeader(title: String, dismiss: DismissAction) -> some View {
    HStack(spacing: 16) {
        Button {
            dismiss()
        } label: {
            YTIcon("yt_outline_arrow_left_24pt", fallback: "arrow.left", size: 22)
                .foregroundStyle(YTTheme.textPrimary)
        }
        .buttonStyle(.plain)

        Text(title)
            .font(YTFontManager.youtubeSans(size: 20, weight: .bold))
            .foregroundStyle(YTTheme.textPrimary)

        Spacer()
    }
    .padding(.horizontal, 16)
    .frame(height: 48)
    .overlay(alignment: .bottom) {
        Rectangle().fill(YTTheme.separator).frame(height: 0.5)
    }
}

// MARK: - Settings > General (`GeneralBrowsing #38`)
public struct YTGeneralSettingsView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button {
                    dismiss()
                } label: {
                    YTIcon("yt_outline_arrow_left_24pt", fallback: "arrow.left", size: 22)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)

                Text("General")
                    .font(YTFontManager.youtubeSans(size: 20, weight: .bold))
                    .foregroundStyle(YTTheme.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .overlay(alignment: .bottom) {
                Rectangle().fill(YTTheme.separator).frame(height: 0.5)
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 24) {
                    // 1. Remind me when it's bedtime
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Remind me when it’s bedtime")
                                .font(.system(size: 16))
                                .foregroundStyle(YTTheme.textPrimary)
                            Text(appVM.bedtimeReminderEnabled ? "On" : "Off")
                                .font(.system(size: 14))
                                .foregroundStyle(YTTheme.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $appVM.bedtimeReminderEnabled)
                            .labelsHidden()
                            .tint(YTTheme.callToActionBlue)
                    }

                    // 2. Appearance (Use device theme / Light theme / Dark theme)
                    Menu {
                        ForEach(["Use device theme", "Light theme", "Dark theme"], id: \.self) { mode in
                            Button(mode) {
                                appVM.appearanceMode = mode
                            }
                        }
                    } label: {
                        HStack {
                            Text("Appearance")
                                .font(.system(size: 16))
                                .foregroundStyle(YTTheme.textPrimary)
                            Spacer()
                            Text(appVM.appearanceMode)
                                .font(.system(size: 14))
                                .foregroundStyle(YTTheme.textSecondary)
                        }
                    }

                    // 3. Restricted Mode
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Restricted Mode")
                                .font(.system(size: 16))
                                .foregroundStyle(YTTheme.textPrimary)
                            Spacer()
                            Toggle("", isOn: $appVM.restrictedMode)
                                .labelsHidden()
                                .tint(YTTheme.callToActionBlue)
                        }
                        Text("This helps hide potentially mature videos. No filter is 100% accurate. This setting only applies to this app on this device.")
                            .font(.system(size: 13))
                            .foregroundStyle(YTTheme.textSecondary)
                    }

                    // 4. Picture-in-picture
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Picture-in-picture")
                                .font(.system(size: 16))
                                .foregroundStyle(YTTheme.textPrimary)
                            Spacer()
                            Toggle("", isOn: $appVM.isPiPEnabled)
                                .labelsHidden()
                                .tint(YTTheme.callToActionBlue)
                        }
                        Text("If you exit YouTube, videos continue in a miniplayer on top of other apps. \"Start PiP Automatically\" must also be turned on in device settings.")
                            .font(.system(size: 13))
                            .foregroundStyle(YTTheme.textSecondary)
                    }

                    // 5. Skip forward and back
                    Menu {
                        ForEach([5, 10, 15, 30, 60], id: \.self) { sec in
                            Button("\(sec) seconds") {
                                appVM.skipSeconds = sec
                            }
                        }
                    } label: {
                        HStack {
                            Text("Skip forward and back")
                                .font(.system(size: 16))
                                .foregroundStyle(YTTheme.textPrimary)
                            Spacer()
                            Text("\(appVM.skipSeconds) seconds")
                                .font(.system(size: 14))
                                .foregroundStyle(YTTheme.textSecondary)
                        }
                    }

                    // 6. Zoom to fill screen
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Zoom to fill screen")
                                .font(.system(size: 16))
                                .foregroundStyle(YTTheme.textPrimary)
                            Spacer()
                            Toggle("", isOn: $appVM.zoomToFillScreen)
                                .labelsHidden()
                                .tint(YTTheme.callToActionBlue)
                        }
                        Text("Always zoom so that videos fill the screen in full screen")
                            .font(.system(size: 13))
                            .foregroundStyle(YTTheme.textSecondary)
                    }

                    // 7. Show in-video info cards
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Show in-video info cards")
                                .font(.system(size: 16))
                                .foregroundStyle(YTTheme.textPrimary)
                            Spacer()
                            Toggle("", isOn: $appVM.showInVideoInfoCards)
                                .labelsHidden()
                                .tint(YTTheme.callToActionBlue)
                        }
                        Text("Allows creator info cards to appear on videos. This doesn't affect ads that may appear on videos.")
                            .font(.system(size: 13))
                            .foregroundStyle(YTTheme.textSecondary)
                    }

                    // 8. Watch on TV
                    Button {
                        appVM.isCastAlertPresented = true
                    } label: {
                        Text("Watch on TV")
                            .font(.system(size: 16))
                            .foregroundStyle(YTTheme.textPrimary)
                    }
                    .buttonStyle(.plain)

                    // 9. Location
                    HStack {
                        Text("Location")
                            .font(.system(size: 16))
                            .foregroundStyle(YTTheme.textPrimary)
                        Spacer()
                        Text("United States")
                            .font(.system(size: 14))
                            .foregroundStyle(YTTheme.textSecondary)
                    }

                    // 10. Stats for nerds
                    HStack {
                        Text("Stats for nerds")
                            .font(.system(size: 16))
                            .foregroundStyle(YTTheme.textPrimary)
                        Spacer()
                        Toggle("", isOn: $appVM.statsForNerdsEnabled)
                            .labelsHidden()
                            .tint(YTTheme.callToActionBlue)
                    }
                }
                .padding(18)
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - 6. Help & Help Article Views (`GeneralBrowsing #16 & #17`)
public struct YTHelpModalView: View {
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var helpSearchText = ""

    private let popularArticles = [
        "Change language or location settings",
        "Can't access YouTube with your account",
        "Use music and sound effects from the Audio Library",
        "Delete or hide your YouTube channel",
        "Troubleshoot video errors, buffering, and freezing"
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        YTIcon("yt_outline_x_24pt", fallback: "xmark", size: 22)
                            .foregroundStyle(YTTheme.textPrimary)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                    Text("Help")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(YTTheme.textPrimary)
                    Spacer()
                    Color.clear.frame(width: 22, height: 22)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)

                // Search help input box (`48pt`, rounded border)
                HStack(spacing: 12) {
                    YTIcon("yt_outline_search_24pt", fallback: "magnifyingglass", size: 20)
                        .foregroundStyle(YTTheme.textSecondary)
                    TextField("Search help", text: $helpSearchText)
                        .font(.system(size: 16))
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(YTTheme.separator, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Text("Popular help resources")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(YTTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(popularArticles, id: \.self) { article in
                            NavigationLink {
                                YTHelpArticleDetailView(title: article)
                            } label: {
                                HStack(spacing: 16) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(YTTheme.color(hex: "#1A73E8"))
                                            .frame(width: 22, height: 22)
                                        Image(systemName: "text.alignleft")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                    }

                                    Text(article)
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundStyle(YTTheme.textPrimary)
                                        .multilineTextAlignment(.leading)

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                        }

                        Rectangle().fill(YTTheme.separator).frame(height: 0.5).padding(.vertical, 6)

                        Button {
                            dismiss()
                            appVM.showToast("Feedback tool opened")
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "exclamationmark.bubble.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(YTTheme.color(hex: "#1A73E8"))

                                Text("Send feedback")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(YTTheme.color(hex: "#1A73E8"))

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        Rectangle().fill(YTTheme.separator).frame(height: 0.5)
                    }
                }
            }
            .background(YTTheme.backgroundPrimary)
        }
    }
}

// MARK: - Help Article Detail (`GeneralBrowsing #16`)
public struct YTHelpArticleDetailView: View {
    @Environment(\.dismiss) private var dismiss
    public let title: String

    public init(title: String) {
        self.title = title
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)

                Text("Help Article")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(YTTheme.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Light blue account recovery banner (`#E8F0FE` in `GeneralBrowsing #16`)
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your account, user@example.com, doesn’t have a recovery email address. If you’re locked out of your account, a recovery email address helps you get back in.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.black)
                            Text("Add your recovery email address ❐ .")
                                .font(.system(size: 14))
                                .foregroundStyle(YTTheme.callToActionBlue)
                        }
                        Spacer()
                        Image(systemName: "xmark")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.black.opacity(0.7))
                    }
                    .padding(16)
                    .background(YTTheme.color(hex: "#E8F0FE"))

                    VStack(alignment: .leading, spacing: 16) {
                        Text(title)
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(YTTheme.textPrimary)

                        Text("You can select your preferred language and location on YouTube using your computer or on mobile web. When using the YouTube mobile app, you can select your location. Language settings change the text that appears during videos.* The location you choose impacts the videos that surface for:")
                            .font(.system(size: 16))
                            .lineSpacing(4)
                            .foregroundStyle(YTTheme.textPrimary)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("•  Recommendations")
                            Text("•  Trending")
                            Text("•  News")
                        }
                        .font(.system(size: 16))
                        .foregroundStyle(YTTheme.textPrimary)
                        .padding(.leading, 8)

                        Text("YouTube provides language and content preferences for all countries/regions and languages where YouTube is available. We're constantly expanding the ability for the product to reach more users. If you cannot find your language or country/region, select an option that is most appropriate for your needs and interests.")
                            .font(.system(size: 16))
                            .lineSpacing(4)
                            .foregroundStyle(YTTheme.textPrimary)
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 32)
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - 7. Debug Console View (Full Real-Time App Activity & Player Logs)
public struct YTDebugConsoleView: View {
    @ObservedObject private var logger = YTDebugLogger.shared
    @EnvironmentObject private var appVM: YTAppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilter: String = "ALL"
    @State private var copiedBanner: Bool = false

    private let filterOptions = ["ALL", "ERROR", "PLAYER", "STREAM", "NET", "UI"]

    public init() {}

    private var filteredEntries: [YTLogEntry] {
        let base = selectedFilter == "ALL"
            ? logger.entries
            : logger.entries.filter { $0.level.rawValue == selectedFilter }
        return base.reversed()
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    YTIcon("yt_outline_arrow_left_24pt", fallback: "arrow.left", size: 22)
                        .foregroundStyle(YTTheme.textPrimary)
                }
                .buttonStyle(.plain)

                Text("Debug Logs")
                    .font(YTFontManager.youtubeSans(size: 20, weight: .bold))
                    .foregroundStyle(YTTheme.textPrimary)

                Spacer()

                Button {
                    logger.copyAllToClipboard()
                    copiedBanner = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedBanner = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedBanner ? "checkmark" : "doc.on.doc")
                        Text(copiedBanner ? "Copié !" : "Copier")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(YTTheme.callToActionBlue))
                }
                .buttonStyle(.plain)

                Button {
                    logger.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(YTTheme.brandRed)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .overlay(alignment: .bottom) {
                Rectangle().fill(YTTheme.separator).frame(height: 0.5)
            }

            // Live Player & HLS Server Diagnostics Banner
            VStack(alignment: .leading, spacing: 4) {
                Text("HLS Local Port: \(YTSequentialStreamServer.shared.listeningPort) | Logs: \(logger.entries.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(YTTheme.textPrimary)
                Text(logger.livePlayerStateSummary)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(YTTheme.textSecondary)
                if let v = appVM.currentVideo {
                    Text("Video: \(v.id) | Time: \(String(format: "%.1f", appVM.currentTime))s / \(String(format: "%.1f", appVM.duration))s")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(YTTheme.callToActionBlue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(YTTheme.backgroundSecondary)

            // Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filterOptions, id: \.self) { opt in
                        Button {
                            selectedFilter = opt
                        } label: {
                            Text(opt)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(selectedFilter == opt ? .white : YTTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(selectedFilter == opt ? (opt == "ERROR" ? YTTheme.brandRed : YTTheme.callToActionBlue) : YTTheme.backgroundSecondary)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Rectangle().fill(YTTheme.separator).frame(height: 0.5)

            // Log Entries List (newest on top)
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(filteredEntries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(entry.formattedTime)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(YTTheme.textSecondary)
                                Text(entry.level.rawValue)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(color(for: entry.level)))
                                Text("[\(entry.tag)]")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(YTTheme.textPrimary)
                            }
                            Text(entry.message)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(entry.level == .error ? YTTheme.brandRed : YTTheme.textPrimary)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        Rectangle().fill(YTTheme.separator.opacity(0.4)).frame(height: 0.5)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .background(YTTheme.backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func color(for level: YTLogLevel) -> Color {
        switch level {
        case .error: return .red
        case .player: return .green
        case .stream: return .blue
        case .net: return .orange
        case .ui: return .purple
        case .info: return .gray
        }
    }
}
