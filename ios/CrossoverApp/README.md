# CrossoverApp (iOS — All-in-One YouTube + Netflix + Spotify)

An all-in-one modular iOS app built with **SwiftUI** and **SwiftPM / `xtool`** that bundles **YouTube**, **Netflix**, and **Spotify** into a single `.ipa` binary.

---

## Architecture & File Map

```text
CrossoverApp/
├── Package.swift                          # Declares CrossoverApp + 3 library modules
├── xtool.yml                              # Bundle ID (com.crossover.allinone) & icon config
└── Sources/
    ├── CrossoverApp/
    │   ├── CrossoverApp.swift             # Root switcher UI, active mode persistence & audio cleanup
    │   ├── Info.plist
    │   └── Assets.xcassets/
    ├── YouTubeModule/                     # Modular YouTube client
    ├── NetflixModule/                     # Modular Netflix client
    └── SpotifyModule/                     # Modular Spotify client
```

---

## How the App Switcher Works

- At launch, `CrossoverApp` restores the last active mode (`YouTube`, `Netflix`, or `Spotify`) from `UserDefaults`.
- **Long-press the Home tab** inside any of the 3 apps to open the **App Switcher** overlay.
- Switching apps automatically pauses/resets active audio/video players from the previous module so streams never overlap.

---

## Configuration Before Building

1. Set your TMDB API key in `Sources/NetflixModule/Services/NFMovixEngine.swift`:
   ```swift
   private let tmdbAPIKey = "YOUR_TMDB_API_KEY"
   ```

---

## Building

```bash
cd ios/CrossoverApp
xtool dev build --ipa
# Output: xtool/CrossoverApp.ipa
```

---

## How to Upgrade / Extend

- **Upgrading an Existing Module**:
  - Update `Sources/YouTubeModule/`, `Sources/NetflixModule/`, or `Sources/SpotifyModule/`.
  - Keep each module's `*App.swift` entry view (`YouTubeRootView`, `NetflixRootView`, `SpotifyRootView`) and `AppIcon` / `CrossoverLongPress` hooks intact so the switcher stays connected.
- **Adding a 4th App Module**:
  1. Add a new target in `Package.swift` under `Sources/<NewApp>Module/`.
  2. Add a new case to `CrossoverMode` in `Sources/CrossoverApp/CrossoverApp.swift`.
  3. Render its root view in the `switch activeMode` block and attach the long-press Home gesture to trigger `CrossoverBus`.
