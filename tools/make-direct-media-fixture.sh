#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v ffmpeg >/dev/null || { echo 'FFmpeg is required for the generated direct-playback fixture.' >&2; exit 1; }
mkdir -p "$ROOT/build/capture-fixture"
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i testsrc2=size=640x360:rate=30 \
  -f lavfi -i 'aevalsrc=0.12*sin(2*PI*440*t)|0.12*sin(2*PI*880*t):s=48000' \
  -t 20 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -g 30 \
  -c:a aac -b:a 128k -movflags +faststart "$ROOT/build/capture-fixture/direct-playback.mp4"
