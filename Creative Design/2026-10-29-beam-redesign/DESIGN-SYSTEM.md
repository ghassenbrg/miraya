# Beam design system

**PROPOSAL ONLY — NOT IMPLEMENTED**

The identity represents two endpoints, not two screens. Orange light describes the source; blue describes the destination. A short luminous connection joins their inward edges. The logo has no wireless waves, frame, play triangle, shield or letterform. Most product surfaces remain neutral so the connection carries meaning.

## Identity and optical construction

The master uses two opposed trapezoidal planes, with slightly rounded corners and a protected central gap. At large sizes, inner faces lift toward seam white. A short light bridge joins them; a thin white H-shaped scaffold was rejected. The mark has no exterior rays. Mono versions use the same silhouette and bridge; light-background color versions use a dark optical seam so the connection remains visible.

Clear space: one inner-gap width around the standalone mark; at least half the symbol’s height around display lockups. Minimum colored standalone mark: 24 px. Use the optical micro mark below 24 px. Minimum wordmark width: 58 px in product UI. Do not stretch, rotate, swap orange/blue sides or add cast/Wi-Fi badges.

The outlined wordmark starts from native system lettering and corrected optical tracking; source paths are preserved in `assets/source/`. It is purposefully restrained beside the Beam. Product controls never depend on a branding font.

## App icons and roles

Sender: warm plane emphasized. Receiver: cool plane emphasized, with a slightly squarer charcoal-navy tile and a quieter rim. Both remain vivid; early half-opacity versions looked muddy and were rejected. At 16–32 px, the active endpoint is filled and the other outlined. The white seam remains a crisp pixel feature. This shape distinction supplements color, while the app name explicitly says Receiver where relevant.

Large platform tiles use selected generated optical material with an editable rounded vector aperture; original source rasters remain intact. The separate all-vector masters describe geometry and provide scalable sources, rather than pretending that the material image is a hand-authored vector. macOS gets an inset navy tile and transparent surroundings. Android TV has a companion tile, central-safe adaptive layers and a room-legible banner. Future iOS has a porcelain light presentation tile and an unmasked vector proposal.

16/32 px are optical exceptions: no bloom, texture or extraneous rim. 64 px is the first material export; 128–1024 px retain the light depth. No export is upscaled from the 1254 px native artwork.

## Semantic palette

| Token | Light Mac | Dark Mac / TV | Use |
|---|---|---|---|
| Background | `#F6F7F9` | Mac `#17202E`; TV `#0B1323` | Main surface |
| Elevated / surface | `#FFFFFF` | Mac `#202C3D`; TV `#172237` | Sheet, menu, receiver panel |
| Primary text | `#182233` | `#F4F7FB` | Headlines, labels |
| Secondary text | `#596474` | Mac `#B4C0D1`; TV `#A8B8CD` | Explanations, values |
| Divider | `#D9DDE4` | Mac `#455165`; TV `#34465E` | Grouping, not an essential control boundary |
| Control boundary | `#7F8A9A` | Mac `#7B8DA6` | Inputs / neutral button outlines |
| Primary action | `#155DDD` with white text | Same filled primary treatment | Share / confirm |
| Focus | `#155DDD` | Mac `#9AC3FF`; TV `#BDD7FF` | Visible keyboard / remote focus |
| Success | `#237348` | Mac `#86D5A7` | Text plus status symbol |
| Warning | `#8D4D00` | Mac `#FFBD75` | Recoverable problem |
| Destructive | `#BE2C3C` | TV `#A92536`; dark-Mac text `#FF9CA5` | Stop / confirmed removal |
| Beam amber | `#FF9651` | Same | Identity, source light |
| Beam blue | `#3478F6` | Same | Identity, destination light |
| Beam seam | `#FFFFFF` | Same | Concentrated connection light |
| Near black | `#080F1D` | Same | Presentation support |

Brand gradients are decorative, not text or control fills. Use neutral/blue actions and restrained destructive red. A green status is always accompanied by “Sharing” or equivalent text. Actual computed contrast pairs are in `audit/accessibility-validation.json` and [ACCESSIBILITY.md](ACCESSIBILITY.md).

## Typography and density

Mac: native SF/system stack. Window title 12 px, primary heading 23 px / 1.17, body and controls 12–13 px, section label 12 px, secondary technical content 11–12 px. Pairing digits 42 px, monospaced tabular, grouped 3 + 3. Compact width 340 pt; normal 420 pt; expanded 540 pt. Standard window height 664 pt with a scrolling body and pinned action footer. Do not shrink type to fit excess options.

