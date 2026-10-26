#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT="${1:-$ROOT/build/capture-fixture}"
mkdir -p "$OUTPUT"
xcrun swiftc -swift-version 5 -O -target "$(uname -m)-apple-macosx13.0" \
  "$ROOT/macos/Sources/Miraya/H264Encoder.swift" \
  "$ROOT/macos/Sources/Miraya/SystemAudioPCM.swift" \
  "$ROOT/tools/capture/Probe.swift" -o "$OUTPUT/capture-probe"
"$OUTPUT/capture-probe" "$OUTPUT"
if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -v error -i "$OUTPUT/video.h264" -f null -
  echo 'PASS: FFmpeg independently decoded the production encoder output'
fi
