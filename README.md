# Nightride FM clients

Native clients for [Nightride FM](https://nightride.fm) — the synthwave
internet radio — sharing the same playback / Now Playing / metadata model
across platforms.

| Platform | Where                   | UI                     | Status                                                         |
|----------|-------------------------|------------------------|----------------------------------------------------------------|
| macOS    | [`macos/`](macos/)      | Menu-bar SwiftUI app   | ✅ Now Playing widget, media keys, AirPods, Discord Rich Presence |
| iOS      | [`ios/`](ios/)          | SwiftUI app + CarPlay  | ✅ Lock-screen / Control Center / CarPlay (entitlement required) |
| Android  | [`android/`](android/)  | Compose + Auto         | ✅ Notification / lock-screen / Android Auto (Media3)            |

All clients stream MP3 directly from `https://stream.nightride.fm/<station>.mp3`
and consume `https://nightride.fm/meta` for live track titles.

## Quickstart

- **macOS:** `cd macos && bash build.sh && open build/Nightride.app`
- **iOS:** `cd ios && bash build.sh` → open `Nightride.xcodeproj` in Xcode → Run on simulator or your phone. See [`ios/README.md`](ios/README.md) for sideloading + CarPlay notes.
- **Android:** open `android/` in Android Studio and hit Run, or `cd android && bash build.sh`. See [`android/README.md`](android/README.md) for Android Auto notes.

## Repo layout

```
.
├── macos/                 # SwiftPM-based menu-bar app
│   ├── Package.swift
│   ├── App/Info.plist
│   ├── Sources/Nightride/
│   └── build.sh
├── ios/                   # Xcode (via xcodegen) iOS app + CarPlay scene
│   ├── project.yml        # xcodegen source of truth
│   ├── App/
│   ├── Sources/
│   └── build.sh
└── android/               # Gradle + Kotlin + Compose app, Media3 + Android Auto
    ├── settings.gradle.kts
    ├── app/src/main/       # Kotlin sources + res/
    └── build.sh
```

No Apple Developer account is required to build the Apple clients;
ad-hoc / personal-team signing is enough for local installs. CarPlay does
require a paid Developer Program account + Apple's CarPlay entitlement
approval — see `ios/README.md`.
