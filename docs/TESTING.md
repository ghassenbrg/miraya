# Verification and product review

Miraya must be tested as two cooperating applications, not merely as two builds. This document separates automated checks from emulator checks and physical-device acceptance. Do not interpret unmeasured latency or unperformed hardware tests as a pass.

## Reproducible commands

```sh
scripts/doctor.sh
scripts/test.sh
scripts/build-macos.sh --universal
scripts/build-android.sh debug
scripts/build-android.sh release
```

Swift tests exercise shared sender protocol logic. Android unit tests exercise receiver parsing/authentication logic. Android lint checks manifest/resources/API use. CI independently builds a packaged universal Mac app and both APK variants. Test names in the repositories are the authority for precise coverage.

The production media encoder and audio conversion can also be exercised without screen-recording permission. The fixture test generates real H.264 access units and PCM from synthetic buffers, and independently decodes video when FFmpeg is installed:

```sh
tools/capture/test-capture.sh
swift build --package-path macos
python3 tools/capture/loopback_receiver.py
```

The loopback harness requires Python 3, OpenSSL and FFmpeg. It runs the shipping Swift TLS transport and encoder against a diagnostic software receiver, covering live media/reconnect plus rejected identity, denied approval, unsupported version, malformed packets and interruption. It binds only to loopback, automatically authorizes its diagnostic sender and writes `build/loopback-report.json`. That diagnostic authorization does not replace the real TV's remote approval path.

The production Bonjour browser has an integration diagnostic on a single host:

```sh
tools/discovery/test-discovery.sh
```

This publishes multiple actual NetService receivers, tests stable-ID discovery/rename/removal/restart and version filtering, and writes `build/discovery-report.json`. It checks the shipping discovery code against macOS Bonjour; it does not substitute for a home-router test with a TV.

The production Bonjour discovery implementation has a separate host integration test:

```sh
tools/discovery/test-discovery.sh
```

It compiles the actual `Discovery.swift` with a native NetService publisher, temporarily advertises disposable `Miraya Test …` entries, tests two TVs, overlapping rename advertisements with a stable UUID, removal/restart, malformed or unsupported advertisements, and refresh, then removes all test services. Results go to `build/discovery-report.json`. This exercises real macOS DNS-SD publication and browsing on one host; it does not prove multicast traversal across a router or emulator's virtual network.

For a TV emulator on a development machine:

```sh
scripts/setup-android.sh --emulator
# Add your SDK's emulator and platform-tools to PATH, or source scripts/android-env.sh.
emulator -avd MirayaTV -no-snapshot
adb wait-for-device
adb install -r dist/Miraya-TV-debug.apk
```

An emulator normally sits behind a virtual router. mDNS/LAN discovery may not cross that boundary; use `adb forward tcp:7421 tcp:7421` and the Mac sender's manual address `127.0.0.1:7421` when testing through adb. This is a development tunnel, not the normal TV setup. It still exercises TLS/authentication/media over the app's real protocol. If the TV displayed a different port, forward that port instead. Validate home-network discovery separately on a real TV.

The receiver has Android instrumentation tests, including real MediaCodec/AudioTrack operation with the generated capture fixture. Generate the fixture first, then run:

```sh
source scripts/android-env.sh
tools/capture/test-capture.sh
android/gradlew -p android connectedDebugAndroidTest
```

For a separate end-to-end run from the native Mac sender to the TV emulator:

```sh
scripts/build-macos.sh
scripts/build-android.sh
source scripts/android-env.sh
python3 tools/emulator-smoke.py --reset
```

The smoke harness deliberately clears Miraya's data on the selected **emulator** to exercise first-time pairing; it refuses physical devices. It reads the certificate code from the displayed UI, rejects a wrong code before authentication, moves remote focus to Allow, streams native H.264/PCM, stops, and reconnects using the full certificate pin/token. Screenshots and logs go to `build/emulator-smoke/`. It does not read private app storage or bypass pairing. Do not run it at the same time as instrumentation tests because both control the receiver activity.

To include a reproducible bandwidth failure and recovery:

```sh
python3 tools/emulator-smoke.py --reset --bandwidth
```

This first completes the normal native media test, then passes its encrypted TCP connection through `tools/network-shaper.py` at 64 KiB/s upload for a 1080p30 stream. The harness requires a controlled failure, samples only the diagnostic process's memory, and restores a direct connection to verify recovery. The relay keeps bounded application buffers, binds only loopback, and never decrypts or stores media. This actually limits the adb-forwarded stream; changing the emulator's simulated Wi-Fi speed alone would not affect traffic tunneled through adb. Physical-radio loss/jitter testing remains a separate check.

## Acceptance scenarios

