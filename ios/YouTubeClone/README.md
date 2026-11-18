# YouTubeClone (iOS — SwiftUI + InnerTube + Localhost HLS)

A native iOS YouTube client built with **SwiftUI** and **AVFoundation**, packaged via **SwiftPM / `xtool`**.

---

## Architecture & File Map

```text
YouTubeClone/
├── App/
│   └── YouTubeCloneApp.swift              # App entry point, TabView, Mini-Player & Watch overlay
├── Models/
│   └── YTModels.swift                     # Video, Channel, Format, Caption & Playback models
├── Services/
│   ├── YTInnerTubeEngine.swift            # YouTube InnerTube API client (search, player, captions, comments)
│   ├── YTSequentialStreamServer.swift     # Embedded 127.0.0.1 HTTP HLS server + sidx fMP4 segmenter
│   ├── YTCacheAndDownloadManager.swift    # Disk/memory image cache & offline video/audio downloads
│   ├── YTCatalogData.swift                # Default categories, channels & mock fallback catalog
│   └── YTDebugLogger.swift                # In-app diagnostic logger (stream, player, network)
├── ViewModels/
│   └── YTAppViewModel.swift               # Global state, AVPlayer/AVAudioPlayer sync, quality switching
├── Views/
│   ├── Components/YTSharedComponents.swift
│   ├── Home/YTHomeAndExploreViews.swift
│   ├── Shorts/YTShortsFeedView.swift
│   ├── Search/YTSearchViews.swift
│   ├── Subscriptions/YTSubscriptionsAndChannelViews.swift
│   ├── Library/YTLibraryViews.swift
│   ├── Watch/YTWatchPlayerView.swift      # Video player UI, controls, mini-player, fullscreen
│   ├── Watch/YTWatchEngagementAndSheets.swift # Quality picker, captions, speed, comments sheets
│   └── Modals/YTModalsAndSettingsViews.swift  # Settings, quality preferences, debug console
├── Theme/
│   └── YTTheme.swift                      # Colors, typography & bundled font registration
├── Resources/                             # Bundled fonts & fallback assets
└── Assets.xcassets/                       # App icons & UI icons
```

---

## How Video Streaming & Quality Selection Work

1. **Stream Resolution (`YTInnerTubeEngine.swift`)**:
   - Queries YouTube InnerTube `/player` (`ANDROID` client first for adaptive H.264/AV1 + `sidx` ranges, falling back to `IOS` client for native `hlsManifestUrl`).
2. **Localhost HLS Engine (`YTSequentialStreamServer.swift`)**:
   - Runs an embedded `NWListener` HTTP server on `127.0.0.1:<port>`.
   - For adaptive MP4 streams, fetches only the tiny `sidx` box (~2–4 KB) and serves an Apple-compliant `.m3u8` master/media playlist so playback starts in `<0.4s`.
   - For native HLS streams (`hlsManifestUrl`), `makeQualityPinnedHLSPlayerItem(from:targetHeight:videoId:)` parses `#EXT-X-STREAM-INF` variants, pins the master playlist to the user's selected resolution, and applies `preferredMaximumResolution`.
3. **Live Quality Switching (`YTAppViewModel.changeQuality(_:)`)**:
   - Replaces the `AVPlayerItem` and seeks cleanly to the saved playback timestamp once `.readyToPlay` fires.

---

## Building

```bash
cd ios/YouTubeClone
xtool dev build --ipa
# Output: xtool/YouTubeClone.ipa
```

---

## How to Upgrade / Extend

- **Update InnerTube Client Versions**: Edit `androidClient` / `iosClient` profiles in `Services/YTInnerTubeEngine.swift` if YouTube deprecates older client versions.
- **Add a New Quality Tier or Codec**: Update `YTResolvedVideoPlayback.availableQualityLabels` and `matchingVideoFormat(for:)` in `Models/YTModels.swift`.
- **Add a New Tab or Modal**: Register new views in `App/YouTubeCloneApp.swift` and state properties in `ViewModels/YTAppViewModel.swift`.
- **Sync with CrossoverApp**: After modifying files here, copy your updated files into `ios/CrossoverApp/Sources/YouTubeModule/` (keeping `App/YouTubeCloneApp.swift` and `Views/Components/YTSharedComponents.swift` aligned with Crossover's module entry).
