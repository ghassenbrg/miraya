# Miraya

Share a Mac display, one window or a selected area with optional system audio to an Android TV. Live mirroring uses native WebRTC encrypted UDP tracks, with TLS pairing and controls. Alternatively, play an original local video/audio file through the same encrypted TLS connection, or let the TV fetch a compatible HTTPS media URL. Mirroring and local-file playback need no account, cloud relay or internet connection; remote URLs need access to their media host.

Mirroring supports one capture source at a time with five presets up to 1080p/60. Direct playback preserves original media, subject to TV codec/display capabilities. TVs appear by friendly room names. First-time pairing compares six digits and requires remote approval; later connections use saved credentials.

## Requirements

| Component | Requirement |
| --- | --- |
| Sender | Mac running macOS 13 Ventura or later; screen recording permission |
| Receiver | Android TV / Google TV running Android 8.0 (API 26) or later, H.264 decoder, app installation access |
| Network | Devices can communicate on the same LAN; Wi-Fi or Ethernet; 5 GHz / 6 GHz Wi-Fi or Ethernet recommended; direct UDP between devices must be allowed |
| Mac development | Xcode 15 or later including Swift 5.9+; full Xcode selected with `xcode-select` |
| Android development | JDK 17 or 21, Android SDK platform 36, build-tools 36.0.0, platform-tools |

Internet access is needed to download development dependencies for the first build. Installed mirroring and local-file playback work offline on the LAN. Bluetooth is not used. TVs with non-Android operating systems cannot install the APK.

## Build both apps

Clone this repository, then run:

```sh
scripts/doctor.sh
scripts/build-macos.sh
scripts/build-android.sh
```

Outputs are `dist/Miraya.app` and `dist/Miraya-TV-debug.apk`. The debug APK is signed and directly installable. The Mac build uses an available Developer ID Application identity, or falls back to ad-hoc signing for local use; distribution signing and notarization are covered in [release instructions](docs/RELEASING.md).

Both builds resolve pinned native WebRTC packages and bundle the runtime; users install only the apps. SwiftPM verifies the Mac binary checksum. Open `macos/Package.swift` in Xcode to develop it. Open `android/` in Android Studio for the TV app. Android uses its checked-in Gradle wrapper; a global Gradle installation is unnecessary.

If Android tooling is missing, install Android Studio and its command-line tools, set `ANDROID_HOME` to your SDK directory, and run:

```sh
scripts/setup-android.sh
```

Scripts detect conventional SDK locations, including Android Studio's default and Homebrew's command-line SDK. They select JDK 21 or 17 when available without modifying your shell configuration.

## Install and share

1. Install the APK on the TV. With Android TV developer debugging enabled, connect using `adb connect TV_IP:5555` when supported, or use the TV's wireless-debugging pairing instructions, then run:

   ```sh
   adb install -r dist/Miraya-TV-debug.apk
   ```

   Alternatively, copy the APK to the TV and open it using a file manager. Permit that file manager to install unknown apps when Android asks. Disable debugging again when finished if you do not need it.

2. Open **Miraya** from the TV's app launcher and leave it open. Give it a recognizable room name with the TV's rename control. The name is saved and appears on your Mac automatically. Its ready screen explains how to connect; a six-digit code appears only during a new pairing.
3. Copy `dist/Miraya.app` to `/Applications`, then open it. Choose the named TV from **Available TVs**. If discovery is blocked, open **Connection details** on the TV and enter its address using **Connect by address…** on the Mac.
4. On first connection, compare the fresh six-digit code on your Mac and TV. If they match, click **Codes match · Pair** on the Mac, then choose **Allow** using the TV remote. No typing is needed. Codes expire after 90 seconds; saved TVs reconnect without another code.
5. Choose **Share screen** and an entire display, one window or selected area, then set profile/quality and audio destination. For **One window**, refresh the list; for **Selected area**, drag a rectangle (Esc cancels). Alternatively choose **Play video on TV**, select a local video/audio file or direct HTTPS media URL and optional SRT/VTT subtitles, then click Play on TV. Direct playback does not need screen capture. For mirroring, start sharing. macOS asks for screen recording access. Enable Miraya under **System Settings → Privacy & Security → Screen & System Audio Recording** (the label varies by macOS version), and reopen Miraya if macOS requires it. On recent macOS versions, also allow **Local Network** access when prompted.
6. Stop from the Mac, or press **Back** on the TV. Closing the receiver also ends the stream.

Keep the same release signing key when updating the APK. Switching between debug and separately signed release APKs usually requires uninstalling the old APK; uninstalling clears pairing and the TV's identity.

The TV app advertises availability while it is open. V1 does not wake a sleeping TV or keep an invisible receiver running after you leave the app. Reopen Miraya on the TV before sharing again.

## Quality and audio

| Mode | Maximum video | Target video bitrate | Use |
| --- | --- | --- | --- |
| Efficient | 1280 × 720, 30 fps | 3 Mbit/s | Weaker Wi-Fi or older TV |
| Balanced | 1920 × 1080, 30 fps | 6 Mbit/s | Presentations, photos, browsing |
| Smooth motion | 1920 × 1080, 60 fps | 10 Mbit/s | Animation and video on a strong network |
| Smooth & light | 1280 × 720, 60 fps | 6 Mbit/s | Motion with a smaller picture |
| Low bandwidth | 854 × 480, 15 fps | 1 Mbit/s | Limited network/device capacity |

