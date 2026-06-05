#!/usr/bin/env bash
# Build, sign, package, and upload Nightride.app to the iOS APP STORE.
#
# This is the iOS counterpart to macos/release-appstore.sh. The shape is the
# same — build → sign with an Apple Distribution identity → package → upload to
# App Store Connect — but iOS goes through Xcode rather than SwiftPM:
#   xcodegen generate            (the .xcodeproj is gitignored, like local builds)
#   xcodebuild … archive         → build/Nightride.xcarchive
#   xcodebuild -exportArchive     → build/export/Nightride.ipa  (manual signing)
#   xcrun altool --upload-app     → App Store Connect
#
# Signing is MANUAL: the Apple Distribution cert lives in the keychain and the
# App Store provisioning profile is read straight from disk — its UUID, Name,
# and Team are extracted here, so the only thing you point this script at is the
# .mobileprovision file. (The everyday Xcode/sideload flow stays on Automatic
# signing; that's untouched in project.yml.)
#
# Like the macOS script, every Apple-account-dependent step is GATED with a
# clear message, so a missing cert/profile/key stops the run instead of
# producing a half-baked artifact.
#
# Prerequisites (one-time — see DEPLOYMENT.md for the full walkthrough):
#   1. An "Apple Distribution" certificate + its private key in the keychain.
#      (The SAME cert used by the macOS App Store build — it's account-wide.)
#   2. An "App Store" distribution provisioning profile for the bundle id
#      dev.plocic.nightride. Point PROVISION_PROFILE at the
#      .mobileprovision (default: App/Nightride.mobileprovision).
#   3. An App Store Connect API key (.p8) saved as
#        ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
#      plus its ASC_KEY_ID and ASC_ISSUER_ID, for the upload step.
#   4. The app record must already exist in App Store Connect.
#
# Usage:
#   bash release-appstore.sh             # build → sign → ipa → upload
#   SIGN_ONLY=1 bash release-appstore.sh # build → signed .ipa only (skip upload)
#
# Override defaults via env:
#   IOS_APP_IDENTITY="Apple Distribution: Your Name (TEAMID)"  # else auto-detected
#   PROVISION_PROFILE="/path/to/Nightride.mobileprovision"
#   BUNDLE_ID="dev.plocic.nightride"
#   ASC_KEY_ID="XXXXXXXXXX"   ASC_ISSUER_ID="xxxxxxxx-xxxx-..."
#   MARKETING_VERSION="0.2.0" BUILD_NUMBER="42"   # stamped into the build
#   CARPLAY=1                                     # sign with carplay-audio (paid + granted)
#   EXPORT_METHOD="app-store-connect"             # Xcode 15.4+; use "app-store" on older Xcode
set -euo pipefail
cd "$(dirname "$0")"

ARCHIVE="build/Nightride.xcarchive"
EXPORT_DIR="build/export"
IPA="${EXPORT_DIR}/Nightride.ipa"
BUNDLE_ID="${BUNDLE_ID:-dev.plocic.nightride}"
PROVISION_PROFILE="${PROVISION_PROFILE:-App/Nightride.mobileprovision}"
# Xcode 15.4+ renamed the App Store export method to "app-store-connect" and
# newer Xcode dropped the old "app-store" name. Default to the new one; override
# with EXPORT_METHOD=app-store on Xcode older than 15.4.
EXPORT_METHOD="${EXPORT_METHOD:-app-store-connect}"

# --- 0. Tooling -------------------------------------------------------------
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "✗ xcodegen not installed. Run: brew install xcodegen" >&2
  exit 1
fi

# --- 1. Resolve signing identity --------------------------------------------
# Auto-pick from the keychain unless pinned via env (CI pins it).
if [[ -z "${IOS_APP_IDENTITY:-}" ]]; then
  IOS_APP_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Apple Distribution" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"
fi
if [[ -z "${IOS_APP_IDENTITY:-}" ]]; then
  cat <<'MSG'
