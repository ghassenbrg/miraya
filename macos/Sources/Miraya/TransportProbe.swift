import Foundation
import Network
import CoreMedia
import CoreVideo
import CoreGraphics
import Security
import MirayaCore
import Darwin

/// Uses the shipping TLS transport and encoder, with generated pixels/audio, so
/// receiver integration can be checked without granting screen access to a test.
final class TransportProbe: @unchecked Sendable {
    private static var active: TransportProbe?
    private let queue = DispatchQueue(label: "app.miraya.probe", qos: .userInteractive)
    private let host: String
    private let port: UInt16
    private let code: String
    private let duration: Double
    private let reconnect: Bool
    private let width: Int
    private let height: Int
    private let fps: Int
    private var pairing: Pairing?
    private var connection: StreamConnection?
    private var encoder: H264Encoder?
    private var timer: DispatchSourceTimer?
    private var started = false
    private var stopping = false
    private var finished = false
    private var generation = 0
    private var inFlight = 0
    private var index = 0
    private var frames = 0
    private var dropped = 0
    private var sent = 0
    private var basePTS: UInt64 = 0
    private var lastConfig: Data?
    private var didReconnect = false
    private var audioFrames = 0
    private var audioFramesWritten = 0
    private var lastAcknowledgedPTS: UInt64 = 0
    private var liveAcknowledgements = 0

