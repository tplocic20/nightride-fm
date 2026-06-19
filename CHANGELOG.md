# Changelog

All notable changes to the Nightride.fm clients are recorded here. The format
follows [Keep a Changelog](https://keepachangelog.com/) and the project uses
[Semantic Versioning](https://semver.org/).

> Edit the **[Unreleased]** section as you work. `scripts/release.sh` stamps it
> with the version and date when you cut a release, and CI feeds those notes to
> the GitHub Release body and Google Play's "What's new".

## [Unreleased]

### Changed

- All platforms: **The now-playing "Artist — Title" line is now larger and
  easier to read at a glance.** Community feedback was that the track label sat
  too small to comfortably see who's playing, so it's been bumped up across iOS,
  Android, and macOS (with a slight contrast lift on mobile). The reserved
  two-line layout is unchanged, so nothing shifts as tracks change.

## [1.3.2] - 2026-06-18

### Fixed

- All platforms: **The track name now stays in sync with the music on its own.**
  1.3.1 held each title change by a fixed ~12s to line up with the buffered
  audio, but the real lag varies per connection (Icecast burst-on-connect +
  client prebuffer), so a single offset drifted — sometimes early, sometimes
  late. The playing station's title now comes from the stream's own in-band ICY
  metadata, which rides the same buffer as the audio, so it flips exactly when
  the song changes in your ears — no offset to tune. The `/meta` feed still
  drives the station list / CarPlay / Android Auto browse (where the instant,
  live-edge value is what you want).

## [1.3.1] - 2026-06-18

### Fixed

- All platforms: **The track name now changes in time with the music.** The
  metadata feed is pushed the instant a song changes at the source, but the
  audio you hear lags ~12s behind it (stream buffering), so the title used to
  flip well before the new song actually started. The displayed track is now
  held back to line up with what's playing.

## [1.3.0] - 2026-06-17

### Changed

- All platforms: **Playback is now MP3-only.** Apple's native HLS handling of the
  live feed proved unstable (stalls with no recovery), so the apps now stream the
  fixed-bitrate MP3 endpoint exclusively, which is rock-solid in practice
  (including in-car). The HLS/MP3 transport picker is removed and the player
  reverts to its simpler pre-1.2.4 behaviour — the HLS-startup tuning added in
  1.2.4/1.2.5 is no longer needed and has been dropped. The HLS code path is kept
  in the codebase, dormant, ready to re-enable if native HLS support improves.

## [1.2.5] - 2026-06-17

### Fixed

- All platforms: **HLS now starts almost instantly.** The players were
  pre-buffering before emitting any audio, which on a live feed could stall the
  start for up to a minute even though the stream itself is fine. They now start
  at the live edge with minimal buffering, the same way the website's web player
  does. As a safety net, if HLS hasn't started within a few seconds the player
  falls back to the instant-start MP3 stream instead of waiting out the
  platform's long internal timeout.

## [1.2.4] - 2026-06-17

### Changed

- macOS: show the "Unofficial fan project — not affiliated with Nightride FM."
  disclaimer in the footer, matching the iOS and Android clients.

## [1.2.3] - 2026-06-17

### Fixed

- All platforms: **HLS streaming works again.** nightride.fm moved its HLS
  endpoint (dropped the `:8443` port and added an `/hls/` path); the apps now
  point at the new URL. The MP3 stream was unaffected.

### Added

- All platforms: **automatic MP3 failover.** If an HLS stream fails to load, the
  player now falls back to the MP3 stream for the same station on its own — so a
  future HLS endpoint change degrades to MP3 instead of going silent. Your
  saved hls / mp3 preference is left untouched.

## [1.2.2] - 2026-06-11

### Fixed

- macOS: the popover no longer gets clipped top and bottom after a track starts
  playing. Release builds are now compiled with the macOS 26 SDK (CI moved to
  `macos-26` runners), which also restores the modern rounded panel chrome on
  macOS 26.

## [1.2.1] - 2026-06-10

- macOS: Tweak buttons alignment

## [1.2.0] - 2026-06-10

### Added

- All platforms: **HLS streaming** — adaptive AAC (~96–320 kbps) that adjusts
  to your connection instead of stuttering. Now the default stream.
- All platforms: an **hls / mp3 switch** below the playback controls. The
  classic fixed-bitrate MP3 stream stays available as a fallback for networks
  that block the HLS port; your choice is remembered across restarts.

## [1.1.0] - 2026-06-08

### Added

- iOS: **CarPlay** support — browse every station and control playback from your
  car's display (Apple-granted `carplay-audio` entitlement).

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
