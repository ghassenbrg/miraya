#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT="${1:-$ROOT/build/discovery-report.json}"
mkdir -p "$ROOT/build/discovery"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
  "$ROOT/macos/Sources/Miraya/Discovery.swift" \
  "$ROOT/tools/discovery/BonjourProbe.swift" -o "$ROOT/build/discovery/bonjour-probe"
"$ROOT/build/discovery/bonjour-probe" "$OUTPUT"
