#!/usr/bin/env bash
# Generates the Xcode project from project.yml.
#
# Usage:
#   bash build.sh                                      # defaults
#   BUNDLE_ID=fm.nightride.ios.tomasz bash build.sh    # custom bundle id
#   DEVELOPMENT_TEAM=ABCDE12345 bash build.sh          # set team upfront
#
# After this, open Nightride.xcodeproj in Xcode and hit Run.
# See README.md for sideloading instructions.
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen not installed. Run: brew install xcodegen" >&2
    exit 1
fi

export BUNDLE_ID="${BUNDLE_ID:-fm.nightride.ios}"
export DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"

echo "→ generating Nightride.xcodeproj from project.yml…"
echo "    BUNDLE_ID=${BUNDLE_ID}"
echo "    DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM:-<pick in Xcode>}"
xcodegen generate --spec project.yml

echo "✓ Nightride.xcodeproj"
echo
echo "Next:"
echo "  1. open Nightride.xcodeproj"
echo "  2. Select the Nightride target → Signing & Capabilities"
echo "  3. Pick your Apple ID team. If the bundle id is taken,"
echo "     re-run with BUNDLE_ID=fm.nightride.ios.<yourname> bash build.sh"
echo "  4. Plug in your iPhone and hit Run."
