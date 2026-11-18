# SpotifyClone (iOS — SwiftUI + Full-Track Streaming + Skyrock Mode)

A native iOS Spotify client built with **SwiftUI** and **AVFoundation**, featuring full-track audio streaming, artist/album navigation, offline downloads, and **Skyrock Mode**.

---

## Architecture & File Map

```text
SpotifyClone/
├── App/
│   └── SpotifyCloneApp.swift              # App entry point, TabView & Now Playing overlay
├── Models/
│   └── SPModels.swift                     # Track, Artist, Album, Playlist & Library models
├── Services/
│   ├── SPMusicEngine.swift                # Charts, search, artist/album metadata & full-track resolver
│   ├── SPDeezerStreamProxy.swift          # Embedded localhost audio stream proxy
│   └── SPImageCacheAndDownloadManager.swift # Artwork cache & offline .m4a/.mp3 manager
├── ViewModels/
│   └── SPAppViewModel.swift               # Queue, playback, Skyrock jingle+varispeed & playlists
├── Views/
│   ├── SPHomeAndLibraryViews.swift        # Home feed, playlists & offline library
│   ├── SPSearchAndSettingsViews.swift     # Search, genres & settings
│   ├── SPPlayerViews.swift                # Mini-player, Now Playing & Track Options (`...`) sheet
│   └── SPArtistAndAlbumViews.swift        # Dedicated Artist & Album detail views
├── Theme/
│   └── SPTheme.swift                      # Spotify palette (#121212, #1ED760)
├── Resources/
│   └── skyrock.mp3                        # Bundled radio jingle for Skyrock Mode
└── Assets.xcassets/
```

---

## Key Features

- **Full-Track Audio**: Resolves full-length `.m4a` streams instead of 30-second previews.
- **Artist & Album Pages**: Tap any artist or album from the feed, search, or `...` options sheet to view top tracks, discography, and similar artists.
- **Skyrock Mode**: Plays the bundled `skyrock.mp3` jingle cleanly with a fade-out, then transitions into the track with a `0.56s` fade-in and `1.025x` varispeed pitch/tempo adjustment (`AVAudioTimePitchAlgorithm.varispeed`).

---

## Building

```bash
cd ios/SpotifyClone
xtool dev build --ipa
# Output: xtool/SpotifyClone.ipa
```

---

## How to Upgrade / Extend

- **Customize Skyrock Mode**: Replace `Resources/skyrock.mp3` with your own jingle and adjust the fade duration or playback rate (`1.025`) in `ViewModels/SPAppViewModel.swift`.
- **Add New Audio Sources**: Extend `Services/SPMusicEngine.swift` to add additional metadata or stream providers.
- **Sync with CrossoverApp**: Mirror changes to `ios/CrossoverApp/Sources/SpotifyModule/`.
