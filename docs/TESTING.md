# Verification and product review

## Merge validation — 2026-10-31

The approved Beam design is implemented in both native applications, including the adaptive macOS menu bar template icon. Version remains 0.1.0. Fresh local validation passed 39 Swift tests, 25 Android JVM tests, Android lint, universal Apple Silicon/Intel Mac packaging with signature verification, Android debug/release packaging, five snapshot/production release-plan tests, Actionlint and Shellcheck. GitHub CI checks the PR against `master`, the repository's primary branch. Existing current GitHub Action major versions are retained.

Physical-TV validation on 2026-10-29 installed build 6 in place and passed two 30-second H.264/Opus Wi-Fi sessions with detailed scene changes, idle/resume and pinned reconnect. A separate 40-second session verified Pause/Resume, 720p/audio-off, 1080p/audio-on, mute and playback gain without replacing the peer. The scene sessions presented 1,011/1,090 and 799/879 frames against their adapted budgets; the live-controls session presented 910/931. Network RTT was 3–13 ms. The stream adapted between 720p/1080p and 30/60 fps; this is not a constant-1080p60 or glass-to-glass latency claim. Native Beam screenshots were rendered and inspected on Mac, emulator and physical TV. Detailed implementation notes are in [BEAM-IMPLEMENTATION.md](BEAM-IMPLEMENTATION.md).

The TV's Android-reported output was 1920 × 1080 at 60 Hz. That is a reported mode, not independent confirmation of native panel specifications. Actual source dimensions, encoded picture, app viewport and output mode remain distinct in the UI. Public distribution still needs production Android signing and Mac notarization; this validation does not claim a completed public release, minimum-OS hardware coverage or a 30-minute physical-TV soak.


Miraya must be tested as two cooperating applications, not merely as two builds. This document separates automated checks from emulator checks and physical-device acceptance. Do not interpret unmeasured latency or unperformed hardware tests as a pass.

## Version 0.1.0 build 6: capture sources, playback modes and diagnostics (2026-10-29)

Both platforms retain version 0.1.0 and advance their local build/versionCode to 6. The final universal Developer ID signed Mac app was installed at `/Applications/Miraya.app`; strict signature verification passed. The optimized TV APK is separately development signed for installation and uses the same local development key. The physical TV was unavailable; it was not updated during this work.

Validation:

- **39 Swift tests** pass, including selected-file authorization/range bounds and revocation, URL policy, region bounds, diagnostic allowlisting/retention and receiver-drop diagnosis (`build/modes-swift-final.log`). Universal packaging passes (`build/modes-macos-final.log`).
- **25 Android JVM tests**, lint, debug and R8-optimized release packaging pass (`build/modes-android-final.log`). All **21 Android receiver integration tests** pass without skips on the debug emulator target (`build/modes-instrumentation-final.log`). New coverage requires actual direct-file video frames/audio buffers, seekable playback, paused position, seek while paused, WebVTT selection/off/on, volume/resume, stop, rejection of unsafe/unselected media addresses and authentication before media loading. The final suite includes the bounded-request and transfer-listener changes.
- A targeted run initially failed because its cleanup answered an already-buffered file-read request after Stop closed TLS. Cleanup now drains the final acknowledgement without sending more media. An earlier attempt to attach the debug instrumentation APK to an R8 release target failed before tests because the separately built test APK expected an unoptimized Kotlin class. It is not counted as a test pass; debug instrumentation and optimized black-box checks are recorded separately, without adding production keep rules solely for the test APK.
- Native ScreenCaptureKit checks captured three generated frames each from a single window and its matching display region, with expected 16:9 output sizes (`build/capture-sources-live.log`). The generated fixture contains no private document content. In the actual installed UI, window discovery populated; dragging the area overlay stored a 320 × 180 point rectangle. These checks verify source selection/capture, not sustained physical-TV transport for each source.
- The actual installed Mac app paired with the emulator through matching six-digit codes and approval. It played the generated 640 × 360 local MP4 through encrypted file ranges, buffered ahead and paused/stopped. After installing the **R8-optimized APK**, the Mac app separately played both that local file and an accessible official HTTPS MP4 fixture. HTTPS playback showed original 320 × 180 dimensions, roughly 30 seconds buffered ahead, pause and accessibility-driven seeking to about 1:08. A different sample URL returned HTTP 403; it produced a bounded visible playback failure rather than a retry loop. These are emulator checks, not home Wi-Fi throughput or picture-quality benchmarks.
- The diagnostic report was exported through the actual Save dialog and parsed successfully. Checks found no media filename, local address, username, device name, user path, token or certificate field. Source definitions use fixed event names and numeric-field allowlists; reports exclude captured content and are never automatically uploaded.
- Final app restart retained the owner's saved Living Room TV, whole-display source, 1080p/60 selection, detail priority and Both audio destination. The temporary Mac-side emulator pairing was removed, ADB forwarding removed and test emulator stopped. Five release-plan tests, Actionlint, sourced-file Shellcheck and diff-whitespace checks passed.

