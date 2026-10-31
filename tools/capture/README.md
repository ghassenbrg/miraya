# Native capture and transport diagnostics

These tools exercise the production Swift encoder, PCM conversion, TLS transport,
framing, and reconnect behavior without capturing your screen. They use generated
pixels and a quiet 220 Hz tone. They do not request Screen Recording permission.

From the repository root on a Mac:

```sh
tools/capture/test-capture.sh
swift build --package-path macos
python3 tools/capture/loopback_receiver.py
```

The first command compiles the production H.264 encoder and audio converter into a
small diagnostic. It checks portrait aspect fitting, timestamps, planar Float32,
interleaved Int16, mono duplication, clipping, and NaN handling. It then encodes
90 real VideoToolbox frames, requests an extra IDR, changes bitrate, extracts
SPS/PPS, and converts AVCC into Annex B. If FFmpeg is installed, it independently
decodes the result. Fixtures are written to `build/capture-fixture/`.

The Python tool requires `openssl` and `ffmpeg`. It creates a temporary self-signed
certificate, binds a receiver to **127.0.0.1 only**, and runs the actual Miraya
executable's `--probe` mode. Test authorization is automatic in this isolated
software receiver. Its checks cover:

- First pairing and a second connection using the full certificate pin and token.
- Sustained independently decoded H.264, PCM packet integrity, live timestamp
  acknowledgments, a requested keyframe, and a clean stop.
- Incorrect certificate code, denied authorization, unsupported version,
  malformed packet header, and a connection lost during streaming.

Results are written to `build/loopback-report.json`. This software receiver has no
Android Surface or AudioTrack; its audio counters mean validated PCM bytes.
Use the Android emulator smoke test and a physical TV to verify Android playback.

To exercise larger encodes with the same loopback test:

```sh
MIRAYA_PROBE_WIDTH=1280 MIRAYA_PROBE_HEIGHT=720 MIRAYA_PROBE_FPS=30 \
  python3 tools/capture/loopback_receiver.py --case success --output build/loopback-720p30-report.json
MIRAYA_PROBE_WIDTH=1920 MIRAYA_PROBE_HEIGHT=1080 MIRAYA_PROBE_FPS=60 \
  python3 tools/capture/loopback_receiver.py --case success --output build/loopback-1080p60-report.json
```

The software decoder uses a single decode thread and low-delay mode. A default
FFmpeg frame-thread pool buffers multiple frames, which is inappropriate for this
test of the sender's presentation-acknowledgment backpressure.

## Test a running Android receiver

Open Miraya on the TV/emulator. For first pairing, the probe asks for the six-digit code that appears on the TV after the commitment exchange:

```sh
MIRAYA_PROBE_BINARY="$(swift build --package-path macos --show-bin-path)/Miraya"
"$MIRAYA_PROBE_BINARY" --probe TV_IP 7421 interactive 8
```

Approve **Miraya diagnostic** on the TV with its remote. `--probe` runs before the
normal macOS UI opens. It sends generated H.264 and PCM through the same transport
as the application, prints receiver statistics, and exits with status 0 only if
the receiver confirms sustained video, audio playback, and advancing media
timestamps. In Android tests, `audioFramesWritten` comes from successful
AudioTrack writes and `audioFrames` from its playback head. A physical TV is still
needed to assess perceptual latency, sound, scaling, and display processing.

Optional environment variables:

| Variable | Meaning |
| --- | --- |
| `MIRAYA_PROBE_WIDTH` / `MIRAYA_PROBE_HEIGHT` | Even video dimensions, at most 1920 × 1080; defaults 640 × 360. |
| `MIRAYA_PROBE_FPS` | 30 or 60; default 30. |
| `MIRAYA_PROBE_SCENES=1` | Change a detailed deterministic image every two seconds, with IDRs and moving overlays. |
| `MIRAYA_PROBE_PAUSE_AT` / `MIRAYA_PROBE_PAUSE_FOR` | Seconds from media start and duration of an idle capture interval; heartbeat/statistics remain active. |
| `MIRAYA_PROBE_RECONNECT=1` | Run a second complete session using the saved full pin and token. |
| `MIRAYA_PROBE_FORGET=1` | Forget this endpoint's diagnostic pairing before starting, useful after revoking TV tokens. |
| `MIRAYA_PROBE_TOKEN` / `MIRAYA_PROBE_FINGERPRINT` / `MIRAYA_PROBE_CLIENT_ID` | Explicit credential overrides for controlled auth tests. |

Probe credentials are kept in a separate macOS Keychain service,
`app.miraya.diagnostic.pairing`, and are never printed. They do not alter the
normal application's pairings. Temporary loopback certificates and private keys
are removed when the Python tool exits.

Actual ScreenCaptureKit capture is tested by opening the packaged `.app`, granting
the normal Screen & System Audio Recording permission, and sharing a display.
The diagnostics deliberately avoid prompting for that permission from Terminal.

For scene-change and idle/resume validation on the TV emulator:

```sh
source scripts/android-env.sh
python3 tools/emulator-smoke.py --reset --performance
```

This clears only the selected emulator's Miraya data, uses the visible pairing
approval, and runs two 20-second 1080p30/PCM sessions with detailed scene changes
and a six-second idle interval. Diagnostic congestion requests fresh IDRs and
reduces bitrate. `maxAckLagMs` measures sender PTS distance to the latest scheduled
frame acknowledged in periodic telemetry; it is **not glass-to-glass latency**.
`pendingAgeMs` measures elapsed time since the oldest still-unacknowledged
generated frame was submitted, avoiding a misleading PTS gap across idle periods.
The final telemetry can precede the last in-flight frames. Logs are under
`build/emulator-smoke/`; this does not capture private desktop content.
