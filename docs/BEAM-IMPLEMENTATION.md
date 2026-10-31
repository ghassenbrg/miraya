# Beam implementation — 0.1.0, build 6

The approved Beam direction is implemented in the native macOS sender and Android TV receiver. The original proposal under `Creative Design/2026-10-29-beam-redesign/` is preserved as the design record.

## Delivered

- Compact native Mac utility: choose TV, choose source, Share. Contextual sheets replace the old navigation. Native title bar, light/dark surfaces, keyboard-accessible controls, and an accessible system-audio toggle.
- Immediate connection milestones, elapsed time, comparison pairing, explicit TV approval, cancellation and actionable recovery. Sharing still means the TV has presented its first frame.
- Live Pause/Resume/Stop, quality ceilings, actual picture/FPS reporting, separate metrics, system-audio routing, and TV playback level. Microphone audio is never captured.
- Fit/Fill/Stretch and one symmetric 0–10% Edge Margin, plus distinct app viewport/output-mode information and individual trusted-device removal.
- TV lake/mountain artwork faithful to the approved reference, large pairing digits, safe-area spacing, strong D-pad focus, contained settings panels and a transient round-button overlay. Content occupies the screen during sharing.
- Native direct-media pause/resume, seeking, tracks and subtitles remain available through the TV overlay. Mirroring Pause/Resume remains on the Mac; the receiver does not invent an unsupported reverse command.
- Related but distinguishable sender and receiver app icons, optical small-size assets, outlined wordmarks, monochrome menu symbol and launcher banner. No future iOS app is implied.

Artwork is imported reproducibly by `scripts/import-beam-assets.py`; provenance is in `assets/beam/README.md`. Normal builds use committed resources and do not need the artwork conversion dependencies.

## Validation

Evidence is under `build/beam-redesign/`:

- 39 Mac core tests: zero failures (`macos-tests.log`).
- Android unit tests and lint: successful (`android-checks.log`).
- 26 emulator instrumentation tests: zero failures (`tv-final-instrumentation.log`), including native Beam focus, pairing, discovery-race and margin tests.
- Additional real decoded direct-media UI test: pause/resume and seeking controls passed (`tv-direct-controls-test.log`).
- Mac release and Android optimized release builds succeeded. Installed Mac signature passes deep/strict verification.
- Actual native Mac views rendered at 340/420 pt widths and light/dark appearance; TV 16:9 native test screenshots rendered and inspected. Mac design-review renders contain in-memory sample state, not live telemetry.
- On the physical TV, updated the existing installation in place to 0.1.0/build 6. Existing TV identity/trust were retained; no data clearing or destructive instrumentation suite ran there.

Physical Wi-Fi evidence and measured results are recorded in `build/beam-redesign/validation.json`. Generated video/audio tests use the production TLS/authentication and WebRTC H.264/Opus path without capturing private desktop content. Their frame-drop and adaptation results are not a guarantee of constant 1080p60. Network RTT is not display or end-to-end latency. Perceptual sound and panel latency still require human observation.

Native screenshots are in `build/beam-redesign/native-previews/`. Files prefixed `tv-hardware-` are captured from the physical TV; other TV previews are emulator captures. The moving multicolor pattern in hardware live screenshots is deliberate diagnostic source content.

## Packaging and limits

The updated Mac app is installed at `/Applications/Miraya.app`; the matching development TV APK is `dist/Miraya-TV-debug.apk`. Fresh archives and checksums are in `dist/`. The merge-validation Mac package includes Apple Silicon and Intel. Public distribution still needs the normal notarization step and an Android release signing key; `Miraya-TV-unsigned.apk` is deliberately unsigned.

This redesign does not change the capture, encoding transport, audio routing or decoder implementations from the implementation-turn baseline. It does not bypass protected-video restrictions or introduce Netflix handoff. The app version remains 0.1.0. Sidefolk was not modified. The initial installation did not publish a release. Merge validation and distribution limits are recorded in `docs/TESTING.md`.
