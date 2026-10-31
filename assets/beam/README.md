# Miraya Beam artwork

Approved for implementation on 29 October 2026. The sender and receiver share the opposing amber/blue planes and luminous seam, with distinct tile and endpoint treatments.

Source: `Creative Design/2026-10-29-beam-redesign/`. Large app icons and the TV landscape use the approved AI-assisted raster material. Logos, outlined wordmarks and optical small icons have vector construction masters. Full generation provenance and exact prompts remain in the approved design package. No font files are distributed.

`macos-icon/` supplies all required ICNS raster sizes, including optical 16/32 px sources. `sources/` supplies the approved standalone SVG identity. Native Mac resources live in `macos/Sources/Miraya/Resources/`; Android artwork lives in `android/app/src/main/res/drawable-nodpi/` and `mipmap-*`.

To refresh from the approved package, run `scripts/import-beam-assets.py` with Pillow, CairoSVG and a Cairo runtime installed. This is an artwork maintenance tool; normal app builds require none of those Python dependencies. Native build scripts package the committed PNG assets without network image requests. Proposal-only metadata is omitted from shipping resource exports.
