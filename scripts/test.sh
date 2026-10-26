#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ "$(uname -s)" == Darwin ]]; then
  swift test --package-path "$ROOT/macos"
fi
source "$ROOT/scripts/android-env.sh"
"$ROOT/android/gradlew" -p "$ROOT/android" --no-daemon testDebugUnitTest lintDebug
