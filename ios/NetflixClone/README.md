# NetflixClone (iOS — SwiftUI + TMDB + Movix)

A native iOS Netflix-style client built with **SwiftUI** and **AVPlayer**, combining **TMDB** metadata with **Movix** HLS/MP4 stream resolution.

---

## Architecture & File Map

```text
NetflixClone/
├── App/
│   └── NetflixCloneApp.swift              # App entry point, Profile gate & Main TabView
├── Models/
│   └── NFModels.swift                     # Movie/TV Show, Season, Episode & Profile models
├── Services/
│   ├── NFMovixEngine.swift                # TMDB API client + Movix stream resolver
│   ├── NFImageCacheAndDownloadManager.swift # Artwork cache & offline HLS/MP4 exporter
│   └── NFDebugLogger.swift                # Network & player diagnostics
├── ViewModels/
│   └── NFAppViewModel.swift               # Catalog state, playback, downloads & profile prefs
├── Views/
│   ├── NFHomeView.swift                   # Billboard Hero, Top 10 & category carousels
│   ├── NFMediaDetailView.swift            # Movie/Series detail sheet, episodes & trailers
│   ├── NFPlayerView.swift                 # Fullscreen player (speed, zoom, source switcher, PiP)
│   └── NFSecondaryTabsView.swift          # New & Hot, Fast Laughs, Search, Downloads & Settings
├── Theme/
│   └── NFTheme.swift                      # Netflix dark palette & bundled fonts
└── Assets.xcassets/
```

---

## Configuration Before Building

Open `NetflixClone/Services/NFMovixEngine.swift` and set your own **TMDB API Key**:

```swift
private let tmdbAPIKey = "YOUR_TMDB_API_KEY"
```

You can generate a free key from [themoviedb.org/settings/api](https://www.themoviedb.org/settings/api).

---

## Building

```bash
cd ios/NetflixClone
xtool dev build --ipa
# Output: xtool/NetflixClone.ipa
```

---

## How to Upgrade / Extend

- **Change or Add Video Providers**: Update the stream resolution endpoints in `Services/NFMovixEngine.swift` (e.g., `purstream`, `fstream`, `links`). Users can also override the base Movix URL directly in the in-app **Settings** menu.
- **Customize Player Controls**: Edit `Views/NFPlayerView.swift` to add subtitle styling, audio track selection, or custom skip intervals.
- **Add New Home Carousels**: Add new TMDB endpoints in `NFMovixEngine.swift` and bind them in `ViewModels/NFAppViewModel.swift` + `Views/NFHomeView.swift`.
- **Sync with CrossoverApp**: Mirror changes to `ios/CrossoverApp/Sources/NetflixModule/`.
