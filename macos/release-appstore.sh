#!/usr/bin/env bash
# Build, sandbox-sign, package, and upload Nightride.app to the MAC APP STORE.
#
# This is the App Store counterpart to release.sh (which produces a notarized
# Developer-ID .dmg for direct download). The compiled binary is identical; only
# the signing/packaging/delivery differs:
#   release.sh           → Developer ID  + Hardened Runtime → notarize → .dmg → GitHub Release
#   release-appstore.sh  → Apple Distribution + App Sandbox → .pkg → App Store Connect
#
# Like release.sh, every Apple-account-dependent step is GATED with a clear
# message, so a missing cert/profile/key stops the run instead of producing a
# half-baked artifact.
#
# Prerequisites (one-time — see DEPLOYMENT.md for the full walkthrough):
#   1. An "Apple Distribution" certificate + its private key in the keychain.
#   2. A "3rd Party Mac Developer Installer" (a.k.a. "Mac Installer Distribution")
#      certificate + key in the keychain (signs the .pkg installer).
#   3. A "Mac App Store" distribution provisioning profile for the bundle id
#      dev.plocic.nightride.mac. Point PROVISION_PROFILE at the .provisionprofile
#      (default: App/Nightride.provisionprofile).
#   4. An App Store Connect API key (.p8) saved as
#        ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
#      plus its ASC_KEY_ID and ASC_ISSUER_ID, for the upload step.
#   5. The app record must already exist in App Store Connect.
#
# Usage:
#   bash release-appstore.sh             # build → sign → pkg → upload
#   SIGN_ONLY=1 bash release-appstore.sh # build → sign only (skip pkg/upload)
#
# Override defaults via env:
#   MAS_APP_IDENTITY="Apple Distribution: Your Name (TEAMID)"
#   MAS_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Your Name (TEAMID)"
#   PROVISION_PROFILE="/path/to/Nightride.provisionprofile"
#   ASC_KEY_ID="XXXXXXXXXX"   ASC_ISSUER_ID="xxxxxxxx-xxxx-..."
#   MARKETING_VERSION="0.2.0" BUILD_NUMBER="42"   # stamped into Info.plist
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Nightride.app"
BIN_DIR="${APP}/Contents/MacOS"
RES_DIR="${APP}/Contents/Resources"
ENTITLEMENTS="App/Nightride.appstore.entitlements"
PKG="build/Nightride.pkg"
PROVISION_PROFILE="${PROVISION_PROFILE:-App/Nightride.provisionprofile}"

# --- 0. Resolve signing identities ------------------------------------------
# Auto-pick from the keychain unless the identity is pinned via env (CI pins it).
if [[ -z "${MAS_APP_IDENTITY:-}" ]]; then
  MAS_APP_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Apple Distribution" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"
fi
if [[ -z "${MAS_APP_IDENTITY:-}" ]]; then
  cat <<'MSG'
✗ No "Apple Distribution" certificate found.

  The App Store build signs the .app with an Apple Distribution identity
  (distinct from the Developer ID cert used by release.sh). Create it via
    Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Apple Distribution
  or developer.apple.com/account, then re-run. See DEPLOYMENT.md.
MSG
  exit 1
fi

if [[ -z "${MAS_INSTALLER_IDENTITY:-}" ]]; then
  # Installer identities aren't listed under -p codesigning; search all.
  MAS_INSTALLER_IDENTITY="$(security find-identity -v 2>/dev/null \
    | grep -E "3rd Party Mac Developer Installer|Mac Installer Distribution" \
    | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"
fi
if [[ -z "${MAS_INSTALLER_IDENTITY:-}" ]]; then
  cat <<'MSG'
✗ No "Mac Installer Distribution" certificate found.

  The .pkg installer must be signed with a "3rd Party Mac Developer Installer"
  (a.k.a. "Mac Installer Distribution") certificate. Create it alongside the
  Apple Distribution cert, then re-run. See DEPLOYMENT.md.
MSG
  exit 1
fi

if [[ ! -f "${PROVISION_PROFILE}" ]]; then
  cat <<MSG
