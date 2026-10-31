# Interaction specification

**PROPOSAL ONLY — NOT IMPLEMENTED**

## Ready and discovery

The Mac opens at Choose TV → Choose source → Share. Destination rows combine current reachability with saved-trust status. A remembered TV that is not currently reachable is labelled offline; it is not silently selected as an available endpoint. Multiple results appear in a compact destination sheet, not a permanent device-management tab. Refresh acknowledges the action immediately. Enter address remains available when Bonjour does not find the receiver.

“No TV found” gives three concrete checks: leave Miraya open on TV, use a mutually reachable local network, try its displayed address. A guest LAN, VPN, firewall, closed app and permission problem can look similar; the UI does not pretend to identify one without evidence. The Local Network recovery state says access may need attention and links directly to settings. Address entry accepts an IP/hostname and port, explains that pairing still applies, and keeps invalid input editable. A malformed address or unreachable host gets its own recovery path.

The source sheet separates screen sharing (display / window / area) from original media playback. Window selection explains application-wide audio. Area selection describes the native selection overlay and Escape cancellation. Neither the ready screen nor this prototype invents a desktop thumbnail.

## Starting and pairing

Share immediately changes the surface to Preparing, shows a spinner/milestone/elapsed time and offers Cancel. Repeated clicking is unnecessary. Later states distinguish waiting for TV, comparing numbers, waiting for remote approval and waiting for the first picture. HTML advances selected external events through a clearly labelled review control; it does not claim a real network handshake.

1. Both endpoints display the independently derived six digits, grouped `481 729` for reading.
2. Mac: “Make sure these numbers match your TV.” The user chooses Numbers match or Numbers don’t match.
3. TV: “Confirm these six digits match your Mac.” After the Mac confirms, the TV shows Allow this Mac and Decline, with **Decline focused by default**.
4. Only explicit remote approval creates new trust. Mac confirmation alone does not share anything.
5. “Connected · waiting for picture” remains a distinct state. Sharing begins only after the first presented-frame acknowledgment.

Mismatch, denial, expiry and interrupted pairing do not save new trust or silently retry approval. Retry creates a fresh attempt; it is not code entry. Cancellation ends the attempt. Later connections use the saved pin/token, while an unexpected identity change blocks the flow and asks the user to review the saved pairing.

## Live sharing

Mac headline names the destination. The source, actual encoded dimensions/frame-rate sample and selected maximum are distinct. The sample `1662 × 1080 · 30 fps` under an “Up to 1080p · 60 fps” maximum illustrates adaptation and source shape; it is not live telemetry. Pause holds the session and shows a distinct Resume action. Stop ends it and returns ready. Source changes are available while paused; switching to original media requires stopping first. Connection details opened from a paused session return to the paused state.

Quality presets are maximums, not targets guaranteed under all workloads. A static desktop or a 24 fps film need not produce 60 different frames every second. “Follow TV resolution” uses the TV’s reported **app viewport** within the selected encode ceiling, preserving source shape. It neither changes Mac display resolution nor turns a 4K TV output mode into 4K Miraya streaming.

System audio is optional. The speaker switch controls sending sound to TV; the destination selector offers Mac only, TV only and Both. The microphone is never captured. TV-only temporarily mutes the **entire default Mac output**, rather than isolating one application’s local playback. The actual app restores output through its audio guardian; the proposal warns in context and provides fallback if routing fails. The TV playback slider changes Miraya gain, not the television’s system-wide volume. Muted/zero volume is named in text.

TV ready and pairing use the reference-led mountain/lake backdrop, centered copy and a glass comparison-code panel. TV live content has no permanent brand header, status strip, receiver backdrop or watermark. The landscape shown in live review screenshots is explicitly labelled illustrative streamed wallpaper outside the TV surface. An arrow/Enter invocation brings up the control overlay. Current mirror controls are Picture, TV volume guidance, Details and Stop. There is **no active TV-originated mirror Pause**: that would be PROPOSED / FUTURE protocol work. Mac-originated pause is represented as “Paused on your Mac.” Original-media mode does support remote Pause / Play.

TV Back closes an open settings panel and restores the overlay. Back on live content or its overlay stops sharing immediately; the overlay says so. Stop is labelled, red, square-glyphed and reachable by D-pad. Back during pairing declines. Back on idle would exit the actual activity; the browser prototype announces this instead of closing the review page.