Actual dimensions preserve the capture source’s aspect ratio. Follow TV resolution respects the reported viewport within the chosen ceiling. Desktop selects 1080p/60 with motion priority; Watching video selects 1080p/30 with detail priority. Quality and priority remain adjustable. Mirroring starts at up to 30 fps and probes a selected 60 fps maximum after healthy moving input. Hardware/network capacity determine actual output. System audio uses 48 kHz stereo Opus, capped at 192 kbit/s, with no microphone or virtual audio driver. Choose Mac only, TV only or Both; TV only temporarily mutes the Mac’s entire default output and restores its original mute on stop/exit. Protected video/audio may be unavailable to capture.

Miraya favors picture detail by default; motion priority is selectable. Native WebRTC estimates bandwidth, paces UDP packets, adapts bitrate/resolution, repairs loss and synchronizes audio/video. The screen-sharing pacer’s 200ms allowance is not total display latency. Prolonged stalls can reconnect. See [validation status](docs/TESTING.md) and [performance findings](docs/PERFORMANCE.md).

## Control a connected TV

Change **Quality**, **Playback priority**, audio destination and TV volume while mirroring. The existing authenticated media connection is retained. Fit shows the whole capture; Fill crops; Stretch changes proportions. A symmetric edge margin compensates for TV overscan. Direct playback has independent seeking, pause/play, volume, audio/subtitle-track controls and native TV controls. Remote URLs must identify compatible HTTPS media (MP4, HLS/DASH, etc.), not a website page. They do not carry Chrome extensions, website login state or a protected-service license.

**Pause Sharing** stops capture; the TV may retain its last picture. **Resume Sharing** starts fresh capture without reconnecting; you can change display, quality or audio while paused. Stop always ends the session. Pause/resume are also available in the menu bar. Do not rely on pause to remove a picture already shown on the TV.

Quality, audio, level, display and last-selected TV are remembered. **Live Metrics** opens a separate window with delivered picture, FPS, frame/decoder caps, encoder adaptation, RTT, jitter, loss and traffic. Missing/stale samples are marked. Direct playback shows buffer and player progress separately. **Save diagnostic report…** exports up to 72 hours / 2,000 local events using allowlisted numeric measurements, excluding media URLs, file/device names, credentials and screen/audio content. Nothing is uploaded automatically. **Manage saved TVs…** and the TV’s **Trusted Macs** controls revoke individual pairings.

## Privacy and trust

Pairing, media negotiation and controls use pinned TLS. Video/audio use DTLS-SRTP encrypted native UDP tracks; their DTLS fingerprints are exchanged inside authenticated TLS. Media is never sent through a reliable WebRTC data channel. No STUN/TURN server is configured and TCP ICE candidates are disabled. First pairing verifies a fresh six-digit comparison code bound to the TLS certificate and committed session nonces, then the TV explicitly approves the sender. No screen, audio or saved credentials are sent to an unverified TV. Later connections pin the full certificate and authenticate with a random token. Mac credentials live in Keychain; the TV's private key lives in AndroidKeyStore and tokens in app-private storage. No analytics, cloud authentication, public listener on the Mac, router port forwarding, or remote input is part of V1.

A local network is not automatically trustworthy. Reject unexpected approval prompts. Use **Forget trusted Macs** on the TV to revoke saved access, and forget the TV on the Mac when giving it away. See [security model](docs/SECURITY.md) for scope and limits.

## Development and verification

```sh
scripts/test.sh                         # Swift tests + Android tests/lint
scripts/build-macos.sh --debug          # Debug .app, still packaged for permissions
scripts/build-macos.sh --universal      # Apple silicon + Intel .app
scripts/build-android.sh release        # Release APK, unsigned without credentials
```

Always run the packaged `.app` for normal screen recording and permissions testing. A bare Swift executable has a different permission identity and does not contain the app's local-network usage description.

CI builds both platforms, runs unit tests and Android lint, and uploads app/APK artifacts. It cannot grant Mac screen-recording permission or measure a physical TV. [Testing](docs/TESTING.md) describes automated, emulator, and hardware checks; [troubleshooting](docs/TROUBLESHOOTING.md) covers common failures.

## Repository

```text
macos/       SwiftUI sender, ScreenCaptureKit/VideoToolbox pipeline, shared Swift core/tests
android/     Kotlin Android TV receiver, TLS server, MediaCodec/AudioTrack playback/tests
protocol/    Versioned cross-platform wire contract
scripts/     Environment checks, app/APK builds, packaging and SDK setup
tools/       Diagnostic and integration utilities
docs/        Decisions, security, testing, troubleshooting and release guide
```

See [architecture and decisions](docs/DECISIONS.md) for evaluated approaches and sources. The protocol and platform capture/codec boundaries allow future Windows/Linux senders or other receivers without making those platforms V1 dependencies. Potential next steps include 4K/HEVC negotiation, per-window capture, and additional receivers. Internet streaming, remote control, media-file casting, and store publication are outside V1.

## License

[MIT](LICENSE).
