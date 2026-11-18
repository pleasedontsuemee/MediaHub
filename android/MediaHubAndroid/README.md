# MediaHubAndroid (Kotlin + Jetpack Compose + Media3 ExoPlayer)

A multi-module Android Gradle project that compiles **four APKs** from a single shared codebase:
- **YouTube** (`:app-youtube`)
- **Netflix** (`:app-netflix`)
- **Spotify** (`:app-spotify`)
- **CrossoverApp** (`:app-crossover` — all 3 apps unified with an instant switcher)

---

## Module Architecture

```text
MediaHubAndroid/
├── settings.gradle.kts                    # Includes all 8 modules
├── build.gradle.kts                       # AGP 8.7.3 + Kotlin 2.0.21 + Compose
├── gradle.properties
├── core/                                  # Shared OkHttpClient + CookieJar, ExoVideoSurface,
│                                          # CrossoverBus, adaptive tablet/phone layout helpers
├── youtube/                               # Shared YouTube library (YouTubeEngine + YouTubeScreen)
├── netflix/                               # Shared Netflix library (NetflixEngine + NetflixScreen)
├── spotify/                               # Shared Spotify library (SpotifyEngine + DeezerStreamProxy + SpotifyScreen)
├── app-youtube/                           # Standalone YouTube APK
├── app-netflix/                           # Standalone Netflix APK
├── app-spotify/                           # Standalone Spotify APK
└── app-crossover/                         # All-in-One Crossover APK
```

### Why Multi-Module?
Because `:youtube`, `:netflix`, and `:spotify` are Android library modules, **any fix or feature you add to a library module automatically applies to both its standalone APK and `app-crossover`!**

---

## Prerequisites & Configuration

1. **JDK 17 or 21** and **Android SDK** (`compileSdk = 35`, `minSdk = 26`).
2. **Gradle 8.13+**.
3. Create `local.properties` in `android/MediaHubAndroid/`:
   ```properties
   sdk.dir=/path/to/your/android-sdk
   ```
4. Set your TMDB API key in `netflix/src/main/java/com/mediahub/netflix/NetflixEngine.kt`:
   ```kotlin
   private const val TMDB_KEY = "YOUR_TMDB_API_KEY"
   ```

---

## Building the APKs

```bash
cd android/MediaHubAndroid

# Build all 4 debug APKs at once:
gradle :app-youtube:assembleDebug :app-netflix:assembleDebug :app-spotify:assembleDebug :app-crossover:assembleDebug
```

Generated APKs are placed in:
- `app-youtube/build/outputs/apk/debug/app-youtube-debug.apk`
- `app-netflix/build/outputs/apk/debug/app-netflix-debug.apk`
- `app-spotify/build/outputs/apk/debug/app-spotify-debug.apk`
- `app-crossover/build/outputs/apk/debug/app-crossover-debug.apk`

---

## Key Features & Adaptive UI

- **Phone & Tablet Responsive Layouts**:
  - Bottom tab bar stays at the bottom on all screen sizes (centered with `widthIn(max = 640.dp)` on tablets).
  - **YouTube**: 1–3 column adaptive grid, 2-pane widescreen watch layout on tablets, and a real **video quality selector** (`Auto` + all detected HLS/progressive resolutions via Media3 `TrackSelectionOverride`).
  - **Netflix**: Widescreen 16:9 Billboard Hero on tablets, season/episode picker, and fullscreen ExoPlayer.
  - **Spotify**: 2-pane Now Playing layout on tablets, full-track playback, and **Skyrock Mode**.
  - **CrossoverApp**: Long-press the **Home** tab anywhere (`Modifier.adaptiveHomeTabGesture`) to switch between YouTube, Netflix, and Spotify.

---

## How to Upgrade / Extend

- **Upgrade YouTube, Netflix, or Spotify**: Edit files inside `youtube/`, `netflix/`, or `spotify/`. Rebuild `:app-crossover` and the corresponding `:app-*` target.
- **Add a Shared UI Helper or Network Interceptor**: Add it to `core/src/main/java/com/mediahub/core/CoreShared.kt` (all modules depend on `:core`).
- **Add a 4th App to Crossover**:
  1. Create a new library module (e.g. `:twitch`) and register it in `settings.gradle.kts`.
  2. Add `implementation(project(":twitch"))` to `app-crossover/build.gradle.kts`.
  3. Add a new entry to `AppMode` in `app-crossover/src/main/java/com/mediahub/app/crossover/MainActivity.kt`.
