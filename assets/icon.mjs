// App-icon generator (distinct from the per-station cover art in generate.mjs).
//
// The icon is deliberately OUR OWN mark, not Nightride FM's logo: the owner
// asked this client not to present as the official app. So the hero is the
// pixel synthwave sun (the same motif baked into the station covers), and the
// maker is signalled by plocic.dev's copper "circuit-P" glyph tucked in the
// corner — i.e. "a Nightride FM client, by plocic", never the official badge.
//
// Renders one master 1024×1024 PNG + an SVG, then fans out into every
// platform's required sizes/containers (macOS .icns, iOS 1024 appicon,
// Android adaptive foreground). Run with:  bun run icon   (or node icon.mjs)

import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync, readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, 'icon');

const SIZE = 1024;
const BG = '#0E0A12';
const ACCENT = '#CC55FF';          // Nightride magenta-violet (matches app primary)
const COPPER = '#E1C292';          // plocic.dev circuit copper
const COPPER_HOT = '#FFB3AD';      // plocic.dev rose (inner traces / pads)

// --- Pixel synthwave sun (same construction as generate.mjs) -----------------
function sun(cx, cy, r, px, color) {
  const rects = [];
  const slits = [[0, 30], [46, 70], [90, 112], [140, 160]];
  for (let yy = cy - r; yy <= cy + r; yy += px) {
    const dy = yy - cy;
    if (dy * dy > r * r) continue;
    if (dy > 0 && !slits.some(([a, b]) => dy >= a && dy < b)) continue;
    const half = Math.sqrt(r * r - dy * dy);
    const x = Math.round((cx - half) / px) * px;
    const w = Math.round((2 * half) / px) * px;
    rects.push(`<rect x="${x}" y="${yy}" width="${w}" height="${px}" fill="${color}"/>`);
  }
  return rects.join('');
}