The HTTPS sample check covers progressive MP4; HLS/DASH use the pinned Media3 modules but were not separately exercised against remote manifests here. External WebVTT was exercised; SRT uses Media3's supported parser but was not separately exercised in this suite. Physical-TV installation, sustained window/area mirroring, high-resolution direct-media codec capability, A/V sync, a longer video soak and production distribution signing/notarization remain acceptance work. No universal protected-playback or freeze-free claim is made.

## Version 0.1.0 build 5: startup, audio routing and live diagnostics (2026-10-29)

This supersedes the build 4 feature list below. The Netflix TV-app launcher and its protocol support were removed at the owner's request. The owner subsequently confirmed Netflix in Chrome with browser extensions could be mirrored after manually disabling Chrome graphics acceleration and relaunching it. That is user-reported compatibility on this setup, not a universal protected-playback guarantee.

The default playback priority now preserves picture detail before frame rate under sustained TV overload; motion-first scaling remains selectable. Follow TV resolution limits capture to the reported app viewport while preserving source aspect ratio. A previous physical sample with 1080p/60 selected was actually 1108 × 720 at about 32 fps and 3 ms network RTT, illustrating why preset selection alone cannot diagnose sharpness. A read-only codec-capability query reported 1080p60 AVC support on this TV; capability reporting does not establish sustained rendering performance.

Live Metrics is a separate Mac window with requested/delivered picture, sampled playback history, frame/decoder caps, encoder adaptation, bitrate, RTT, jitter, packet loss and numeric decoded-audio peak. Missing and stale samples are distinct from healthy measurements. No Wi-Fi RSSI/router distance or total display latency is inferred. New-session diagnostics reset encoder/decoder metadata rather than retaining the preceding session's values.

Startup acknowledges Start immediately, exposes milestones/elapsed time/Cancel, keeps native media initialization and Keychain saves off the UI actor, and confirms Sharing only after a first TV-presented frame. The actual installed UI displayed its Connecting card and Cancel while awaiting the TV. Mac-only/TV-only/Both routes are available. The mute guardian passed normal-parent-EOF and unexpected-parent-exit restoration checks; the output was already muted (original state 1), so the unmuted-to-muted-to-unmuted physical transition is not claimed.

Validation records: 22 Android JVM tests, lint and debug/optimized release builds passed (`build/sharing-controls-android.log`); all 18 Android integration tests passed without skips on the emulator (`build/sharing-controls-instrumentation.log`). The integration suite is deliberately not run against the owner's TV because it changes trust/test state. All **33 final Swift tests** and universal Mac packaging passed (`build/sharing-controls-swift-final.log`, `build/sharing-controls-macos-final.log`). Actionlint, Shellcheck with sourced files, five release-plan tests and diff-whitespace checks passed. The fresh packaged Mac executable matches the installed executable; strict signature verification and all four refreshed distribution checksums passed.

Build 5 was installed on both devices on October 28. The final Mac diagnostics refinement was installed on October 29 with the same Developer ID designated requirement. Its separate metrics window was inspected visually and through accessibility: missing measurements say Waiting and transport says Not connected. Start displayed the Connecting acknowledgement, elapsed time and Cancel; clicking Cancel returned to idle with Connection cancelled and enabled controls. The saved TV was offline and ADB timed out, so a new physical detail-priority/audio-routing soak is pending. Public notarization, hosted release execution and production Android signing remain unverified.

## Historical version 0.1.0 build 4: presentation, handoff experiment and workflows (2026-10-28)

The owner reported smooth sharing, including browser video, on the preceding native build. The current app version is now **0.1.0 (build/versionCode 4)** on both platforms. Source versioning comes from `VERSION`; earlier 1.0.x entries below remain historical test records.

