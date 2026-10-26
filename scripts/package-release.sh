#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$ROOT/scripts/test.sh"
"$ROOT/scripts/build-macos.sh" --universal
"$ROOT/scripts/build-android.sh" debug
"$ROOT/scripts/build-android.sh" release
ditto -c -k --sequesterRsrc --keepParent "$ROOT/dist/Miraya.app" "$ROOT/dist/Miraya-macOS.zip"
cd "$ROOT/dist"
shasum -a 256 Miraya-macOS.zip Miraya-TV*.apk > SHA256SUMS
echo "Packages and checksums: $ROOT/dist"
