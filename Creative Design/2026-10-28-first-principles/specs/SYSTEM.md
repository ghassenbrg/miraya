# Product + visual system — proposal only

## Primary job
Share one selected Mac display directly to one paired TV over an encrypted LAN connection, with optional **system audio only**. Microphone audio is never offered.

## Pairing and trust
First pairing compares six digits on both screens and requires explicit TV-remote approval. Later connections use saved trust. Removing trust affects one Mac↔TV relationship and forces a new comparison next time.

## Quality
Presets are ceilings, never promises: `480p15`, `720p30`, `720p60`, `1080p30`, `1080p60`. Automatic adaptation may reduce actual dimensions or frame rate.

## TV framing
- **Fit** shows the entire source with bars when needed.
- **Fill** deliberately crops.
- **Stretch** changes proportions.
- One symmetric **0–10% edge-margin** compensates for overscan.

Report app viewport separately from physical output mode and mirroring encode ceiling. Example: app viewport `1920×1080`, physical output `3840×2160 @ 60 Hz`, mirroring `up to 1080p60 maximum`. A 4K panel does not imply 4K encoding.

Any RTT is labeled **network round trip**, never total display latency.

## Netflix handoff — proposal/future
Mirroring ends, the installed native TV app opens, and the TV remote handles profile/title selection. It does not mirror DRM video or transfer browser sessions, cookies or accounts.

## Palette
Ink `#10131B`; Paper `#F6F5F2`; Slate `#646B7A`; Iris `#6D5DF5`; Iris Dark `#4A3DCC`; Iris Soft `#E9E5FF`; Mint `#B8F2E6`; TV Focus Lime `#D6F65E`; Ember `#FF7A6B`; TV Ink `#08090D`.

## Type + spacing
No font files are bundled. Mac uses the system UI stack: 12–13 utility, 13–16 controls, 19–20 endpoint names, 27–29 state heading. TV uses Roboto/system: 16–17 minimum secondary copy, 20 actions, 34 brand, 44–80 primary heading, 70–126 pairing digits. Base spacing 4 px with 8/12/16/24/32/48 increments.

TV focus is a 2 px lime stroke + 5 px halo + optional 1.03 scale, never color alone.