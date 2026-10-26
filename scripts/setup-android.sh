#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[[ "${1:-}" == '' || "${1:-}" == --emulator ]] || { echo 'Usage: scripts/setup-android.sh [--emulator]' >&2; exit 2; }
source "$ROOT/scripts/android-env.sh"
command -v sdkmanager >/dev/null || { echo 'Install Android Studio command-line tools, then add sdkmanager to PATH.' >&2; exit 1; }
if [[ -z "${ANDROID_HOME:-}" ]]; then
  echo 'Set ANDROID_HOME to the directory where you want the SDK installed.' >&2
  exit 1
fi
sdkmanager --sdk_root="$ANDROID_HOME" --licenses
sdkmanager --sdk_root="$ANDROID_HOME" 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0'
if [[ "${1:-}" == --emulator ]]; then
  case "$(uname -m)" in
    arm64|aarch64) ABI=arm64-v8a ;;
    *) ABI=x86_64 ;;
  esac
  sdkmanager --sdk_root="$ANDROID_HOME" emulator "system-images;android-36;android-tv;$ABI"
  if ! avdmanager list avd -c | grep -qx MirayaTV; then
    printf 'no\n' | avdmanager create avd --name MirayaTV --package "system-images;android-36;android-tv;$ABI" --device tv_1080p
  fi
  echo 'Start TV emulator: emulator -avd MirayaTV -no-snapshot'
fi