The final universal Mac app is Developer ID signed with the same designated requirement as the installed build; strict verification passed. The optimized Android release APK was signed in a separate test copy using the existing development key. Its SHA-256 certificate matched the physical TV's previous Miraya install, allowing an in-place upgrade without clearing data or trust. Both apps were installed and opened on the user's actual Mac/TV. The TV reported versionCode 4 / versionName 0.1.0.

Validation:

- **28 Swift tests**, **22 Android JVM tests**, Android lint and optimized/debug packaging passed.
- **19 final Android integration tests passed**, with no skips. They include authenticated display reporting, all picture modes/margins without replacing the native session, malformed settings rejection, and a fixed-app Netflix handoff that acknowledges then releases media before invoking a test launch callback. Logs: `build/tv-presentation-final-instrumentation.log`, `build/tv-presentation-final-android-build.log`, `build/tv-presentation-final-swift-tests.log`.
- An initial full instrumentation run failed the existing legacy jitter/idle recovery test. That same test passed alone, the full 19-test rerun passed, and the final 19-test suite passed after the renderer changes. This was an intermittent initial-run failure, not counted as a pass. The test now records its last statistics if it fails again.
- Actual installed-app verification: saved-TV sharing resumed without new capture permission or pairing. The TV reported a 1920 × 1080 app viewport and physical output mode at 60 Hz. Fit → Fill → Fit and edge margin 0 → 2 → 0 applied while sharing stayed active. The low-bandwidth preset was selected live; one sample reported 492 × 320, 12 fps and 0.8 Mbit/s after adaptation. The 720p/60 option was selected; this brief UI check does not certify sustained 60 fps.
- The Mac subsequently received `appOpening` for Netflix and returned to idle with the expected TV-remote handoff guidance. Android's activity event log recorded creation of `com.netflix.ninja/.MainActivity`. No Netflix account/profile/title was selected by the agent, and protected Netflix playback itself was not inspected or certified. Mirroring protected video remains unsupported.
- **5 release-plan tests**, Actionlint, Shellcheck, shell syntax and diff-whitespace checks passed. CI is restricted to master pushes/PRs. Release workflows were not dispatched; publishing, repository-secret configuration, and Apple's hosted notarization path remain untested here. Sidefolk was accessed read-only.

The test emulator was stopped after final checks. The TV's native Netflix launch and the new presentation controls do not imply that protected video can be screen-captured, that every TV can sustain 60 fps, or that 4K panel dimensions are 4K encoded media. A longer physical-TV video soak, A/V sync assessment, minimum-OS checks and public-release signing/notarization acceptance remain necessary before production sign-off.

## Mac pairing/permission regression, version 1.0.1

Reproduced in the actual desktop UI: Living Room TV appeared and was selected, but Start Sharing returned ScreenCaptureKit's user-declined TCC error before any pairing. System Settings showed Miraya enabled, confirming that the running copy could still have a stale/rejected capture grant. The long error was only in the window footer.

The updated app was installed at `/Applications/Miraya.app` and launched there. Its primary action displayed Pair & Share; clicking it produced the six-digit comparison sheet for the actual discovered TV, without a prior screen-access check. Comparison/remote approval were left to the user; no unseen TV code was automatically approved. No successful screen-capture or physical playback claim is made by this UI check. All 26 Swift tests and universal packaging passed (`build/pairing-permission-tests.log`, `build/pairing-permission-build.log`).

Follow-up, 2026-10-28: the paired TV remained saved, but capture was still denied. The macOS TCC log explicitly reported `Failed to match existing code requirement for subject app.miraya.sender and service kTCCServiceScreenCapture`, with different hashes for the old grant and the running ad-hoc executable. Both app copies contained the same executable, ruling out a difference between those particular copies. A valid Developer ID Application identity was available locally. The build script now automatically selects a single such identity, requires explicit selection if several exist, and retains an explicit ad-hoc development option.

Universal packaging with Developer ID, trusted timestamp, hardened runtime and the same Team ID on the embedded WebRTC framework passed strict signature verification (`build/stable-signing-build.log`). Its designated requirement identifies the bundle/team rather than one executable hash. The signed app was installed at `/Applications/Miraya.app` and launched from that path, with the saved Living Room TV intact. Only Miraya's ScreenCapture approval was reset through `tccutil`; System Settings confirmed the stale entry disappeared. The permission-refresh Add action reached macOS's Touch ID/password prompt, which was left for the user. Capture, physical-TV playback and notarization remain unverified for this signed artifact at this point.

