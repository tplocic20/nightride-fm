// Shared per-station cover-art generator.
//
// Renders one PNG per station: a synthwave pixel "sun" + the station name set
// in the unscii-16 pixel font, tinted with that station's accent colour. The
// font is used ONLY here — baked into a static image — so the app UI keeps
// normal, readable fonts. Output is committed to assets/artwork/ and bundled
// by each platform (macOS / iOS / Android).
//
// Pipeline: opentype.js (text → vector paths, no system-font install) →
// hand-built SVG → rsvg-convert → PNG. Run with:  bun run build   (or node)

import opentype from 'opentype.js';
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, 'artwork');
const fontBuf = readFileSync(join(HERE, 'fonts', 'unscii-16.ttf'));
const FONT = opentype.parse(
  fontBuf.buffer.slice(fontBuf.byteOffset, fontBuf.byteOffset + fontBuf.byteLength)
);

const SIZE = 1024;
const BG = '#0E0A12';
const NAME_COLOR = '#ECE6F0';

// Contrast-checked per-station accents — inspired by nightride.fm's own
// gradient-stop colours, but lightened/clamped so they stay legible on dark
// (their raw values + CSS filters are deliberately stylised and low-contrast).
const STATIONS = [
  { id: 'nightride', name: 'NIGHTRIDE', accent: '#CC55FF' },
  { id: 'chillsynth', name: 'CHILLSYNTH', accent: '#FFCBA6' },
  { id: 'datawave', name: 'DATAWAVE', accent: '#FFE696' },
  { id: 'spacesynth', name: 'SPACESYNTH', accent: '#3DD6A8' },
  { id: 'darksynth', name: 'DARKSYNTH', accent: '#FD3D9D' },
  { id: 'horrorsynth', name: 'HORRORSYNTH', accent: '#5BFF6A' },
  { id: 'ebsm', name: 'EBSM', accent: '#E6E6E6' },
  { id: 'rekt', name: 'REKT', accent: '#FF4D4D' },
  { id: 'rektory', name: 'REKTORY', accent: '#C9A86A' },
];

// A chunky pixel synthwave sun: solid top half, slatted bottom half.
function sun(cx, cy, r, px, color) {
  const rects = [];
  const slits = [[0, 30], [46, 70], [90, 112], [140, 160]]; // dy ranges kept in lower half
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

// Centre a string set in unscii, returned as an SVG <path>.
function centeredText(text, baselineY, fontSize, color) {
  const width = FONT.getAdvanceWidth(text, fontSize);
  const x = (SIZE - width) / 2;
  const d = FONT.getPath(text, x, baselineY, fontSize).toPathData(1);
  return `<path d="${d}" fill="${color}"/>`;
}

function svgFor(station) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}" shape-rendering="crispEdges">
  <defs>
    <radialGradient id="glow" cx="50%" cy="40%" r="55%">
      <stop offset="0%" stop-color="${station.accent}" stop-opacity="0.22"/>
      <stop offset="100%" stop-color="${station.accent}" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="${SIZE}" height="${SIZE}" fill="${BG}"/>
  <rect width="${SIZE}" height="${SIZE}" fill="url(#glow)"/>
  ${sun(512, 392, 176, 16, station.accent)}
  <rect x="96" y="600" width="832" height="6" fill="${station.accent}"/>
  ${centeredText(station.name, 760, 96, NAME_COLOR)}
  ${centeredText('· NIGHTRIDE FM ·', 856, 32, station.accent)}
</svg>`;
}

mkdirSync(OUT, { recursive: true });
const tmp = join(OUT, '_tmp.svg');
for (const station of STATIONS) {
  writeFileSync(tmp, svgFor(station));
  const png = join(OUT, `${station.id}.png`);
  execFileSync('rsvg-convert', ['-w', String(SIZE), '-h', String(SIZE), '-o', png, tmp]);
  console.log(`✓ ${station.id}.png  (${station.accent})`);
}
rmSync(tmp);
console.log(`\n${STATIONS.length} covers → assets/artwork/`);