✗ Provisioning profile not found at: ${PROVISION_PROFILE}

  Download a "Mac App Store" distribution profile for dev.plocic.nightride.mac
  from developer.apple.com/account and save it there, or set PROVISION_PROFILE.
  See DEPLOYMENT.md.
MSG
  exit 1
fi

echo "→ app identity:       ${MAS_APP_IDENTITY}"
echo "→ installer identity: ${MAS_INSTALLER_IDENTITY}"
echo "→ provisioning:       ${PROVISION_PROFILE}"

# --- 1. Build + assemble the bundle (same layout as release.sh) -------------
echo "→ building Swift target (release)…"
swift build -c release --arch arm64

echo "→ assembling ${APP}…"
rm -rf "${APP}"
mkdir -p "${BIN_DIR}" "${RES_DIR}"
cp ".build/arm64-apple-macosx/release/Nightride" "${BIN_DIR}/Nightride"
cp "App/Info.plist" "${APP}/Contents/Info.plist"
cp ../assets/artwork/*.png "${RES_DIR}/" 2>/dev/null || echo "  (no artwork — run: cd assets && node generate.mjs)"
cp "App/Nightride.icns" "${RES_DIR}/Nightride.icns" 2>/dev/null || echo "  (no icon — run: cd assets && node icon.mjs)"

# Stamp the version into the bundle's Info.plist (same as release.sh). The
# App Store REQUIRES a monotonically increasing CFBundleVersion per upload —
# CI feeds BUILD_NUMBER from the run number.
PLIST="${APP}/Contents/Info.plist"
if [[ -n "${MARKETING_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${MARKETING_VERSION}" "${PLIST}"
  echo "→ marketing version: ${MARKETING_VERSION}"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${PLIST}"
  echo "→ build number: ${BUILD_NUMBER}"
fi

# --- 2. Embed the provisioning profile --------------------------------------
echo "→ embedding provisioning profile…"
cp "${PROVISION_PROFILE}" "${APP}/Contents/embedded.provisionprofile"

# --- 3. Sign with Apple Distribution + the App Sandbox entitlements ----------
# No --deep (deprecated; there is no nested code anyway). Hardened Runtime is
# enabled to match Xcode's modern App Store archives; the sandbox entitlement is
# the mandatory part for the store.
echo "→ codesigning (Apple Distribution + sandbox)…"
codesign --force --timestamp --options runtime \
  --entitlements "${ENTITLEMENTS}" \
  --sign "${MAS_APP_IDENTITY}" "${APP}"

echo "→ verifying signature…"
codesign --verify --strict --verbose=2 "${APP}"

if [[ "${SIGN_ONLY:-0}" == "1" ]]; then
  echo "✓ signed (SIGN_ONLY) → ${APP}"
  echo "→ inspect entitlements: codesign -d --entitlements - ${APP}"
  exit 0
fi

# --- 4. Build the signed installer .pkg -------------------------------------
echo "→ building ${PKG}…"
rm -f "${PKG}"
productbuild --component "${APP}" /Applications \
  --sign "${MAS_INSTALLER_IDENTITY}" "${PKG}"

# --- 5. Upload to App Store Connect -----------------------------------------
# Requires the App Store Connect API key. altool finds the .p8 automatically at
# ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8.
if [[ -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" ]]; then
  cat <<MSG
✗ App Store Connect API credentials missing.

  The .pkg is built and signed at ${PKG}. To upload it, set:
    ASC_KEY_ID, ASC_ISSUER_ID
  and place the key at ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8,
  then re-run. See DEPLOYMENT.md.
MSG
  exit 1
fi

echo "→ validating with App Store Connect…"
xcrun altool --validate-app -f "${PKG}" -t macos \
  --apiKey "${ASC_KEY_ID}" --apiIssuer "${ASC_ISSUER_ID}"

echo "→ uploading to App Store Connect (this can take a few minutes)…"
xcrun altool --upload-app -f "${PKG}" -t macos \
  --apiKey "${ASC_KEY_ID}" --apiIssuer "${ASC_ISSUER_ID}"

echo
echo "✓ uploaded ${PKG} to App Store Connect."
echo "→ It will appear under the app's macOS builds after processing."
echo "→ Add metadata/screenshots and click Submit for Review in App Store Connect."
