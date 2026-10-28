# Render validation — proposal only

The interactive HTML was rendered in headless Chromium and checked at desktop and compact widths. Representative rendered PNGs are included in `previews/`.

Validation checks:
- no horizontal clipping in tested Mac/TV widths;
- compact Mac connection plane reflows rather than clipping;
- Mac does not imply a live desktop preview;
- TV primary copy and remote actions stay inside safe-edge composition;
- six pairing digits remain visually dominant;
- D-pad focus is visible beyond color alone;
- app viewport, physical output and encode ceiling are separated;
- RTT is labeled `network round trip`;
- Netflix copy ends mirroring and keeps profile/title selection on the TV;
- iOS and Netflix are explicitly future/proposed.

Mock metrics are illustrative. PNGs are review evidence, not production assets.