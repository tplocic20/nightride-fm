# Changelog

All notable changes to the Nightride.fm clients are recorded here. The format
follows [Keep a Changelog](https://keepachangelog.com/) and the project uses
[Semantic Versioning](https://semver.org/).

> Edit the **[Unreleased]** section as you work. `scripts/release.sh` stamps it
> with the version and date when you cut a release, and CI feeds those notes to
> the GitHub Release body and Google Play's "What's new".

## [Unreleased]

## [1.4.8] - 2026-09-07

### Changed

- iOS: **The artwork spins both ways now.** The easter egg's flip used to turn
  one direction only and stop dead at half a turn. Drag the cover either way,
  as far as you like, and let go — a flick throws it through several turns and
  glides to a stop on a face, fidget-spinner style. A short drag that doesn't
  clear halfway falls back to where it started. The spectrum stays live for the
  whole spin, so the bars are moving every time the back face sweeps past.

## [1.4.7] - 2026-09-07

### Added

- iOS: **The artwork easter egg is back.** Swipe or tap the cover and it flips
  to the live pixel spectrum again. The removal in 1.4.6 was a misdiagnosis:
  `MTAudioProcessingTap` is fine on iOS 26. The tap was created with no init
  callback, and `MTAudioProcessingTapGetStorage` returns only what that
  callback parks in `tapStorageOut` — so storage was NULL and the first
  `prepare` dereferenced it. One init callback fixes it.

### Fixed

- iOS: **Flipping the cover no longer interrupts the stream.** The tap was
  attached by assigning `audioMix` to an item that was already playing, which
  makes AVPlayer rebuild its audio pipeline — an audible drop-out, and several
  seconds before the tap delivered a single buffer. The tap is now attached
  when the item is created, and showing or hiding the egg only gates the FFT,
  so the audio path never changes. Measured on device: callbacks hold a steady
  12/s straight through a flip.
- iOS: **The bars no longer drop out at random.** Every 20-35 seconds AVPlayer
  re-prepares the tap to refill its buffer: callbacks pause for up to two
  seconds and the buffers either side of that arrive as digital silence, all
  while the speaker plays on. The old decay read both as silence and slammed
  the bars down. Now the player tells the engine when it is streaming, silent
  batches are skipped rather than analysed, and the fade is time-based and
  only starts after playback really stops. Measured over 150 seconds on
  device: every remaining dip tracks genuinely quiet audio.
- iOS: **The cover turns with your finger.** Dragging rotates it in real time
  and it springs back if you let go early; a flick or a third of the width
  completes the turn. The card is `Animatable`, so the faces swap at the true
  halfway point of the animation rather than the moment it is scheduled — and
  the spectrum no longer renders mirrored, with its bass bands on the right.
- iOS: **The spectrum animates.** The `Canvas` ignored its `TimelineView`
  context, so SwiftUI saw an unchanged view and redrew it whenever something
  else on screen happened — 9 times in 17 seconds, against 104 analysis
  updates. Threading the timeline's date into the drawing takes it to 60fps.
- iOS: **Spectrum bands now show the right frequencies.** The FFT handed
  `vDSP_fft_zrip` a real array with a zeroed imaginary half instead of
  deinterleaving with `vDSP_ctoz`, which zero-stuffs the signal and mirrors
  the spectrum. The transform also grew to 4096 points, because 43 Hz bins
  could not separate the bottom bands, and band level is now summed energy so
  a tone reads the same in a narrow low band as in a wide high one. Levels are
  calibrated against the live stream, and `AudioSpectrum.selfCheck()` asserts
  that test tones light the band that contains them.

## [1.4.6] - 2026-09-07

### Fixed

- iOS: **Crashing easter egg removed.** The artwork-flip spectrum relied on
  `MTAudioProcessingTap`, which on iOS 26 devices invokes its callbacks
  through an out-of-process XPC path where the client context arrives NULL —
  unfixable from app code (crash: `aptapR_PrepareTapIfNeeded` /
  `EXC_BAD_ACCESS`). The cover is back to plain artwork with its glow. The
  pixel-spectrum UI and FFT engine live in git history, ready to return on a
  supported audio-tap API or an `AVSampleBufferAudioRenderer` re-plumb.

## [1.4.5] - 2026-09-07

### Fixed

- iOS: **Easter egg crash, for real this time.** The tap was still being
  created and freed on every flip, and the device audio pipeline kept
  executing its callback on the dying tap — use-after-free that the simulator
  tolerated but hardware did not. The tap is now created once and never freed
  during flips; attach/detach only swap the audio mix. The analysis path is
  also allocation-free now, as a realtime thread should be.

### Changed

- iOS: **Station name morphs instead of scrambling.** Letters shared between
  the old and new station name hold still while the rest flickers and
  re-locks (SpaceWave → DataWave keeps the "a…wave"), settling in 0.45s.
  Song/artist line is back to plain text — multi-word titles churned too much
  to read.

## [1.4.4] - 2026-09-07

### Fixed

- iOS: **Easter egg no longer crashes the app on flip.** The spectrum tap's
  reference was over-released on detach (my C-bridge refcount guess was
  wrong); the created tap is now transferred to the audio mix, which owns it
  outright. Reproduced and stress-verified: 6 rapid flip cycles twice over,
  zero crashes.

## [1.4.3] - 2026-09-06

### Added

- iOS: **Artwork easter egg.** Swipe or tap the cover — it flips over to a
  live pixel-art spectrum (14 bands, LED-style cells with white-capped peaks)
  driven by a real FFT of the playing stream. The audio tap behind it is
  attached only while the spectrum is on screen; flip back and the audio path
  is completely stock again.

## [1.4.2] - 2026-09-06

### Added

- iOS: **Scramble-in text animation.** The station name and track line resolve
  left-to-right out of cycling glyphs on every station switch and track change.
- iOS: **CRT scanlines toggle** in the About sheet — a standalone on/off for
  the scanline overlay, replacing the amber theme.

### Changed

- iOS: **Track action chips fade instead of collapsing.** The apple / spotify /
  youtube / copy row keeps its height reserved when no track is known, so the
  layout no longer shifts on pause; the chips fade out and become untappable.

### Removed

- iOS: **Amber theme deleted.** The station accent now always drives the UI
  (midnight behavior); the scanlines live on as a toggle. Existing amber users
  keep their scanlines enabled automatically.

## [1.4.1] - 2026-09-06

### Fixed

- iOS: **Split view no longer hijacks the iPhone on play.** The full-bleed
  artwork layer added in 1.4.0 used an unframed `scaledToFill`, which reported
  its full aspect-filled size (~905×905pt for a square cover) to the layout
  system. That inflated the root stack, pushed the layout past the 600pt
  tablet breakpoint, and flipped the phone into the iPad split view the moment
  playback started. The artwork now fills the screen without touching layout.

## [1.4.0] - 2026-09-06

### Added

- iOS: **Sleep timer.** Pick 15/30/60 minutes from the moon button; volume
  fades over the last minute and playback pauses gently instead of cutting.
- iOS: **Themes.** *midnight* (per-station accent, the classic look) and
  *amber* (monochrome phosphor CRT — one hue, scanlines, text bloom).
  Switchable from the About sheet, applied live.
- iOS: **Full-bleed artwork.** The station's cover fills the screen, blurred
  into a color field — the artwork itself becomes the background tint.
- iOS: **Micro-interactions.** Play/pause glyph morph and an artwork
  crossfade-with-settle on station switch.

### Changed

- iOS: **Richer station tinting.** Layered accent gradients recolor the whole
  player per station, with a blurred artwork glow behind the cover.

## [1.3.5] - 2026-09-06

### Changed

- iOS: **CarPlay opens straight into playback.** The Now Playing screen is now
  the root — one tap on play resumes the last station, whose name and logo are
  shown immediately even from a cold start. The station list moved to a button
  in the playback control row instead of being the entry screen, removing the
  nested browse-then-play navigation.

## [1.3.4] - 2026-09-06

### Fixed

- All platforms: **No more stale artist after the app's been idle.** The
  now-playing line used to sit on the last song heard (possibly hours old) and
  visibly flip the moment you hit play. It now shows the brand name while idle
  and clears on pause/station switch; the in-band ICY title fills it in as
  playback buffers.

### Removed

- All platforms: **Dormant HLS transport code deleted** (transport enum,
  HLS→MP3 failover, saved preferences, Android `media3-exoplayer-hls` dep).
  MP3-only since 1.3.0; the code lives in git history if native HLS support
  ever improves.
- Dead code: unused `TrackMeta.album` field (Apple clients), unused macOS
  theme colors, the now-unused macOS `/meta` SSE client, and two unused
  Android Gradle dependencies.

### Changed

- Comment cleanup across macOS/CarPlay/MetaStream — comments trimmed to the
  "why", not a restatement of the code.

## [1.3.3] - 2026-06-19

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
