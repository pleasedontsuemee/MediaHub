import SwiftUI

// MARK: - 1. Floating Mini-Player Bar (Above Tab Bar)
public struct SPMiniPlayerBar: View {
    @EnvironmentObject private var appVM: SPAppViewModel

    public init() {}

    public var body: some View {
        if let track = appVM.currentTrack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button {
                        appVM.isNowPlayingPresented = true
                    } label: {
                        HStack(spacing: 10) {
                            SPCachedAsyncImage(url: track.coverURL) {
                                Rectangle().fill(SPTheme.backgroundElevated)
                            }
                            .frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(track.title)
                                        .font(SPFontManager.mix(13, bold: true))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    if appVM.isSkyrockMode {
                                        Text("SKYROCK")
                                            .font(.system(size: 8, weight: .black))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(SPTheme.skyrockBlue))
                                    }
                                }
                                Text(track.artistName)
                                    .font(SPFontManager.mix(12))
                                    .foregroundStyle(SPTheme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        appVM.toggleSkyrockMode()
                    } label: {
                        Image(systemName: "radio.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(appVM.isSkyrockMode ? SPTheme.skyrockBlue : SPTheme.textSecondary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)

                    Button {
                        appVM.togglePlayPause()
                    } label: {
                        Image(systemName: appVM.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: SPTheme.miniPlayerHeight - 2)

                // Thin bottom progress bar
                GeometryReader { g in
                    let pct = appVM.duration > 0 ? min(1, max(0, appVM.currentTime / appVM.duration)) : 0
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.2))
                        Rectangle()
                            .fill(appVM.isSkyrockMode ? SPTheme.skyrockBlue : Color.white)
                            .frame(width: g.size.width * CGFloat(pct))
                    }
                }
                .frame(height: 2)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.16, green: 0.16, blue: 0.16)))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - 2. Fullscreen Now Playing View (with Skyrock Mode)
public struct SPNowPlayingView: View {
    @EnvironmentObject private var appVM: SPAppViewModel
    @ObservedObject private var downloadManager = SPOfflineDownloadManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var localTrackOptions: SPTrack? = nil

    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    appVM.isSkyrockMode ? Color(red: 0.04, green: 0.22, blue: 0.36) : Color(red: 0.18, green: 0.22, blue: 0.26),
                    SPTheme.backgroundPrimary
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if let track = appVM.currentTrack {
                VStack(spacing: 0) {
                    // Top Bar
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        VStack(spacing: 2) {
                            Text("LECTURE EN COURS")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(SPTheme.textSecondary)
                            Text(appVM.currentContextTitle)
                                .font(SPFontManager.mix(12, bold: true))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            localTrackOptions = track
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    Spacer()

                    // Cover Artwork
                    SPCachedAsyncImage(url: track.coverURL) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(SPTheme.backgroundElevated)
                    }
                    .frame(width: 330, height: 330)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.45), radius: 22, y: 10)

                    Spacer()

