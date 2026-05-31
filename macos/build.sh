#!/usr/bin/env bash
# Build Nightride.app out of the SwiftPM target.
#
# We compile a plain executable with `swift build`, then assemble the .app
# bundle by hand (Info.plist + binary in Contents/MacOS) and ad-hoc codesign.
# That keeps the project Xcode-project-free and reproducible from the CLI.
set -euo pipefail

cd "$(dirname "$0")"

APP="build/Nightride.app"
BIN_DIR="${APP}/Contents/MacOS"
RES_DIR="${APP}/Contents/Resources"

echo "→ building Swift target (release)…"
swift build -c release --arch arm64

echo "→ assembling ${APP}…"
rm -rf "${APP}"
mkdir -p "${BIN_DIR}" "${RES_DIR}"
cp ".build/arm64-apple-macosx/release/Nightride" "${BIN_DIR}/Nightride"
cp "App/Info.plist" "${APP}/Contents/Info.plist"

# Shared per-station cover art (generated in /assets) → bundle Resources.
cp ../assets/artwork/*.png "${RES_DIR}/" 2>/dev/null || echo "  (no artwork — run: cd assets && bun run build)"

echo "→ ad-hoc codesigning…"
codesign --force --sign - --timestamp=none "${APP}"

echo "✓ ${APP}"
echo
echo "Run:    open ${APP}"
echo "Or:     ${BIN_DIR}/Nightride"
