# Troubleshooting

## TV does not appear

Open Miraya on the TV and leave its ready screen visible. Its friendly room name should appear automatically in the Mac's Available TVs list; use Rename TV on the TV when multiple rooms need distinct names. V1 advertises while the TV app is open, rather than waking the TV or receiving invisibly in the background. Both devices need to be reachable on the same local network. The same Wi-Fi name is insufficient if a guest network or router's AP/client-isolation setting blocks device-to-device traffic. Ethernet and Wi-Fi can work together if the router bridges them.

Allow Local Network access for Miraya on macOS where available. Disconnect a VPN temporarily to test, or enable its LAN bypass. Bonjour discovery uses mDNS (UDP 5353); corporate/guest networks often block it. Open Connection details on the TV and enter its IP address/port through Connect by address on the Mac when discovery is unavailable. This still uses the same secure pairing. A manual address cannot overcome client isolation or a firewall that blocks the actual TCP connection.

If multiple TVs appear, compare their names and TV-displayed codes. The code validates the selected receiver independently of its advertised name. Never approve an unexpected Mac on the TV.

## Connection refused or timed out

Check that the TV app is foreground and shows an address. Verify its displayed port; 7421 is preferred but may differ if occupied. Restart the TV app after a network change. Home internet connectivity is irrelevant, but the router must still pass local traffic.

Do not open ports on your router. macOS's application firewall normally permits an outbound sender connection; third-party firewalls may need an allow rule for Miraya's local connection. Different subnets can work only if routing/firewall rules permit TCP, and discovery generally will not cross them.

## Pairing fails or certificate changed

Read the code on the physical TV and type all 16 hexadecimal characters. Grouping dashes/spaces are formatting. Approve within the TV's timeout. A denial is final for that attempt; try again deliberately.

If the TV was reinstalled, its app data cleared or its identity reset, forget it on the Mac, verify the new code and pair again. If no reset was expected, investigate instead of accepting a changed identity. Revoking Macs on the TV requires pairing again; a saved UUID alone cannot regain access.

## Screen recording denied or blank

Use the packaged `Miraya.app`, preferably copied to `/Applications`, instead of running the executable directly. Enable Miraya under **System Settings → Privacy & Security → Screen & System Audio Recording** (or **Screen Recording** on older macOS versions). Close and reopen Miraya if macOS asks. After rebuilding an ad-hoc app, an old permission entry can still appear enabled while its code signature no longer matches. Turning the switch off/on may leave that old identity unchanged: select only Miraya, remove its entry with the minus button, quit and reopen Miraya, and request access again. Developer ID signing provides a stable identity across releases.

The display must still be connected and available. Sleep, logout, display removal or a revoked permission may stop capture; reconnect and select an available display. Protected video can intentionally appear black. Screen recording permission cannot override DRM.

## Keychain asks after a local rebuild

Saved TV authorization lives in your login Keychain. Rebuilding an ad-hoc signed app changes its code identity, so macOS may ask whether the new Miraya build can read its previously saved pairing. Approve only the Miraya build you created and intend to use; macOS may require your password. Do not share that password or the pairing token in a bug report. Release builds signed consistently with Developer ID avoid this per-build identity change. Unlock the login Keychain if the app reports a Keychain error. Forgetting a TV removes its local credentials; pairing again requires its displayed code and remote approval.

## No sound or echo

Enable system audio in the sender before sharing, and check TV volume/output. ScreenCaptureKit does not capture protected audio from every application. No microphone is transmitted. The Mac continues local playback, so sound from both devices can be perceived as echo. Lower Mac speaker volume or use an appropriate local output. Audio capture and TV output behavior should be checked with the actual app/TV you intend to use.

## Lag, stutter or picture breakup

Try Efficient quality, use 5 GHz/6 GHz Wi-Fi closer to the access point, or wire either endpoint with Ethernet. Other downloads and weak signals create retransmission delays. Miraya uses reliable TCP: packet loss can temporarily stall subsequent media until retransmission. Bounded queues, frame skipping and reconnects keep it from building unlimited delay, but cannot repair a congested radio channel.

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
