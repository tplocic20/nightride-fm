# Nightride · iOS

Native iPhone / iPad client for [Nightride FM](https://nightride.fm), with
CarPlay scaffolding ready to activate once Apple grants the entitlement.

> **Shipping to the App Store?** This README covers building and sideloading to
> your own device. For the signed CI pipeline that uploads to App Store Connect
> off a `v*` tag, see [DEPLOYMENT.md](DEPLOYMENT.md).

| Feature                                | Works on free Apple ID? | Works with paid account? |
|----------------------------------------|--------------------------|---------------------------|
| Phone UI, background audio, Lock Screen/Control Center controls, AirPods | ✅ | ✅ |
| Long-lived install (no 7-day refresh)  | ❌ (7-day expiry)        | ✅                        |
| TestFlight distribution to friends     | ❌                       | ✅                        |
| CarPlay                                | ❌                       | ⏳ requires Apple's entitlement approval |

## First time setup

```bash
brew install xcodegen        # one-off, ~30 s
bash build.sh                # generates Nightride.xcodeproj
open Nightride.xcodeproj
```

## Sideloading to your iPhone with a free Apple ID

1. In Xcode, **Settings → Accounts → +** and sign in with your Apple ID.
2. Select the `Nightride` target → **Signing & Capabilities**.
3. Set **Team** to your name (Personal Team).
4. If Xcode complains the bundle id is already in use, change it (any unique
   string works, e.g. `dev.plocic.nightride.tomasz`). To make the change permanent,
   regenerate the project with the override:
   ```bash
   BUNDLE_ID=dev.plocic.nightride.tomasz bash build.sh
   ```
5. Plug your iPhone in and unlock it. The first time, you may need to
   **trust the computer** on the phone.
6. In Xcode's device picker (top toolbar), choose your iPhone.
7. Hit **▶ Run**.
8. On the phone: **Settings → General → VPN & Device Management →**
   trust your Apple ID's developer profile. After that the app icon will open.

The build is valid for **7 days**. After that, plug into Xcode and hit Run
again to refresh it.

> **Why 7 days?** Apple gives free personal teams ad-hoc-style provisioning
> that expires weekly. The paid Developer Program ($99/yr) gives 1-year
> profiles plus TestFlight (90-day expiry, distributable to other devices
> over the air).

## Enabling CarPlay

The CarPlay scene delegate (`Sources/CarPlaySceneDelegate.swift`) and the
matching scene config in `App/Info.plist` are already in place. iOS just
won't connect to them without the right entitlement on your build's
provisioning profile. Once you're enrolled in the Developer Program:

1. Go to <https://developer.apple.com/contact/carplay/> and submit the
   CarPlay entitlement request. Pick **Audio**. Describe Nightride briefly.
   Approval typically lands within a few business days for audio apps.
2. After approval, Apple adds `com.apple.developer.carplay-audio` to your
   team's capabilities list.
3. In `project.yml`, change the target's
   `CODE_SIGN_ENTITLEMENTS` (or just edit it in Xcode's Signing &
   Capabilities tab) from `App/Nightride.entitlements` to
   `App/Nightride.carplay.entitlements`.
4. Rebuild. Xcode will regenerate the provisioning profile with the
   CarPlay capability.
5. Plug the phone into a real CarPlay head unit (or use Xcode's CarPlay
   Simulator under **Window → External Displays → CarPlay**). Nightride
   should appear in CarPlay's app grid.

## Files

```
ios/
├── project.yml                          # xcodegen source of truth
├── build.sh                             # generate the .xcodeproj (Xcode/sideload)
├── release-appstore.sh                  # archive → .ipa → App Store Connect
├── DEPLOYMENT.md                        # App Store CI + secrets walkthrough
├── App/
│   ├── Info.plist                       # UIBackgroundModes + CarPlay scene
│   ├── Nightride.entitlements           # empty — free-signing friendly
│   ├── Nightride.carplay.entitlements   # carplay-audio key, paid only
│   └── Assets.xcassets/
└── Sources/
    ├── NightrideApp.swift               # @main + AppDelegate
    ├── ContentView.swift                # SwiftUI phone UI
    ├── PlayerStore.swift                # AVPlayer + Now Playing
    ├── RemoteCommands.swift             # MPRemoteCommandCenter
    ├── MetaStream.swift                 # SSE consumer
    ├── Stations.swift                   # static station list
    └── CarPlaySceneDelegate.swift       # CarPlay templates
```
