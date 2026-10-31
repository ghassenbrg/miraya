# Troubleshooting

## Choose the playback path

Use **Share screen** for Chrome extensions, browser overlays, demonstrations or general desktop use. Choose an entire display, one window or a dragged screen area. Window audio includes its containing app, potentially other browser tabs/windows. A selected window can be shared while you use other apps. Refresh its list if a window was opened/closed; choose a new area after changing the display layout. Esc cancels area selection.

**Desktop** selects 1080p/60 with motion priority; **Watching video** selects 1080p/30 with picture-detail priority. You can override quality/priority afterward. These are ceilings, not guaranteed delivered rates. The video profile does not override protected-content capture behavior.

Use **Play video on TV** for an original local video/audio file or compatible direct HTTPS media URL. The TV buffers/decodes it without screen re-encoding. MP4 and common containers, HLS and DASH depend on the TV's supported codecs. A website page, browser blob URL, login session or protected-service license is not a playable media address. A source returning HTTP 403/404 must be corrected at the source; lowering Miraya's quality cannot fix it. Non-HTTPS resources and credentials embedded in URLs are rejected.

Choose external **SRT / VTT subtitles** before starting, then select subtitle and audio tracks during playback. Use the seek bar, play/pause and TV volume from the Mac, or native player controls with the TV remote. Fit/Fill/Stretch and edge margin also apply. Stop ends the session and revokes selected-file access. After a failed direct session, restart deliberately; it is not automatically replayed from the beginning. Mirroring quality/FPS settings do not limit direct playback. This path does not include Chrome extensions.

In **Live Metrics**, direct mode shows player state, original dimensions, sampled TV presentation, drops and buffered-ahead time. Mirror mode shows encoder/network/receiver measurements. **Save diagnostic report…** saves a local JSON report with up to 72 hours / 2,000 allowlisted events; no media URLs, file/device names, pairing secrets or captured content, and no automatic upload.

## TV does not appear

Open Miraya on the TV and leave its ready screen visible. Its friendly room name should appear automatically in the Mac's Available TVs list; use Rename TV on the TV when multiple rooms need distinct names. V1 advertises while the TV app is open, rather than waking the TV or receiving invisibly in the background. Both devices need to be reachable on the same local network. The same Wi-Fi name is insufficient if a guest network or router's AP/client-isolation setting blocks device-to-device traffic. Ethernet and Wi-Fi can work together if the router bridges them.

Allow Local Network access for Miraya on macOS where available. Disconnect a VPN temporarily to test, or enable its LAN bypass. Bonjour discovery uses mDNS (UDP 5353); corporate/guest networks often block it. Open Connection details on the TV and enter its IP address/port through Connect by address on the Mac when discovery is unavailable. This still uses the same secure pairing. A manual address cannot overcome client isolation or a firewall that blocks the actual TCP connection.

If multiple TVs appear, compare their names and TV-displayed codes. The code validates the selected receiver independently of its advertised name. Never approve an unexpected Mac on the TV.

## Connection refused or timed out

Check that the TV app is foreground and shows an address. Verify its displayed port; 7421 is preferred but may differ if occupied. Restart the TV app after a network change. Home internet connectivity is irrelevant, but the router must still pass local traffic.

Do not open ports on your router. macOS's application firewall normally permits an outbound sender connection; third-party firewalls may need an allow rule for Miraya's local connection. Different subnets can work only if routing/firewall rules permit TCP, and discovery generally will not cross them.

## Pairing fails or certificate changed

Select the TV, compare the six-digit code on both screens, click Codes match · Pair on the Mac and approve on the TV. The comparison expires in 90 seconds and remote approval in 30 seconds. If the numbers differ, cancel and start a fresh attempt; do not approve a mismatch. A denial is final for that attempt; try again deliberately.

If the TV was reinstalled, its app data cleared or its identity reset, forget it on the Mac, verify the new code and pair again. If no reset was expected, investigate instead of accepting a changed identity. Revoking Macs on the TV requires pairing again; a saved UUID alone cannot regain access.

## Screen recording denied or blank

Use the packaged `Miraya.app`, preferably copied to `/Applications`, instead of running the executable directly. Enable Miraya under **System Settings → Privacy & Security → Screen & System Audio Recording** (or **Screen Recording** on older macOS versions). Close and reopen Miraya if macOS asks. After rebuilding an ad-hoc app, an old permission entry can still appear enabled while its code signature no longer matches. Turning the switch off/on may leave that old identity unchanged: select only Miraya, remove its entry with the minus button, quit and reopen Miraya, and request access again. Developer ID signing provides a stable identity across releases.