    private struct Pairing: Codable {
        let clientID: String
        let fingerprint: String
        let token: String
    }

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let offset = args.firstIndex(of: "--probe") else { return }
        setbuf(stdout, nil)
        guard args.count >= offset + 4, let port = UInt16(args[offset + 2]), port > 0 else {
            fputs("Usage: Miraya --probe HOST PORT TV-CODE [SECONDS]\n", stderr); exit(2)
        }
        let code = args[offset + 3].lowercased().filter { $0 != "-" && !$0.isWhitespace }
        let seconds = args.count > offset + 4 ? Double(args[offset + 4]) ?? 8 : 8
        guard code.count == 16, code.allSatisfy({ $0.isHexDigit }), seconds >= 3, seconds <= 300 else {
            fputs("The TV code must contain 16 hexadecimal characters; duration must be 3–300 seconds.\n", stderr); exit(2)
        }
        let env = ProcessInfo.processInfo.environment
        let width = Int(env["MIRAYA_PROBE_WIDTH"] ?? "640") ?? 0
        let height = Int(env["MIRAYA_PROBE_HEIGHT"] ?? "360") ?? 0
        let fps = Int(env["MIRAYA_PROBE_FPS"] ?? "30") ?? 0
        guard (2...1920).contains(width), (2...1080).contains(height), width % 2 == 0, height % 2 == 0, [30, 60].contains(fps) else {
            fputs("Diagnostic dimensions must be even and within 1920×1080; fps must be 30 or 60.\n", stderr); exit(2)
        }
        let probe = TransportProbe(host: args[offset + 1], port: port, code: code, duration: seconds)
        active = probe
        probe.queue.async { probe.connect() }
        dispatchMain()
    }

    private init(host: String, port: UInt16, code: String, duration: Double) {
        self.host = host; self.port = port; self.code = code; self.duration = duration
        let environment = ProcessInfo.processInfo.environment
        self.reconnect = environment["MIRAYA_PROBE_RECONNECT"] == "1"
        self.width = Int(environment["MIRAYA_PROBE_WIDTH"] ?? "640")!
        self.height = Int(environment["MIRAYA_PROBE_HEIGHT"] ?? "360")!
        self.fps = Int(environment["MIRAYA_PROBE_FPS"] ?? "30")!
        if environment["MIRAYA_PROBE_FORGET"] == "1" {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "app.miraya.diagnostic.pairing", kSecAttrAccount as String: "\(host):\(port)"] as CFDictionary)
        } else if let data = Self.readSecret(account: "\(host):\(port)"), let saved = try? JSONDecoder().decode(Pairing.self, from: data), saved.fingerprint.hasPrefix(code) {
            pairing = saved
        }
        let env = ProcessInfo.processInfo.environment
        if let token = env["MIRAYA_PROBE_TOKEN"], let fingerprint = env["MIRAYA_PROBE_FINGERPRINT"], fingerprint.count == 64 {
            pairing = Pairing(clientID: env["MIRAYA_PROBE_CLIENT_ID"] ?? UserDefaults.standard.string(forKey: "MirayaProbeClientID") ?? UUID().uuidString,
                fingerprint: fingerprint.lowercased(), token: token)
        }
    }

    private func connect() {
        generation += 1
        let current = generation
        started = false; stopping = false; frames = 0; dropped = 0; sent = 0; index = 0; lastConfig = nil; inFlight = 0
        audioFrames = 0; audioFramesWritten = 0; lastAcknowledgedPTS = 0; liveAcknowledgements = 0
        let clientID = pairing?.clientID ?? UUID().uuidString
        UserDefaults.standard.set(clientID, forKey: "MirayaProbeClientID")
        let transport = StreamConnection()
        connection = transport
        transport.onConnected = { print("PROBE: TLS identity verified; waiting for TV authorization if required") }
        transport.onControl = { [weak self, weak transport] object in
            self?.queue.async {
                guard let self, self.generation == current, let transport else { return }
                switch object["op"] as? String {
                case "pending": print("PROBE: approve Miraya diagnostic on the TV using its remote")
                case "welcome":
                    guard object["version"] as? Int == 1, let token = object["token"] as? String else {
                        self.finish(false, "Invalid welcome"); return
                    }
                    self.pairing = Pairing(clientID: clientID, fingerprint: transport.fingerprint, token: token)
                    self.savePairing()
                    transport.sendControl(["op": "start", "audio": true])
                case "ready":
                    guard !self.started else { self.finish(false, "Duplicate ready"); return }
                    do { try self.beginMedia(generation: current) } catch { self.finish(false, error.localizedDescription) }
                case "stats":
                    self.frames = (object["frames"] as? NSNumber)?.intValue ?? self.frames
                    self.dropped = (object["dropped"] as? NSNumber)?.intValue ?? self.dropped
                    self.audioFrames = (object["audioFrames"] as? NSNumber)?.intValue ?? self.audioFrames
                    self.audioFramesWritten = (object["audioFramesWritten"] as? NSNumber)?.intValue ?? self.audioFramesWritten
                    if let pts = object["lastPts"] as? NSNumber, pts.int64Value > 0, pts.uint64Value > self.lastAcknowledgedPTS {
                        self.lastAcknowledgedPTS = pts.uint64Value
                        self.liveAcknowledgements += 1
                    }
                    let latest = self.basePTS + UInt64(max(0, self.index - 1)) * 1_000_000 / UInt64(self.fps)
                    let lag = self.lastAcknowledgedPTS > 0 && latest > self.lastAcknowledgedPTS ? (latest - self.lastAcknowledgedPTS) / 1000 : 0
                    print("PROBE: receiver rendered=\(self.frames) dropped=\(self.dropped) audioPlayed=\(self.audioFrames) audioWritten=\(self.audioFramesWritten) ackLagMs=\(lag)")
                case "requestKeyframe": self.encoder?.requestKeyframe()
                case "stopped":
                    if self.stopping { self.sessionFinished() }
                    else { self.finish(false, "Receiver stopped unexpectedly") }
                case "error": self.finish(false, object["message"] as? String ?? "Receiver rejected session")
                default: break
                }
            }
        }
        transport.onFailure = { [weak self] error in
            self?.queue.async {
                guard let self, self.generation == current, !self.finished else { return }
                if self.stopping { self.sessionFinished() }
                else { self.finish(false, error.localizedDescription) }
            }
        }
        print("PROBE: connecting to \(host):\(port)\(pairing == nil ? " for first pairing" : " using saved certificate/token")")
        transport.connect(to: .hostPort(host: .init(host), port: .init(rawValue: port)!),
            expectedFingerprint: pairing?.fingerprint ?? code, pinned: pairing != nil,
            clientID: clientID, name: "Miraya diagnostic", token: pairing?.token)
    }

    private func beginMedia(generation current: Int) throws {
        started = true
        basePTS = DispatchTime.now().uptimeNanoseconds / 1000
        let bitrate = max(1_500_000, min(10_000_000, width * height * fps / 10))
        let encoder = try H264Encoder(width: width, height: height, fps: fps, bitrate: bitrate)
        self.encoder = encoder
        encoder.output = { [weak self] result in
            self?.queue.async {
                guard let self, current == self.generation, !self.stopping, !self.finished else { return }
                self.inFlight = max(0, self.inFlight - 1)
                do {
                    guard let sample = try result.get() else { return }
                    let packet = try H264Encoder.packet(from: sample, width: self.width, height: self.height, fps: self.fps)
                    if let config = packet.config, self.lastConfig != config {
                        self.connection?.send(type: .videoConfig, payload: config)
                        self.lastConfig = config
                    }
                    self.connection?.send(type: .video, payload: packet.data, pts: packet.pts, keyframe: packet.keyframe)
                    self.sent += 1
                } catch { self.finish(false, error.localizedDescription) }
            }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / fps), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
        print("PROBE: streaming real H.264 \(width)×\(height)/\(fps) and 48 kHz stereo PCM for \(duration) seconds")
        queue.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.generation == current, !self.finished else { return }
            self.stopping = true
            self.timer?.cancel(); self.timer = nil
            self.encoder?.close(); self.encoder = nil
            self.connection?.sendControl(["op": "stop"])
            self.queue.asyncAfter(deadline: .now() + 1) {
                guard self.generation == current, !self.finished else { return }
                self.sessionFinished()
            }
        }
    }

    private func tick() {
        guard !stopping, !finished else { return }
        defer { index += 1 }
        guard connection?.shouldEncode == true, inFlight < 3 else { return }
        do {
            var optional: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &optional)
            guard status == kCVReturnSuccess, let buffer = optional else { throw CaptureFailure.encoding(status) }
            CVPixelBufferLockBaseAddress(buffer, [])
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: stride, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
                CVPixelBufferUnlockBaseAddress(buffer, [])
                throw CaptureFailure.invalidVideo("could not generate diagnostic pixels")
            }
            for bar in 0..<8 {
                context.setFillColor(CGColor(red: Double(bar & 1), green: Double((bar >> 1) & 1), blue: Double((bar >> 2) & 1), alpha: 1))
                context.fill(CGRect(x: bar * width / 8, y: 0, width: width / 8 + 1, height: height))
            }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: (index * max(2, width / 128)) % max(1, width - width / 8), y: height / 3,
                width: max(1, width / 8), height: max(1, height / 3)))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let pts = basePTS + UInt64(index) * 1_000_000 / UInt64(fps)
            inFlight += 1
            try encoder?.encode(buffer, pts: CMTime(value: Int64(pts), timescale: 1_000_000))
            let sampleCount = 48_000 / fps
            var audio = [Int16](repeating: 0, count: sampleCount * 2)
            for sample in 0..<sampleCount {
                let phase = Double(index * sampleCount + sample) * 2 * Double.pi * 220 / 48_000
                let value = Int16((sin(phase) * 820).rounded()).littleEndian
                audio[sample * 2] = value; audio[sample * 2 + 1] = value
            }
            connection?.send(type: .audio, payload: audio.withUnsafeBytes { Data($0) }, pts: pts)
        } catch { finish(false, error.localizedDescription) }
    }

    private func sessionFinished() {
        guard !finished, stopping else { return }
        guard frames > 0 else { finish(false, "No rendered frame statistics arrived from the receiver"); return }
        guard frames >= Int(duration * Double(fps) * 0.5) else {
            finish(false, "The receiver rendered only \(frames) frames in \(duration) seconds at \(fps) fps; sustained playback did not keep up")
            return
        }
        guard audioFrames > 0, audioFramesWritten > 0 else { finish(false, "No confirmed AudioTrack playback arrived from the receiver"); return }
        guard liveAcknowledgements > 0, lastAcknowledgedPTS >= basePTS else { finish(false, "No live presentation timestamp acknowledgements arrived from the receiver"); return }
        print("PROBE: session passed; sent=\(sent), rendered=\(frames), dropped=\(dropped), audioPlayed=\(audioFrames), liveAcks=\(liveAcknowledgements)")
        connection?.close(); connection = nil
        // Invalidate the old session's already scheduled end timer before the
        // second session begins, keeping explicit reconnect verification isolated.
        generation += 1
        if reconnect && !didReconnect {
            didReconnect = true
            print("PROBE: reconnecting with the fully pinned certificate and saved token")
            queue.asyncAfter(deadline: .now() + 1) { self.connect() }
        } else { finish(true, "TLS/authentication, H.264 playback, PCM transport, statistics and clean stop verified") }
    }

    private func finish(_ success: Bool, _ message: String) {
        guard !finished else { return }
        finished = true; timer?.cancel(); timer = nil; encoder?.close(); encoder = nil; connection?.close()
        print("\(success ? "PASS" : "FAIL"): \(message)")
        fflush(stdout)
        queue.asyncAfter(deadline: .now() + 0.15) { exit(success ? 0 : 1) }
    }

    private func savePairing() {
        guard let pairing, let data = try? JSONEncoder().encode(pairing) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.miraya.diagnostic.pairing", kSecAttrAccount as String: "\(host):\(port)"]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            if SecItemAdd(add as CFDictionary, nil) != errSecSuccess { print("PROBE: pairing remains in memory; Keychain save was unavailable") }
        } else if status != errSecSuccess { print("PROBE: pairing remains in memory; Keychain update was unavailable") }
    }

    private static func readSecret(account: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.miraya.diagnostic.pairing", kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