✗ No "Apple Distribution" certificate found.

  The App Store build signs the app with an Apple Distribution identity. This is
  the same cert the macOS App Store build uses (it's account-wide). Create it via
    Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Apple Distribution
  or developer.apple.com/account, then re-run. See DEPLOYMENT.md.
MSG
  exit 1
fi

# --- 2. Read the provisioning profile ---------------------------------------
if [[ ! -f "${PROVISION_PROFILE}" ]]; then
  cat <<MSG
✗ Provisioning profile not found at: ${PROVISION_PROFILE}

  Download an "App Store" distribution profile for ${BUNDLE_ID} from
  developer.apple.com/account and save it there, or set PROVISION_PROFILE.
  See DEPLOYMENT.md.
MSG
  exit 1
fi

# A .mobileprovision is a CMS-signed plist; decode it to read UUID/Name/Team.
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
security cms -D -i "${PROVISION_PROFILE}" > "${TMP}/profile.plist" 2>/dev/null
PROFILE_UUID="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "${TMP}/profile.plist")"
PROFILE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :Name' "${TMP}/profile.plist")"
TEAM_ID="${DEVELOPMENT_TEAM:-$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "${TMP}/profile.plist")}"

# Xcode looks up profiles by UUID under this directory.
PROFILES_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
mkdir -p "${PROFILES_DIR}"
cp "${PROVISION_PROFILE}" "${PROFILES_DIR}/${PROFILE_UUID}.mobileprovision"

echo "→ app identity:   ${IOS_APP_IDENTITY}"
echo "→ provisioning:   ${PROFILE_NAME}  (${PROFILE_UUID})"
echo "→ team:           ${TEAM_ID}"
echo "→ bundle id:      ${BUNDLE_ID}"

# --- 3. Generate the Xcode project ------------------------------------------
# CarPlay's com.apple.developer.carplay-audio is a restricted entitlement Apple
# grants on request; default to the empty entitlements so the build signs
# against any App Store profile. Set CARPLAY=1 once it's granted AND the profile
# carries the capability. (Mirrors build.sh.)
if [[ "${CARPLAY:-0}" == "1" ]]; then
  export ENTITLEMENTS="App/Nightride.carplay.entitlements"
else
  export ENTITLEMENTS="App/Nightride.entitlements"
fi
export BUNDLE_ID DEVELOPMENT_TEAM="${TEAM_ID}"

echo "→ generating Nightride.xcodeproj (ENTITLEMENTS=${ENTITLEMENTS})…"
xcodegen generate --spec project.yml

# --- 4. Archive -------------------------------------------------------------
# Override the project's Automatic/Apple-Development signing with manual
# Apple-Distribution signing for the release. Command-line build settings take
# precedence over project.yml, so the day-to-day Xcode flow is unaffected.
echo "→ archiving (release, manual Apple Distribution signing)…"
rm -rf "${ARCHIVE}" "${EXPORT_DIR}"
ARCHIVE_ARGS=(
  -project Nightride.xcodeproj
  -scheme Nightride
  -configuration Release
  -destination 'generic/platform=iOS'
  -archivePath "${ARCHIVE}"
  archive
  DEVELOPMENT_TEAM="${TEAM_ID}"
  PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID}"
  CODE_SIGN_STYLE=Manual
  CODE_SIGN_IDENTITY="${IOS_APP_IDENTITY}"
  PROVISIONING_PROFILE_SPECIFIER="${PROFILE_NAME}"
)
# The App Store requires a monotonically increasing build number per upload —
# CI feeds BUILD_NUMBER from the run number. Only override when provided so a
# bare local run keeps project.yml's values.
[[ -n "${MARKETING_VERSION:-}" ]] && ARCHIVE_ARGS+=(MARKETING_VERSION="${MARKETING_VERSION}") && echo "→ marketing version: ${MARKETING_VERSION}"
[[ -n "${BUILD_NUMBER:-}" ]] && ARCHIVE_ARGS+=(CURRENT_PROJECT_VERSION="${BUILD_NUMBER}") && echo "→ build number: ${BUILD_NUMBER}"
xcodebuild "${ARCHIVE_ARGS[@]}"

# --- 5. Export the signed .ipa ----------------------------------------------
echo "→ exporting signed .ipa…"
cat > "${TMP}/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>${EXPORT_METHOD}</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>${BUNDLE_ID}</key>
    <string>${PROFILE_NAME}</string>
  </dict>
  <key>uploadSymbols</key><true/>
  <key>stripSwiftSymbols</key><true/>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE}" \
  -exportPath "${EXPORT_DIR}" \
  -exportOptionsPlist "${TMP}/ExportOptions.plist"

if [[ ! -f "${IPA}" ]]; then
  # Some Xcode versions name the .ipa after the scheme; find whatever was made.
  IPA="$(ls "${EXPORT_DIR}"/*.ipa 2>/dev/null | head -1 || true)"
fi
[[ -z "${IPA}" || ! -f "${IPA}" ]] && { echo "✗ export produced no .ipa in ${EXPORT_DIR}"; exit 1; }

if [[ "${SIGN_ONLY:-0}" == "1" ]]; then
  echo "✓ signed (SIGN_ONLY) → ${IPA}"
  exit 0
fi

# --- 6. Upload to App Store Connect -----------------------------------------
# altool finds the .p8 automatically at
# ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8.
if [[ -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" ]]; then
  cat <<MSG
✗ App Store Connect API credentials missing.

  The signed .ipa is built at ${IPA}. To upload it, set:
    ASC_KEY_ID, ASC_ISSUER_ID
  and place the key at ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8,
  then re-run. See DEPLOYMENT.md.
MSG
  exit 1
fi

echo "→ validating with App Store Connect…"
xcrun altool --validate-app -f "${IPA}" -t ios \
  --apiKey "${ASC_KEY_ID}" --apiIssuer "${ASC_ISSUER_ID}"

echo "→ uploading to App Store Connect (this can take a few minutes)…"
xcrun altool --upload-app -f "${IPA}" -t ios \
  --apiKey "${ASC_KEY_ID}" --apiIssuer "${ASC_ISSUER_ID}"

echo
echo "✓ uploaded ${IPA} to App Store Connect."
echo "→ It will appear under the app's iOS builds (TestFlight) after processing."
echo "→ Add metadata/screenshots and click Submit for Review in App Store Connect."