The user subsequently completed the macOS authentication prompt. The installed app was added through the top Screen & System Audio Recording list and restarted using macOS's Quit & Reopen action. The app then reached live sharing with the user's actual Living Room TV: its UI reported encrypted UDP, 1662 × 1080 encoding and sampled TV playback of 24 fps with 6 ms network RTT. This verifies actual capture/connection progress after refreshing the stale grant; it is not a video-soak or glass-to-glass measurement.

Version **1.0.2 (3)** was then built, signed with the same Developer ID and installed. The old and new designated requirements matched exactly. Its new help-panel **Check Screen Access** action succeeded through ScreenCaptureKit without another permission prompt, verifying that the grant survived this update. Saved-TV reconnect reached sharing again, reporting 28 fps and 4 ms network RTT in one sample. Pause and Resume changed state correctly without pairing again; a later sample still showed sharing, adapted to 1108 × 720 at 24 fps with 4 ms network RTT. These samples do not establish sustained 1080p30. All 26 Swift tests, universal packaging, strict installed-app signature verification, shell syntax, diff whitespace and final archive/APK checksums passed (`build/stable-signing-update-tests.log`, `build/stable-signing-update-build.log`). Longer browser/video playback, perceptual A/V sync, a 30-minute physical-TV soak, minimum OS checks and notarization still require acceptance testing. No freeze-free claim follows from these brief samples.

## Current native UDP validation, 2026-10-27

This section describes the current apps. Later sections retain historical TLS-media results and do not certify the new native pipeline.

The sender uses native H.264/Opus tracks over DTLS-SRTP UDP; authenticated TLS carries pairing, signaling, controls and stats. Tests use the packaged universal Mac binary and an **R8-optimized Android release APK**, signed with a development key in a separate test copy. The public release artifact remains unsigned. The SDK's JNI classes/native entry points are explicitly retained; testing caught and fixed an optimized-build startup crash that debug builds did not expose.

- **26 Swift unit tests**, **17 Android JVM tests**, Android lint and **16 Android instrumentation tests** passed, with no instrumentation skips.
- Native checks require actual EGL rendering, a nominated UDP pair, H.264/Opus negotiation, started AudioTrack, non-silent and distinct decoded left/right samples, and near-real-time audio packet/sample progression. The custom audio device uses M150's render-block path so stereo input is not truncated to half its samples.
- Five sequential scenarios passed both first pairing (displayed six-digit comparison plus TV remote approval) and saved-certificate/token reconnect. Input is generated NV12, matching production ScreenCaptureKit output. It contains detailed scene changes, a moving overlay and static intervals. Logs: `build/webrtc-delivery-tests.json`, `build/webrtc-delivery*.log`.

| Scenario (two sessions each) | Rendered callback counts | Adapted active-frame budgets | Largest sampled progress gap |
| --- | --- | --- | --- |
| 60fps maximum; automatic TV-capacity probe | 711, 685 | 759, 760 | 442ms |
| 1080p30 maximum; scenes/static/resume | 408, 379 | 421, 421 | 475ms |
| Live quality/audio/gain and nine-second pause | 806, 804 | 931, 931 | 1007ms |
| 1080p maximum; 2% loss, delay/jitter, 350ms outage | 370, 339 | 421, 421 | 614ms |
| 720p maximum; same impairments plus 8Mbps cap | 347, 392 | 421, 421 | 754ms |

Frame rates and dimensions are maximums. The emulator cannot sustain the 60fps trial reliably; playback feedback returns it to 30fps without replacing the peer or reconnecting. That scenario passes against the **adapted** target and does not demonstrate sustained 1080p60 on hardware. Healthy physical receivers can retain the higher rate after the one-time probe. Persistent 30fps overload can reduce dimensions. Live quality changes reset the trial; pause retains learned capacity.

The final sender also passed two 20-second sessions with a **nine-second static interval**, longer than the eight-second progress deadline, followed by resumed motion (326/334 render callbacks). A separate **12-second UDP outage** deliberately failed with “The TV stopped presenting video” after the presentation deadline while TLS controls still worked. That is an expected bounded failure, not a throughput pass; the normal app feeds it into its saved-device retry policy. Logs: `build/webrtc-long-static.log`, `build/webrtc-prolonged-outage.log`, `build/webrtc-liveness.json`.

Normal scene/idle cases require 90% of the adapted active-frame budget; impaired cases require 80%. Live-control checks additionally require the same media UUID, paused presentation, resumed/new-resolution output, audio state, mute and gain. The diagnostic ends input, disables cached repeats and allows 500ms for in-flight presentation/statistics before stop. Actual user stop still closes immediately. Native audio sample duration tracks elapsed time (including diagnostic drain), rather than merely reporting a running silent clock.

