# Nightride for macOS

A small native menu-bar app for streaming [Nightride FM](https://nightride.fm).
Plays through `AVPlayer`, registers with the macOS Now Playing widget, responds
to the keyboard's media keys and to AirPods controls, and mirrors the currently
playing track to Discord Rich Presence.

Inspired by [`nightride-cli`](https://github.com/babycommando/nightride-cli) —
this version trades the terminal for the menu bar.

## Build

```bash
bash build.sh
```

That produces `build/Nightride.app`. Double-click it (or `open build/Nightride.app`).
The app lives in the menu bar; click the pixel mark to open the player.

Requires Xcode 15+ / Swift 5.9+, macOS 13+. No Apple Developer account needed;
the build script ad-hoc codesigns the bundle.

## Look & feel

The menu-bar popover uses a custom CRT/pixel theme (shared design language with
[plocic.dev](https://plocic.dev)): phosphor-synthwave palette, SF Mono UI chrome,
sharp-cornered bordered transport with hand-drawn pixel glyphs, a terminal-style
station list (`> nightride` is the live one), and a scanline overlay you can
toggle from the footer (`crt: on/off`, on by default; the moving sweep backs off
when Reduce Motion is enabled).

Theme tokens live in `Sources/Nightride/Theme.swift`; the pixel glyphs in
`PixelGlyph.swift`; the popover in `PlayerView.swift`. The playback engine
(`PlayerStore`, `MetaStream`, `RemoteCommands`) is unchanged — this was a
presentation-layer rebuild from the old native `NSMenu`.