If macOS disables the Remove button, quit Miraya and reset only its screen-capture entry with `tccutil reset ScreenCapture app.miraya.sender`. This removes the stale approval; it does not grant access. Reopen `/Applications/Miraya.app` and approve its screen access again. Alternatively, use the top list's **+** button to select that installed app. Complete any Touch ID/password prompt directly in System Settings. This does not delete the TV pairing or affect other applications' permissions. The build script now prefers a single available Developer ID identity so subsequent builds retain a consistent identity; switching from an old ad-hoc signature still needs this one-time refresh.

The display must still be connected and available. Sleep, logout, display removal or a revoked permission may stop capture; reconnect and select an available display. Protected video can intentionally appear black. Screen recording permission cannot override DRM.

### Netflix has audio/subtitles but black video

The owner confirmed Netflix browser mirroring worked on this Mac after turning off **Chrome → Settings → System → Use graphics acceleration when available**, then relaunching Chrome. Translation and dual-caption extensions stay in the browser. This changes Chrome's rendering path; it is a compatibility setting, not a guaranteed Netflix-mirroring capability on every device. [Anker documents the same graphics-setting approach for captured displays](https://service.anker.com/article-description/What-Should-I-Do-If-Protected-Videos-Won-t-Play-On-My-Mac-When-Connected-to-a-DisplayLink-Monitor-A83B3). Netflix does not officially support screen mirroring as a TV playback path ([Netflix guidance](https://help.netflix.com/en/node/11634)).

The setting affects Chrome, not Miraya's hardware encoder or other apps. It can increase CPU/battery use or affect demanding browser graphics; test the actual content before assuming it will stutter. There is no Netflix TV-app launcher in the current app: the user needs browser extensions and explicitly rejected that alternative. For a protected external-display path with browser extensions and acceleration on, use a compatible HDMI/HDCP connection; a virtual screen does not itself establish HDCP.

### Sound on Mac, TV, or both

Choose **Play audio on → Mac only / TV only / Both**. Mac only disables the transmitted audio track; Both keeps local playback and sends audio to the TV. TV only temporarily mutes the Mac's default output device, affecting all local apps, while ScreenCaptureKit continues supplying system audio to the TV. Stop/quit restores the previous mute state unless the user has changed it. A small local guardian restores mute after unexpected sender exit too. Some outputs do not support automatic mute; Miraya reports that and returns to Both instead of claiming TV-only routing succeeded. TV volume still controls the receiver's playback gain.

### Picture cropped or the Mac and TV have different shapes

Update both apps, connect, then choose **TV picture → Fit** to keep the entire Mac display visible. The TV reports its app viewport and physical display mode separately; a 4K output can still host a 1080p app viewport, and encoding currently tops out at 1080p.

**Fill** fills the viewport by cropping edges; **Stretch** fills it by changing proportions. Different aspect ratios require bars to show everything without distortion. A symmetric **Edge margin** of 0–10% on each edge compensates for physical TV overscan that the app cannot measure. Start with 2–5% if desktop corners are missing, or disable overscan/use Just Scan/Screen Fit in the TV's settings. The same options are available through **Picture** on the TV remote; the TV remembers them. Changes affect presentation in the same media session, without pairing/capture restart.

## Keychain asks after a local rebuild

Saved TV authorization lives in your login Keychain. Rebuilding an ad-hoc signed app changes its code identity, so macOS may ask whether the new Miraya build can read its previously saved pairing. Approve only the Miraya build you created and intend to use; macOS may require your password. Do not share that password or the pairing token in a bug report. Release builds signed consistently with Developer ID avoid this per-build identity change. Unlock the login Keychain if the app reports a Keychain error. Forgetting a TV removes its local credentials; pairing again requires its displayed code and remote approval.

## No sound or echo

Choose the intended destination under **Play audio on**, and check that device's volume/output. Both can produce an echo because the two devices play at different times; use TV only or Mac only. ScreenCaptureKit does not capture protected audio from every application. No microphone is transmitted. Audio capture and TV output behavior should be checked with the actual app/TV you intend to use.

## Diagnose delivered quality

Open **Live Metrics** using the waveform button in the Mac app header, or the link beside the delivered-picture readout while sharing. The separate window stays available while you use other controls. It shows the selected maximum and actual encoded dimensions, sampled TV frame rate, active frame-rate cap, negotiated decoder limit, encoder/decoder implementation, recent playback graph and frame drops. Network measurements include round-trip time, jitter, recent packet loss, actual video traffic, encoder target and WebRTC's bandwidth estimate. Missing measurements say Waiting; stale measurements are explicitly flagged instead of presenting a healthy diagnosis.

