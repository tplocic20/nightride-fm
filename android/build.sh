#!/usr/bin/env bash
# Builds the debug APK with the Gradle wrapper.
#
# Usage:
#   bash build.sh            # assembleDebug → app/build/outputs/apk/debug/
#   bash build.sh install    # build + install on the connected device (adb)
#
# Prereqs: a JDK 17+ and the Android SDK. The easiest path is to open this
# folder in Android Studio (Giraffe+), which bundles both and a JDK, then hit
# Run. See README.md. This script is the headless/CI equivalent.
set -euo pipefail

cd "$(dirname "$0")"

# Bootstrap the wrapper jar if it isn't present yet (it's intentionally not
# committed). Android Studio does this for you on first sync.
if [ ! -f gradle/wrapper/gradle-wrapper.jar ]; then
    if command -v gradle >/dev/null 2>&1; then
        echo "→ generating Gradle wrapper…"
        gradle wrapper --gradle-version 8.11.1
    else
        echo "gradle-wrapper.jar is missing and 'gradle' isn't on PATH." >&2
        echo "Open this folder in Android Studio once (it generates the wrapper)," >&2
        echo "or install Gradle (brew install gradle) and re-run." >&2
        exit 1
    fi
fi

if [ -z "${ANDROID_HOME:-}${ANDROID_SDK_ROOT:-}" ] && [ ! -f local.properties ]; then
    echo "⚠  Android SDK not found. Set ANDROID_HOME or create local.properties:" >&2
    echo "     echo \"sdk.dir=\$HOME/Library/Android/sdk\" > local.properties" >&2
fi

TARGET="${1:-assembleDebug}"
case "$TARGET" in
    install) ./gradlew installDebug ;;
    *)       ./gradlew assembleDebug ;;
esac

echo
echo "✓ APK: app/build/outputs/apk/debug/app-debug.apk"
echo "  Install on a device:  adb install -r app/build/outputs/apk/debug/app-debug.apk"
