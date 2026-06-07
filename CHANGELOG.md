# Changelog

All notable changes to the Nightride.fm clients are recorded here. The format
follows [Keep a Changelog](https://keepachangelog.com/) and the project uses
[Semantic Versioning](https://semver.org/).

> Edit the **[Unreleased]** section as you work. `scripts/release.sh` stamps it
> with the version and date when you cut a release, and CI feeds those notes to
> the GitHub Release body and Google Play's "What's new".

## [Unreleased]

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
