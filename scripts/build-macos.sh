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
VERSION=${MIRAYA_VERSION:-$(tr -d '\n\r' < "$ROOT/VERSION")}
BUILD_NUMBER=${MIRAYA_BUILD_NUMBER:-6}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'MIRAYA_VERSION must be X.Y.Z.' >&2; exit 2; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo 'MIRAYA_BUILD_NUMBER must be numeric.' >&2; exit 2; }
export MACOSX_DEPLOYMENT_TARGET=13.0
# Prefer the developer's stable identity when exactly one is available. An
# ad-hoc signature identifies this particular executable by its hash, so a
# rebuild can invalidate an apparently enabled screen-recording grant.
# An explicit CODESIGN_IDENTITY=- still supports unsigned development hosts.
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  SIGNING_IDENTITY=$CODESIGN_IDENTITY
else
  DEVELOPER_IDS=()
  while IFS= read -r identity; do
    [[ -n "$identity" ]] && DEVELOPER_IDS+=("$identity")
  done < <(security find-identity -v -p codesigning | sed -nE 's/^[[:space:]]*[0-9]+\) ([[:xdigit:]]{40}) "Developer ID Application:.*$/\1/p')
  case ${#DEVELOPER_IDS[@]} in
    0) SIGNING_IDENTITY=- ;;
    1) SIGNING_IDENTITY=${DEVELOPER_IDS[0]} ;;
    *) echo 'Multiple Developer ID identities found. Set CODESIGN_IDENTITY explicitly (or - for an ad-hoc build).' >&2; exit 2 ;;
  esac
fi
swift build --package-path "$ROOT/macos" --configuration "$CONFIG" --product Miraya "${ARCH_ARGS[@]+${ARCH_ARGS[@]}}"
BIN_DIR=$(swift build --package-path "$ROOT/macos" --configuration "$CONFIG" --show-bin-path "${ARCH_ARGS[@]+${ARCH_ARGS[@]}}")
APP="$ROOT/dist/Miraya.app"
mkdir -p "$ROOT/dist"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Miraya" "$APP/Contents/MacOS/Miraya"
# SwiftPM binary framework must be embedded and signed for the packaged app.
WEBRTC_FRAMEWORK="$ROOT/macos/.build/artifacts/webrtc/WebRTC/WebRTC.xcframework/macos-x86_64_arm64/WebRTC.framework"
[[ -d "$WEBRTC_FRAMEWORK" ]] || { echo 'Missing resolved WebRTC framework.' >&2; exit 1; }
ditto "$WEBRTC_FRAMEWORK" "$APP/Contents/Frameworks/WebRTC.framework"
cp "$ROOT/scripts/macos/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/Beam"
cp "$ROOT/macos/Sources/Miraya/Resources/"*.png "$APP/Contents/Resources/Beam/"
if [[ -d "$BIN_DIR/Miraya_Miraya.bundle" ]]; then ditto "$BIN_DIR/Miraya_Miraya.bundle" "$APP/Contents/Resources/Miraya_Miraya.bundle"; fi
mkdir -p "$APP/Contents/Resources/licenses"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/licenses/"
cp "$ROOT/licenses/"* "$APP/Contents/Resources/licenses/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
ICONSET="$ROOT/macos/.build/Miraya.iconset"
mkdir -p "$ICONSET"
swift "$ROOT/scripts/macos/generate-icon.swift" "$ICONSET"
iconutil --convert icns "$ICONSET" --output "$APP/Contents/Resources/Miraya.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY")
# Hardened runtime library validation requires a real common Team ID for the
# executable and embedded framework. Ad-hoc development signatures have none.
# Production Developer ID builds retain hardened runtime without LV exceptions.
if [[ "$SIGNING_IDENTITY" != - ]]; then SIGN_ARGS+=(--options runtime --timestamp); fi
codesign "${SIGN_ARGS[@]}" "$APP/Contents/Frameworks/WebRTC.framework"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "Application: $APP"
if [[ "$SIGNING_IDENTITY" == - ]]; then
  echo 'Ad-hoc signed local build. For distribution, use Developer ID signing and notarization; see docs/RELEASING.md.'
  echo 'Rebuilding an ad-hoc app can invalidate its saved macOS capture and Keychain permissions.'
else
  echo 'Developer identity signing applied. Public distribution still requires notarization; see docs/RELEASING.md.'
fi
