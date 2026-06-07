#!/usr/bin/env bash
# Release script — bump the marketing version across macOS, iOS, and Android in
# lockstep, then commit, tag (vX.Y.Z) and push to main.
#
# The pushed tag triggers the store workflows (macos-dmg, macos-appstore,
# ios-appstore, android-playstore, android-apk), which build the TAGGED commit. Because the bump happens BEFORE
# the tag, the tagged commit already carries the right version everywhere — the
# repo is the single source of truth, no post-tag sync.
#
# What it touches (marketing / user-visible version only):
#   macOS    macos/App/Info.plist           CFBundleShortVersionString
#   iOS      ios/project.yml                MARKETING_VERSION
#   Android  android/app/build.gradle.kts   versionName  (+ versionCode, derived)
#
# Build NUMBERS are deliberately left alone: iOS/macOS get theirs from CI (the
# GitHub run number, monotonic per upload); Android's integer versionCode is
# derived from the version here (major*1e6 + minor*1e3 + patch) so it's unique
# and increasing without a second counter to manage.
#
# Usage:
#   bash scripts/release.sh 0.2.0            # bump -> commit -> tag -> push
#   bash scripts/release.sh 0.2.0 --dry-run  # show the plan, write nothing
#   bash scripts/release.sh 0.2.0 --yes      # skip the confirmation prompt (CI)
#
# Rules enforced before anything is written:
#   - <version> is a plain semver x.y.z (no pre-release / build metadata)
#   - <version> is STRICTLY GREATER than the current macOS version (canonical)
#   - you are on a clean `main`, up to date with origin/main
#   - the tag vX.Y.Z does not already exist (locally or on origin)
set -euo pipefail

# --- colors ------------------------------------------------------------------
if [[ -t 1 ]]; then
  RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; DIM=$'\033[2m'; BLD=$'\033[1m'; RST=$'\033[0m'
else
  RED=; GRN=; YEL=; DIM=; BLD=; RST=
fi
die() { echo "${RED}✗ $*${RST}" >&2; exit 1; }

REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "$REPO"

MAC_PLIST="macos/App/Info.plist"
IOS_YML="ios/project.yml"
ANDROID_GRADLE="android/app/build.gradle.kts"
for f in "$MAC_PLIST" "$IOS_YML" "$ANDROID_GRADLE"; do
  [[ -f "$f" ]] || die "expected file not found: $f"
done

# --- parse args --------------------------------------------------------------
TARGET=""; DRY=0; YES=0
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRY=1 ;;
    --yes|-y)     YES=1 ;;
    -*)           die "unknown flag: $a" ;;
    *)            [[ -z "$TARGET" ]] && TARGET="$a" || die "unexpected extra argument: $a" ;;
  esac
done
[[ -n "$TARGET" ]] || die "Usage: bash scripts/release.sh <x.y.z> [--dry-run] [--yes]"

