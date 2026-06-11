// iOS App Store screenshot composer (iPhone + iPad).
//
// Takes raw simulator screenshots and frames each into a portrait store
// image: centred kicker + unscii pixel headline in the slide's accent + sans
// body copy on top, the device (dark bezel, rounded screen, phosphor glow in
// the accent) below. Background carries the approved CRT treatment from the
// macOS set: the accent bleeding out of the dark ground as a soft glow, with
// subtle scanlines under the device and text. Heroes are hand-made and
// untouched.
//
// Canvases match what App Store Connect already holds: 1284×2778 (iPhone
// 6.5") and 2048×2732 (iPad 12.9").
//
// Pipeline matches store-macos.mjs. Run:
//   node store-ios.mjs [screenshots-dir]      (default ~/Documents/night-fm/iOS)
// Outputs to <screenshots-dir>/store/.

import opentype from 'opentype.js';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, rmSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { homedir } from 'node:os';

const HERE = dirname(fileURLToPath(import.meta.url));
const SHOTS = process.argv[2] ?? join(homedir(), 'Documents', 'night-fm', 'iOS');
const OUT = join(SHOTS, 'store');

function loadFont(path) {
  const buf = readFileSync(path);
  return opentype.parse(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength));
}
const UNSCII = loadFont(join(HERE, 'fonts', 'unscii-16.ttf'));
const ARIAL = loadFont('/System/Library/Fonts/Supplemental/Arial.ttf');

const FLAT_BG = '#0B0710';

const IPHONE = (n) => `Simulator Screenshot - iPhone 17e - 2026-06-10 at 14.40.${n}.png`;
const IPAD = (n) => `Simulator Screenshot - iPad Pro 11-inch (M5) - 2026-06-10 at 14.40.${n}.png`;

// Copy mirrors the v1.0 set; slide 4 is new for the HLS/MP3 source switch.
const COPY = {
  anywhere: {
    accent: '#CC55FF',
    headline: ['LIVE SYNTHWAVE', 'ANYWHERE'],
    body: 'Live now-playing, on every station.',
  },
  stations: {
    accent: '#CC55FF',
    headline: ['EVERY STATION,', 'ONE TAP AWAY'],
    body: 'Nine stations, always one tap away.',
  },
  track: {
    accent: '#FF4D4D',
    headline: ['FOUND A TRACK', 'YOU LOVE?'],
    body: 'Spotify, Apple Music, or YouTube.',
  },
  hls: {
    accent: '#FF4D9D',
    headline: ['ADAPTIVE HLS,', 'CLASSIC MP3'],
    body: 'Adaptive HLS — or classic MP3. One tap.',
  },
};

const DEVICES = [
  {
    prefix: 'ios-iphone',
    W: 1284, H: 2778,
    // Text block baselines / sizes, then the box the framed device must fit.
    kickerY: 268, headY: [372, 489], headSize: 96, bodyY: 574, bodySize: 42,
    deviceBox: { top: 833, bottom: 2600, maxW: 880 },
    bezel: 22, screenRadius: 84,
    slides: [
      { out: 'ios-iphone-1', shot: IPHONE('22'), ...COPY.anywhere },
      { out: 'ios-iphone-2', shot: IPHONE('25'), ...COPY.stations },
      { out: 'ios-iphone-3', shot: IPHONE('28'), ...COPY.track },
      { out: 'ios-iphone-4', shot: IPHONE('19'), ...COPY.hls },
    ],
  },
  {
    prefix: 'ios-ipad',
    W: 2048, H: 2732,
    kickerY: 140, headY: [310, 472], headSize: 104, bodyY: 652, bodySize: 46,
    deviceBox: { top: 830, bottom: 2580, maxW: 1380 },
    bezel: 26, screenRadius: 64,
    slides: [
      { out: 'ios-ipad-1', shot: IPAD('37'), ...COPY.anywhere },
      { out: 'ios-ipad-2', shot: IPAD('32'), ...COPY.stations },
      { out: 'ios-ipad-3', shot: IPAD('39'), accent: '#FFCBA6', headline: COPY.track.headline, body: COPY.track.body },
      { out: 'ios-ipad-4', shot: IPAD('32'), ...COPY.hls },
    ],
  },
];

function pngSize(buf) {
  return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
}

