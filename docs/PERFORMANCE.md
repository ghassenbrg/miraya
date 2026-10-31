# Streaming performance and release validation

## Current streaming mechanism

Version 0.1.0 build 6 also supports window/region capture, Desktop/Watching video presets and a separate direct-media path. Mirror detail priority is now the default: preserve pixel dimensions and reduce frame rate under sustained receiver overload; motion priority retains pixel-scaling fallback. The historical motion-first descriptions below describe that selectable policy.

Direct media uses AndroidX Media3 1.11.1. Explicitly selected local files are read in bounded 32 KiB ranges over the existing authenticated TLS connection; remote compatible media is fetched over HTTPS by the TV. This avoids screen capture/re-encoding and permits a 15–30 second player buffer (subject to byte/load-control limits). Buffering/codec/source compatibility remain real constraints. Direct playback is separate from interactive screen sharing and does not transmit Chrome overlays, login state or protected-service licenses. Its frame counters and buffer depth are not glass-to-glass latency measurements.

Current Mac and Android apps use `webrtc-udp-v1`: ScreenCaptureKit raw display frames feed native VideoToolbox H.264; captured system PCM feeds an input-only WebRTC device and stereo Opus. Authenticated TLS carries pairing, SDP/ICE, playback controls and stats. Native media uses direct ICE/DTLS-SRTP UDP, with no reliable data channel, STUN/TURN service or cloud relay.

The native stack supplies bandwidth estimation, pacing, retransmission/keyframe feedback, jitter buffering and A/V synchronization. Sender limits are 720p30/3Mbps, 1080p30/6Mbps and 1080p60/10Mbps; actual output can adapt below those maximums. H.264 level negotiation respects decoder limits rather than feeding 1080p into the upstream Mac factory's default level-3.1 encoder. Native sender adaptation prioritizes frame cadence. Live changes replace capture/source as needed while retaining the peer, ICE and DTLS session.

The native screen source prioritizes frame cadence. M150's screen-sharing pacer queue allowance is reduced from 2875ms to 200ms (pacing factor 1.5), retaining application-limited bandwidth probes. Explicit quality/resume changes temporarily stop quality scaling to remove stale resource restrictions, then restore frame priority. A bounded quality-recovery probe also retries a larger picture after two healthy bandwidth samples, at most once per ten seconds. Native congestion/CPU adaptation can reduce it again. The audio bridge holds at most 60ms of captured PCM and emits 10ms blocks with host-clock capture timestamps. Sparse complete-screen repeats permit static-screen loss recovery. Ready/offer, encoder progress, end-to-end presentation and disconnected-peer deadlines prevent an indefinitely stuck session. The M150 custom audio-device direct-buffer path truncates interleaved stereo to half its samples; Miraya uses its documented render-block path to forward all 480 stereo frames per 10ms. Native audio packet rate and captured-sample duration are checked in integration tests. These are internal budgets, not a glass-to-glass latency guarantee.

TV playback feedback is distinct from network bandwidth. Sessions start at up to 30fps. Smooth motion probes 60fps once after five healthy seconds of moving input; a TV that falls behind returns to 30fps without reconnecting. While input contains motion, persistent receiver drops at 30fps reduce pixel dimensions; the fallback uses 2/3 and 1/2 dimension scales, with a three-second adjustment cooldown. Static/paused screens are excluded. Learned playback limits survive pause; an explicit quality change retries the requested mode. This avoids continuously encoding faster than the receiver presents.

Pause stops capture and disables the tracks, with TLS/ICE alive; a long pause is not an outstanding-frame failure. Resume, live quality/audio and gain retain authorization. New pairing compares six digits, then requires remote approval. Install both updated apps; current Mac senders explicitly reject an older TV without the new transport.

## Legacy TCP findings, 2026-10-27

The following fixes remain in the compatibility path and diagnostic fixtures; current app media uses native UDP instead of these custom TCP queue/clock mechanisms.

The reported freeze/reconnect pattern has software causes in addition to any
network or TV limitations. Lowering resolution alone cannot fix these failures.

| Failure | Consequence | Fix |
| --- | --- | --- |
| The playback-stall timer survived a fully acknowledged static desktop | The first window change after a long idle could immediately trigger reconnect | Start a new progress deadline when new video becomes outstanding |
| Backpressure completely stopped capture when the TV was behind | The recovery IDR could never reach the decoder | Throttle with a recovery opportunity every 250ms; keep audio admission separate |
| Playback timing retained an obsolete epoch after a short delay | Subsequent decoded frames were continually discarded as late | Re-anchor playout after timing slips; disregard stalled audio clocks |
| A queue overflow replayed configuration by recreating MediaCodec | Repeated codec startup made overload worse and discarded an incoming recovery IDR | Preserve pending configuration and incoming IDRs; flush the existing decoder and resubmit SPS/PPS |
| A 5ms input-buffer miss flushed the decoder immediately | Normal hardware backpressure became repeated recovery | Drain output while retrying input for a bounded 120ms |
| Scene changes could exceed a 1.5MB transport limit, and queue age triggered disconnect | A valid large IDR or short write delay restarted the entire connection | Allow a valid single frame; discard stale unsent dependencies, request a fresh IDR, and retain TLS |
| Adaptation reacted only to receiver frame drops | TCP backlog could grow while decoding still made gradual progress | Use decode feedback and local write pressure to reduce bitrate; cap encoder bursts |
| The Mac lacked a process activity assertion | Background/minimized sharing was eligible for App Nap throttling | Hold a latency-critical user-initiated activity during sharing and release it on stop/failure |
| Receiver framing performed individual header writes directly to TLS | Unnecessary small TLS records and network operations | Buffer framing I/O and flush each complete control packet |