[[ "$TARGET" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] \
  || die "\"$TARGET\" is not a plain semver x.y.z (e.g. 0.2.0)."
T_MAJ=${BASH_REMATCH[1]}; T_MIN=${BASH_REMATCH[2]}; T_PAT=${BASH_REMATCH[3]}
TAG="v$TARGET"

# --- read current versions ---------------------------------------------------
read_mac()     { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MAC_PLIST" 2>/dev/null; }
read_ios()     { grep -E 'MARKETING_VERSION:' "$IOS_YML" | head -1 | sed -E 's/.*"([^"]*)".*/\1/'; }
read_android() { grep -E 'versionName[[:space:]]*=' "$ANDROID_GRADLE" | head -1 | sed -E 's/.*"([^"]*)".*/\1/'; }
read_android_code() { grep -E 'versionCode[[:space:]]*=' "$ANDROID_GRADLE" | head -1 | sed -E 's/[^0-9]//g'; }

CUR_MAC="$(read_mac)";     [[ -n "$CUR_MAC" ]]     || die "could not read CFBundleShortVersionString from $MAC_PLIST"
CUR_IOS="$(read_ios)";     [[ -n "$CUR_IOS" ]]     || die "could not read MARKETING_VERSION from $IOS_YML"
CUR_ANDROID="$(read_android)"; [[ -n "$CUR_ANDROID" ]] || die "could not read versionName from $ANDROID_GRADLE"
CUR_CODE="$(read_android_code)"; CUR_CODE="${CUR_CODE:-0}"

# macOS plist is canonical for the strictly-greater check; the others are forced
# into lockstep and any mismatch is reported as drift (like the original tool).
ver_gt() { # 0 if $1 > $2 (lenient: missing components = 0)
  local -a A B; local IFS=. i x y
  read -r -a A <<<"$1"; read -r -a B <<<"$2"
  for i in 0 1 2; do
    x=$((10#${A[i]:-0})); y=$((10#${B[i]:-0}))
    if (( x > y )); then return 0; fi
    if (( x < y )); then return 1; fi
  done
  return 1
}
ver_gt "$TARGET" "$CUR_MAC" \
  || die "new version $TARGET must be strictly greater than current $CUR_MAC ($MAC_PLIST)."

# Android versionCode, derived from the semver so it's monotonic with no 2nd knob.
NEW_CODE=$(( 10#$T_MAJ * 1000000 + 10#$T_MIN * 1000 + 10#$T_PAT ))

# --- show the plan -----------------------------------------------------------
echo "${BLD}Release ${CUR_MAC} ${DIM}→${RST} ${GRN}${TARGET}${RST}"
echo "  ${DIM}commit \"chore(release): ${TAG}\", tag ${TAG}, push origin main + ${TAG}${RST}"
echo "    ${DIM}${MAC_PLIST}${RST}              CFBundleShortVersionString → ${TARGET}"
echo "    ${DIM}${IOS_YML}${RST}                 MARKETING_VERSION → ${TARGET}"
echo "    ${DIM}${ANDROID_GRADLE}${RST}  versionName → ${TARGET}, versionCode ${CUR_CODE} → ${NEW_CODE}"
[[ -f CHANGELOG.md ]] && grep -q '^## \[Unreleased\]' CHANGELOG.md \
  && echo "    ${DIM}CHANGELOG.md${RST}              [Unreleased] → [${TARGET}] - $(date +%Y-%m-%d)"

drift=()
[[ "$CUR_IOS"     != "$CUR_MAC" ]] && drift+=("${IOS_YML} = ${CUR_IOS}")
[[ "$CUR_ANDROID" != "$CUR_MAC" ]] && drift+=("${ANDROID_GRADLE} = ${CUR_ANDROID}")
if (( ${#drift[@]} )); then
  echo "  ${YEL}⚠ not currently at ${CUR_MAC} (will be set to ${TARGET} anyway):${RST}"
  for d in "${drift[@]}"; do echo "    ${YEL}${d}${RST}"; done
fi
if (( NEW_CODE <= CUR_CODE )); then
  echo "  ${YEL}⚠ Android versionCode ${NEW_CODE} is not greater than current ${CUR_CODE} — Play Store would reject it.${RST}"
fi

if (( DRY )); then
  echo "${YEL}Dry run — nothing written.${RST}"
  exit 0
fi

# --- git preconditions (real runs only) --------------------------------------
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$BRANCH" == "main" ]] || die "releases must be cut from \"main\" (you are on \"$BRANCH\")."

DIRTY="$(git status --porcelain)"
[[ -z "$DIRTY" ]] || die "working tree is not clean — commit or stash first:"$'\n'"$DIRTY"

[[ -z "$(git tag --list "$TAG")" ]] || die "tag $TAG already exists locally."
[[ -z "$(git ls-remote --tags origin "$TAG" 2>/dev/null)" ]] || die "tag $TAG already exists on origin."

git fetch --quiet origin main 2>/dev/null || true
BEHIND="$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"
[[ "$BEHIND" == "0" ]] || die "local main is $BEHIND commit(s) behind origin/main — pull first."

if (( ! YES )); then
  read -r -p "${BLD}Proceed?${RST} (y/N) " ans
  [[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]] || die "aborted."
fi

# --- apply -------------------------------------------------------------------
sed_inplace() { # portable in-place sed (BSD/macOS)
  sed -E -i '' "$1" "$2"
}

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${TARGET}" "$MAC_PLIST"
sed_inplace "s/(MARKETING_VERSION:[[:space:]]*\")[^\"]*(\")/\1${TARGET}\2/" "$IOS_YML"
sed_inplace "s/(versionName[[:space:]]*=[[:space:]]*\")[^\"]*(\")/\1${TARGET}\2/" "$ANDROID_GRADLE"
sed_inplace "s/(versionCode[[:space:]]*=[[:space:]]*)[0-9]+/\1${NEW_CODE}/" "$ANDROID_GRADLE"

# Verify every edit actually landed (guards against a future format change that
# silently no-ops the regex).
[[ "$(read_mac)"          == "$TARGET"   ]] || die "failed to update $MAC_PLIST"
[[ "$(read_ios)"          == "$TARGET"   ]] || die "failed to update $IOS_YML"
[[ "$(read_android)"      == "$TARGET"   ]] || die "failed to update $ANDROID_GRADLE (versionName)"
[[ "$(read_android_code)" == "$NEW_CODE" ]] || die "failed to update $ANDROID_GRADLE (versionCode)"

# Stamp the changelog: turn the top "## [Unreleased]" into this version + date,
# leaving a fresh empty [Unreleased] above it (Keep a Changelog). The tagged
# commit then carries the notes CI publishes to the GitHub Release and Play.
if [[ -f "CHANGELOG.md" ]] && grep -q '^## \[Unreleased\]' "CHANGELOG.md"; then
  awk -v ver="$TARGET" -v date="$(date +%Y-%m-%d)" '
    !done && /^## \[Unreleased\]/ {
      print "## [Unreleased]"; print ""; print "## [" ver "] - " date
      done = 1; next
    }
    { print }
  ' "CHANGELOG.md" > "CHANGELOG.md.tmp" && mv "CHANGELOG.md.tmp" "CHANGELOG.md"
  git add "CHANGELOG.md"
fi

git add "$MAC_PLIST" "$IOS_YML" "$ANDROID_GRADLE"
git commit -q -m "chore(release): ${TAG}"
git tag -a "$TAG" -m "Release ${TAG}"

if ! git push origin main; then
  die "push of main failed — your commit and tag exist locally. Fix the cause, then:
  git push origin main && git push origin ${TAG}
Or undo entirely:
  git tag -d ${TAG} && git reset --hard HEAD~1"
fi
if ! git push origin "$TAG"; then
  die "main pushed, but pushing the tag failed. Retry:
  git push origin ${TAG}"
fi

echo "${GRN}✓ Released ${TAG}${RST}"
echo "${DIM}macos-dmg, macos-appstore, ios-appstore, android-playstore and android-apk will build the tagged commit.${RST}"
echo "${DIM}DMG + APK → GitHub Release; Apple builds → App Store Connect (TestFlight); Android → Play internal track.${RST}"