The UDP relay is a diagnostic workaround for emulator NAT, not a production relay or physical Wi-Fi measurement. The loss cases use 12ms one-way delay with ±8ms variation, preserve per-direction order, inject 2% random loss plus a 350ms outage, and optionally cap 720p traffic at 8Mbps. Effective losses can exceed 2% during the outage/queue limit; relay reports record the actual counts. Separate exploratory tests with aggressive per-datagram reordering and an 8Mbps 1080p cap missed throughput targets while still recovering. They are not counted as passes. Resolution/frame-rate reductions under congestion remain expected behavior.

`frames` counts EGL rendering callbacks; audio counters measure PCM offered to AudioTrack. Sampled progress gaps include the 250ms telemetry cadence and are not camera-observed freezes or glass-to-glass latency. Network RTT also excludes capture, decoding and panel processing.

Production sign-off remains outstanding: the user's physical TV/LAN, actual browser/video playback and A/V sync, a 30-minute soak, minimum-supported OS checks, visual Mac UI verification, production release signing and Mac notarization. Protected services can restrict screen/audio capture and may require their TV app. No claim of universally freeze-free Wi-Fi or production certification is made.

## Historical TLS pairing and live controls, 2026-10-27

The normal first-pairing flow now compares a fresh six-digit code on the Mac and
TV, with no typing. The receiver validates the sender's nonce commitment before
showing the code. Matching codes and TV approval precede token storage/capture;
future connections retain the original full-certificate pin and random token.
Existing saved pairings remain valid. The long certificate code is confined to
legacy protocol/diagnostic compatibility.

Quality and system-audio changes stop old capture, reconfigure receiver media,
and restart capture within the existing authenticated TLS session. The volume
slider applies AudioTrack gain immediately, including initial/restarted audio.
Pause closes capture/playout and releases audio focus; resume can use a different
display/quality/audio setting without pairing again. Power assertions and stream
progress deadlines reset with the media lifecycle. Saved settings and per-device
trust management are available on the normal UI.

Validation on the API 36 TV emulator:

- 18 Swift tests, 14 Android JVM tests and Android lint pass. Both platforms use
  the same commitment/SAS vector, including leading-zero-safe decimal output.
- All 13 instrumentation tests passed with no skips. New scenarios cover matching
  visible six-digit codes, no approval/trust before confirmation, changed nonce
  commitment rejection, saved reconnect, independent trusted-Mac revocation,
  audio/volume changes, pause/resume and stop on the same authorized connection.
  Actual fixture playback changes from 640×360 without audio to 1280×720 with
  audio, then back after pause; new-resolution video and AudioTrack progress
  are required. Generate the second fixture with:

  ```sh
  MIRAYA_FIXTURE_WIDTH=1280 MIRAYA_FIXTURE_HEIGHT=720 \
    tools/capture/test-capture.sh build/capture-fixture/720p
  ```

- All ten native-transport/independent-FFmpeg loopback cases pass, including early
  welcome, short-pairing downgrade, malformed challenge and mismatched six-digit
  code rejection. Unverified peers cannot start media.
- The native 1080p30 scene/idle smoke test completed six-digit verification using
  the actual displayed TV code and remote approval, then a full-pin saved
  reconnect. Both 20-second sessions passed the 90% active-frame budget with zero
  reported receiver drops. See `build/controls-native-smoke.log`.
- Universal Mac packaging and Android debug/optimized release builds pass. The
  Mac artifact is ad-hoc signed; the release APK remains unsigned. Normal public
  release signing/notarization and physical-TV/LAN acceptance remain outstanding.

Logs: `build/controls-checks-final.log`, `build/controls-instrumentation-final.log`,
`build/controls-loopback-final.json`, `build/controls-live-final.log`. Native desktop UI
inspection was attempted twice but the computer-use service timed out; visual
Mac UI verification is not counted as passed. Automated compilation and protocol/
media behavior do not replace physical-device UX and audio synchronization tests.

## Historical TLS performance regression validation, 2026-10-27

The freeze/reconnect fixes and their release boundary are explained in
[PERFORMANCE.md](PERFORMANCE.md). Tests ran on the Apple silicon Mac and API 36
`MirayaTV` emulator, with actual TLS, VideoToolbox, MediaCodec Surface and
AudioTrack. Generated media avoids private screen capture.

