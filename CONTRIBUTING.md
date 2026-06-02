# Contributing

Thanks for wanting to help make Nightride feel a little more at home on your
devices. 🌃 This is a small, friendly project — contributions of all sizes are
welcome, from typo fixes to whole features.

By contributing, you agree your contributions are licensed under the project's
[MIT licence](LICENSE). Please also read [TRADEMARK.md](TRADEMARK.md): the code
is open, but the app's name/icon and the Nightride FM brand are reserved — keep
those in mind, especially for anything UI-facing.

## Ground rules

- Be kind — see the [Code of Conduct](CODE_OF_CONDUCT.md).
- Keep the project's promise intact: **no ads, no trackers, no analytics, no
  accounts.** PRs that add a tracking/ad/telemetry SDK, a new phone-home
  endpoint, or bundled third-party binaries will be declined. New runtime
  dependencies need a good reason — the Apple clients currently have **zero**
  third-party dependencies and we'd like to keep that bar high.
- Match the surrounding style. Each client follows its platform's idioms; read
  the neighbouring file before adding to it.

## Project layout

This is a monorepo with three independent clients that share a design language
and the same playback/metadata model (but no shared code module):

| Client | Stack | Source |
|--------|-------|--------|
| `macos/` | SwiftPM, SwiftUI menu-bar app | `macos/Sources/Nightride/` |
| `ios/` | xcodegen + Xcode, SwiftUI + CarPlay | `ios/Sources/` |
| `android/` | Gradle + Kotlin + Compose + Media3 | `android/app/src/main/` |

Shared, generated assets (cover art, app icon, launch logo) live in `assets/`
and are produced by the Node scripts there — see [`assets/README.md`](assets/README.md).

## Building & running

### macOS
```bash
cd macos
bash build.sh            # → build/Nightride.app (ad-hoc signed, local use)
open build/Nightride.app
```
Requires Xcode 15+ / Swift 5.9+, macOS 13+. No Apple account needed for local
builds. `release.sh` is the signed/notarised distribution path and needs a
Developer ID cert (see its header).

### iOS
```bash
cd ios
bash build.sh            # regenerates Nightride.xcodeproj via xcodegen
```
Then open `Nightride.xcodeproj` in Xcode and Run. The `.xcodeproj` is
**generated** — edit [`ios/project.yml`](ios/project.yml), not the project file,
and re-run `build.sh` (needs [`xcodegen`](https://github.com/yonaskolb/XcodeGen):
`brew install xcodegen`). CarPlay needs a paid Developer Program account +
Apple's CarPlay entitlement — see [`ios/README.md`](ios/README.md).

### Android
```bash
cd android
bash build.sh            # or open the folder in Android Studio and Run
```

### Regenerating assets
```bash
cd assets
bun install              # or: npm install
node icon.mjs            # app icons + iOS launch logo  → assets/icon/
node generate.mjs        # per-station cover art         → assets/artwork/
```
Requires `rsvg-convert` (`brew install librsvg`). Commit the regenerated PNGs
along with the script change that produced them.

## Submitting changes

1. **Open an issue first** for anything non-trivial, so we can agree on the
   approach before you invest time.
2. Branch off `main`; keep the change focused (one concern per PR).
3. **Build the client(s) you touched** and confirm they run. If a change spans
   platforms, try to keep them in sync.
4. Write clear commit messages. Don't include generated build output
   (`build/`, `.build/`, `DerivedData/`) — these are gitignored.
5. Open the PR with a short description of *what* and *why*, plus a screenshot
   for any UI change.

## Good first contributions

- Bug fixes and crash reports (with repro steps).
- Accessibility improvements.
- Tightening platform parity (a feature one client has and another doesn't).
- Docs and README clarity.

Not sure where to start? Open an issue and ask — happy to point you somewhere.
