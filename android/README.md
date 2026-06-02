# Nightride · Android

Native Android client for [Nightride FM](https://nightride.fm), built with
Kotlin + Jetpack Compose and Media3. Background playback, a media-style
notification, lock-screen / Bluetooth / headset controls and **Android Auto**
all come from a single `MediaLibraryService` — there's no Auto-specific UI to
maintain, the same way the iOS app reuses its Now Playing center for CarPlay.

| Feature | Status |
|---------|--------|
| Compose phone UI (synthwave gradient, station picker) | ✅ |
| Background audio + media notification | ✅ |
| Lock screen / Bluetooth / wired headset transport | ✅ |
| Live track titles from `nightride.fm/meta` (SSE) | ✅ |
| Android Auto (browse stations → Now Playing) | ✅ no extra signup needed |
| Android Automotive OS (built-in car) | 🛠 should work via the same service; untested |

## First-time setup

The simplest path is **Android Studio** (it bundles a JDK, the SDK, and Gradle):

1. Open the `android/` folder in Android Studio (Giraffe or newer).
2. Let it sync — it generates the Gradle wrapper and downloads dependencies.
3. Pick a device/emulator in the toolbar and hit **▶ Run**.

### Headless / command line

Needs a JDK 17+ and the Android SDK on `ANDROID_HOME` (plus `gradle` on PATH
the very first time, to generate the wrapper):

```bash
bash build.sh            # → app/build/outputs/apk/debug/app-debug.apk
bash build.sh install    # build + adb install onto a connected device
```

If the SDK isn't auto-detected, point at it:

```bash
echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties
```

## Trying Android Auto

No developer signup or entitlement is required (unlike CarPlay):

1. On your phone, enable **Developer settings** in Android Auto
   (Auto app → tap the version 10× → ⋮ → **Developer settings**) and turn on
   **Unknown sources** so a debug build is allowed.
2. Use the **Desktop Head Unit (DHU)** from the SDK
   (`$ANDROID_HOME/extras/google/auto/desktop-head-unit`) over USB, or plug
   into a real Android Auto head unit.
3. Nightride appears among the media apps; its browse list is the station
   list, and selecting one opens the standard Now Playing screen with working
   play/pause/next/prev.

## How it maps to the Apple clients

| Apple (`ios/`, `macos/`) | Android (`android/`) |
|--------------------------|----------------------|
| `Stations.swift` | `Station.kt` + `Stations.kt` |
| `MetaStream.swift` (SSE) | `MetaStream.kt` (OkHttp + coroutines) |
| `PlayerStore.swift` (AVPlayer + Now Playing) | `PlaybackService.kt` (ExoPlayer + `MediaLibrarySession`) |
| `RemoteCommands.swift` | handled by `MediaSession` (no code) |
| `CarPlaySceneDelegate.swift` | the library callbacks in `PlaybackService.kt` |
| `ContentView.swift` (SwiftUI) | `ui/PlayerScreen.kt` (Compose) + `PlayerController.kt` |
| `splitTitle(...)` | `Titles.split(...)` |

## Files

```
android/
├── build.gradle.kts                 # root Gradle config
├── settings.gradle.kts
├── gradle/libs.versions.toml         # version catalog
├── build.sh                          # wrapper bootstrap + assembleDebug
└── app/
    ├── build.gradle.kts
    ├── proguard-rules.pro
    └── src/main/
        ├── AndroidManifest.xml        # perms + service + Auto meta-data
        ├── java/dev/plocic/nightride/
        │   ├── Station.kt             # model + MediaItem mapping
        │   ├── Stations.kt            # static station list
        │   ├── Titles.kt              # "Artist - Title" → (track, artist)
        │   ├── MetaStream.kt          # SSE consumer
        │   ├── PlaybackService.kt     # ExoPlayer + MediaLibrarySession (+ Auto)
        │   ├── PlayerController.kt     # UI-side MediaController wrapper
        │   ├── MainActivity.kt
        │   └── ui/
        │       ├── Theme.kt
        │       └── PlayerScreen.kt    # Compose UI
        └── res/
            ├── values/                # strings, colors, themes
            ├── xml/automotive_app_desc.xml
            ├── drawable/ic_launcher_foreground.xml
            └── mipmap-anydpi-v26/     # adaptive launcher icon
```
