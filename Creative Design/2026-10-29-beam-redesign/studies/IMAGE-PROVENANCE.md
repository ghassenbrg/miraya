# Image provenance and material direction

**PROPOSAL ONLY — NOT IMPLEMENTED**

Mode: built-in `image_gen` through the imagegen skill. No API-key CLI fallback was used. The user explicitly authorized generation and asked for reference-level finish rather than a cheap SVG adaptation.

## Inputs

`../audit/approved-beam-reference.jpg` is the supplied approved creative direction, copied unchanged for comparison. It establishes opposing warm/cool planes, a central light seam, navy support and premium restraint. It is not a claim that the reference itself is a shipping application screen.

## Selected finished artwork

Exact prompts are preserved in [imagegen-prompts.json](imagegen-prompts.json).

| Asset | Input / method | Saved source |
|---|---|---|
| macOS Sender | Generate using approved reference; single isolated tile, inward light, warm endpoint slightly emphasized | `../assets/icons/macos/icon-artwork-master.png` |
| Android TV Receiver | Edit sender source; preserve geometry/framing, subtly emphasize cool destination, retain saturated warm plane | `../assets/icons/android-tv/icon-artwork-master.png` |
| Future iOS Sender | Edit sender source; porcelain light tile, same Beam and warm emphasis | `../assets/icons/ios-future/icon-artwork-master.png` |

Built-in output IDs: sender `exec-76487ac5-bf68-472a-8075-dc4e087c7c72.png`; receiver `exec-11534b7a-d1af-4af8-899e-d10f0c86c539.png`; future iOS `exec-fcafb34c-c2e7-48d9-8187-2c2795cd3cef.png`. The original generated files remain under the session’s Codex generated-images directory; all project-used copies are inside this package.

Native output is 1254 × 1254 RGBA, despite a higher-resolution quality intention in the sender prompt. No false 2048 px claim or AI upscaling is made. A deterministic rounded vector aperture suppresses peripheral alpha specks; the original pixel source remains intact. The selected material is embedded in a standalone `icon-material-master.svg` for each platform. Native PNG exports are rendered down to 1024 / 512 / 256 / 128 / 64. The 16 / 32 px sizes are separately constructed optical vectors, not blurred downsamples.

## Initial material study

`beam-material-study.png` predates the final icon refinement. It explored three consistent satin/glass Beam treatments using the approved reference. Prompt intent was warm/cool planes, narrow seam, inward illumination and controlled depth, without UI screenshots or gaming neon, with a proposal footer. This is a summary of that exploration, not a claimed verbatim prompt. Original output ID: `exec-754991e6-a302-489e-879a-0b8154d826f4.png`.

The study’s reflection and broad light flare were not adopted as product UI. The final logo/state marks and layout are deterministic SVG/HTML/CSS, with no generated text or screen controls. The final app tile deliberately retains richer optical material than the flat construction proof. The exact final icon prompts and asset methods are disclosed so this distinction is reviewable.

Receiver v1 was rejected because it was too similar to Sender. `receiver-material-v1.png` preserves that study. The final receiver has a slightly squarer charcoal-navy tile and a quieter rim, alongside cool endpoint emphasis. The second receiver prompt is included in the exact prompt JSON.

## TV mountain / lake refinement

At the owner’s explicit request, the background inside the approved reference’s TV mockups became the visual target. Built-in `image_gen` generated `../assets/backgrounds/tv-beam-lake.png` from that reference. Exact prompt: [tv-background-prompt.json](tv-background-prompt.json). Output ID: `exec-3efddc47-3779-41c1-ae4d-d2bd78cb54c9.png`. Native output: 1672 × 941 RGBA/RGB artwork, not a claimed 4K image. The source is copied into the package and given proposal metadata; no bitmap visual retouching or artificial upscaling was applied.

The landscape closely follows the reference’s deep blue sky, layered alpine silhouettes, lake, cropped amber right-edge light plane and water reflection. UI, text, focus, scrims and glass panels remain reproducible HTML/CSS. The same asset in live previews stands for illustrative received wallpaper, explicitly labelled outside the TV surface. The receiver backdrop does not overlay actual shared video. `tv-before/` preserves the earlier plain-TV renders for comparison.
