#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/scripts/android-env.sh"
if [[ -z "${ANDROID_HOME:-}" ]]; then
  echo 'Android SDK not found. Install Android Studio or set ANDROID_HOME; see README.md.' >&2
  exit 1
fi
MODE=${1:-debug}
# Optimized test copies are signed separately after validation. Do not leave an
# older one beside fresh outputs where it could be mistaken for this build.
rm -f "$ROOT/dist/Miraya-TV-optimized-test.apk"
case "$MODE" in
  debug) TASK=assembleDebug ;;
  release) TASK=assembleRelease ;;
  *) echo 'Usage: scripts/build-android.sh [debug|release]' >&2; exit 2 ;;
esac
# A previous signed release must never be mistaken for this build's unsigned output.
rm -rf "$ROOT/android/app/build/outputs/apk/$MODE"
"$ROOT/android/gradlew" -p "$ROOT/android" --no-daemon "$TASK"
mkdir -p "$ROOT/dist"
if [[ "$MODE" == debug ]]; then
  cp "$ROOT/android/app/build/outputs/apk/debug/app-debug.apk" "$ROOT/dist/Miraya-TV-debug.apk"
  echo "Installable development APK: $ROOT/dist/Miraya-TV-debug.apk"
else
  APK="$ROOT/android/app/build/outputs/apk/release/app-release.apk"
  if [[ -f "$APK" ]]; then
    rm -f "$ROOT/dist/Miraya-TV-unsigned.apk"
    cp "$APK" "$ROOT/dist/Miraya-TV.apk"
    echo "Release APK: $ROOT/dist/Miraya-TV.apk"
  else
    rm -f "$ROOT/dist/Miraya-TV.apk"
    cp "$ROOT/android/app/build/outputs/apk/release/app-release-unsigned.apk" "$ROOT/dist/Miraya-TV-unsigned.apk"
    echo "Unsigned release APK: $ROOT/dist/Miraya-TV-unsigned.apk"
    echo 'Sign with your release key before installing; see docs/RELEASING.md.'
  fi
fi