| Scenario | Expected behavior | Test method |
| --- | --- | --- |
| First run | TV launcher entry, readable ready screen, focused remote controls; Mac explains permissions | Clean app data / clean Mac user |
| Discovery | Matching TV appears; multiple receivers remain individually selectable | Two receivers on LAN |
| TV names | Rename persists after restart, updates discovery, and preserves saved cryptographic trust | Rename two room TVs |
| Manual address | Connects when mDNS is filtered but TCP routing works | Manual IP, multicast blocked |
| Pairing | Wrong certificate code fails before application data; right code still requires TV approval | First connection + remote |
| Deny/timeout | No capture starts, useful error; a deliberate new attempt works | Deny or wait 30s |
| Saved trust | Reopen apps and reconnect without retyping code or approving | App restart |
| Revocation | Forget on TV invalidates token; explicit fresh pairing needed | Revoke + reconnect |
| Start/stop | Selected display appears full screen; Mac stop and TV Back immediately end sharing | Both controls |
| Scaling | 16:10/ultrawide/portrait sources preserve aspect and content | Multiple displays/orientations |
| Display change | Rotation/resolution change reconfigures or clearly ends/restarts; no crash | OS display settings |
| System audio | Stereo audio audible; silence and long playback do not drift materially | Flash/beep sync clip; 30min run |
| Permissions | Denial/cancellation shows recovery instructions, no capture leak | Revoke screen/local-network access |
| Unavailable TV | Connection deadline; no indefinite spinner | Receiver off / wrong IP |
| Different network | Helpful timeout; no cloud fallback | Guest Wi-Fi / client isolation |
| Receiver closes | Sender stops capture; bounded retry only for unexpected loss | Force stop, reopen |
| Network interruption | Bounded buffering, clear disconnected/reconnecting state; retries cancellable | Router/Wi-Fi interruption |
| Explicit TV stop | No automatic resume after TV Back/denial | Stop during stream |
| Congestion | Efficient mode recovers better; no unbounded memory or accumulated lag | Bandwidth/loss impairment |
| Decoder error | Receiver reports unsupported configuration; later clean connection works | Unsupported stream/limited device |
| Malformed peer | Invalid/oversized headers fail closed without OOM; sequence numbers are diagnostic | Protocol tests/integration harness |
| Busy receiver | Second sender rejected without interrupting approved stream | Two Macs or test clients |
| Offline internet | LAN streaming still works | Disconnect router WAN only |
| Minimum OS | App installs/starts or rejects unsupported environment clearly | macOS13 and Android26 devices |

## Measuring real behavior

Use a moving millisecond counter on the shared display and film both Mac and TV in the same high-frame-rate camera shot. Estimate glass-to-glass delay from their visible counters; repeat Balanced/Motion/Efficient modes, Wi-Fi and wired Ethernet, and TV game/picture modes. Report median and worst observed values alongside frame rate and hardware. Do not infer display latency from TCP round-trip time.

For audio/video sync, play a locally generated flash/click pattern and film the TV. Check initial alignment and 30-minute drift, with starts/stops and network impairment. Test more than one TV/SoC because decoder buffering and AudioTrack behavior differ. Check speech, video motion, crisp UI text, static photos, cursor, browser scrolling and presentation changes.

For network impairment, prefer a separate test router or a network link conditioner profile on the development Mac. Record its bandwidth/loss/delay settings. Restore normal networking after the test. Never disable the user's normal network without coordination.

## Environment and results log

Initial environment inspection, 2026-10-26: Apple silicon Mac, macOS 27.0.1, Xcode 27.0, Swift 6.4; JDK21.0.9; SDK platform36/build-tools36.0.0; no physical Android TV was attached. `scripts/doctor.sh` passed all prerequisite checks. Native icon generation and `iconutil` packaging passed. Additional automated/emulator results will be recorded below as they are performed.

Universal packaging check, 2026-10-26: `scripts/build-macos.sh --universal` completed. `lipo -archs` confirmed x86_64 and arm64, `vtool -show-build` confirmed minimum macOS 13.0 in both slices, `plutil -lint` passed the bundled Info.plist, and `codesign --verify --strict` passed the hardened-runtime ad-hoc signature. `ditto` produced the distributable app ZIP. This verifies packaging, not Developer ID/notarization or minimum-OS runtime behavior.

Android packaging check, 2026-10-26: debug and release Gradle builds completed, producing an installable development APK and an unsigned release APK in `dist/`. Release signing was exercised with a temporary external keystore and SDK `apksigner` verified its v2 signature. The temporary key was discarded and the normal unsigned release output restored. Kotlin license and notice assets are included. This verifies the release-signing path without claiming possession of the owner's production signing key.

Automated checks, 2026-10-26: seven Swift core tests and seven Android JVM framing tests passed. All eight Android instrumentation tests passed on the API 36 TV emulator: new-sender remote approval/saved authorization, room-name persistence/welcome, background disconnect/restart with trust retained, invalid token/media-before-start rejection, unsupported resolution/recovery, remote decline/concurrent busy handling, media-before-authentication/version rejection, and native video/audio decode with remote stop. The production Bonjour browser's eight host integration checks passed, including two named TVs, renamed overlapping advertisements, stable-ID deduplication, removal/restart and invalid-version filtering. Android lint and both package builds passed. CI configuration is included, but no remote GitHub Actions run is claimed in this local validation.

