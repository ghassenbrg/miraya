#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[[ "$(uname -s)" == Darwin ]] || { echo 'A Mac with Xcode is required.' >&2; exit 1; }
CONFIG=release
ARCH_ARGS=()
for option in "$@"; do
  case "$option" in
    --debug) CONFIG=debug ;;
    --universal) ARCH_ARGS=(--arch arm64 --arch x86_64) ;;
    *) echo 'Usage: scripts/build-macos.sh [--debug] [--universal]' >&2; exit 2 ;;
  esac
done
VERSION=${MIRAYA_VERSION:-1.0.0}
BUILD_NUMBER=${MIRAYA_BUILD_NUMBER:-1}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'MIRAYA_VERSION must be X.Y.Z.' >&2; exit 2; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo 'MIRAYA_BUILD_NUMBER must be numeric.' >&2; exit 2; }
export MACOSX_DEPLOYMENT_TARGET=13.0
swift build --package-path "$ROOT/macos" --configuration "$CONFIG" --product Miraya "${ARCH_ARGS[@]+${ARCH_ARGS[@]}}"
BIN_DIR=$(swift build --package-path "$ROOT/macos" --configuration "$CONFIG" --show-bin-path "${ARCH_ARGS[@]+${ARCH_ARGS[@]}}")
APP="$ROOT/dist/Miraya.app"
mkdir -p "$ROOT/dist"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Miraya" "$APP/Contents/MacOS/Miraya"
cp "$ROOT/scripts/macos/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
ICONSET="$ROOT/macos/.build/Miraya.iconset"
mkdir -p "$ICONSET"
swift "$ROOT/scripts/macos/generate-icon.swift" "$ICONSET"
iconutil --convert icns "$ICONSET" --output "$APP/Contents/Resources/Miraya.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
SIGNING_IDENTITY=${CODESIGN_IDENTITY:--}
SIGN_ARGS=(--force --options runtime --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != - ]]; then SIGN_ARGS+=(--timestamp); fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "Application: $APP"
if [[ "$SIGNING_IDENTITY" == - ]]; then
  echo 'Ad-hoc signed local build. For distribution, use Developer ID signing and notarization; see docs/RELEASING.md.'
fi
