import Foundation
import Network
import Security
import CryptoKit
import MirayaCore

struct ConnectionFailure: Error, LocalizedError {
    let message: String
    var retryable = true
    var errorDescription: String? { message }
}

/// All transport state belongs to queue. Only backpressure is read cross-thread, under lock.
final class StreamConnection {
    var onControl: (([String: Any]) -> Void)?
    var onFailure: ((ConnectionFailure) -> Void)?
    var onConnected: (() -> Void)?
    var onPairingRequired: ((String) -> Void)?
    var onCongestion: (() -> Void)?
    private(set) var fingerprint = ""
    private let queue = DispatchQueue(label: "app.miraya.network", qos: .userInteractive)
    private let pressureLock = NSLock()
    private var bufferedBytes = 0
    private var flow = StreamFlowControl()
    private var inFlightBytes = 0
    private var sendStartedAt: TimeInterval?
    private var lastCongestionAt: TimeInterval = -.infinity
    private var congestionCallbackPending = false
    private var connection: NWConnection?
    private var parser = PacketParser()
    private var sequence: UInt32 = 0
    private var packets = MediaSendQueue()
    private var sending = false
    private var closed = false
    private var established = false
    private var lastReceived = CFAbsoluteTimeGetCurrent()
    private var started = CFAbsoluteTimeGetCurrent()
    private var pending = false
    private var welcomed = false
    private var timer: DispatchSourceTimer?
    private var nonce: UInt32 = 0
    private var certificateMismatch = false
    private var identityVerified = false
    private var senderNonce: String?
    private var comparisonCode: String?
    private var pairingClientID = ""
    private var pairingStage = ""

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    var shouldEncode: Bool {
        pressureLock.lock(); defer { pressureLock.unlock() }
        return !closed && flow.shouldEncode(bufferedBytes: bufferedBytes, now: now)
    }
    var shouldSendAudio: Bool {
        pressureLock.lock(); defer { pressureLock.unlock() }
        return !closed && bufferedBytes < 128_000
    }
    private func updatePressure() {
        pressureLock.lock(); bufferedBytes = packets.byteCount + inFlightBytes; pressureLock.unlock()
    }
    private func congested() {
        let remaining = 0.75 - (now - lastCongestionAt)
        if remaining > 0 {
            // A dropped recovery IDR on a static desktop may have no subsequent
            // capture callback. Coalesce the request, but never lose it.
            if !congestionCallbackPending {
                congestionCallbackPending = true
                queue.asyncAfter(deadline: .now() + remaining) { [weak self] in
                    guard let self, !self.closed else { return }
                    self.congestionCallbackPending = false; self.congested()
                }
            }
            return
        }
        lastCongestionAt = now; onCongestion?()
    }

