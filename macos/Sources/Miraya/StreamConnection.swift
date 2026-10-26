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
    private(set) var fingerprint = ""
    private let queue = DispatchQueue(label: "app.miraya.network", qos: .userInteractive)
    private let pressureLock = NSLock()
    private var bufferedBytes = 0
    private var latestVideoPTS: UInt64 = 0
    private var renderedPTS: UInt64 = 0
    private var renderProgressAt = CFAbsoluteTimeGetCurrent()
    private var firstVideoAt: CFAbsoluteTime?
    private var connection: NWConnection?
    private var parser = PacketParser()
    private var sequence: UInt32 = 0
    private var packets: [(Data, CFAbsoluteTime)] = []
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

    var shouldEncode: Bool {
        pressureLock.lock(); defer { pressureLock.unlock() }
        let remoteBehind = renderedPTS > 0 && latestVideoPTS > renderedPTS && latestVideoPTS - renderedPTS > 700_000
        return bufferedBytes < 180_000 && !remoteBehind
    }
    private func adjustBytes(_ value: Int) { pressureLock.lock(); bufferedBytes += value; pressureLock.unlock() }

    func connect(to endpoint: NWEndpoint, expectedFingerprint: String, pinned: Bool, clientID: String, name: String, token: String?) {
        guard expectedFingerprint.count == (pinned ? 64 : 16), expectedFingerprint.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            queue.async { self.fail(ConnectionFailure(message: "The TV pairing identity is invalid. Forget this TV and pair again using the code on its screen.", retryable: false)) }
            return
        }
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
        // A physical-TV pairing code authenticates first contact. Every later connection verifies all 256 bits.
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { [weak self] _, trust, complete in
            guard let self else { complete(false); return }
            let ref = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let cert = SecTrustCopyCertificateChain(ref) as? [SecCertificate], let leaf = cert.first else { complete(false); return }
            let hash = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
            let valid = pinned ? hash == expectedFingerprint : hash.hasPrefix(expectedFingerprint)
            self.fingerprint = hash; self.certificateMismatch = !valid
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

    func sendControl(_ object: [String: Any]) { queue.async { [weak self] in self?.sendControlOnQueue(object) } }
    private func sendControlOnQueue(_ object: [String: Any]) {
        do { enqueue(try Packet(type: .control, sequence: nextSequence(), payload: JSONSerialization.data(withJSONObject: object)).encoded()) }
        catch { fail(ConnectionFailure(message: error.localizedDescription, retryable: false)) }
    }
    func send(type: PacketType, payload: Data, pts: UInt64 = 0, keyframe: Bool = false) {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            if type == .video {
                if self.firstVideoAt == nil { self.firstVideoAt = CFAbsoluteTimeGetCurrent(); self.renderProgressAt = CFAbsoluteTimeGetCurrent() }
                self.pressureLock.lock(); self.latestVideoPTS = max(self.latestVideoPTS, pts); self.pressureLock.unlock()
            }
            do { self.enqueue(try Packet(type: type, flags: keyframe ? 1 : 0, pts: pts, sequence: self.nextSequence(), payload: payload).encoded()) }
            catch { self.fail(ConnectionFailure(message: error.localizedDescription, retryable: false)) }
        }
    }
    private func nextSequence() -> UInt32 { defer { sequence &+= 1 }; return sequence }
    private func enqueue(_ data: Data) {
        guard !closed else { return }
        pressureLock.lock(); let current = bufferedBytes; pressureLock.unlock()
        guard current + data.count <= 1_500_000 else { fail(ConnectionFailure(message: "The network can’t keep up with sharing. Move closer to the router or choose Efficient quality.")); return }
        packets.append((data, CFAbsoluteTimeGetCurrent())); adjustBytes(data.count); drain()
    }
    private func drain() {
        guard !sending, !packets.isEmpty, !closed else { return }
        sending = true
        let (data, queuedAt) = packets.removeFirst()
        guard CFAbsoluteTimeGetCurrent() - queuedAt < 0.8 else { fail(ConnectionFailure(message: "The network stalled. Reconnecting to clear delayed frames…")); return }
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, !self.closed else { return }
            self.adjustBytes(-data.count); self.sending = false
            if let error { self.fail(ConnectionFailure(message: "The connection to the TV ended: \(error.localizedDescription)")) }
            else { self.drain() }
        })
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
                        if op == "pending" {
                            guard !self.pending, !self.welcomed else { throw WireError.invalidControl }
                            self.pending = true; self.started = CFAbsoluteTimeGetCurrent()
                        }
                        if op == "welcome" {
                            guard !self.welcomed else { throw WireError.invalidControl }
                            self.welcomed = true; self.pending = false
                        }
                        if op == "stats", let pts = control["lastPts"] as? NSNumber, pts.int64Value > 0, pts.uint64Value <= self.latestVideoPTS {
                            self.pressureLock.lock()
                            if pts.uint64Value > self.renderedPTS { self.renderProgressAt = CFAbsoluteTimeGetCurrent(); self.renderedPTS = pts.uint64Value }
                            self.pressureLock.unlock()
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
            if !self.welcomed && now - self.started > (self.pending ? 35 : 12) {
                self.fail(ConnectionFailure(message: self.pending ? "Pairing timed out. Choose Allow on your TV within 30 seconds." : "The TV didn’t respond. Check the TV address, Wi-Fi and local network permission.", retryable: !self.pending)); return
            }
            if self.welcomed && now - self.lastReceived > 10 { self.fail(ConnectionFailure(message: "The TV stopped responding. Check its power and network connection.")); return }
            if self.firstVideoAt != nil {
                self.pressureLock.lock()
                let hasUnrenderedVideo = self.latestVideoPTS > self.renderedPTS && self.latestVideoPTS - self.renderedPTS > 100_000
                let stalled = hasUnrenderedVideo && now - self.renderProgressAt > 5
                self.pressureLock.unlock()
                if stalled { self.fail(ConnectionFailure(message: "TV playback stalled. Reconnecting to clear delayed frames. Try Efficient quality if this continues.")); return }
            }
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
        guard !closed else { return }; closed = true
        timer?.cancel(); timer = nil; connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        packets.removeAll(); pressureLock.lock(); bufferedBytes = 0; pressureLock.unlock()
    }
    deinit { timer?.cancel(); connection?.cancel() }
}