Native sender → Android TV emulator check, 2026-10-26: Android TV 16 / API 36 arm64 AVD `MirayaTV`, with its actual AndroidKeyStore TLS listener, MediaCodec Surface and AudioTrack. The smoke harness rejected an incorrect certificate code before authentication, approved a new Mac through remote D-pad focus, streamed generated H.264 + 48 kHz stereo PCM, stopped, and reconnected with the full saved certificate pin/token. Two eight-second 640×360/30 sessions rendered 238/240 and 233/240 frames with no reported drops; AudioTrack playback heads advanced to 375,360 and 368,832 samples. Ready/playback screenshots were inspected. This exercises the shipping transport/encoder and receiver playback, using generated media rather than ScreenCaptureKit or a physical audio output.

Bandwidth failure/recovery check, 2026-10-26: the same encrypted connection was relayed through the bounded loopback shaper at 65,536 B/s Mac→TV. A 1080p30 stream encountered the expected playback stall, exited with the useful “TV playback stalled… Try Efficient quality” message in 9.19 seconds, and the native probe's sampled peak RSS was 46,576 KiB. After restoring the direct connection, a five-second 1080p30 session rendered 148/150 frames, reported no drops and advanced AudioTrack to 232,832 samples. This verifies bounded failure/recovery under severe bandwidth restriction; it does not simulate physical Wi-Fi loss, establish glass-to-glass latency, or measure the GUI application's full memory footprint. Logs are reproducible under `build/emulator-smoke/`.

The same native sender/emulator path also passed two eight-second 1920×1080/60 sessions with generated video/PCM and a full pinned reconnect. Final telemetry snapshots reported 479 rendered of 479 sent with zero drops, then 461 rendered of 480 sent with four drops, and AudioTrack playback heads of 380,800 and 369,920 samples. Counts are the latest asynchronous telemetry at stop, so not every in-flight frame appears in that final snapshot. Logs are in `build/emulator-smoke/1080p60.log`. This confirms the high-frame-rate protocol/codec path on this development environment, not sustained 1080p60 support on every physical TV.

Physical-TV LAN discovery, sustained hardware decode, TV audio latency, minimum OS devices, real Wi-Fi degradation, and notarized clean-install behavior require appropriate devices/credentials and remain acceptance checks until explicitly recorded as performed. An emulator does not establish a universal claim of home-TV compatibility or latency.

Native discovery review, 2026-10-26: `tools/discovery/test-discovery.sh` passed eight checks using the actual Mac discovery class: two independently named receivers and ports; deduplication while old/new names overlap under one UUID; old-name removal; closing only one receiver; rejection of incompatible version/malformed ID; refresh without stale entries; complete disappearance; and restart with the same UUID and a fresh name/port. All temporary publishers were stopped. `build/discovery-report.json` records the host-only scope explicitly.

Mac protocol review, 2026-10-26: seven Swift unit tests passed, including bytewise TCP fragmentation, coalesced packets, the 4 MiB boundary, malformed flags/length/reserved bytes, the shared wire vector, and a high-bit timestamp rejected before payload arrival. Both platforms now accept media timestamps only in `0...Int64.max` even though the wire field occupies eight unsigned bytes.

Real capture check, 2026-10-26: the packaged Mac UI completed first-time certificate verification and TV remote approval through the emulator's local adb tunnel. ScreenCaptureKit captured the built-in Retina display, and the Android Surface showed the actual live Mac desktop with correct pillarboxing for its 16:10 aspect ratio. The TV output changed between inspected frames, confirming live playback rather than a static startup image. A three-second locally played test tone caused the receiver's AudioTrack player to report started playback with Miraya holding audio focus. Mac Stop Sharing returned the TV to its ready screen and released audio focus. This verifies actual capture and playout plumbing, not perceptual audio/video synchronization on a physical TV. Private desktop screenshots remain ignored local test artifacts and are not distributed.

The actual Android receiver appeared automatically in the Mac's TV list, and renaming it to Bedroom TV changed its displayed name live. The emulator's virtual network remains a separate routing boundary, so the real-capture connection used adb forwarding; no physical home-router discovery/routing claim follows from this check.

Saved-pairing regression, 2026-10-26: GUI testing found macOS returns `errSecParam` for a login-Keychain query combining `kSecMatchLimitAll` with `kSecReturnData`. The sender now enumerates account attributes and reads each matching item individually. A real, disposable-Keychain integration test passed create, reopen, multi-TV enumeration, update, independent revoke and missing-item handling; all eight Swift tests passed. The test uses a unique namespace and removes its own items. Existing user credentials are never inspected by that test.
