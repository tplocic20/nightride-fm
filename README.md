# Nightride · Apple platforms

Native [Nightride FM](https://nightride.fm) clients for the Apple ecosystem —
sharing the same playback / Now Playing / metadata core across macOS and iOS.

| Platform | Where               | UI                     | Highlights                                                     |
|----------|---------------------|------------------------|----------------------------------------------------------------|
| macOS    | [`macos/`](macos/)  | Menu-bar SwiftUI app   | Now Playing widget, media keys, AirPods, Discord Rich Presence |
| iOS      | [`ios/`](ios/)      | SwiftUI app + CarPlay  | Lock-screen + Control Center controls, CarPlay audio app       |

Both apps stream via `AVPlayer`, register with `MPRemoteCommandCenter`, and
consume the Nightride FM SSE `meta` feed for live track metadata.

## Quickstart

- **macOS:** `cd macos && bash build.sh && open build/Nightride.app`
- **iOS:** `cd ios && bash build.sh` then open `Nightride.xcodeproj` in Xcode and Run on simulator or your phone. See [`ios/README.md`](ios/README.md) for sideloading + CarPlay notes.

## Repo layout

```
.
├── macos/                 # SwiftPM-based menu-bar app
│   ├── Package.swift
│   ├── App/Info.plist
│   ├── Sources/Nightride/
│   └── build.sh
└── ios/                   # Xcode (via xcodegen) iOS app + CarPlay scene
    ├── project.yml        # xcodegen source of truth
    ├── App/
    ├── Sources/
    └── build.sh
```

No Apple Developer account is required to build either; ad-hoc / personal-team
signing is enough for local installs.
