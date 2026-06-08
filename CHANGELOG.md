# Changelog

All notable changes to the Nightride.fm clients are recorded here. The format
follows [Keep a Changelog](https://keepachangelog.com/) and the project uses
[Semantic Versioning](https://semver.org/).

> Edit the **[Unreleased]** section as you work. `scripts/release.sh` stamps it
> with the version and date when you cut a release, and CI feeds those notes to
> the GitHub Release body and Google Play's "What's new".

## [Unreleased]

## [1.0.1] - 2026-06-08
### Changed
- macOS: link the canonical `discord.com/invite/synthwave` invite URL (the form
  used on nightride.fm) instead of the short `discord.gg` alias.

## [1.0.0] - 2026-06-08
First public release — native Nightride.fm players for macOS, iOS and Android.

### Added
- **Live synthwave radio**: stream every Nightride.fm station with real-time
  "now playing" track titles.
- **Built into your system** — macOS menu-bar Now Playing with media keys and
  AirPods controls; iOS lock screen, Control Center and CarPlay; Android
  notification, lock screen and Android Auto.
- **One-tap music links**: open the current track on Spotify, Apple Music or
  YouTube, or copy the artist and title.
- **CRT / synthwave interface** — a pixel-styled neon UI across all three apps.

### Privacy
- No ads, no analytics, no trackers, no accounts. The apps connect only to
  Nightride.fm for the stream and track metadata — and to a music service only
  when you tap a link.

## [0.5.1] - 2026-06-07
### Added
- Android tag-based CI/CD: a `v*` tag now ships a signed App Bundle to Google
  Play (internal testing) and attaches a signed APK to the GitHub Release.

## [0.5.0] - 2026-06-07
### Added
- In-app **About** on macOS, iOS and Android — author attribution plus links to
  plocic.dev and the GitHub issue tracker.

### Changed
- Redesigned the macOS menu-bar footer as a tidy 2×2 link grid.
- Documentation accuracy: removed the stale Discord Rich Presence claims and
  documented the complete network behaviour.

## [0.2.0] - 2026-06-05
### Added
- macOS and iOS **App Store** CI/CD, plus one-command releases across all three
  apps via `scripts/release.sh`.