Sender media normally waits at most 200ms in the application queue, with a 512KB
pending-media budget and an allowance for one wire-valid IDR. Removing an encoded
reference frame also removes its dependent queued video; only an IDR resumes
video. Control and codec configuration retain their order. A static screen can
send a fresh IDR from its latest captured buffer even when ScreenCaptureKit has
no new complete frame. Recovery timestamps are monotonic.

The receiver initially targets 40ms of playout buffering. Audio more than 120ms
behind newly received audio is skipped. Eight seconds of outstanding video with
no decoded progress, a stuck write, or a lost connection still invokes bounded
reconnect. These budgets are implementation limits, not a promise of 40ms
glass-to-glass latency. TCP and TV hardware can add buffering outside the app.

The changes preserve protocol v1 and its pairing, certificate pinning, token
authentication, explicit TV stop and bounded retry behavior. Install both updated
apps to receive the sender and receiver fixes. Existing pairings survive updates
signed with the same identities; ad-hoc Mac builds can require renewed Keychain
and screen-recording approval.

## Why internet playback can look better

An internet player receives video encoded ahead of time and can build a large
buffer, adapt its bitrate, and hide short delivery delays. Mirroring continually
captures and encodes the current screen and has a small latency budget. Wi-Fi
between two wireless endpoints also consumes airtime in both directions through
the access point. Reliable TCP holds later media behind retransmissions. A fast
WAN download does not measure capture, encoder bursts, local delivery, decoder
queueing or panel processing. This incident reproduced on an emulator without a
physical Wi-Fi link, confirming that a network upgrade alone is not the fix.

## Reproduce the checks

```sh
scripts/test.sh
tools/capture/test-capture.sh
scripts/build-macos.sh --universal
scripts/build-android.sh debug
scripts/build-android.sh release
source scripts/android-env.sh
android/gradlew -p android connectedDebugAndroidTest
python3 tools/capture/loopback_receiver.py --sender dist/Miraya.app/Contents/MacOS/Miraya
python3 tools/emulator-smoke.py --reset --webrtc --udp-relay --performance
python3 tools/emulator-smoke.py --reset --webrtc --udp-relay --performance --performance-fps 60
python3 tools/emulator-smoke.py --reset --webrtc --udp-relay --controls
python3 tools/emulator-smoke.py --reset --webrtc --udp-relay --performance --udp-loss .02 --udp-delay-ms 12 --udp-jitter-ms 8 --udp-rate-mbps 8 --udp-stall-at 12 --udp-stall-for .35 --udp-ordered --minimum-ratio .8
python3 tools/emulator-smoke.py --reset --bandwidth
```

The emulator must already be booted. The smoke harness deliberately clears
Miraya data on the selected **emulator only**, then pairs through the displayed
code and remote approval. Never use this reset workflow against a physical TV.

The new Android integration scenario introduces 350ms of jitter, leaves the
same authenticated session idle for six seconds, overruns its video queue with
a burst, then resumes paced playback. It asserts that presentation progresses
through every stage without reconnecting. It failed against the previous APK
at the jitter presentation assertion and passed against the patched receiver.

`--performance --webrtc` runs two H.264/Opus UDP sessions: 20 seconds at a 30fps maximum, or 30 seconds with a 60fps maximum using `--performance-fps 60` with NV12 buffers matching production ScreenCaptureKit output, detailed scene
changes every two seconds, moving overlays and a six-second idle interval in
each session. It requires at least 90% of the active-period frame budget at the actual adapted frame-rate target in each session. A 60fps maximum runs for 30 seconds; this is not a requirement that a slow receiver stay at 60fps. Telemetry records every frame-rate adjustment and the resulting target budget. The ordinary probe also supports 720p. `--controls` checks a nine-second pause, resume at 720p/audio off, return to 1080p/audio on, mute and gain without replacing the peer UUID. The raw UDP relay is diagnostic-only: adb cannot forward UDP through emulator NAT. It forwards untouched encrypted datagrams, can introduce bounded loss/delay/jitter/bandwidth/outages, and never decrypts or stores media. By default, independent per-datagram jitter also causes heavy reordering; `--udp-ordered` varies delay while retaining per-direction order. Report which model was used. Neither reproduces a physical radio or certifies a TV.

`ackLagMs` is a distance between media PTSs in periodic telemetry. An idle gap
can temporarily make it large when the first new frame is not yet acknowledged;
it must not be interpreted as six seconds of visible delay. `pendingAgeMs`
instead measures elapsed time since the oldest unacknowledged generated frame
was submitted, and still includes telemetry cadence. Neither metric measures
camera-observed latency or proves that a scheduled Surface buffer was displayed.

## Release boundary

The automated checks cover protocol handling, clock recovery, bounded queues,
real VideoToolbox encoding, TLS, Android MediaCodec/AudioTrack, visible approval,
saved authorization, stop, reconnect and bandwidth failure/recovery. Test outputs
and measured counts are recorded in [TESTING.md](TESTING.md).

Production sign-off still requires the target physical TV and LAN: at least
30 minutes of browser video with system audio; repeated window/application
switches; long static periods followed by motion; Wi-Fi interruption and
recovery; A/V sync; camera-measured median/tail glass-to-glass latency; and
minimum-supported-OS checks. Verify the final signed APK and Developer ID signed,
notarized Mac app on clean installations. Local ad-hoc and unsigned release
artifacts do not satisfy public-distribution signing.

API references: [Android codec flush/keyframe requirements](https://developer.android.com/reference/android/media/MediaCodec#flush()),
[Android Surface render scheduling](https://developer.android.com/reference/android/media/MediaCodec#releaseOutputBuffer(int,%20long)),
[Apple encoder data-rate limits](https://developer.apple.com/documentation/videotoolbox/kvtcompressionpropertykey_dataratelimits).