    func connect(to endpoint: NWEndpoint, expectedFingerprint: String?, pinned: Bool, clientID: String, name: String, token: String?) {
        if let expectedFingerprint {
            guard expectedFingerprint.count == (pinned ? 64 : 16), expectedFingerprint.allSatisfy({ "0123456789abcdef".contains($0) }) else {
                queue.async { self.fail(ConnectionFailure(message: "The saved TV identity is invalid. Forget this TV and pair again.", retryable: false)) }
                return
            }
        } else if pinned || token != nil {
            queue.async { self.fail(ConnectionFailure(message: "Saved TV credentials are incomplete. Forget this TV and pair again.", retryable: false)) }
            return
        }
        pairingClientID = clientID
        if expectedFingerprint == nil { senderNonce = PairingSession.nonce() }
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
        // A physical-TV pairing code authenticates first contact. Every later connection verifies all 256 bits.
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { [weak self] _, trust, complete in
            guard let self else { complete(false); return }
            let ref = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let cert = SecTrustCopyCertificateChain(ref) as? [SecCertificate], let leaf = cert.first else { complete(false); return }
            let hash = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
            let valid = expectedFingerprint.map { pinned ? hash == $0 : hash.hasPrefix($0) } ?? true
            self.fingerprint = hash; self.certificateMismatch = !valid
            self.identityVerified = valid && expectedFingerprint != nil
            complete(valid)
            if !valid {
                self.queue.async { self.fail(ConnectionFailure(message: "The TV identity didn’t match. Check the pairing code on the TV. If the TV was reset, forget its old pairing first.", retryable: false)) }
            }
        }, queue)
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true; tcp.connectionTimeout = 8
        let parameters = NWParameters(tls: options, tcp: tcp)
        parameters.includePeerToPeer = false
        let nw = NWConnection(to: endpoint, using: parameters)
        connection = nw
        nw.stateUpdateHandler = { [weak self] state in
            guard let self, !self.closed else { return }
            switch state {
            case .ready:
                self.established = true; self.lastReceived = CFAbsoluteTimeGetCurrent()
                var hello: [String: Any] = ["op": "hello", "version": 1, "clientId": clientID, "name": name]
                if let token { hello["token"] = token }
                if let nonce = self.senderNonce {
                    hello["pairing"] = PairingSession.method
                    hello["commitment"] = PairingSession.commitment(nonce: nonce)
                }
                self.sendControlOnQueue(hello); self.receive(); self.onConnected?()
            case .failed(let error):
                self.fail(ConnectionFailure(message: self.certificateMismatch ? "The TV identity didn’t match. Check the pairing code on the TV. If the TV was reset, forget its old pairing first." : "Couldn’t connect to the TV: \(error.localizedDescription). Check that Miraya is open on the TV and both devices are on the same network.", retryable: !self.certificateMismatch))
            case .waiting(let error):
                // Path may recover within the bounded connection deadline.
                if CFAbsoluteTimeGetCurrent() - self.started > 8 { self.fail(ConnectionFailure(message: "TV unavailable: \(error.localizedDescription)")) }
            default: break
            }
        }
        queue.async { [weak self] in self?.installTimer() }
        nw.start(queue: queue)
    }

    func confirmPairing(code: String) {
        queue.async { [weak self] in
            guard let self, !self.closed, self.pairingStage == "code", let expected = self.comparisonCode else { return }
            guard PairingCode.normalize(code) == expected else {
                self.fail(ConnectionFailure(message: "The pairing codes do not match. Nothing was shared. Select the TV again to retry.", retryable: false)); return
            }
            self.identityVerified = true; self.pairingStage = "confirmed"; self.started = CFAbsoluteTimeGetCurrent()
            self.sendControlOnQueue(["op":"pairConfirm"])
        }
    }

    func sendControl(_ object: [String: Any]) { queue.async { [weak self] in self?.sendControlOnQueue(object) } }
    private func sendControlOnQueue(_ object: [String: Any]) {
        do { enqueue(Packet(type: .control, sequence: nextSequence(), payload: try JSONSerialization.data(withJSONObject: object))) }
        catch { fail(ConnectionFailure(message: error.localizedDescription, retryable: false)) }
    }
    func send(type: PacketType, payload: Data, pts: UInt64 = 0, keyframe: Bool = false) {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            guard self.identityVerified && self.welcomed else {
                self.fail(ConnectionFailure(message: "Pairing must finish before sharing.", retryable: false)); return
            }
            self.enqueue(Packet(type: type, flags: keyframe ? 1 : 0, pts: pts, sequence: self.nextSequence(), payload: payload))
        }
    }
    private func nextSequence() -> UInt32 { defer { sequence &+= 1 }; return sequence }
    private func enqueue(_ packet: Packet) {
        guard !closed else { return }
        // Validate before retaining a caller's packet, including the wire size limit.
        do { try packet.validate() }
        catch { fail(ConnectionFailure(message: error.localizedDescription, retryable: false)); return }
        if packets.append(packet, now: now) { congested() }
        updatePressure()
        if packets.byteCount > 4_194_304 + 131_072 {
            fail(ConnectionFailure(message: "The TV control queue exceeded its limit.", retryable: false)); return
        }
        drain()
    }
    private func drain() {
        guard !sending, !packets.isEmpty, !closed else { return }
        // A transient stall should request a fresh IDR, not restart capture/TLS.
        var entry = packets.pop()
        if let current = entry, (current.packet.type == .video || current.packet.type == .audio), now - current.queuedAt > 0.2 {
            packets.discardMedia(); congested(); entry = packets.pop()
        }
        guard let entry else { updatePressure(); return }
        do {
            let data = try entry.packet.encoded()
            sending = true; inFlightBytes = data.count; sendStartedAt = now
            if entry.packet.type == .video {
                pressureLock.lock(); flow.sent(pts: entry.packet.pts, now: now); pressureLock.unlock()
            }
            updatePressure()
            connection?.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self, !self.closed else { return }
                self.inFlightBytes = 0; self.sendStartedAt = nil; self.sending = false; self.updatePressure()
                if let error { self.fail(ConnectionFailure(message: "The connection to the TV ended: \(error.localizedDescription)")) }
                else {
                    self.drain()
                    if !self.sending && self.packets.needsKeyframe { self.congested() }
                }
            })
        } catch { fail(ConnectionFailure(message: error.localizedDescription, retryable: false)) }
    }
    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self, !self.closed else { return }
            do {
                if let data, !data.isEmpty {
                    self.lastReceived = CFAbsoluteTimeGetCurrent()
                    for packet in try self.parser.append(data) {
                        let control = try packet.control
                        let op = control["op"] as? String
                        if op == "pairChallenge" {
                            guard self.senderNonce != nil, self.comparisonCode == nil, !self.welcomed,
                                  control["pairing"] as? String == PairingSession.method,
                                  let nonce = control["nonce"] as? String, PairingSession.validHex(nonce) else { throw WireError.invalidControl }
                            self.comparisonCode = PairingSession.code(fingerprint: self.fingerprint, clientID: self.pairingClientID,
                                senderNonce: self.senderNonce!, receiverNonce: nonce)
                            self.sendControlOnQueue(["op":"pairReveal", "nonce":self.senderNonce!])
                            continue
                        }
                        if op == "pending" {
                            guard !self.welcomed else { throw WireError.invalidControl }
                            let stage = control["stage"] as? String ?? "approval"
                            if self.senderNonce != nil {
                                if stage == "code" {
                                    guard self.pairingStage.isEmpty, let code = self.comparisonCode else { throw WireError.invalidControl }
                                    self.pairingStage = "code"; self.pending = true; self.started = CFAbsoluteTimeGetCurrent()
                                    self.onPairingRequired?(code)
                                    continue
                                }
                                guard stage == "approval", self.pairingStage == "confirmed", self.identityVerified else { throw WireError.invalidControl }
                            } else { guard !self.pending else { throw WireError.invalidControl } }
                            self.pairingStage = "approval"; self.pending = true; self.started = CFAbsoluteTimeGetCurrent()
                        }
                        if op == "welcome" {
                            guard !self.welcomed, self.identityVerified else { throw WireError.invalidControl }
                            self.welcomed = true; self.pending = false
                        }
                        if op == "paused" || op == "ready" {
                            self.pressureLock.lock(); self.flow = StreamFlowControl(); self.pressureLock.unlock()
                        }
                        if op == "stats", let pts = (control["lastDecodedPts"] ?? control["lastPts"]) as? NSNumber, pts.int64Value >= 0 {
                            self.pressureLock.lock()
                            self.flow.acknowledge(pts: pts.uint64Value, now: self.now)
                            self.pressureLock.unlock()
                        }
                        if !self.identityVerified && op != "ping" && op != "pong" && op != "error" {
                            throw WireError.invalidControl
                        }
                        if op == "ping" { self.sendControlOnQueue(["op":"pong", "nonce":control["nonce"] ?? 0]) }
                        else if op != "pong" {
                            self.onControl?(control)
                            // A TV stop/rejection is authoritative. Close here
                            // without a second EOF failure racing the UI actor's
                            // queued control handler and starting an auto retry.
                            if op == "error" || op == "stopped" { self.closeOnQueue(); return }
                        }
                    }
                }
                if let error { self.fail(ConnectionFailure(message: "Connection interrupted: \(error.localizedDescription)")) }
                else if complete { self.fail(ConnectionFailure(message: "The TV closed the connection. Make sure Miraya is still open on your TV.")) }
                else { self.receive() }
            } catch { self.fail(ConnectionFailure(message: error.localizedDescription, retryable: false)) }
        }
    }
    private func installTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, !self.closed else { return }
            let now = CFAbsoluteTimeGetCurrent()
            if !self.welcomed && now - self.started > (self.pairingStage == "code" ? 90 : self.pending ? 35 : 12) {
                self.fail(ConnectionFailure(message: self.pending ? "Pairing expired. Select the TV again and compare the new six-digit code." : "The TV didn’t respond. Check the TV address, Wi-Fi and local network permission.", retryable: !self.pending)); return
            }
            if self.welcomed && now - self.lastReceived > 10 { self.fail(ConnectionFailure(message: "The TV stopped responding. Check its power and network connection.")); return }
            self.pressureLock.lock()
            let stalled = self.flow.stalled(now: self.now)
            let playbackBehind = self.flow.congested(now: self.now)
            self.pressureLock.unlock()
            if stalled || self.sendStartedAt.map({ self.now - $0 > 8 }) == true {
                self.fail(ConnectionFailure(message: "TV playback stalled for 8 seconds. Check the TV and network connection.")); return
            }
            if playbackBehind || self.sendStartedAt.map({ self.now - $0 > 0.2 }) == true { self.congested() }
            if self.established { self.nonce &+= 1; self.sendControlOnQueue(["op":"ping", "nonce":self.nonce]) }
        }
        self.timer = timer; timer.resume()
    }
    private func fail(_ error: ConnectionFailure) { guard !closed else { return }; closeOnQueue(); onFailure?(error) }
    func close(gracefully: Bool = false) {
        // Retain the session until this operation runs: the UI drops its last
        // reference immediately on Stop, before a weak queued closure can fire.
        queue.async { [self] in
            if gracefully && !self.closed {
                self.sendControlOnQueue(["op":"stop"])
                self.queue.asyncAfter(deadline: .now() + 0.15) { self.closeOnQueue() }
            } else { self.closeOnQueue() }
        }
    }
    private func closeOnQueue() {
        guard !closed else { return }; pressureLock.lock(); closed = true; pressureLock.unlock()
        timer?.cancel(); timer = nil; connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        packets = MediaSendQueue(); inFlightBytes = 0; updatePressure()
    }
    deinit { timer?.cancel(); connection?.cancel() }
}
