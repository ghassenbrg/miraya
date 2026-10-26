# Miraya

Share a Mac display and optional system audio directly to an Android TV over your home network. Miraya includes a native macOS sender and a remote-friendly Android TV receiver. Streaming uses an encrypted connection between the two devices; no account, cloud relay, internet connection, or HDMI cable is needed.

V1 supports one Mac display at a time, up to 1080p, with three quality modes. TVs appear automatically by their friendly names, such as Living Room TV or Bedroom TV. The receiver fills the TV while preserving the display's aspect ratio. First-time pairing verifies the TV's identity and requires approval with its remote. Later connections use saved credentials.

## Requirements

| Component | Requirement |
| --- | --- |
| Sender | Mac running macOS 13 Ventura or later; screen recording permission |
| Receiver | Android TV / Google TV running Android 8.0 (API 26) or later, H.264 decoder, app installation access |
| Network | Devices can communicate on the same LAN; Wi-Fi or Ethernet; 5 GHz / 6 GHz Wi-Fi or wired Ethernet recommended |
| Mac development | Xcode 15 or later including Swift 5.9+; full Xcode selected with `xcode-select` |
| Android development | JDK 17 or 21, Android SDK platform 36, build-tools 36.0.0, platform-tools |

Internet access is needed to download development dependencies for the first build. The installed apps work offline on the LAN. Bluetooth is not used. TVs running proprietary non-Android operating systems cannot install the APK.

## Build both apps

Clone this repository, then run:

```sh
scripts/doctor.sh
scripts/build-macos.sh
scripts/build-android.sh
```

Outputs are `dist/Miraya.app` and `dist/Miraya-TV-debug.apk`. The debug APK is signed and directly installable. The Mac build is ad-hoc signed for local use; distribution signing and notarization are covered in [release instructions](docs/RELEASING.md).

The macOS app needs no downloaded runtime or third-party package. Open `macos/Package.swift` in Xcode to develop it. Open `android/` in Android Studio for the TV app. Android uses its checked-in Gradle wrapper; a global Gradle installation is unnecessary.

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

2. Open **Miraya** from the TV's app launcher and leave it open. Give it a recognizable room name with the TV's rename control. The name is saved and appears on your Mac automatically. Its ready screen also shows the first-connection pairing code.
3. Copy `dist/Miraya.app` to `/Applications`, then open it. Choose the named TV from **Available TVs**. If discovery is blocked, open **Connection details** on the TV and enter its address using **Connect by address…** on the Mac.
4. On first connection, enter the TV's 16-character pairing code on the Mac. Approve the Mac on the TV using the remote. Compare the code on the actual TV; do not copy it from another person's message.
5. Choose a display and quality mode, enable system audio if wanted, then start sharing. macOS asks for screen recording access. Enable Miraya under **System Settings → Privacy & Security → Screen & System Audio Recording** (the label varies by macOS version), and reopen Miraya if macOS requires it. On recent macOS versions, also allow **Local Network** access when prompted.
6. Stop from the Mac, or press **Back** on the TV. Closing the receiver also ends the stream.

Keep the same release signing key when updating the APK. Switching between debug and separately signed release APKs usually requires uninstalling the old APK; uninstalling clears pairing and the TV's identity.

The TV app advertises availability while it is open. V1 does not wake a sleeping TV or keep an invisible receiver running after you leave the app. Reopen Miraya on the TV before sharing again.

## Quality and audio

| Mode | Maximum video | Target video bitrate | Use |
| --- | --- | --- | --- |
| Efficient | 1280 × 720, 30 fps | 3 Mbit/s | Weaker Wi-Fi or older TV |
| Balanced | 1920 × 1080, 30 fps | 6 Mbit/s | Presentations, photos, browsing |
| Smooth motion | 1920 × 1080, 60 fps | 10 Mbit/s | Animation and video on a strong network |

Actual dimensions preserve the source display's aspect ratio; portrait displays are pillarboxed. Hardware and available bandwidth determine the achieved frame rate. System audio uses 48 kHz stereo PCM, adding about 1.54 Mbit/s. It needs no virtual audio driver or microphone permission. The Mac continues playing sound locally: lower the Mac's speaker volume if hearing both devices is distracting. Some apps tie volume to their own output, so test your intended player. Protected video or protected audio may be unavailable to screen capture.

Miraya prioritizes bounded latency over buffering. Poor Wi-Fi may lower quality, drop stale frames, or reconnect. This is screen mirroring for everyday viewing and demonstrations; real TV panel processing adds delay, so it is not a competitive gaming solution. Real-device latency and audio synchrony must be checked on the target TV; see [validation status](docs/TESTING.md).

## Privacy and trust

All control, video, and audio travel over TLS directly to the selected TV. Pairing verifies a certificate code displayed on the TV before sending application data, then the TV explicitly approves the sender. Later connections pin the full certificate and authenticate with a random token. Mac credentials live in Keychain; the TV's private key lives in AndroidKeyStore and tokens in app-private storage. No analytics, cloud authentication, public listener on the Mac, router port forwarding, or remote input is part of V1.

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

See [architecture and decisions](docs/DECISIONS.md) for evaluated approaches and sources. The protocol and platform capture/codec boundaries allow future Windows/Linux senders or other receivers without making those platforms V1 dependencies. Potential next steps include UDP/WebRTC transport, compressed audio, 4K/HEVC negotiation, per-window capture, and additional receivers. Internet streaming, remote control, media-file casting, and store publication are outside V1.

## License

[MIT](LICENSE).
