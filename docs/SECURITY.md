# Security and privacy

## Trust boundary

Miraya assumes you control the Mac and Android TV, can read the TV's display, and have a router that lets them communicate. Other LAN clients and discovery messages are untrusted. It does not protect against malware on either endpoint, a compromised TV OS, a malicious physically approved sender, or someone who can view/control the TV during pairing.

Pairing, authentication, control and WebRTC signaling use TLS 1.2 or later. Native media uses DTLS-SRTP with the media fingerprints bound to that authenticated signaling channel. Only audio/video SDP and bounded direct UDP candidates are accepted; no STUN/TURN service or reliable media data channel is configured. No native media session starts before authentication and an explicit start command. Legacy clients can still use media inside TLS. The TV uses an AndroidKeyStore private key and its self-signed certificate. For a new TV the TLS connection is provisional: only pairing messages, public Mac identity/name and heartbeat/error controls are allowed. Capture and stored credentials are withheld. The Mac commits to a fresh 256-bit sender nonce before the TV reveals its fresh 256-bit receiver nonce. After validating the sender's reveal, both derive a six-digit comparison code from a domain-separated SHA-256 hash of the full TV certificate fingerprint, client UUID and both nonces. The code is never sent as an authentication password. Compare the numbers on the actual screens, choose Codes match · Pair on the Mac, then approve with the TV remote. There is one code per attempt, a 90-second comparison deadline, a 30-second approval deadline, a five-second global interval between new pairing attempts, and one active session.

The commitment prevents choosing nonce material after seeing the other peer's complete short-code inputs. Six digits provide approximately one-in-a-million resistance per active substitution attempt, conditional on checking the code; being on a LAN is not itself authentication. Full SHA-256 certificate pinning and the saved random token apply to every subsequent connection. Legacy clients/diagnostics can still use the original 64-bit certificate-prefix verification plus remote approval; the ordinary apps no longer expose a long code. New senders refuse a peer that omits the short-code exchange or attempts welcome before verification. The [hash-commitment principle for short authentication strings](https://www.rfc-editor.org/rfc/rfc6189.html#section-4.4.1.1) informs this exchange; Miraya's wire format is specified in PROTOCOL.md.

Separately, the TV must approve an unknown sender with its remote. Pairing approval expires and is rate-limited. Knowing a pairing code does not by itself authorize a stream. After approval, a cryptographically random 256-bit bearer token binds the saved client ID to the receiver. A client ID or Bonjour name is not a credential. Saved credentials use Mac Keychain and Android app-private storage. Tokens must not be included in diagnostic logs or bug reports.

## Session restrictions

Only one sender can stream to the TV at a time. The receiver requires a valid hello/authentication and start sequence before accepting media. Packet type, size, header and configuration limits constrain memory allocation. Heartbeats and deadlines clear abandoned sessions. Unknown clients cannot stream while waiting for TV approval.

The app only receives while its TV activity is active. Leaving or closing it ends the current stream. Pressing Back explicitly ends the session; the Mac must not automatically override that choice. The Mac stops capture when sharing ends or the connection fails. A visible sharing state and stop control remain available on the Mac.

## Revoking and resetting

Use **Trusted Macs** on the TV to invalidate one saved Mac or forget all. Use **Manage saved TVs…** or **Forget TV** on the Mac to remove credentials. Clearing TV app data or uninstalling it deletes trust state and may replace its TLS identity, so it must be paired again. A changed certificate is an error, not a reason to silently accept a new key.

Use a distinct release signing key, keep it backed up securely, and preserve it across APK updates. A different signing key cannot update the installed app in place. Ad-hoc Mac builds are for local development; Developer ID signing provides a stable identity for normal distribution and permission behavior.

## Network and data

Mirroring and local-file playback use no cloud relay, analytics endpoint, user account, internet lookup, port forwarding or router mapping. In direct URL mode the TV fetches the user-supplied HTTPS media address and its referenced HTTPS resources; that media host receives normal request metadata. URLs can contain access tokens, so they are excluded from diagnostics. User credentials embedded in URLs, non-HTTPS resources, cross-protocol redirects and arbitrary file/content schemes are rejected. The Mac exposes no additional listener: selected-file range reads remain in the existing authenticated TLS session, restricted to explicitly opened handles and revoked on stop/failure. File paths are never accepted from the receiver.

Discovery exposes the TV service name, stable random receiver ID, protocol version and TCP port to the LAN. Screen capture can contain private windows and notifications; choose the intended display, window or area and stop when finished. Window audio covers the containing application, potentially including other tabs/windows. Protected media may be black or silent due to platform restrictions. Direct playback does not transfer browser login state, extensions or protected-service licenses.

Local diagnostic history retains at most 2,000 events for up to 72 hours, using fixed event names and allowlisted finite numeric fields. Screen/audio content, media URLs, file/device names, certificate pins and pairing tokens are excluded. Manual export saves a local JSON file; nothing is uploaded automatically.

Miraya is intended for trusted home/office networks. Do not forward its receiver port to the internet. An attacker can still deny service by disrupting Wi-Fi or flooding connections; application limits reduce resource exposure but cannot prevent network-level disruption.

## Reporting

For security reports, include the affected version, platform, reproduction steps and expected/observed behavior. Remove tokens, full screen captures of private material, and signing credentials. Do not publish an active credential as proof. Until a private reporting channel is configured, request one from the repository owner before disclosing an exploitable issue publicly.