TV: platform Roboto / Noto Sans, with system/Arial fallbacks in HTML only. Scale relative to a 1920 × 1080 app viewport. Ready heading approximately 82.6 px; pairing heading 64 px; digits 155.5 px; primary instructions 32.6–36 px; controls 27–30 px; secondary guidance minimum 24 px. Metadata is secondary, never the only source of essential instructions. Use large text and focus for a remote at 2–4 m; physical couch-distance validation remains required before implementation acceptance.

Spacing uses a 4 pt base: 4, 8, 12, 16, 20, 24, 32, 40. Mac body inset 24 pt; rows approximately 62 pt. Related values share a grouped surface instead of separate cards. Button radius 7 pt; fields/groups 12 pt; window framing 14–18 pt. TV scale equivalents use approximately 16–28 px radii and generous 24–48 px spacing.

## Native composition

Mac has no sidebar, bottom navigation or main settings dashboard. Destination and source lead the ready state. Contextual sheets hold quality, picture and trust management. In live state, destination and actually delivered output lead; Pause/Resume and red Stop remain pinned. No marketing section, desktop illustration or fake preview is inserted.

TV uses 5% safe-area insets: 96 px horizontally and 54 px vertically at 1080p. The title/room sit at opposite corners. Pairing is centered, with digits larger than every decorative element. Live content fills the application; controls appear only on invocation. A compact overlay uses four mirror actions or five direct-media actions. Panels can scroll instead of cutting off controls.

## Controls, icons and focus

Primary blue is reserved for advancing a valid flow. Stop is red and includes a square icon and text. Pause has pause bars; Resume has a play symbol. Forget is a text action until confirmation; Cancel is the safe default. Never use the Beam gradient as a generic button fill.

Use SF Symbols for display, window, area, speaker, lock, pause, play, stop, information, refresh and warning on Mac. Use Android platform equivalents on TV. The delivered 24-unit SVGs specify stroke/weight and keep the prototype portable; they do not require replacing good native glyphs with a custom font. Custom Fit/Fill/Stretch thumbnails preserve a recognizable source shape to explain bars, cropping and distortion.

Keyboard ring: 3 px with 3 px separation. TV focus: near-white fill, dark text, 3 px pale-blue outline with 5 px offset and a quiet outer halo. Focus is a shape/contrast change, not only color. Selected presentation mode also has pressed semantics. Modal focus stays inside the dialog and returns to its trigger on dismissal.

## Beam states and motion

| State | Visual | Required text |
|---|---|---|
| Idle | Planes slightly apart, no connecting bridge | Ready / looking |
| Discovering | Brief, low-amplitude light activity | Looking for TVs |
| Pairing | Planes aligned, stable inner edges | Compare six digits |
| Connecting | Connected geometry, brighter seam | Preparing / waiting for picture |
| Connected | Stable seam | Sharing, only after first presented frame |
| Paused | Dimmer, narrower connection | Paused |
| Error | Planes separate, restrained warm warning | Specific failure and next action |
| Offline | Low illumination, no bridge | Offline / not reachable |

Control transitions: 120–180 ms. Connection alignment: approximately 240 ms. Discovery activity runs briefly (three cycles), not forever. No lens flare, particle motion, looping screensaver or pulsing live content. Reduced Motion removes all nonessential animation. Motion never substitutes for readable progress or an elapsed-time indicator. No handoff state is needed because Netflix handoff is outside current scope.

## TV scenic background — reference refinement

The approved reference’s mountain/lake treatment is now the receiver’s visual foundation. `assets/backgrounds/tv-beam-lake.png` is generated cinematic artwork with layered navy mountains, still water, a right-edge amber light plane and a localized warm reflection. The native source is 1672 × 941; it is presented with a minimal cover crop at 16:9. No native-4K source claim is made.

The main text moves to a centered composition. Its clear sky region is protected by a restrained scrim; the warm plane stays outside the central text area. Pairing digits sit inside a dark glass panel with consistent foreground contrast. The duplicate floating Beam illustration is removed because the landscape already carries that motif. Ready controls retain the large D-pad focus treatment. Panels have quiet opaque surfaces so details do not fight the scenery.

The artwork is static. It does not animate, pan, cycle, add a decoded-video background or consume a streaming layer. During actual sharing, received content completely replaces the idle backdrop. The HTML live previews use the landscape as an explicitly labelled illustrative shared wallpaper, not as a permanent background or watermark behind/over real content.