// Width of a string incl. per-glyph tracking, for centring.
function measure(font, str, size, tracking) {
  let w = 0, n = 0;
  for (const ch of str) { w += font.getAdvanceWidth(ch, size); n++; }
  return w + tracking * Math.max(0, n - 1);
}

function centeredText(font, str, canvasW, baselineY, size, color, { tracking = 0, opacity = 1 } = {}) {
  let d = '', cx = (canvasW - measure(font, str, size, tracking)) / 2;
  for (const ch of str) {
    d += font.getPath(ch, cx, baselineY, size).toPathData(1);
    cx += font.getAdvanceWidth(ch, size) + tracking;
  }
  return `<path d="${d}" fill="${color}" fill-opacity="${opacity}"/>`;
}

function svgFor(dev, slide) {
  const { W, H } = dev;
  const shotBuf = readFileSync(join(SHOTS, slide.shot));
  const { w: sw, h: sh } = pngSize(shotBuf);

  // Fit the framed device into its box, preserving the screenshot's aspect.
  const box = dev.deviceBox;
  let screenW = box.maxW - 2 * dev.bezel;
  let screenH = Math.round(screenW * sh / sw);
  const maxScreenH = box.bottom - box.top - 2 * dev.bezel;
  if (screenH > maxScreenH) {
    screenH = maxScreenH;
    screenW = Math.round(screenH * sw / sh);
  }
  const devW = screenW + 2 * dev.bezel;
  const devH = screenH + 2 * dev.bezel;
  const devX = Math.round((W - devW) / 2);
  const devY = box.top;
  const devR = dev.screenRadius + dev.bezel;

  return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <defs>
    <radialGradient id="glow" cx="50%" cy="42%" r="80%">
      <stop offset="0%" stop-color="${slide.accent}" stop-opacity="0.20"/>
      <stop offset="55%" stop-color="${slide.accent}" stop-opacity="0.07"/>
      <stop offset="100%" stop-color="${slide.accent}" stop-opacity="0"/>
    </radialGradient>
    <pattern id="scan" width="6" height="6" patternUnits="userSpaceOnUse">
      <rect width="6" height="3" fill="#000000" fill-opacity="0.22"/>
    </pattern>
    <filter id="dglow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="38"/>
    </filter>
    <clipPath id="screen">
      <rect x="${devX + dev.bezel}" y="${devY + dev.bezel}" width="${screenW}" height="${screenH}" rx="${dev.screenRadius}"/>
    </clipPath>
  </defs>
  <rect width="${W}" height="${H}" fill="${FLAT_BG}"/>
  <rect width="${W}" height="${H}" fill="url(#glow)"/>
  <rect width="${W}" height="${H}" fill="url(#scan)"/>
  ${centeredText(UNSCII, 'NIGHTRIDE.FM PLAYER', W, dev.kickerY, 30, '#B9A9C4', { tracking: 6, opacity: 0.9 })}
  ${centeredText(UNSCII, slide.headline[0], W, dev.headY[0], dev.headSize, slide.accent, { tracking: 8 })}
  ${centeredText(UNSCII, slide.headline[1], W, dev.headY[1], dev.headSize, slide.accent, { tracking: 8 })}
  ${centeredText(ARIAL, slide.body, W, dev.bodyY, dev.bodySize, '#ECE6F0', { opacity: 0.88 })}
  <rect x="${devX}" y="${devY}" width="${devW}" height="${devH}" rx="${devR}" fill="${slide.accent}" fill-opacity="0.5" filter="url(#dglow)"/>
  <rect x="${devX}" y="${devY}" width="${devW}" height="${devH}" rx="${devR}" fill="#15101B" stroke="${slide.accent}" stroke-opacity="0.35" stroke-width="2"/>
  <image clip-path="url(#screen)" x="${devX + dev.bezel}" y="${devY + dev.bezel}" width="${screenW}" height="${screenH}" xlink:href="data:image/png;base64,${shotBuf.toString('base64')}"/>
</svg>`;
}

mkdirSync(OUT, { recursive: true });
const tmp = join(OUT, '_tmp.svg');
for (const dev of DEVICES) {
  for (const slide of dev.slides) {
    writeFileSync(tmp, svgFor(dev, slide));
    execFileSync('rsvg-convert', ['-w', String(dev.W), '-h', String(dev.H), '-o', join(OUT, `${slide.out}.png`), tmp]);
    console.log(`✓ ${slide.out}.png`);
  }
}
rmSync(tmp);
console.log(`\n8 slides → ${OUT}`);
