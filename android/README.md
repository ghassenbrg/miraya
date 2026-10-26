# Android TV receiver

Miraya is a foreground, remote-controlled TV app. Open it before connecting from your Mac. It advertises `_miraya._tcp.` on your home network, listens on port 7421 when available, and displays its actual port and LAN addresses for manual connections. It neither contacts an internet service nor runs a hidden background receiver.

## Build and install

From the repository root, run `./scripts/setup-android.sh` if you do not have the required Android SDK components, then `./scripts/build-android.sh debug`. The script uses JDK 21, Android platform 36 and build tools 36.0.0. The app supports Android TV 8.0/API 26 and later. Gradle 8.11.1 is downloaded by the checked-in wrapper and its SHA-256 is verified.

Install `dist/Miraya-TV-debug.apk` using `adb install -r dist/Miraya-TV-debug.apk` with a USB or wireless-debugging TV connection. You can also copy the APK to your TV and use its package installer after allowing installation from that source. Debug APKs are installable development builds signed with your local Android debug key.

Open **Miraya** in the TV launcher. Choose **Rename TV** to give it a room name such as Living Room TV or Bedroom TV, or enter your own name with the TV keyboard. The name persists and appears automatically in the nearby TV list on your Mac. On the Mac choose your TV, enter the 16-character code visible on the TV, and choose **Allow** with your TV remote. Later connections reuse stored authorization. **Connection details** provides IP/port fallback when discovery is blocked. **Forget trusted Macs** revokes all existing tokens. The Mac must also forget this TV before pairing again after a reset/reinstall.

During playback use Back to stop sharing. Press a direction or Select to show the Stop sharing control. Home or switching to another app immediately closes the receiver and stream. Video is displayed with black bars when needed to preserve aspect ratio. The TV's existing volume controls adjust system audio playback.

## Release signing

`./scripts/build-android.sh release` produces an unsigned release APK when signing variables are absent. To generate an installable production release, provide all four environment variables: `MIRAYA_KEYSTORE` (absolute keystore path), `MIRAYA_KEY_ALIAS`, `MIRAYA_STORE_PASSWORD`, `MIRAYA_KEY_PASSWORD`. Partial configuration fails the build with the missing variable names. Keep the same signing key for subsequent APK updates. Keystore files and passwords must remain outside the repository. Verify with the SDK's `apksigner verify --verbose` before distributing. The release build shrinks/optimizes application code.

## Tests and diagnostics

`./scripts/test.sh` runs Android JVM framing tests with the Swift tests. Android instrumentation exercises real AndroidKeyStore TLS, approval through the visible TV UI, authorization reuse, rejection before authentication/start, incompatible versions, concurrent clients, invalid dimensions, Activity stop/resume and H.264/AudioTrack playout.

For full device tests, generate the portable capture fixture with `tools/capture/test-capture.sh`, boot a TV emulator or connect a TV, then run `cd android && ./gradlew connectedDebugAndroidTest`. The generated fixture is included only in the test APK; when absent the decoder fixture test is skipped. Other protocol/UI tests always run. Tests require port 7421 to be free and control the foreground UI, so do not run another sender or smoke test concurrently.

`adb logcat -s Miraya MediaCodec AudioTrack` provides diagnostics without logging screen content, pairing secrets or bearer tokens. A disconnected client is isolated from the listener; the next valid sender can reconnect. Socket, pairing and write deadlines bound stalled peers, and decoder/audio queues have fixed capacities.

## Permissions and limits

Only normal manifest permissions are required: internet socket access, network/Wi-Fi state, and a multicast lock for discovery. The app requests no camera, microphone, location, storage or notification permission. Application data backup is disabled. The TLS private key is generated in AndroidKeyStore; trusted Mac tokens are stored in private app storage. Android currently receives SDR H.264 up to 1080p60 and optional 48 kHz stereo PCM. Actual hardware codec and display latency varies by TV; try 720p and wired Ethernet or 5 GHz Wi-Fi if playback stutters. Protected video may be black because macOS capture honors DRM restrictions.