If a 1080p selection delivers a smaller picture, compare the encoder adaptation reason and negotiated picture limit. **Picture detail** favors preserving dimensions and reduces frame rate first under sustained TV overload; **Smooth motion** permits reducing dimensions. WebRTC can still adapt within actual network/encoder limits. A low frame rate on a static desktop or a 24 fps film is normal and does not by itself indicate poor Wi-Fi. Network RTT is not total display latency, the bandwidth estimate is not a speed test, and Miraya cannot infer your distance from the router from these measurements.

**Follow TV resolution** uses the TV app's reported viewport within the selected preset's ceiling, preserving the Mac display's shape. It does not change macOS's display mode or manufacture extra detail. A 3024 × 1964 Mac display fitted into a 1920 × 1080 viewport yields about 1662 × 1080 encoded pixels, with bars to preserve the whole screen. Fit/Fill/Stretch changes TV presentation, not capture quality. Tiny Retina text can lose detail when downscaled; increase the source app's zoom or UI size when viewing across a room.

## Lag, stutter or picture breakup

Update **both apps** for the playback-recovery fixes. Earlier builds could disconnect on the first change after an idle desktop, stop sending the keyframes required to recover, or continually discard video after a short timing slip. These are software failures even on a fast LAN. See [performance findings and verification](PERFORMANCE.md).

Internet video is encoded in advance and can buffer seconds of content before playback. Mirroring must capture, encode, transmit and decode the current screen with a small buffer. A brief delay in any stage is visible, and loss on the shared TCP stream holds up video, audio and control together. A good internet speed test alone does not measure that path.

Try Efficient (720p/30) or Low bandwidth (480p/15), use 5 GHz/6 GHz Wi-Fi closer to the access point, or wire either endpoint with Ethernet. For motion detail, choose Smooth & light (720p/60) or Smooth motion (1080p/60). These are ceilings: the native engine considers the negotiated decoder level, TV playback progress and Wi-Fi capacity and may lower frame rate/resolution to stay responsive. Current media uses encrypted UDP; authenticated TCP carries controls/signaling. Legacy TCP media is compatibility-only. Prolonged stalls still trigger bounded reconnect. No preset can repair a congested radio channel or exceed the TV decoder's capacity.

TV picture enhancement/motion smoothing adds display latency; a TV's Game/PC picture mode can reduce it. Older TVs may not sustain 1080p60. H.264 encoding is lossy and uses 4:2:0 chroma, so tiny colored text may be less crisp than HDMI. Use a larger presentation/UI scale when needed.

## Stream stops or TV goes home

Pressing TV Back, switching apps, TV sleep or an unexpected receiver termination ends sharing. Reopen the receiver and connect from the Mac. An unexpected network loss can trigger bounded retry on the Mac; explicit stop/denial must not. If a retry cannot recover, stop and start a fresh connection. Media is never sent to a different discovered TV automatically.

## APK cannot install

Confirm this is Android TV/Google TV, Android 8.0 or later. A Samsung Tizen or LG webOS TV cannot run an Android APK. Ensure unknown-app installation is enabled for the installer or use adb. `INSTALL_FAILED_UPDATE_INCOMPATIBLE` means signing keys differ: use the same key, or uninstall the existing app first (which clears trust). `adb devices` must show the TV as `device`, not `unauthorized`; approve its debugging prompt.

## Build problems

Run `scripts/doctor.sh`. For Android, use JDK 17 or 21 and install platform 36/build-tools 36.0.0. Set `ANDROID_HOME` explicitly if your SDK is elsewhere. First builds need internet access to Maven and the Gradle distribution. For Mac builds, select full Xcode and ensure command-line license/setup is complete. CI is a second reproducibility check, not a replacement for checking capture permission and TV hardware.

## Useful diagnostics

```sh
scripts/doctor.sh
adb devices -l
adb logcat -s Miraya ActivityManager AndroidRuntime MediaCodec
dns-sd -B _miraya._tcp local.
```

The Bonjour command runs until interrupted. For a bug, include versions, quality mode, network layout, whether manual connection works, and the app's error text. Do not attach pairing tokens or private screen contents.

## Native Wi-Fi engine

Install both updated apps. Current Mac senders require a TV advertising `webrtc-udp-v1`; an older TV must be updated. Allow Miraya local-network access and direct UDP between devices. VPN routing, guest-network client isolation and per-app firewalls can allow the TLS handshake while blocking media. Miraya uses no STUN/TURN fallback. A successful pairing therefore does not prove that UDP is reachable.

The app reports network RTT separately from rendered FPS and encoder target/capacity. RTT excludes capture, encoding, decoding and TV processing. Quality modes set upper limits. Native encoder adaptation may recover after congestion; receiver-overload limits remain conservative until the quality or playback-priority selection changes. For diagnosis, compare 1080p/30 and 1080p/60, and connect the TV by Ethernet if available to remove one Wi-Fi airtime hop. Physical-device validation remains necessary.
