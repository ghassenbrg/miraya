# Engineering decisions

This is a record of the choices behind Miraya V1, started 2026-10-26. The priority is a complete local Mac-to-TV experience with an inspectable, small build and no third-party media service.

## Native applications

The Mac app uses SwiftUI with AppKit integration, ScreenCaptureKit and VideoToolbox. The TV app uses Kotlin, native focusable views, SurfaceView, MediaCodec and AudioTrack. TV screens use large type, a launcher banner, D-pad focus and Back behavior; no phone layout or browser is embedded. Android documents a dedicated TV launcher entry, no touchscreen requirement, and remote navigation as fundamental requirements. [Android TV app setup](https://developer.android.com/training/tv/get-started/create).

Flutter, Electron, and a WebView receiver were considered. They would still require native capture/codec/security integration. For two initial platforms, they increase dependencies without removing the media work. Swift UI code stays in the Mac app, while the wire format and media contract are platform-independent. Future Windows/Linux senders can reuse the protocol, not ScreenCaptureKit.

## Capture and codecs

ScreenCaptureKit provides display video and system audio as timestamped sample buffers and exposes frame rate, output dimensions, pixel format, audio sample rate and channel count. V1 requires macOS 13 for system audio and avoids virtual audio drivers. Audio is optional; microphones are outside scope. [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), [audio capture configuration](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio).

H.264 is used for broad installed-TV compatibility. VideoToolbox performs real-time encoding with no frame reordering, and Android decodes directly to a Surface. Native WebRTC packetizes H.264 for RTP. The older TCP compatibility path retains Annex B access units and explicit SPS/PPS configuration. H.264 is a platform-supported Android format; actual resolution, profile and frame rate support remain decoder-specific. [Android supported formats](https://developer.android.com/media/platform/supported-formats), [VideoToolbox compression sessions](https://developer.apple.com/documentation/videotoolbox/vtcompressionsession-api-collection).

HEVC/AV1 could reduce bandwidth and 4:4:4 could improve text quality, but support and latency vary. V1 uses SDR 8-bit 4:2:0 and caps output at 1080p. These are deliberate compatibility limits, not an assertion that every TV handles 1080p60. Lower quality mode is available when necessary. No DRM bypass is attempted.

System audio is captured as 48kHz stereo PCM and fed to WebRTC's input-only custom device, then encoded as Opus up to 192kbit/s. The bounded 60ms PCM buffer and capture host timestamps preserve a common timing basis for native A/V sync. Android's native audio module drives AudioTrack with media/movie attributes. No microphone or virtual driver is used. The old PCM/TLS decoder remains for compatibility fixtures.

## Native UDP media and TLS control

The initial implementation used one TLS/TCP connection for media and controls to keep dependency costs low. Actual playback and overload testing showed that head-of-line blocking and custom recovery were a poor fit for Wi-Fi video. Current apps therefore use native WebRTC RTP/RTCP tracks over DTLS-SRTP UDP, with TLS retained for identity, pairing, signaling, controls and telemetry. This decision supersedes the original TCP-only design. No cloud service, external STUN/TURN server or reliable data channel is involved.

The Mac dependency is stasel/WebRTC 150.0.0, pinned by version, Git revision and binary checksum. Android pins io.github.webrtc-sdk:android:150.7871.04. Both use M150 for compatible native behavior. Bundled framework signing and license assets are part of packaging. Dependencies need ongoing security review and upgrades; see [notices](../THIRD_PARTY_NOTICES.md). [Native WebRTC development](https://webrtc.github.io/webrtc-org/native-code/development/).

The generic M150 Mac encoder factory advertises H.264 level 3.1, which cannot encode 1080p. Miraya advertises level 4.2, checks Android's decoder limits, and scales output to the negotiated receiving level. Android's generic H.264 declaration is raised only within reported platform decoder capacity. This avoids a successful handshake followed by a permanently failing VideoToolbox encoder.

Native congestion control adapts bitrate and resolution while prioritizing frame cadence. Audio/video use synchronized native tracks; packet pacing, NACK/RTX and keyframe feedback replace the application's TCP media queue. M150's default screen-sharing profile permits almost three seconds of pacing queue. Miraya retains screen-content handling while setting supported screen-sharing pacing/probing to factor 1.5 and a 200ms queue allowance. Quality/resume changes remove old scaler restrictions before restoring frame priority; a bounded retry restores larger dimensions after bandwidth recovers. Receiver presentation/drop feedback separately limits frame rate and pixels when TV playback cannot keep up, rather than assuming network feedback measures decoder capacity. Actual latency includes capture, network, codec and TV processing, and must be measured on hardware. HLS/DASH segment buffering remains unsuitable for interactive sharing.

## Discovery and pairing

Android NSD publishes `_miraya._tcp.`; the Mac browses Bonjour. TXT carries version and stable receiver UUID only. A manual IP/port path handles multicast-disabled routers, VPNs and emulator testing. Android's NSD supports service discovery on the local network without an internet service. [Android local connectivity and NSD](https://developer.android.com/develop/connectivity/wifi).

First pairing uses a fresh six-digit short authentication string bound to the full TLS certificate, client UUID and both committed session nonces. Compare the two screens, confirm on the Mac, then approve with the TV remote. The code is never sent as a password. Saved sessions pin the entire certificate and require a random 256-bit token. Older diagnostics retain certificate-prefix verification, but normal apps expose six digits. See [security](SECURITY.md) and [protocol](../protocol/PROTOCOL.md).

Bluetooth was rejected: existing Wi-Fi/Ethernet already carries media, while Bluetooth would add permissions, cross-platform pairing work and limited bandwidth without solving the core screen-streaming problem. No UPnP, router configuration or inbound internet exposure is needed.

## Packaging and reproducibility

Swift Package Manager builds the Mac executable; a repository script assembles the actual `.app`, icon and Info.plist, then signs it. NSBonjourServices and NSLocalNetworkUsageDescription describe local discovery/transport. Ad-hoc signing supports local builds; public distribution requires Developer ID and notarization credentials. [Apple local-network usage description](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription), [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Android uses the versioned Gradle wrapper and SDK, with a signed development APK and a release configuration ready for an external signing key. Signing credentials never enter source control. [Android command-line builds](https://developer.android.com/build/building-cmdline).
