#!/usr/bin/env bash
# Table-driven test for scripts/release.sh. Runs ONLY inside a throwaway clone
# whose origin is a throwaway bare repo, so nothing real is committed/tagged/pushed.
# Usage: bash scripts/test-release.sh
set -uo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# Throwaway origin + working clone seeded from the real repo's HEAD tree.
git clone -q --bare "$SRC" "$T/origin.git"
git clone -q "$T/origin.git" "$T/work"
cd "$T/work"
git config user.email t@t; git config user.name t
git checkout -q main 2>/dev/null || git checkout -q -b main
CUR="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' macos/App/Info.plist)"

pass=0; fail=0
# check <name> <expect: ok|fail> <output-substring> <args...>   (dry-run, no writes)
check() {
  local name=$1 want=$2 sub=$3; shift 3
  local out rc; out="$(bash scripts/release.sh "$@" 2>&1)"; rc=$?
  local got=ok; ((rc)) && got=fail
  if [[ $got == "$want" && $out == *"$sub"* ]]; then pass=$((pass+1)); echo "PASS $name"
  else fail=$((fail+1)); echo "FAIL $name (rc=$rc want=$want sub='$sub')"; echo "$out" | sed 's/^/    /'; fi
}

# name | want | output substring | version
while IFS='|' read -r name want sub ver; do
  check "$name" "$want" "$sub" "$ver" --dry-run
done <<EOF2
reject 1.2|fail|not a plain semver|1.2
reject prerelease|fail|not a plain semver|1.2.3-beta
reject v-prefix|fail|not a plain semver|v1.2.3
reject equal|fail|strictly greater|$CUR
reject downgrade|fail|strictly greater|0.0.1
numeric not lexical 10.0.0|ok|→ 10000000|10.0.0
accept 1.99.99 -> code|ok|→ 1099099|1.99.99
accept 2.0.0 -> code|ok|→ 2000000|2.0.0
EOF2


# Real run in the throwaway clone: files bumped, tag created, pushed to throwaway origin.
if bash scripts/release.sh 10.0.0 --yes >/dev/null 2>&1 \
   && grep -q 'versionCode = 10000000' android/app/build.gradle.kts \
   && grep -q 'versionName = "10.0.0"' android/app/build.gradle.kts \
   && grep -q 'MARKETING_VERSION: "10.0.0"' ios/project.yml \
   && git -C "$T/origin.git" tag --list v10.0.0 | grep -q v10.0.0; then
  pass=$((pass+1)); echo "PASS real run bumps all 3 files, tags, pushes"
else fail=$((fail+1)); echo "FAIL real run"; fi

# Ordering: 9.0.0 is now a downgrade vs 10.0.0 (lexically "9" > "10"); tag-exists is also guarded.
check "9.0.0 < 10.0.0 (numeric)" fail "strictly greater" 9.0.0 --dry-run
git tag v11.0.0
check "tag already exists" fail "already exists locally" 11.0.0 --yes

echo "passed=$pass failed=$fail"; ((fail==0))
