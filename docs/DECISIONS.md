# Engineering decisions

This is a record of the choices behind Miraya V1, started 2026-10-26. The priority is a complete local Mac-to-TV experience with an inspectable, small build and no third-party media service.

## Native applications

The Mac app uses SwiftUI with AppKit integration, ScreenCaptureKit and VideoToolbox. The TV app uses Kotlin, native focusable views, SurfaceView, MediaCodec and AudioTrack. TV screens use large type, a launcher banner, D-pad focus and Back behavior; no phone layout or browser is embedded. Android documents a dedicated TV launcher entry, no touchscreen requirement, and remote navigation as fundamental requirements. [Android TV app setup](https://developer.android.com/training/tv/get-started/create).

Flutter, Electron, and a WebView receiver were considered. They would still require native capture/codec/security integration. For two initial platforms, they increase dependencies without removing the media work. Swift UI code stays in the Mac app, while the wire format and media contract are platform-independent. Future Windows/Linux senders can reuse the protocol, not ScreenCaptureKit.

## Capture and codecs

ScreenCaptureKit provides display video and system audio as timestamped sample buffers and exposes frame rate, output dimensions, pixel format, audio sample rate and channel count. V1 requires macOS 13 for system audio and avoids virtual audio drivers. Audio is optional; microphones are outside scope. [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), [audio capture configuration](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio).

H.264 is used for broad installed-TV compatibility. VideoToolbox performs real-time encoding with no frame reordering, and Android decodes directly to a Surface. The sender transmits Annex B access units, plus explicit SPS/PPS configuration. H.264 is a platform-supported Android format; actual resolution, profile and frame rate support remain decoder-specific. [Android supported formats](https://developer.android.com/media/platform/supported-formats), [VideoToolbox compression sessions](https://developer.apple.com/documentation/videotoolbox/vtcompressionsession-api-collection).

HEVC/AV1 could reduce bandwidth and 4:4:4 could improve text quality, but support and latency vary. V1 uses SDR 8-bit 4:2:0 and caps output at 1080p. These are deliberate compatibility limits, not an assertion that every TV handles 1080p60. Lower quality mode is available when necessary. No DRM bypass is attempted.

Audio is interleaved signed PCM16LE at 48 kHz stereo. It costs 1.536 Mbit/s before TLS but avoids encoder delay, audio codec dependencies and priming ambiguity. Android AudioTrack's stream mode can use a low-latency path where the TV supports it; buffer management and the output device still affect latency. This is a LAN tradeoff. AAC or Opus is a later negotiated protocol extension. [Android AudioTrack](https://developer.android.com/reference/android/media/AudioTrack).

## TLS over TCP

One local TLS/TCP connection carries framing, control, H.264 and PCM. Authentication and encryption use platform TLS implementations, not custom cryptography. TCP makes configuration, keyframes and control ordered/reliable, and integrates directly with Apple's Network framework and Java's SSLSocket. The protocol bounds packet sizes, queued media, connection deadlines and heartbeat silence. Under congestion, capture is throttled before encoding and stale receiver output is discarded; arbitrary reference-frame drops on the wire would corrupt decoding.

WebRTC was seriously considered: it offers congestion control, SRTP, loss recovery and audio tooling suited to mirroring. Its native build adds Chromium's large toolchain and a native dependency distribution problem; official development uses depot_tools/GN/Ninja with platform-specific builds. These costs were rejected for V1's small offline LAN scope, not because WebRTC needs a cloud relay. A future transport can carry the same captured/encoded media. [WebRTC native development](https://webrtc.github.io/webrtc-org/native-code/development/), [native prerequisites](https://webrtc.googlesource.com/src/+/refs/heads/main/docs/native-code/development/prerequisite-sw/README.md).

TCP has head-of-line blocking: severe loss can interrupt playback. Bounded queues and reconnect behavior prevent unbounded lag but do not replace RTP/WebRTC's behavior on poor networks. Hardware/network soak testing determines whether this choice is sufficient for a particular home; V1 makes no sub-frame latency guarantee. HLS/DASH were rejected because segment buffering conflicts with interactive screen use. Unauthenticated RTSP would not meet the trust model.

## Discovery and pairing

Android NSD publishes `_miraya._tcp.`; the Mac browses Bonjour. TXT carries version and stable receiver UUID only. A manual IP/port path handles multicast-disabled routers, VPNs and emulator testing. Android's NSD supports service discovery on the local network without an internet service. [Android local connectivity and NSD](https://developer.android.com/develop/connectivity/wifi).

The TV displays a 64-bit prefix of its TLS certificate fingerprint, which the user types on the Mac before first connection. The Mac checks this during the TLS trust decision, then the TV separately approves the Mac with its remote. Full fingerprint pinning and a random 256-bit token protect subsequent sessions. A short PIN sent through an otherwise unverified TLS connection was rejected because a LAN intermediary could intercept it. Discovery TXT is treated as untrusted metadata. See [security](SECURITY.md) and [protocol](../protocol/PROTOCOL.md).

Bluetooth was rejected: existing Wi-Fi/Ethernet already carries media, while Bluetooth would add permissions, cross-platform pairing work and limited bandwidth without solving the core screen-streaming problem. No UPnP, router configuration or inbound internet exposure is needed.

## Packaging and reproducibility

Swift Package Manager builds the Mac executable; a repository script assembles the actual `.app`, icon and Info.plist, then signs it. NSBonjourServices and NSLocalNetworkUsageDescription describe local discovery/transport. Ad-hoc signing supports local builds; public distribution requires Developer ID and notarization credentials. [Apple local-network usage description](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription), [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Android uses the versioned Gradle wrapper and SDK, with a signed development APK and a release configuration ready for an external signing key. Signing credentials never enter source control. [Android command-line builds](https://developer.android.com/build/building-cmdline).
