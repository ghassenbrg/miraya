# Functional source of truth

**PROPOSAL ONLY — NOT IMPLEMENTED**

Read-only review covered the repository’s Mac and Android sources, core models, protocol, security, UX, performance, testing and release documentation, resources, manifests and workflow definitions. Existing screens were read for behavior, not used as visual templates. This is an audit of the current checkout, including its preexisting uncommitted work; it is not a claim that those changes have shipped.

| Area | Repository behavior | Consequence for this proposal |
|---|---|---|
| Mac architecture | Native SwiftUI, ScreenCaptureKit, WebRTC sender | A compact native utility, not a web dashboard. HTML is only the review medium. |
| TV receiver | Android activity, receiver service while app is open, hardware/software decoder paths | TV says to keep Miraya open. Closing / Back ends receiving. |
| Discovery | Bonjour plus saved-device and manual endpoint recovery | Nearby/offline states; refresh and address entry. Failure alone cannot prove wrong Wi-Fi, denied permission or a closed TV app. |
| First pairing | Both endpoints derive six digits from the full certificate/nonce commitment; Mac comparison then explicit TV approval | Read-only `481 729` on both screens. Never type a long code. Default TV action is Decline. |
| Pairing time limits | 90-second comparison and 30-second approval window | Separate illustrative expiry messages and safe retry. No automatic trust after timeout. |
| Saved trust | Full certificate pin plus token in Mac Keychain; receiver identity/trust storage | Per-device Forget with confirmation; changed identity blocks reconnect. No silent pin replacement. |
| Last seen | Persistent last-seen timestamps are not stored | Do not invent dates. Use current Nearby / Currently offline. |
| Source | Whole display, selected window or selected display region | Contextual source chooser. No fabricated live preview. |
| Window audio | ScreenCaptureKit captures the containing application’s audio | Explain that one browser window does not isolate a single tab’s sound. |
| Start | Connection milestones, elapsed time, cancel and first presented-frame acknowledgment | Immediate “Preparing” feedback. Connected is distinct from Sharing. |
| Mirror pause | Mac can pause/resume and change source while paused | Clear Mac Pause / Resume / Stop. No active TV mirror-pause control. |
| Quality | 480p15 / 720p30 / 720p60 / 1080p30 / 1080p60 ceilings; adaptive behavior | Always “Up to”; requested maximum and delivered sample shown separately. |
| Profiles | Desktop selects motion/1080p60; video selects detail/1080p30; manual overrides possible | Profile and priority live in a secondary quality sheet. |
| TV size | Authenticated viewport and physical output information; capture limited by preset and aspect ratio | “Follow TV resolution” means use app viewport within ceiling. Does not change Mac display mode or promise 4K. |
| TV presentation | Fit / Fill / Stretch; symmetric edge margin 0–10% | Fit shows everything; Fill deliberately crops; Stretch distorts. One margin adjusts all edges. |
| System audio | Optional system audio only; Mac / TV / Both destinations | Speaker icon, never microphone. TV-only temporarily mutes the Mac’s entire default output. |
| Volume | Miraya playback gain from Mac; physical remote controls TV master volume | Gain slider labelled TV playback. TV overlay explains remote volume; no invented TV master-volume API. |
| Permissions | Capture access check and direct Recording / Local Network settings actions | Guidance and direct recovery actions, represented as simulations in HTML. No silent OS changes. |
| Transport | Direct encrypted local UDP/WebRTC media with pinned TLS signaling, no STUN/TURN relay | “Direct encrypted UDP” inside details. No cloud-performance claim. |
| Metrics | Actual encoded size, capture/presentation fps, bitrate/target/estimate, loss, jitter, RTT, frame drops, receiver limits | Measurements stay secondary. Network RTT is never called display or end-to-end latency. No Wi-Fi RSSI/distance diagnosis. |
| Diagnostics | Numeric allowlist, up to 72 hours / 2,000 events, manual local export | No content, names, URLs or secrets; no automatic upload. |
| Original media | Local video/audio through bounded TLS ranges; compatible direct HTTPS media; TV-native decoder, seek, pause and tracks; external SRT/VTT | Contextual “Play original media” source. Direct-media TV pause is active. No website extraction or login transfer. |
| Protected browser video | Browser/OS capture behavior can black out protected surfaces | No promised DRM mirroring. The owner’s Chrome graphics-setting workaround is contextual help, not a universal fix. |
| Netflix handoff | Removed from current scope at the owner’s request | No Netflix button, profile/title selection, remote Netflix controls, session/cookie transfer or implied handoff. |
| Release | 0.1.0 configuration and master CI / release work preexist in checkout | Read-only context. No version or workflow changes in this proposal. |

## Source map

Paths are relative to the repository root:

- `macos/Sources/Miraya/AppModel.swift`: session lifecycle, milestones, first-frame checks, reconfiguration, reconnect, playback, routing, report export; `openRecordingSettings()` and `openNetworkSettings()` at lines 848–849 at audit time.
- `macos/Sources/Miraya/{Discovery,StreamConnection,TrustStore,CaptureEngine,MacAudioRouter,PlaybackControls,SharingMetricsView}.swift`: discovery, pinning, sources, system audio, player controls and diagnostics UI.
- `macos/Sources/MirayaCore/{PairingSession,SharingOptions,AudioDestination,ConnectionStep,TVDisplay,PlaybackCapacity,StreamHealth,DiagnosticHistory,MediaFileProvider}.swift`: pairing, ceilings, dimensions, adaptation, bounded measurements and file serving.
- `android/app/src/main/java/dev/miraya/tv/{MainActivity,ReceiverServer,PairingSession,Identity,TVPresentation,RtcMediaReceiver,DirectMediaReceiver,DirectMediaPolicy}.kt`: remote approval, receiver lifecycle, identity, presentation, media and source policy.
- `protocol/PROTOCOL.md`, `docs/{SECURITY,UX,PERFORMANCE,TESTING,DECISIONS,RELEASE-NOTES}.md`: wire semantics, trust and performance boundaries.

## Capability versus proposal

Everything in this directory is a **new visual/interaction proposal**, even when it represents an existing capability. Native sheets, focus engines, system settings, native file pickers and network progress are simulated, not integrated. A redesigned receiver overlay can expose existing picture, stop and detail capabilities, but TV-originated mirroring pause would need a future protocol/application change and is intentionally absent from the active overlay. Future iOS is not implemented. A live desktop preview, stored last-seen history, physical-overscan detection, 4K mirroring and browser-session transfer are not introduced.
