# Security and privacy

## Trust boundary

Miraya assumes you control the Mac and Android TV, can read the TV's display, and have a router that lets them communicate. Other LAN clients and discovery messages are untrusted. It does not protect against malware on either endpoint, a compromised TV OS, a malicious physically approved sender, or someone who can view/control the TV during pairing.

All application traffic is inside TLS 1.2 or later. The TV uses an AndroidKeyStore private key and its self-signed certificate. The first 16 hexadecimal characters of the certificate's SHA-256 fingerprint appear on the TV. The Mac checks that prefix **during** TLS verification, before sending its name, credentials, screen or audio. Type it from the TV in front of you. A 64-bit prefix balances manual entry and resistance to a certificate substitution attack; full SHA-256 pinning applies after pairing.

Separately, the TV must approve an unknown sender with its remote. Pairing approval expires and is rate-limited. Knowing a pairing code does not by itself authorize a stream. After approval, a cryptographically random 256-bit bearer token binds the saved client ID to the receiver. A client ID or Bonjour name is not a credential. Saved credentials use Mac Keychain and Android app-private storage. Tokens must not be included in diagnostic logs or bug reports.

## Session restrictions

Only one sender can stream to the TV at a time. The receiver requires a valid hello/authentication and start sequence before accepting media. Packet type, size, header and configuration limits constrain memory allocation. Heartbeats and deadlines clear abandoned sessions. Unknown clients cannot stream while waiting for TV approval.

The app only receives while its TV activity is active. Leaving or closing it ends the current stream. Pressing Back explicitly ends the session; the Mac must not automatically override that choice. The Mac stops capture when sharing ends or the connection fails. A visible sharing state and stop control remain available on the Mac.

## Revoking and resetting

Use **Forget trusted Macs** on the TV to invalidate saved tokens. Use **Forget TV** on the Mac to remove its credentials. Clearing TV app data or uninstalling it deletes trust state and may replace its TLS identity, so it must be paired again. A changed certificate is an error, not a reason to silently accept a new key.

Use a distinct release signing key, keep it backed up securely, and preserve it across APK updates. A different signing key cannot update the installed app in place. Ad-hoc Mac builds are for local development; Developer ID signing provides a stable identity for normal distribution and permission behavior.

## Network and data

No cloud relay, analytics endpoint, user account, internet lookup, port forwarding or router mapping is used. Discovery exposes the TV service name, stable random receiver ID, protocol version and TCP port to the LAN. The screen can contain private windows and notifications; choose the intended display and stop sharing when finished. Protected media may be black or silent due to platform capture restrictions.

Miraya is intended for trusted home/office networks. Do not forward its receiver port to the internet. An attacker can still deny service by disrupting Wi-Fi or flooding connections; application limits reduce resource exposure but cannot prevent network-level disruption.

## Reporting

For security reports, include the affected version, platform, reproduction steps and expected/observed behavior. Remove tokens, full screen captures of private material, and signing credentials. Do not publish an active credential as proof. Until a private reporting channel is configured, request one from the repository owner before disclosing an exploitable issue publicly.