// --- plocic.dev circuit-P glyph (recoloured copper from the source favicon) --
// Pulled verbatim from assets/glyph/circuit-p.svg (viewBox 0 0 380 470) and
// dropped into a <g> we scale/translate into the corner. We keep its two-tone
// copper/rose strokes; only the hard-coded background fill of the solder pads
// is swapped to our icon ground so they read as pads, not holes.
function circuitGlyph() {
  const raw = readFileSync(join(HERE, 'glyph', 'circuit-p.svg'), 'utf8');
  // Strip the outer <svg> wrapper + <title>, keep the inner shapes.
  const inner = raw
    .replace(/<\?xml[\s\S]*?\?>/g, '')
    .replace(/<svg[\s\S]*?>/, '')
    .replace(/<\/svg>/, '')
    .replace(/<title>[\s\S]*?<\/title>/g, '')
    .replace(/#131411/g, BG)                 // pad centres → our ground
    .replace(/stroke-width="2.2"/g, 'stroke-width="3.4"')  // bolder so it survives downscaling
    .trim();
  return inner;
}

// Master icon. `glyph` toggles the corner maker's mark — we drop it for the
// tiniest macOS sizes (16/32px), where the copper traces are illegible and the
// sun alone should carry the identity.
function masterSVG({ glyph = true } = {}) {
  const gx = 648, gy = 612, gw = 300;
  const scale = gw / 380;            // glyph native box 380×470
  const gh = 470 * scale;
  const pad = 26;
  // When the glyph is present, stop the horizon line short of its plate so they
  // don't visually collide; otherwise run it full width.
  const horizonEnd = glyph ? (gx - pad - 24) : 928;
  const horizonW = horizonEnd - 96;
  const maker = glyph ? `
  <rect x="${gx - pad}" y="${gy - pad}" width="${gw + pad * 2}" height="${gh + pad * 2}"
        rx="40" fill="#000000" fill-opacity="0.28"/>
  <g transform="translate(${gx},${gy}) scale(${scale})" shape-rendering="geometricPrecision">
    ${circuitGlyph()}
  </g>` : '';
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}" shape-rendering="crispEdges">
  <defs>
    <radialGradient id="glow" cx="50%" cy="44%" r="62%">
      <stop offset="0%" stop-color="${ACCENT}" stop-opacity="0.30"/>
      <stop offset="100%" stop-color="${ACCENT}" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="${SIZE}" height="${SIZE}" fill="${BG}"/>
  <rect width="${SIZE}" height="${SIZE}" fill="url(#glow)"/>

  <!-- Hero: pixel synthwave sun + horizon line, centred and large -->
  ${sun(512, 470, 270, 24, ACCENT)}
  <rect x="96" y="772" width="${horizonW}" height="10" fill="${ACCENT}"/>
  ${maker}
</svg>`;
}

// --- Render helpers ----------------------------------------------------------
function png(svgPath, outPath, w, h = w) {
  execFileSync('rsvg-convert', ['-w', String(w), '-h', String(h), '-o', outPath, svgPath]);
}

mkdirSync(OUT, { recursive: true });
const masterSvgPath = join(OUT, 'icon.svg');             // full, with glyph
const smallSvgPath = join(OUT, 'icon-small.svg');        // glyph-free (tiny sizes)
const masterPngPath = join(OUT, 'icon-1024.png');
writeFileSync(masterSvgPath, masterSVG({ glyph: true }));
writeFileSync(smallSvgPath, masterSVG({ glyph: false }));
png(masterSvgPath, masterPngPath, SIZE);
console.log(`✓ master  → ${masterPngPath}`);

// === macOS: build Nightride.icns from an .iconset ============================
const ICONSET = join(OUT, 'Nightride.iconset');
mkdirSync(ICONSET, { recursive: true });
const macSizes = [16, 32, 64, 128, 256, 512, 1024];
for (const s of macSizes) {
  png(masterSvgPath, join(ICONSET, `icon_${s}x${s}.png`), s);
  // @2x variants where the iconset convention expects them
  if (s <= 512) png(masterSvgPath, join(ICONSET, `icon_${s}x${s}@2x.png`), s * 2);
}
// Rename to Apple's exact iconset filenames.
const renames = [
  ['icon_16x16.png', 'icon_16x16.png'],
  ['icon_32x32.png', 'icon_16x16@2x.png'],
  ['icon_32x32.png', 'icon_32x32.png'],
  ['icon_64x64.png', 'icon_32x32@2x.png'],
  ['icon_128x128.png', 'icon_128x128.png'],
  ['icon_256x256.png', 'icon_128x128@2x.png'],
  ['icon_256x256.png', 'icon_256x256.png'],
  ['icon_512x512.png', 'icon_256x256@2x.png'],
  ['icon_512x512.png', 'icon_512x512.png'],
  ['icon_1024x1024.png', 'icon_512x512@2x.png'],
];
// Re-render straight into the canonical names (simpler than tracking the @2x set above).
rmSync(ICONSET, { recursive: true, force: true });
mkdirSync(ICONSET, { recursive: true });
for (const [, name] of renames) {
  const base = parseInt(name.match(/(\d+)x\d+/)[1], 10);
  const px = name.includes('@2x') ? base * 2 : base;
  // Drop the maker's-mark glyph on the smallest rendered sizes (≤32px), where
  // the copper traces just turn to mud — the sun alone carries those.
  const src = px <= 32 ? smallSvgPath : masterSvgPath;
  png(src, join(ICONSET, name), px);
}
const icns = join(OUT, 'Nightride.icns');
execFileSync('iconutil', ['-c', 'icns', ICONSET, '-o', icns]);
console.log(`✓ macOS   → ${icns}`);

// === iOS: single 1024 appicon ================================================
const iosIcon = join(OUT, 'AppIcon-1024.png');
png(masterSvgPath, iosIcon, 1024);
console.log(`✓ iOS     → ${iosIcon}`);

// === Android: adaptive foreground (sun+glyph, transparent ground) ============
// Adaptive icons supply their own background colour, so the foreground PNG is
// rendered on transparency. Android also expects the key art within the safe
// centre ~66%, so we render at full bleed and let the system mask it.
function androidForegroundSVG() {
  // Adaptive icons crop to the safe centre ~66%, so keep the sun smaller and
  // centred and pull the glyph in tighter than the master.
  const gx = 624, gy = 590, gw = 240;
  const scale = gw / 380;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}" shape-rendering="crispEdges">
  <rect width="${SIZE}" height="${SIZE}" fill="none"/>
  ${sun(512, 452, 220, 20, ACCENT)}
  <rect x="160" y="712" width="704" height="9" fill="${ACCENT}"/>
  <g transform="translate(${gx},${gy}) scale(${scale})" shape-rendering="geometricPrecision">
    ${circuitGlyph()}
  </g>
</svg>`;
}
const androidSvgPath = join(OUT, 'android-foreground.svg');
writeFileSync(androidSvgPath, androidForegroundSVG());
png(androidSvgPath, join(OUT, 'android-foreground-432.png'), 432);
console.log(`✓ Android → ${join(OUT, 'android-foreground-432.png')} (+ svg)`);

// === iOS launch logo =========================================================
// A centred sun + horizon + circuit-P lockup on TRANSPARENCY, so the launch
// screen's own dark background colour (LaunchBackground) shows through instead
// of the old flat-pink AccentColor fill. Rendered square at 3 scales; the
// launch screen centres it on the dark ground.
function launchLogoSVG() {
  const S = 600;                 // logical points; @1/2/3x rendered below
  const cx = S / 2;
  const gw = 150;                // glyph width
  const gscale = gw / 380;
  const gh = 470 * gscale;
  const gx = cx - gw / 2;
  const gy = 372;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}" viewBox="0 0 ${S} ${S}" shape-rendering="crispEdges">
  <rect width="${S}" height="${S}" fill="none"/>
  ${sun(cx, 210, 132, 12, ACCENT)}
  <rect x="${cx - 190}" y="338" width="380" height="6" fill="${ACCENT}"/>
  <g transform="translate(${gx},${gy}) scale(${gscale})" shape-rendering="geometricPrecision">
    ${circuitGlyph()}
  </g>
</svg>`;
}
const launchSvgPath = join(OUT, 'launch-logo.svg');
writeFileSync(launchSvgPath, launchLogoSVG());
for (const [scale, px] of [[1, 600], [2, 1200], [3, 1800]]) {
  png(launchSvgPath, join(OUT, `launch-logo${scale > 1 ? `@${scale}x` : ''}.png`), px);
}
console.log(`✓ iOS splash → ${join(OUT, 'launch-logo{,@2x,@3x}.png')}`);

console.log('\nicon set → assets/icon/');
