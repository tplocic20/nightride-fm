# Shared assets — per-station cover art

One generator, one set of covers, used by every client (macOS / iOS / Android).

The **unscii-16 pixel font lives here only** — it's baked into static PNGs at
generation time, never shipped into the apps. That's the deliberate split: the
pixel font is fine for a fixed, ASCII station name rendered into an image, but
the app UIs keep normal, readable fonts for live track/artist text (which can
contain accented characters, needs to scale, etc.).

## What it makes

`artwork/<station>.png` — a 1024×1024 cover per station: a chunky pixel
synthwave sun + the station name in unscii, tinted with that station's accent.
Accents are inspired by nightride.fm's own per-station gradient colours, but
lightened/contrast-clamped so they stay legible on the dark ground (their raw
values + CSS filters are deliberately stylised and often low-contrast).

These PNGs feed each platform's Now Playing artwork — so they show on the
lock screen, Control Center, CarPlay and Android Auto.

## Regenerate

```bash
cd assets
bun install        # one-off: opentype.js
bun run build      # → artwork/*.png
```

Pipeline: `opentype.js` turns the station name into vector paths (no system
font install needed) → a hand-built SVG (sun + text + glow) → `rsvg-convert`
rasterises to PNG. Requires `rsvg-convert` (`brew install librsvg`).

## Editing

- Accent colours + station names: the `STATIONS` array in `generate.mjs`.
- Sun shape / layout: `sun()` and `svgFor()` in `generate.mjs`.

## Committed vs ignored

`fonts/unscii-16.ttf` (public domain), `generate.mjs`, `package.json`,
`bun.lock`, and `artwork/*.png` are committed. `node_modules/` is not.
