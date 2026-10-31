# Validation results

**PROPOSAL ONLY — NOT IMPLEMENTED**

The final package was rendered and inspected in an owned Chromium browser session using the Playwright CLI. The source is served only from the dated proposal directory over loopback. This is design/prototype validation, not a test of native applications or a production-readiness certification.

## Rendering

[Render report](audit/render-validation.json): **27 PNG captures**, including the overview, principal Mac and TV states, brand board, icon board, all seven actual icon sizes and system board. These are real renders of `index.html` and `review-overview.html`, not AI-generated screenshots or mockup promises.

**266 state / size / appearance checks**: 37 Mac states × 3 widths (340 / 420 / 540) × 2 appearances, plus 22 TV states × 2 widths (1180 / 1920). No horizontal clipping of checked controls/headings/digits, broken images, script exceptions or misplaced pinned Mac footers were found. Vertical scrolling inside long native-style bodies/sheets is intentional; the checker does not falsely treat offscreen scroll content as a layout failure.

Important renders were visually inspected: Mac ready, compact, pairing, live and recovery; TV ready, pairing, live controls; finished app icons and their role/size board; brand and small-icon proofs; the final overview. Earlier weak output was revised as recorded in [CRITIQUE.md](CRITIQUE.md). The initial flat icon material and excessive TV overlay did not become the final proposed finish.

## Interactions and responsive behavior

[Interaction report](audit/interaction-validation.json): **64 checks** cover five quality presets, profile/priority defaults, follow-TV toggle, three audio destinations, invalid address/port, immediate start acknowledgment, six-digit comparison, explicit remote approval and first-picture distinction, pause/resume/stop, paused source changes, details return state, individual/offline trust removal and cancellation, focus trapping/restoration, picture modes, symmetric range endpoints, TV panel containment/Back, invoked overlays, direct-media pause and selection, subtitles, reduced motion, asset loading and resetting illustrative settings.

Responsive checks use 375 / 768 / 1280 px browser viewports and both Mac appearances. A compact Mac was additionally tested at **2× presentation scale**: 680 px outer window, 676 px footer inside its scaled border. This is browser presentation magnification, not native OS dynamic-text certification. At a 1920 × 1080 TV frame, pairing digits measure **155.52 px** and remain within the 5% safe region; measured safe inset is approximately 96.89 × 54.89 px including the frame border.

No page exceptions or failed HTTP resources were observed in the final interaction run. A historical `ERR_CONNECTION_RESET` during rapid rendering was investigated; the referenced SVG exists and decodes correctly, and final resource checks pass. Logs are retained locally for provenance and excluded from the clean archive.

## Scenic TV refinement

The TV receiver was revised to follow the approved reference’s mountain/lake setting closely. Ready and pairing were centered, the comparison code gained a dark glass panel, and controls gained a quiet glass surface. The live wallpaper is labelled illustrative streamed content; actual received content replaces the receiver backdrop completely. The refreshed TV previews and overview are real browser renders.

[Scenic contrast report](audit/scenic-background-validation.json): **96 text-region checks**, all passing a conservative 4.5:1 contrast threshold against actual rendered image/surface pixels. The first pass identified four weak regions; supporting foregrounds and the connection-loss text surface were corrected. Final minimum is 4.61:1.

## Assets and contrast

[Asset report](audit/asset-validation.json): all supplied SVGs parse; logo/wordmark SVGs have outlined paths rather than font-dependent text; all asset PNGs have proposal-status metadata. Both sender and receiver export at exactly 16 / 32 / 64 / 128 / 256 / 512 / 1024 px. The 16 px seam has a tested white center pixel; role variants have different pixels, not just different names/metadata. Material sources retain alpha and are not upscaled.

[Accessibility report](audit/accessibility-validation.json): all **18 solid-color contrast pairs** pass their recorded text/nontext thresholds. The measured pairs and focus behavior are described in [ACCESSIBILITY.md](ACCESSIBILITY.md). This is a targeted review, not a blanket accessibility conformance claim.

## Repository scope

[Scope report](audit/scope-validation.json) compares all **351 baseline outside files** with their starting SHA-256 hashes and checks for new outside files. Result: **zero outside modifications and zero new outside files** attributable to design work. The branch is `creative-design/2026-10-29-beam-redesign`.

The checkout already contained shipping-code changes before this task. Those remain untouched. A raw `git diff` against HEAD still shows those preexisting changes; the baseline comparison is the evidence that this proposal introduced changes only inside `Creative Design/2026-10-29-beam-redesign/`. Git whitespace diff checks were also run. No production code, icons, resources, versions, scripts, workflows or Sidefolk files were changed by this task. No commit, push or release was performed.

## Reproduce locally

Serve this folder with Python’s loopback HTTP server. Rendering uses `tools/render-review.py` / `tools/render-review.js`; interaction checks use `tools/run-interactions.py` / `tools/check-interactions.js`; asset, contrast and scope checks use `tools/check-package.py`. The browser helpers reference the local installed Playwright CLI wrapper and owned `miraya-beam` session, so adjust that wrapper path on another workstation. They do not modify the apps.

Vector construction can be rebuilt with `tools/build-assets.py` and native `tools/outline-wordmark.swift` (macOS/CoreText). Then run `tools/build-material-icons.py` to restore the selected material exports and banner. CairoSVG requires a Cairo runtime; on this Mac `DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib` is used. Original generated sources and exact final prompts are included.

## Limits

No physical TV was available. Streaming bandwidth, actual Wi-Fi behavior, decoder capacity, capture latency, native remote events, native permission prompts and native assistive technology were not tested by this proposal. Generated material is design source, not a signed platform resource. Future iOS is a concept. Applying the redesign requires a later implementation instruction and native/hardware acceptance checks.
