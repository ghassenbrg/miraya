# Miraya / Beam — Review package

**PROPOSAL ONLY — NOT IMPLEMENTED**
29 October 2026 · Branch: `creative-design/2026-10-29-beam-redesign`

A complete proposal for Miraya’s identity, native Mac utility and Android / Google TV receiver. The approved Beam reference sets the visual direction; the repository sets the capability boundary. None of this package is installed in the real applications.

## Open the prototype

Open **[index.html](index.html)** in a browser. It has no build step, remote fonts, external dependencies or device access. Alternatively, serve this directory only:

```sh
python3 -m http.server 8841 --bind 127.0.0.1
```

Then open `http://127.0.0.1:8841/`. The review uses five sections: Mac experience, TV experience, Identity, App icons and Design system. The state selector exposes every principal state, including failures. Mac appearance and width can be changed in the review toolbar. These toolbar controls are not proposed product UI.

Try Choose TV → Bedroom TV → Share → Numbers match → Continue approval on TV → Allow this Mac → Simulate first picture. The simulation buttons live outside the app surface so no invented product controls appear inside it. In the TV surface use arrow keys and Enter. Esc / Backspace represents TV Back. Back closes a settings panel first; on live content it stops the session. Reset clears illustrative edits.

All devices, addresses, codes, content, counters and connection measurements are **illustrative**. There is no real desktop preview. The scenic wallpaper in live TV previews is explicitly labelled illustrative shared content outside the application surface. A real shared stream replaces the receiver backdrop.

## What to review

Start with the [visual overview](previews/review-overview.png) or its [HTML source](review-overview.html), then use the interactive prototype to inspect details.

- [Mac ready](previews/mac-ready.png), [pairing](previews/mac-pairing.png), [live](previews/mac-live.png), [recovery](previews/mac-error-recovery.png), [compact](previews/mac-compact.png), [dark](previews/mac-dark-live.png).
- [TV ready](previews/tv-ready.png), [pairing](previews/tv-pairing.png), [remote approval](previews/tv-approval.png), [live](previews/tv-live.png), [controls](previews/tv-controls.png), [picture modes](previews/tv-picture-modes.png).
- [Brand board](previews/brand-board.png), [icon board](previews/icon-board.png), [all seven actual icon sizes](previews/small-icon-test.png), [system board](previews/design-system-board.png).
- [Functionality audit](FUNCTIONAL-AUDIT.md), [design system](DESIGN-SYSTEM.md), [interaction specification](INTERACTIONS.md), [accessibility](ACCESSIBILITY.md), [critique](CRITIQUE.md), [validation](VALIDATION.md), [review checklist](REVIEW-CHECKLIST.md).

## TV scenic refinement

The receiver now follows the approved TV reference closely: layered blue-hour mountains, a quiet alpine lake, a cropped amber Beam plane on the right and its reflection in the water. Ready/recovery states use centered text; pairing uses a dark glass code panel. The backdrop is static artwork, not a continuously animated scene. The same landscape appears as clearly labelled sample streamed content in live previews; it is never placed over real shared content. Source: [TV Beam lake](assets/backgrounds/tv-beam-lake.png). Prompt and provenance: [TV background prompt](studies/tv-background-prompt.json).

## Asset delivery

`assets/logos/` contains standalone Beam symbols, light/dark and monochrome variants, horizontal/vertical lockups, eight state marks, a micro mark and outlined wordmarks. There are no font dependencies in wordmark SVGs.

`assets/icons/` contains sender/receiver artwork and optical exports at 16, 32, 64, 128, 256, 512 and 1024 px. High-resolution generated material is used for large platform icons; the 16–32 px exports use pixel-hinted vectors. The sender emphasizes the warm source plane; the receiver emphasizes the blue destination plane. At micro size, filled versus outlined planes adds a shape distinction. Names remain the authoritative role cue.

Each platform has an editable, **all-vector `icon-master.svg`**, plus a standalone **`icon-material-master.svg`** containing the selected raster material in an editable vector aperture. They are deliberately different production techniques: the vector source is for geometry and adaptable construction; the material master is the intended large-size visual finish. Source rasters are 1254 × 1254; the package does not claim native 2K/4K generation or upscale those images.

Android TV also has adaptive foreground/background sources and a 16:9 launcher banner at 1920 × 1080 and 320 × 180. The future iOS tile is **FUTURE / PROPOSED** presentation artwork; an unmasked vector construction is supplied. It is not an iOS build or App Store submission asset.

Custom picture-mode thumbnails and portable UI icon proofs live in `assets/ui/`. Actual implementation should use SF Symbols and Android platform icons for familiar actions as specified in the design system.

Generated source provenance and exact final prompts: [studies/IMAGE-PROVENANCE.md](studies/IMAGE-PROVENANCE.md), [imagegen-prompts.json](studies/imagegen-prompts.json). No brand or product UI is a generated screenshot.

## Validation and boundaries

The screenshots are actual Chromium renders of this prototype. The audit JSON files contain the measured results. Rendering and interaction checks do not certify native macOS behavior, real D-pad hardware, streaming performance or physical-TV readability. No TV was available for this proposal review.

The checkout already contained production changes before design work. `audit/repository-baseline.json` records that starting state and outside-file hashes. Final validation compares against that baseline to distinguish preexisting changes from this proposal. Sidefolk was not modified. No shipping resources, metadata, version, scripts or workflows were changed by the design work.

The archive in `exports/` contains the review package without browser-session logs. Sources remain here for inspection and refinement. Approval of the design is a later decision; implementation requires a separate instruction.