## TV presentation and remote navigation

Fit: show the entire source with possible bars. Fill: fill the surface through deliberate cropping. Stretch: fill by changing proportions. Thumbnails compare those meanings instead of using three indistinguishable rectangles. Edge Margin is one slider, 0–10%, applied symmetrically; there are no four-edge adjustments. It compensates for overscan but does not measure a physical TV’s crop. Physical Screen Fit / Just Scan remains a separate TV setting.

Arrow navigation is spatial and stays within the active panel/dialog. Enter activates the selected button. Ranges keep their native left/right behavior. Focus never lands on disabled controls. TV approval defaults Decline; removal defaults Cancel. Mac Tab follows the visible hierarchy, sheets trap focus, Escape dismisses and returns focus to the trigger. Local review controls remain outside application modal traps.

## Saved trust

Mac lists each trusted TV; TV lists each trusted Mac. Forget opens a named-device confirmation with Cancel first. Removal changes only that device; offline status does not prevent deleting local trust. Explain that the device must pair again. Do not include a destructive Forget all as the sole management option. Last-seen dates are omitted because they are not stored. TV room-name presets are simulated; custom input in the current app uses the TV’s native text dialog and is described rather than impersonating that keyboard.

## Connection details and diagnosis

Primary screen: actual output plus selected maximum. Secondary details: encoded size, TV presentation fps and drops, encoder adaptation, traffic, target bitrate, estimated available bandwidth, recent loss, jitter, **network RTT**, receiver scale/limits, TV app viewport and TV physical output mode. Every mock measurement says Illustrative.

RTT measures a network round trip; it excludes capture, encoding, decoding, frame queues and display scanout. It must never be relabelled display latency or total latency. A bandwidth estimate is not a Wi-Fi speed test. Miraya does not measure router distance or RSSI. The warning state names measured loss/adaptation and links to details; it does not blame Wi-Fi merely because a video looks poor.

Report export is a native local save action in the real app. The review explains its contents and privacy boundary, without faking file access or uploading anything. Keep raw engineering messages in expandable details.

## Recovery matrix

| Observed condition | User-facing action |
|---|---|
| No devices / saved TV offline / app possibly closed | Open Miraya on TV, refresh, verify mutual LAN reachability, enter address |
| Discovery access unavailable | Open Local Network settings, return and retry; other causes remain possible |
| Capture access denied or stale | Open Recording settings, enable Miraya, reopen when macOS requests, check access |
| Invalid address / port | Inline correction; no connection claim |
| Connection refused / TV lost during start | Verify TV app and address, retry; never label Sharing before picture |
| Pairing rejected / mismatch / expired | End this attempt; compare a fresh code when ready |
| Invalid / revoked trust | Review and remove the named pairing, verify identity again |
| System audio unavailable | Check capture/output permission, use Mac-only fallback, keep video usable |
| Decoder problem | Try a lower fps ceiling, update apps, reconnect; no unsupported certainty about network cause |
| Unsupported media / inaccessible URL | Choose a supported file/direct HTTPS source; browser pages and cookies are not media URLs |
| Unstable network sample | Show measured symptoms and effective output; open details for evidence |
| Interrupted / reconnecting | State that screen is not being sent, show attempt count and Cancel |
| Reconnect exhausted | Stop after three attempts; give manual retry with TV/LAN checks |

Explicit Stop, denial, Back and user cancellation must not trigger automatic reconnection. Direct movies must not restart from the beginning automatically after an interruption.

## Original media and protected content

Original media is a separate source path, not “better browser capture.” Choose a local video/audio file or a compatible direct HTTPS media URL; optionally attach SRT/VTT; start the TV-native player. Mac/TV controls provide play/pause, seek, supported tracks, subtitles and gain. Codec, authentication and format support still depend on source and TV. HTML uses labelled illustrative selections rather than native file access.

Use screen sharing for browser extensions and overlays. There is no Netflix handoff button, DRM bypass, cookie/login transfer, automatic profile/title selection or remote Netflix control. The owner-confirmed Chrome graphics-setting workaround is described as device/browser dependent. No claim is made that every protected service can be captured.
