// App-icon generator (distinct from the per-station cover art in generate.mjs).
//
// The icon is deliberately OUR OWN mark, not Nightride FM's logo: the owner
// asked this client not to present as the official app. So the hero is the
// pixel synthwave sun (the same motif baked into the station covers), nothing
// else — never the official badge.
//
// Renders one master 1024×1024 PNG + an SVG, then fans out into every
// platform's required sizes/containers (macOS .icns, iOS 1024 appicon,
// Android adaptive foreground). Run with:  bun run icon   (or node icon.mjs)

import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, 'icon');

const SIZE = 1024;
const BG = '#0E0A12';
const ACCENT = '#CC55FF';          // Nightride magenta-violet (matches app primary)

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

// Master icon.
function masterSVG() {
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
  <rect x="96" y="772" width="832" height="10" fill="${ACCENT}"/>
</svg>`;
}

// --- Render helpers ----------------------------------------------------------
function png(svgPath, outPath, w, h = w) {
  execFileSync('rsvg-convert', ['-w', String(w), '-h', String(h), '-o', outPath, svgPath]);
}

mkdirSync(OUT, { recursive: true });
const masterSvgPath = join(OUT, 'icon.svg');
const masterPngPath = join(OUT, 'icon-1024.png');
writeFileSync(masterSvgPath, masterSVG());
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
  png(masterSvgPath, join(ICONSET, name), px);
}
const icns = join(OUT, 'Nightride.icns');
execFileSync('iconutil', ['-c', 'icns', ICONSET, '-o', icns]);
console.log(`✓ macOS   → ${icns}`);

// === iOS: single 1024 appicon ================================================
const iosIcon = join(OUT, 'AppIcon-1024.png');
png(masterSvgPath, iosIcon, 1024);
console.log(`✓ iOS     → ${iosIcon}`);

// === Android: adaptive foreground (sun, transparent ground) ============
// Adaptive icons supply their own background colour, so the foreground PNG is
// rendered on transparency. Android also expects the key art within the safe
// centre ~66%, so we render at full bleed and let the system mask it.
function androidForegroundSVG() {
  // Adaptive icons crop to the safe centre ~66%, so keep the sun smaller and
  // centred.
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}" shape-rendering="crispEdges">
  <rect width="${SIZE}" height="${SIZE}" fill="none"/>
  ${sun(512, 452, 220, 20, ACCENT)}
  <rect x="160" y="712" width="704" height="9" fill="${ACCENT}"/>
</svg>`;
}
const androidSvgPath = join(OUT, 'android-foreground.svg');
writeFileSync(androidSvgPath, androidForegroundSVG());
png(androidSvgPath, join(OUT, 'android-foreground-432.png'), 432);
console.log(`✓ Android → ${join(OUT, 'android-foreground-432.png')} (+ svg)`);

// === iOS launch logo =========================================================
// A centred sun + horizon lockup on TRANSPARENCY, so the launch
// screen's own dark background colour (LaunchBackground) shows through instead
// of the old flat-pink AccentColor fill. Rendered square at 3 scales; the
// launch screen centres it on the dark ground.
function launchLogoSVG() {
  const S = 600;                 // logical points; @1/2/3x rendered below
  const cx = S / 2;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}" viewBox="0 0 ${S} ${S}" shape-rendering="crispEdges">
  <rect width="${S}" height="${S}" fill="none"/>
  ${sun(cx, 210, 132, 12, ACCENT)}
  <rect x="${cx - 190}" y="338" width="380" height="6" fill="${ACCENT}"/>
</svg>`;
}
const launchSvgPath = join(OUT, 'launch-logo.svg');
writeFileSync(launchSvgPath, launchLogoSVG());
for (const [scale, px] of [[1, 600], [2, 1200], [3, 1800]]) {
  png(launchSvgPath, join(OUT, `launch-logo${scale > 1 ? `@${scale}x` : ''}.png`), px);
}
console.log(`✓ iOS splash → ${join(OUT, 'launch-logo{,@2x,@3x}.png')}`);

console.log('\nicon set → assets/icon/');
