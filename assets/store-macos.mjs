// Mac App Store screenshot composer.
//
// Takes raw popover screenshots (772px-wide PNGs with their native macOS
// shadow + transparent margin, as captured with ⇧⌘4+space) and frames each
// into a 2880×1800 store image: popover on the left, unscii pixel headline in
// the slide's accent + small kicker + sans body copy on the right. Two
// variants per slide: flat near-black, and `_bg` with a soft purple radial
// gradient. The hero (macos-0-hero.png) is hand-made separately and untouched.
//
// Pipeline matches generate.mjs: opentype.js (text → vector paths, no
// system-font dependency in the SVG) → rsvg-convert → PNG. Run:
//   node store-macos.mjs [screenshots-dir]     (default ~/Documents/night-fm/macOS)
// Outputs to <screenshots-dir>/store/.

import opentype from 'opentype.js';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, rmSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { homedir } from 'node:os';

const HERE = dirname(fileURLToPath(import.meta.url));
const SHOTS = process.argv[2] ?? join(homedir(), 'Documents', 'night-fm', 'macOS');
const OUT = join(SHOTS, process.env.OUTDIR ?? 'store');

function loadFont(path) {
  const buf = readFileSync(path);
  return opentype.parse(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength));
}
const UNSCII = loadFont(join(HERE, 'fonts', 'unscii-16.ttf'));
const ARIAL = loadFont('/System/Library/Fonts/Supplemental/Arial.ttf');

const W = 2880, H = 1800;
const FLAT_BG = '#0B0710';

// One entry per store slide. Accents follow the station shown in the shot
// (see Stations.swift). v1.3.0 (MP3-only): re-shot popovers, and the HLS/MP3
// slide 4 is gone (feature removed). Slide 3 now shows Darksynth (pink).
const SLIDES = [
  {
    out: 'macos-1',
    shot: 'SCR-20260618-gojf.png',
    accent: '#CC55FF',
    headline: ['LIVE SYNTHWAVE', 'IN YOUR MENU BAR'],
    body: ['Every Nightride FM station, always', 'one click away in the menu bar.'],
  },
  {
    out: 'macos-2',
    shot: 'SCR-20260618-gojn.png',
    accent: '#FFCBA6',
    headline: ['NOW PLAYING,', 'ALWAYS IN VIEW'],
    body: ['The current track and artist,', 'updating live as the station plays.'],
  },
  {
    out: 'macos-3',
    shot: 'SCR-20260618-gojy.png',
    accent: '#FD3D9D',
    headline: ['FOUND A TRACK', 'YOU LOVE?'],
    body: ['Open it on Spotify, Apple Music or', 'YouTube — or copy artist and title.'],
  },
];

// PNG pixel size straight from the IHDR chunk (always first, fixed offsets).
function pngSize(buf) {
  return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
}

// A string as one SVG <path>, with optional per-glyph tracking (opentype.js
// has no letter-spacing of its own).
function text(font, str, x, baselineY, size, color, { tracking = 0, opacity = 1 } = {}) {
  let d = '', cx = x;
  for (const ch of str) {
    d += font.getPath(ch, cx, baselineY, size).toPathData(1);
    cx += font.getAdvanceWidth(ch, size) + tracking;
  }
  return `<path d="${d}" fill="${color}" fill-opacity="${opacity}"/>`;
}

function svgFor(slide, withGradient) {
  const shotBuf = readFileSync(join(SHOTS, slide.shot));
  const { w: sw, h: sh } = pngSize(shotBuf);
  const shotW = 908;                                // popover column, as in v1.0 set
  const shotH = Math.round(sh * (shotW / sw));
  const shotX = 256;
  const shotY = Math.round((H - shotH) / 2);
  const TX = 1344;                                  // text column left edge

  // `_bg` variant: the slide's accent bleeds out of the dark ground as a soft
  // phosphor glow (same colour as the headline), with subtle CRT scanlines
  // laid over the background — visible mostly inside the glow, like a real
  // tube. The popover + text render above the lines so they stay crisp.
  const background = withGradient
    ? `<defs>
         <radialGradient id="glow" cx="50%" cy="46%" r="75%">
           <stop offset="0%" stop-color="${slide.accent}" stop-opacity="0.18"/>
           <stop offset="55%" stop-color="${slide.accent}" stop-opacity="0.06"/>
           <stop offset="100%" stop-color="${slide.accent}" stop-opacity="0"/>
         </radialGradient>
         <pattern id="scan" width="6" height="6" patternUnits="userSpaceOnUse">
           <rect width="6" height="3" fill="#000000" fill-opacity="0.22"/>
         </pattern>
       </defs>
       <rect width="${W}" height="${H}" fill="${FLAT_BG}"/>
       <rect width="${W}" height="${H}" fill="url(#glow)"/>
       <rect width="${W}" height="${H}" fill="url(#scan)"/>`
    : `<rect width="${W}" height="${H}" fill="${FLAT_BG}"/>`;

  return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  ${background}
  <image x="${shotX}" y="${shotY}" width="${shotW}" height="${shotH}" xlink:href="data:image/png;base64,${shotBuf.toString('base64')}"/>
  ${text(UNSCII, 'NIGHTRIDE.FM PLAYER', TX, 608, 34, '#B9A9C4', { tracking: 6, opacity: 0.9 })}
  ${text(UNSCII, slide.headline[0], TX, 800, 112, slide.accent, { tracking: 8 })}
  ${text(UNSCII, slide.headline[1], TX, 992, 112, slide.accent, { tracking: 8 })}
  ${text(ARIAL, slide.body[0], TX, 1128, 44, '#ECE6F0', { opacity: 0.88 })}
  ${text(ARIAL, slide.body[1], TX, 1196, 44, '#ECE6F0', { opacity: 0.88 })}
</svg>`;
}

mkdirSync(OUT, { recursive: true });
const tmp = join(OUT, '_tmp.svg');
for (const slide of SLIDES) {
  for (const grad of [false, true]) {
    writeFileSync(tmp, svgFor(slide, grad));
    const name = `${slide.out}${grad ? '_bg' : ''}.png`;
    execFileSync('rsvg-convert', ['-w', String(W), '-h', String(H), '-o', join(OUT, name), tmp]);
    console.log(`✓ ${name}`);
  }
}
rmSync(tmp);
console.log(`\n${SLIDES.length} slides ×2 variants → ${OUT}`);
