# Nightride FM clients

Native clients for [Nightride FM](https://nightride.fm) — the synthwave
internet radio — sharing the same playback / Now Playing / metadata model
across platforms.

> [!NOTE]
> **Unofficial fan project.** This is not the official Nightride FM app and is
> not affiliated with or endorsed by the station — see [TRADEMARK.md](TRADEMARK.md).

## Why this exists

I built this out of love for Nightride FM — the radio and the community around
it. I always missed being able to take it with me: on long midnight rides in
the car, the station I wanted was never quite *there*, never quite integrated
into the moment. I wanted the radio closer to me — more personal, woven into
everyday life instead of living behind a browser tab.

So these clients are exactly that: the stream, where you already are — the menu
bar, the lock screen, CarPlay, Android Auto — plus one-tap links to find the
current track on Spotify / Apple Music / YouTube when a song grabs you. Nothing
more. No ads, no trackers, no accounts. Just the music, on the drive home.

| Platform | Where                   | UI                     | Status                                                         |
|----------|-------------------------|------------------------|----------------------------------------------------------------|
| macOS    | [`macos/`](macos/)      | Menu-bar SwiftUI app   | ✅ Now Playing widget, media keys, AirPods controls            |
| iOS      | [`ios/`](ios/)          | SwiftUI app + CarPlay  | ✅ Lock-screen / Control Center / CarPlay (entitlement required) |
| Android  | [`android/`](android/)  | Compose + Auto         | ✅ Notification / lock-screen / Android Auto (Media3)            |

All clients stream MP3 directly from `https://stream.nightride.fm/<station>.mp3`
— the playing station's "now playing" title rides the stream's in-band ICY
metadata, while `https://nightride.fm/meta` feeds the station list / CarPlay /
Android Auto browse.

## Quickstart

- **macOS:** `cd macos && bash build.sh && open build/Nightride.app`
- **iOS:** `cd ios && bash build.sh` → open `Nightride.xcodeproj` in Xcode → Run on simulator or your phone. See [`ios/README.md`](ios/README.md) for sideloading + CarPlay notes.
- **Android:** open `android/` in Android Studio and hit Run, or `cd android && bash build.sh`. See [`android/README.md`](android/README.md) for Android Auto notes.

## Releasing

One command bumps the marketing version across **all three apps** in lockstep,
then commits, tags, and pushes to `main`:

```bash
bash scripts/release.sh 0.2.0            # macOS + iOS + Android → commit → tag v0.2.0 → push main
bash scripts/release.sh 0.2.0 --dry-run  # preview the plan, write nothing
```

The pushed `v*` tag fans out to the store workflows — `macos-dmg` (notarized
`.dmg` on a GitHub Release), plus `macos-appstore` and `ios-appstore` (signed
builds to App Store Connect / TestFlight). Build numbers come from the CI run
number on iOS/macOS; Android's `versionCode` is derived from the version.
Per-platform signing + secrets: [`macos/DEPLOYMENT.md`](macos/DEPLOYMENT.md),
[`ios/DEPLOYMENT.md`](ios/DEPLOYMENT.md).

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

## What this app does — and doesn't

Open source means you don't have to take my word for it; read the code. But to
save you the grep, here is the **complete** network and data behaviour:

**Every network connection the app makes:**

| Connection | When | Why |
|------------|------|-----|
| `https://stream.nightride.fm/<station>.mp3` | while playing | the audio stream + the playing station's in-band ICY "now playing" title |
| `https://nightride.fm/meta` | while open | live "now playing" titles for the station list / CarPlay / Android Auto browse (server-sent events) |
| Spotify / Apple Music / YouTube search URLs | **only when you tap** a chip | open that track in your music app |
| `https://itunes.apple.com/search` | **only when you tap Apple Music** (iOS / Android) | resolve the exact track's catalog link — Apple's public, no-auth lookup; falls back to a plain search |
| nightride.fm · Discord invite · plocic.dev · GitHub Issues | **only when you tap** a link | open the site / community / author / bug tracker in your browser |

**That's the whole list.** Specifically, this app has:

- ❌ **No ads.**
- ❌ **No analytics, telemetry, or trackers.** (No Firebase, Sentry, Amplitude,
  Mixpanel, Segment, AdMob, AppsFlyer — grep for yourself.)
- ❌ **No accounts, logins, or personal data collection.** It never asks who
  you are.
- ❌ **No crypto miners** 🙂, no background phone-home, no hidden endpoints.
- ❌ **No third-party SDKs on Apple platforms** — macOS and iOS use only
  Apple's own frameworks (`AVFoundation`, `MediaPlayer`, SwiftUI). Android uses
  standard AndroidX / Jetpack Compose / Media3 / OkHttp — all mainstream, none
  for ads or tracking.

The music-service buttons just build a **search URL** and hand it to the OS
(Apple Music on iOS/Android first does the no-auth catalog lookup above to
land on the exact song); they don't have (or want) access to your
Spotify/Apple Music account.

## Licence & contributing

- Code: [MIT](LICENSE). Use it, learn from it, fork it.
- Branding (names, icon, the circuit-P glyph, Nightride FM marks): see
  [TRADEMARK.md](TRADEMARK.md) — the code is open, the identity is reserved.
- Want to help? See [CONTRIBUTING.md](CONTRIBUTING.md) and the
  [Code of Conduct](CODE_OF_CONDUCT.md). Found a security issue? [SECURITY.md](SECURITY.md).