- **Reproduced before fixing:** the new jitter/idle/overflow integration scenario
  was installed with the previous `dist` receiver APK. Its 350ms interruption
  failed the presentation-progress assertion (`build/performance-baseline.log`).
- **Regression suite:** 15 Swift tests, 12 Android JVM tests, Android lint, and all
  nine Android instrumentation tests passed without skips. Coverage includes
  idle-to-motion liveness, bounded IDR recovery, progressing-but-delayed TCP,
  playback clock slips, preserved configuration, visible pairing, auth, stop and
  receiver lifecycle. The jitter/idle/overflow scenario passes with the patched
  APK (`build/performance-instrumentation.log`).
- **Native 1080p30 performance:** two 20-second sessions with detailed scene
  changes every two seconds and a six-second idle interval each. Sent 420/420
  active-period frames; final asynchronous telemetry reported 416 and 415
  scheduled, zero receiver drops, and advancing AudioTrack heads of 664,064 and
  661,888 samples. The sessions stayed connected through idle/resume. Each passed
  the 90% frame-budget requirement; the second session reused the full saved
  certificate pin and token. Maximum sampled pending-frame ages were 19ms and
  10ms; these are telemetry samples, **not display latency**. Logs:
  `build/performance-native-final.log`.
- **Native 1080p60 motion:** two 30-second sessions with detailed scene changes
  and PCM. Sent 1,798 and 1,800 frames; final telemetry reported 1,791 and 1,789
  scheduled, zero receiver drops, and successful saved-trust reconnect. This is
  a one-minute generated-media check on the emulator, not a physical-TV soak
  (`build/performance-1080p60.log`).
- **Severe bandwidth:** encrypted upload restricted to 65,536 B/s. The probe
  requested IDRs and reduced bitrate, presented only 90 frames in ten seconds,
  and correctly failed its throughput requirement in 10.62s. Sampled probe peak
  RSS was 48,576 KiB. After removing the restriction, direct 1080p30 recovered
  with 146/150 frames in final telemetry and zero receiver drops. This is a
  bounded diagnostic failure/recovery, not a claim of smooth playback at
  0.52 Mbit/s (`build/performance-bandwidth-smoke.log`).
- **Codec and packages:** the production encoder generated all 90 fixture
  frames, including a requested IDR and bitrate change; FFmpeg independently
  decoded them. Universal arm64/x86_64 Mac packaging and strict ad-hoc signature
  verification passed. Android debug and optimized unsigned release APKs built;
  the debug APK's signature verified.
- **Independent software receiver:** all six loopback cases passed on the final
  transport/encoder: sustained decode with saved-trust reconnect, incorrect
  certificate, denial, version mismatch, malformed packet and interruption
  (`build/performance-loopback-final.json`).

The local Mac build is ad-hoc signed and the Android release APK is unsigned.
No production signing/notarization, physical-TV LAN run, camera latency,
perceptual A/V sync or 30-minute hardware soak is claimed. Those remain release
acceptance gates; an emulator cannot certify the user's TV or Wi-Fi.

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

The smoke harness deliberately clears Miraya's data on the selected **emulator** to exercise first-time pairing; it refuses physical devices. It reads the six-digit session code from the displayed UI, verifies it with the native sender's local derivation, moves remote focus to Allow, streams native H.264/PCM, stops, and reconnects using the full certificate pin/token. Screenshots and logs go to `build/emulator-smoke/`. It does not read private app storage or bypass pairing. Do not run it at the same time as instrumentation tests because both control the receiver activity.

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
| Pairing | Fresh six-digit comparison, changed commitment/mismatched code fail before trust/media; TV approval still required | First connection + remote |
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

Final installed-app check, 2026-10-26: the final universal app was copied to `/Applications/Miraya.app` and its screen permission was granted through macOS Settings. It uses ScreenCaptureKit's own shareable-content authorization request, with a cancellable permission state, rather than blocking on the legacy Core Graphics preflight result. The installed UI paired with the TV emulator, reached live sharing, stopped, quit and relaunched. The saved Bedroom TV reappeared from Keychain, and selecting it started real screen sharing again without code entry or another TV approval. TV Back returned the Mac to idle with “Sharing ended on the TV”; it did not automatically reconnect. The final app and APK packages contain these fixes. Development-signature permission refresh and Keychain prompts are documented in troubleshooting; no TCC database or permission-grant bypass is used.
