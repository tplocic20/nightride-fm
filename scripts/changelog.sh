#!/usr/bin/env bash
# Print the CHANGELOG.md section body for a version (default: Unreleased).
#
#   scripts/changelog.sh 0.5.1   # the notes under "## [0.5.1] - <date>"
#   scripts/changelog.sh         # the notes under "## [Unreleased]"
#
# Emits the section's lines with leading blank lines stripped. The release
# workflows feed this to the GitHub Release body and Google Play's whatsnew, so
# the changelog is the single source of truth. Matching is anchored on the exact
# "## [<ver>]" header (the closing bracket prevents 0.5.1 matching 0.5.10).
set -euo pipefail

VER="${1:-Unreleased}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CHANGELOG="$ROOT/CHANGELOG.md"
[[ -f "$CHANGELOG" ]] || { echo "no CHANGELOG.md at $CHANGELOG" >&2; exit 1; }

awk -v ver="$VER" '
  index($0, "## [" ver "]") == 1 { grab = 1; next }
  grab && /^## \[/ { exit }
  grab { print }
' "$CHANGELOG" | awk 'NF { seen = 1 } seen'
