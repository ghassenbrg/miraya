#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/scripts/android-env.sh"
failures=0
check() {
  if command -v "$1" >/dev/null 2>&1; then printf 'OK   %s: %s\n' "$1" "$(command -v "$1")"
  else printf 'MISS %s\n' "$1"; failures=$((failures + 1)); fi
}
echo 'Miraya build environment'
check git
check java
java -version 2>&1 | head -1
if ! java -version 2>&1 | head -1 | grep -Eq '"(17|21)\.'; then
  echo 'MISS JDK 17 or 21 (set JAVA_HOME)'
  failures=$((failures + 1))
fi
echo "Android SDK: ${ANDROID_HOME:-not found}"
if [[ -n "${ANDROID_HOME:-}" ]]; then
  for entry in platforms/android-36/android.jar build-tools/36.0.0/apksigner platform-tools/adb; do
    if [[ -f "$ANDROID_HOME/$entry" ]]; then printf 'OK   %s\n' "$entry"
    else printf 'MISS %s\n' "$entry"; failures=$((failures + 1)); fi
  done
else
  failures=$((failures + 1))
fi
if [[ "$(uname -s)" == Darwin ]]; then
  check swift
  if ! xcodebuild -version 2>&1; then
    echo 'MISS full Xcode selected with xcode-select'
    failures=$((failures + 1))
  fi
  echo 'Screen capture permission is checked by the application when you share.'
else
  echo 'macOS application builds require a Mac with Xcode.'
fi
echo "Missing tools: $failures"
exit "$failures"