                    // Title, Artist, Like & Skyrock Toggle
                    VStack(spacing: 16) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title)
                                    .font(SPFontManager.mix(22, bold: true))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Button {
                                    appVM.openArtist(id: track.artistId, name: track.artistName)
                                } label: {
                                    Text(track.artistName)
                                        .font(SPFontManager.mix(15))
                                        .foregroundStyle(SPTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                            Button {
                                appVM.toggleLike(track)
                            } label: {
                                Image(systemName: appVM.isLiked(track) ? "heart.fill" : "heart")
                                    .font(.system(size: 24))
                                    .foregroundStyle(appVM.isLiked(track) ? SPTheme.spotifyGreen : .white)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                        }

                        // Scrubber
                        VStack(spacing: 4) {
                            GeometryReader { barGeo in
                                let pct = appVM.duration > 0 ? min(1, max(0, appVM.currentTime / appVM.duration)) : 0
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.25)).frame(height: 4)
                                    Capsule()
                                        .fill(appVM.isSkyrockMode ? SPTheme.skyrockBlue : Color.white)
                                        .frame(width: barGeo.size.width * CGFloat(pct), height: 4)
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 12, height: 12)
                                        .offset(x: max(0, min(barGeo.size.width - 12, barGeo.size.width * CGFloat(pct) - 6)))
                                }
                                .frame(height: 22)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { val in
                                            let p = max(0, min(1, val.location.x / max(1, barGeo.size.width)))
                                            appVM.seek(to: Double(p) * appVM.duration)
                                        }
                                )
                            }
                            .frame(height: 22)

                            HStack {
                                Text(formatTime(appVM.currentTime))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(SPTheme.textSecondary)
                                Spacer()
                                if appVM.isSkyrockTransitioning {
                                    Text("JINGLE SKYROCK...")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(SPTheme.skyrockBlue)
                                } else if !appVM.currentStreamLabel.isEmpty {
                                    Text(appVM.currentStreamLabel)
                                        .font(.system(size: 10))
                                        .foregroundStyle(SPTheme.textMuted)
                                }
                                Spacer()
                                Text("-\(formatTime(max(0, appVM.duration - appVM.currentTime)))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(SPTheme.textSecondary)
                            }
                        }

                        // Main Playback Controls
                        HStack {
                            Button {
                                appVM.isShuffleEnabled.toggle()
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(appVM.isShuffleEnabled ? SPTheme.spotifyGreen : .white)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                appVM.previousTrack()
                            } label: {
                                Image(systemName: "backward.end.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 52)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                appVM.togglePlayPause()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 66, height: 66)
                                    if appVM.isBuffering && !appVM.isSkyrockTransitioning {
                                        ProgressView().tint(.black)
                                    } else {
                                        Image(systemName: appVM.isPlaying ? "pause.fill" : "play.fill")
                                            .font(.system(size: 26))
                                            .foregroundStyle(.black)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                appVM.nextTrack()
                            } label: {
                                Image(systemName: "forward.end.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 52)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                appVM.isRepeatEnabled.toggle()
                            } label: {
                                Image(systemName: "repeat")
                                    .font(.system(size: 20))
                                    .foregroundStyle(appVM.isRepeatEnabled ? SPTheme.spotifyGreen : .white)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                        }

                        // Bottom Action Row: Skyrock Version Toggle + Download + AirPlay
                        HStack(spacing: 14) {
                            Button {
                                appVM.toggleSkyrockMode()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "radio.fill")
                                        .font(.system(size: 14))
                                    Text(appVM.isSkyrockMode ? "Version Skyrock (1.025x) ON" : "Version Skyrock")
                                        .font(SPFontManager.mix(13, bold: true))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(appVM.isSkyrockMode ? SPTheme.skyrockBlue : SPTheme.backgroundElevated)
                                )
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            let isDl = downloadManager.isDownloaded(track.id)
                            let isDling = downloadManager.activeDownloads.contains(track.id)
                            Button {
                                Task {
                                    appVM.showToast("Téléchargement en cours...")
                                    let ok = await downloadManager.downloadTrack(track)
                                    appVM.showToast(ok ? "Titre téléchargé hors-ligne !" : "Échec du téléchargement")
                                }
                            } label: {
                                Group {
                                    if isDling {
                                        ProgressView().tint(SPTheme.spotifyGreen)
                                    } else {
                                        Image(systemName: isDl ? "arrow.down.circle.fill" : "arrow.down.circle")
                                            .font(.system(size: 22))
                                            .foregroundStyle(isDl ? SPTheme.spotifyGreen : .white)
                                    }
                                }
                                .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                }
            }
        }
        .sheet(item: $localTrackOptions) { t in
            SPTrackOptionsSheet(track: t)
                .environmentObject(appVM)
                .presentationDetents([.medium, .large])
        }
    }

    private func formatTime(_ sec: TimeInterval) -> String {
        let total = max(0, Int(sec))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
