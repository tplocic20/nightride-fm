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
The app lives in the menu bar; click the icon to pick a station.

Requires Xcode 15+ / Swift 5.9+, macOS 13+. No Apple Developer account needed;
the build script ad-hoc codesigns the bundle.
