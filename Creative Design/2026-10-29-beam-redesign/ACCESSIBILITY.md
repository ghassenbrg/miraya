# Accessibility review

**PROPOSAL ONLY — NOT IMPLEMENTED**

This is a browser prototype audit and an implementation specification. It is not a blanket WCAG certification or native VoiceOver/TalkBack acceptance result.

## Measured contrast

Computed from the actual solid semantic colors using linearized sRGB relative luminance. Full results: [audit/accessibility-validation.json](audit/accessibility-validation.json). All 18 chosen text/control pairs pass their stated thresholds. Decorative Beam gradients and nonessential dividers are not treated as text backgrounds or required control boundaries.

| Pair | Ratio | Threshold |
|---|---:|---:|
| Mac primary / background | 14.89:1 | 4.5:1 |
| Mac secondary / background | 5.60:1 | 4.5:1 |
| White Share label / blue action | 5.77:1 | 4.5:1 |
| White Stop label / red action | 5.81:1 | 4.5:1 |
| Light control boundary / white | 3.50:1 | 3:1 |
| Inactive switch / background | 4.01:1 | 3:1 |
| Dark Mac secondary / elevated surface | 7.66:1 | 4.5:1 |
| Dark control boundary / elevated surface | 4.17:1 | 3:1 |
| TV primary / background | 17.27:1 | 4.5:1 |
| TV secondary / panel | 7.88:1 | 4.5:1 |
| TV focused label / white focus fill | 16.02:1 | 4.5:1 |
| TV focus outline / button surface | 10.50:1 | 3:1 |
| TV Stop label / red | 6.99:1 | 4.5:1 |

## Focus and operation

Mac controls use visible keyboard focus. Sheets have dialog semantics, initial focus, a Tab/Shift-Tab trap and Escape dismissal. Dismissal restores the originating control’s focus. The visible order is destination → source → quality → audio → picture → primary action, with secondary help/details. Every interactive icon has a text label or accessible name; decorative glyphs are hidden from assistive technology. Toggles expose switch state; display-mode buttons expose pressed state; range controls have labels. Pairing code has an explicit spoken digit label.

TV uses a high-contrast filled focus state plus outline. Arrow-key navigation stays inside the active dialog/panel and preserves native slider operation. Approval starts on Decline; forget confirmation starts on Cancel. Stop has text, square glyph and red treatment. Pause/resume use distinct glyphs and labels. The mirror overlay contains no unsupported active pause action. The browser audit exercises remote approval, modal navigation, range endpoints, direct-media pause and Back behavior.

## Readability, safe area and scale

TV layouts are designed at 16:9 with 5% safe areas, 96 × 54 px at 1920 × 1080. Pair digits are approximately 155.5 px; primary guidance is approximately 33–36 px; controls about 27–30 px; captions at least 24 px at 1080p. Pairing artwork is subordinate to digits. The browser audit checks 1180px and full-HD layouts, with screenshots rendered at native 1920 × 1080 plus an external proposal caption. Edge Margin is an optional symmetric content inset, not a replacement for UI safe areas.

Mac body content scrolls at compact sizes while its actions remain pinned. Layout checks cover 340, 420 and 540 pt widths and both appearances. Responsive review tests use 375, 768 and 1280 px browser viewports. Additional magnification checks verify that compact Mac controls remain accessible rather than being scaled down to fit. Native macOS text-size/accessibility preferences must be tested after implementation; this HTML simulation is not a replacement for native scaling behavior.

## Non-color information and motion

Every state has a readable name. Success/paused/offline/error meanings do not depend on amber, blue, green or red alone. Sender/receiver micro marks differ in filled/outlined endpoint shape and their app names identify roles. Icon material bloom is never essential state information. Reduced Motion removes nonessential animation; the audit checks that discovery activity stops. Forced-colors mode supplies control outlines and foreground masks, but native high-contrast verification is still required after implementation.

## Privacy and clarity

“System audio” is explicit and uses a speaker, never a microphone. Permission screens explain scope and recovery. No content is shared before approval and first picture. Metrics say Illustrative. Network RTT is correctly bounded as a network measurement. “Follow TV resolution” and 4K physical output do not imply guaranteed encode resolution or frame rate.

## Remaining physical/native acceptance

Check a real remote and TV at 2–4 m, including bright-room readability, overscan, 720p viewport scaling and panel contrast. Verify VoiceOver/TalkBack names, native rotor/order, OS Increase Contrast, text scaling, focus restoration and actual permission/file dialogs once implemented. No hardware was available for this proposal; those checks are open acceptance work, not claimed passes.

## Scenic-TV contrast follow-up

After the reference-led mountain/lake background was added, contrast was checked against actual Chromium-rendered background pixels, not just palette swatches. [audit/scenic-background-validation.json](audit/scenic-background-validation.json) covers 96 text regions across ready, pairing, approval, offline/lost/expired recovery, details, picture, controls and paused states at 1920 × 1080. Text and shadows were temporarily hidden in the test render; each text rectangle was compared against its worst background luminance using a conservative 4.5:1 threshold even for large headings.

The first pass found four weak regions. Pairing/approval supporting text became seam white; scenic supporting text was brightened; the longer connection-loss instruction received a restrained dark glass surface. The corrected pass has no failures; minimum measured contrast is 4.61:1. Pairing digits remain 155.52 px and retain their dedicated glass panel. This supplements the solid-token contrast review and does not claim physical-TV accessibility acceptance.
