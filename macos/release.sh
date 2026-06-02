#!/usr/bin/env bash
# Build, Developer-ID sign, notarize, staple, and package Nightride.app into a
# distributable .dmg for DIRECT DOWNLOAD (not the Mac App Store).
#
# This is the release counterpart to build.sh (which only ad-hoc signs for local
# use). Every Apple-account-dependent step is GATED: until your Apple Developer
# Program is active and credentials are in place, the script stops with a clear
# message instead of producing a half-signed artifact.
#
# Prerequisites (one-time, once the Developer Program activates):
#   1. A "Developer ID Application" certificate in your login keychain.
#        Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Developer ID
#        Application — or download from developer.apple.com/account.
#        Verify with:  security find-identity -v -p codesigning
#   2. A notarytool credential profile stored in the keychain:
#        xcrun notarytool store-credentials nightride-notary \
#          --apple-id "hello@plocic.dev" \
#          --team-id "<YOUR_TEAM_ID>" \
#          --password "<APP_SPECIFIC_PASSWORD>"   # appleid.apple.com ▸ App-Specific Passwords
#
# Usage:
#   bash release.sh                 # build → sign → notarize → staple → dmg
#   SIGN_ONLY=1 bash release.sh     # build → sign only (skip notarize/dmg)
#
# Override the defaults via env:
#   DEV_ID_APP="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE="nightride-notary"
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Nightride.app"
BIN_DIR="${APP}/Contents/MacOS"
RES_DIR="${APP}/Contents/Resources"
ENTITLEMENTS="App/Nightride.entitlements"
DMG="build/Nightride.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-nightride-notary}"

# --- 0. Resolve the Developer ID Application identity ------------------------
# Auto-pick the first "Developer ID Application" identity unless DEV_ID_APP is set.
if [[ -z "${DEV_ID_APP:-}" ]]; then
  # `|| true` so a no-match grep doesn't trip `set -e` before the check below.
  DEV_ID_APP="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 \
    | sed -E 's/.*"(.*)"/\1/' || true)"
fi
if [[ -z "${DEV_ID_APP:-}" ]]; then
  cat <<'MSG'
✗ No "Developer ID Application" certificate found.

  This is expected until your Apple Developer Program membership is active.
  You currently only have an "Apple Development" cert (local dev only), which
  CANNOT be used for distribution.

  Once the Program activates:
    Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Developer ID Application
  then re-run this script. (See the header of this file for full setup.)

  For a local, unsigned test build use:  bash build.sh
MSG
  exit 1
fi
echo "→ signing identity: ${DEV_ID_APP}"

# --- 1. Build + assemble the bundle (same layout as build.sh) ---------------
echo "→ building Swift target (release)…"
swift build -c release --arch arm64

echo "→ assembling ${APP}…"
rm -rf "${APP}"
mkdir -p "${BIN_DIR}" "${RES_DIR}"
cp ".build/arm64-apple-macosx/release/Nightride" "${BIN_DIR}/Nightride"
cp "App/Info.plist" "${APP}/Contents/Info.plist"
cp ../assets/artwork/*.png "${RES_DIR}/" 2>/dev/null || echo "  (no artwork — run: cd assets && bun run build)"
cp "App/Nightride.icns" "${RES_DIR}/Nightride.icns" 2>/dev/null || echo "  (no icon — run: cd assets && node icon.mjs)"

# --- 2. Developer-ID sign with Hardened Runtime -----------------------------
# --options runtime enables the Hardened Runtime (required for notarization);
# --timestamp adds a secure timestamp (also required). Deep-sign so any nested
# code is covered.
echo "→ codesigning (Developer ID + hardened runtime)…"
codesign --force --deep --options runtime --timestamp \
  --entitlements "${ENTITLEMENTS}" \
  --sign "${DEV_ID_APP}" "${APP}"

echo "→ verifying signature…"
codesign --verify --strict --verbose=2 "${APP}"

if [[ "${SIGN_ONLY:-0}" == "1" ]]; then
  echo "✓ signed (SIGN_ONLY) → ${APP}"
  exit 0
fi

# --- 3. Notarize ------------------------------------------------------------
# Notarization requires a zip (or dmg/pkg) of the app. We submit a zip, wait,
# then staple the ticket to the .app and package the .dmg from the stapled app.
if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
  cat <<MSG
✗ notarytool credential profile "${NOTARY_PROFILE}" not found.

  Store it once (after the Developer Program is active):
    xcrun notarytool store-credentials ${NOTARY_PROFILE} \\
      --apple-id "hello@plocic.dev" \\
      --team-id "<YOUR_TEAM_ID>" \\
      --password "<APP_SPECIFIC_PASSWORD>"

  The app is already signed at ${APP}; re-run to notarize + package.
MSG
  exit 1
fi

ZIP="build/Nightride-notarize.zip"
echo "→ zipping for notarization…"
ditto -c -k --keepParent "${APP}" "${ZIP}"

echo "→ submitting to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "${ZIP}" --keychain-profile "${NOTARY_PROFILE}" --wait

echo "→ stapling ticket…"
xcrun stapler staple "${APP}"
rm -f "${ZIP}"

# --- 4. Package the .dmg ----------------------------------------------------
echo "→ building ${DMG}…"
rm -f "${DMG}"
STAGE="build/dmg-stage"
rm -rf "${STAGE}"; mkdir -p "${STAGE}"
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"   # drag-to-install affordance
hdiutil create -volname "Nightride" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}"
rm -rf "${STAGE}"

# Sign + staple the dmg too, so the download itself is trusted.
codesign --force --sign "${DEV_ID_APP}" --timestamp "${DMG}"
xcrun stapler staple "${DMG}" 2>/dev/null || echo "  (dmg staple skipped — app ticket already stapled)"

echo
echo "✓ ${DMG}"
echo "→ verify Gatekeeper acceptance:  spctl -a -vvv --type install ${DMG}"
echo "→ and the app itself:            spctl -a -vvv ${APP}"
