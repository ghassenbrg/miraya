#!/bin/bash
set -euo pipefail
want="${MIRAYA_XCODE:-}"
if [[ -n "$want" ]]; then
  app="$want"
  [[ -d "$app" ]] || app="/Applications/Xcode_$want.app"
  [[ -d "$app" ]] || { echo "Requested Xcode is unavailable: $want" >&2; exit 1; }
  sudo xcode-select -s "$app/Contents/Developer"
fi
xcodebuild -version | sed -n 1p
swift --version 2>&1 | sed -n 1p
