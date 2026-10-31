#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${RELEASE_VERSION:?}" "${RELEASE_BUILD:?}" "${CHANNEL:?}" "${RELEASE_TAG:?}"
export MIRAYA_VERSION="$RELEASE_VERSION" MIRAYA_BUILD_NUMBER="$RELEASE_BUILD"
swift test --package-path macos
python3 tools/test-release-plan.py
source scripts/android-env.sh
android/gradlew -p android --no-daemon testDebugUnitTest lintDebug
arch=()
if [[ "${UNIVERSAL:-false}" == true ]]; then arch=(--universal); fi
scripts/build-macos.sh "${arch[@]+${arch[@]}}"
assets="build/release-assets/$RELEASE_TAG"
mkdir -p "$assets"
name="Miraya-$RELEASE_VERSION${RELEASE_LABEL:+-$RELEASE_LABEL}"
mac="$assets/$name-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent dist/Miraya.app "$mac"
if [[ "${SIGNING:-no}" == yes ]]; then
  xcrun notarytool submit "$mac" --keychain-profile miraya-notary --keychain "$SIGNING_KEYCHAIN" --wait --timeout "${MIRAYA_NOTARY_MINUTES:-180}m"
  xcrun stapler staple dist/Miraya.app
  xcrun stapler validate dist/Miraya.app
  spctl --assess --type execute --verbose=2 dist/Miraya.app
  ditto -c -k --sequesterRsrc --keepParent dist/Miraya.app "$mac"
elif [[ "$CHANNEL" == production ]]; then
  echo 'Refusing a production release without notarization.' >&2; exit 1
fi
if [[ "${ANDROID_SIGNING:-no}" == yes ]]; then
  scripts/build-android.sh release
  "$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --verbose dist/Miraya-TV.apk
  cp dist/Miraya-TV.apk "$assets/$name-TV.apk"
elif [[ "$CHANNEL" == snapshot ]]; then
  scripts/build-android.sh debug
  cp dist/Miraya-TV-debug.apk "$assets/$name-TV-development.apk"
else
  echo 'Refusing a production release without an Android release key.' >&2; exit 1
fi
cd "$assets"
shasum -a 256 "$name"* > SHA256SUMS
shasum -a 256 -c SHA256SUMS
