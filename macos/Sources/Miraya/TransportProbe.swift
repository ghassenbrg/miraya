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
    private var rtc: RTCStreamSender?
    private let useRTC = ProcessInfo.processInfo.environment["MIRAYA_PROBE_WEBRTC"] == "1"
    private var udpConfirmed = false
    private var codecsConfirmed = false
    private var rtcAudioPlaying = false
    private var rtcAudioSignal = false
    private var rtcStereoSignal = false
    private var rtcAudioPackets = 0
    private var rtcAudioSamplesDuration = 0.0
    private var adaptiveFPS = 60
    private var targetFrames = 0.0
    private let testControls = ProcessInfo.processInfo.environment["MIRAYA_PROBE_CONTROLS"] == "1"
    private var controlPhase = 0
    private var controlReadies = 0
    private var pausedConfirmed = false
    private var pausedFrames: Int?
    private var smallVideoConfirmed = false
    private var fullVideoConfirmed = false
    private var muteConfirmed = false
    private var levelConfirmed = false
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
    private var targetBitrate = 1_500_000
    private var lastReduction: TimeInterval = -.infinity
    private var background: CGImage?
    private var backgroundScene = -1
    private var nv12Background: (scene: Int, width: Int, height: Int, y: Data, uv: Data)?
    private var pauseFrames = 0
    private var maximumAckLag: UInt64 = 0
    private var latestVideoPTS: UInt64 = 0
    private var outstandingVideo: [(pts: UInt64, sentAt: TimeInterval)] = []
    private var maximumPendingAge = 0
    private var lastRenderProgress = ProcessInfo.processInfo.systemUptime
    private var maximumRenderGapMs = 0
    private let sceneChanges = ProcessInfo.processInfo.environment["MIRAYA_PROBE_SCENES"] == "1"
    private let pauseAt = Double(ProcessInfo.processInfo.environment["MIRAYA_PROBE_PAUSE_AT"] ?? "0") ?? 0
    private let pauseFor = Double(ProcessInfo.processInfo.environment["MIRAYA_PROBE_PAUSE_FOR"] ?? "0") ?? 0

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
        guard (code == "interactive" || (code.count == 16 && code.allSatisfy({ $0.isHexDigit }))), seconds >= 3, seconds <= 300 else {
            fputs("Use interactive for six-digit pairing, or a legacy certificate code; duration must be 3–300 seconds.\n", stderr); exit(2)
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
        } else if let data = Self.readSecret(account: "\(host):\(port)"), let saved = try? JSONDecoder().decode(Pairing.self, from: data), (code == "interactive" || saved.fingerprint.hasPrefix(code)) {
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
        udpConfirmed = false; codecsConfirmed = false; rtcAudioPlaying = false; rtcAudioSignal = false
        rtcStereoSignal = false
        rtcAudioPackets = 0; rtcAudioSamplesDuration = 0
        adaptiveFPS = fps; targetFrames = 0
        controlPhase = 0; controlReadies = 0; pausedConfirmed = false; pausedFrames = nil
        smallVideoConfirmed = false; fullVideoConfirmed = false; muteConfirmed = false; levelConfirmed = false
        started = false; stopping = false; frames = 0; dropped = 0; sent = 0; index = 0; lastConfig = nil; inFlight = 0
        audioFrames = 0; audioFramesWritten = 0; lastAcknowledgedPTS = 0; liveAcknowledgements = 0
        outstandingVideo.removeAll(); maximumPendingAge = 0
        lastRenderProgress = ProcessInfo.processInfo.systemUptime; maximumRenderGapMs = 0
        pauseFrames = 0; maximumAckLag = 0; latestVideoPTS = 0; background = nil; backgroundScene = -1; lastReduction = -.infinity
        nv12Background = nil
        let clientID = pairing?.clientID ?? UUID().uuidString
        UserDefaults.standard.set(clientID, forKey: "MirayaProbeClientID")
        let transport = StreamConnection()
        connection = transport
        transport.onConnected = { print("PROBE: TLS connected; identity verification and TV authorization may still be required") }
        transport.onPairingRequired = { [weak self, weak transport] _ in
            print("PROBE: enter six-digit code displayed on the TV")
            Thread {
                guard let value = readLine() else { self?.queue.async { self?.finish(false, "Pairing input ended") }; return }
                let entered = value.filter { !$0.isWhitespace }
                transport?.confirmPairing(code: entered)
            }.start()
        }
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
                    transport.sendControl(["op": "start", "audio": true, "transport": self.useRTC ? RTCSignaling.transport : "tcp-v1"] )
                case "paused":
                    guard self.testControls, self.controlPhase == 1 else { self.finish(false, "Unexpected pause"); return }
                    self.pausedConfirmed = true
                case "ready":
                    if self.started && self.testControls {
                        guard object["session"] as? String == self.rtc?.sessionID else { self.finish(false, "Live controls replaced the media session"); return }
                        self.controlReadies += 1
                        self.rtc?.update(quality: self.controlPhase == 2 ? .efficient : .balanced, audio: self.controlPhase != 2)
                        return
                    }
                    guard !self.started else { self.finish(false, "Duplicate ready"); return }
                    do {
                        if self.useRTC {
                            guard let id = object["session"] as? String, object["transport"] as? String == RTCSignaling.transport else {
                                self.finish(false, "Receiver does not support native UDP media"); return
                            }
                            let quality: CaptureQuality = self.fps <= 15 ? .lowBandwidth : self.fps == 60 ? (self.width <= 1280 ? .efficientMotion : .motion) : self.width <= 1280 ? .efficient : .balanced
                            self.rtc = try RTCStreamSender(sessionID: id, quality: quality,
                                audio: true, signal: { [weak self, weak transport] value in if let value = self?.relaySignal(value, local: true) { transport?.sendControl(value) } },
                                connected: { [weak self] in self?.queue.async {
                                    guard let self, self.generation == current, !self.finished, !self.started else { return }
                                    do { try self.beginMedia(generation: current) } catch { self.finish(false, error.localizedDescription) }
                                } }, failure: { [weak self] failure in self?.queue.async {
                                    guard let self, self.generation == current, !self.finished, !self.stopping else { return }
                                    self.finish(false, failure.localizedDescription)
                                } }, stats: { [weak self] value in
                                    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), let json = String(data: data, encoding: .utf8) { print("PROBE_RTC: \(json)") }
                                    self?.queue.async { [weak self] in
                                        guard let self, self.generation == current, !self.finished else { return }
                                        self.rtcAudioPackets = (value["audioPackets"] as? NSNumber)?.intValue ?? self.rtcAudioPackets
                                        self.rtcAudioSamplesDuration = (value["audioSamplesDuration"] as? NSNumber)?.doubleValue ?? self.rtcAudioSamplesDuration
                                        self.adaptiveFPS = (value["maxFPS"] as? NSNumber)?.intValue ?? self.adaptiveFPS
                                    }
                                })
                            self.rtc?.start()
                        } else { try self.beginMedia(generation: current) }
                    } catch { self.finish(false, error.localizedDescription) }
                case "rtcAnswer", "rtcCandidate": if let value = self.relaySignal(object, local: false) { self.rtc?.receive(value) }
                case "stats":
                    let previous = self.frames
                    self.frames = (object["frames"] as? NSNumber)?.intValue ?? self.frames
                    let now = ProcessInfo.processInfo.systemUptime
                    let elapsed = Double(self.index) / Double(self.fps)
                    let idle = (self.testControls && self.controlPhase == 1) || (self.pauseFor > 0 && elapsed >= self.pauseAt && elapsed < self.pauseAt + self.pauseFor)
                    if !self.started || idle { self.lastRenderProgress = now }
                    else if self.frames > previous {
                        self.maximumRenderGapMs = max(self.maximumRenderGapMs, Int((now - self.lastRenderProgress) * 1000))
                        self.lastRenderProgress = now
                    }
                    if self.useRTC {
                        if self.frames > previous { self.liveAcknowledgements += 1 }
                        self.udpConfirmed = object["protocol"] as? String == "udp" || self.udpConfirmed
                        self.codecsConfirmed = (object["videoCodec"] as? String)?.lowercased() == "video/h264" && (object["audioCodec"] as? String)?.lowercased() == "audio/opus" || self.codecsConfirmed
                        self.rtcAudioPlaying = object["audioPlaying"] as? Bool == true || self.rtcAudioPlaying
                        self.rtcAudioSignal = object["audioSignal"] as? Bool == true || self.rtcAudioSignal
                        self.rtcStereoSignal = object["audioStereoSignal"] as? Bool == true || self.rtcStereoSignal
                        if self.testControls {
                            if object["paused"] as? Bool == true {
                                if let baseline = self.pausedFrames, self.frames > baseline + 1 { self.finish(false, "Video continued rendering while paused"); return }
                                self.pausedFrames = self.frames
                            }
                            let width = (object["videoWidth"] as? NSNumber)?.intValue ?? 0
                            let height = (object["videoHeight"] as? NSNumber)?.intValue ?? 0
                            let audio = object["audioEnabled"] as? Bool == true
                            let level = (object["volume"] as? NSNumber)?.doubleValue ?? -1
                            if self.controlPhase == 2 && width == 1280 && height == 720 && !audio { self.smallVideoConfirmed = true }
                            if self.controlPhase >= 3 && width == 1920 && height == 1080 && audio { self.fullVideoConfirmed = true }
                            if self.controlPhase == 4 && level == 0 { self.muteConfirmed = true }
                            if self.controlPhase == 5 && abs(level - 0.8) < 0.001 { self.levelConfirmed = true }
                            if self.frames > previous { print("PROBE: live resolution=\(width)x\(height), audio=\(audio), phase=\(self.controlPhase)") }
                        }
                    }
                    self.dropped = (object["dropped"] as? NSNumber)?.intValue ?? self.dropped
                    self.rtc?.playback(frames: self.frames, drops: self.dropped, paused: self.testControls && self.controlPhase == 1)
                    self.audioFrames = (object["audioFrames"] as? NSNumber)?.intValue ?? self.audioFrames
                    self.audioFramesWritten = (object["audioFramesWritten"] as? NSNumber)?.intValue ?? self.audioFramesWritten
                    if let pts = object["lastPts"] as? NSNumber, pts.int64Value > 0, pts.uint64Value > self.lastAcknowledgedPTS {
                        self.lastAcknowledgedPTS = pts.uint64Value
                        self.liveAcknowledgements += 1
                    }
                    let latest = self.latestVideoPTS
                    let lag = self.lastAcknowledgedPTS > 0 && latest > self.lastAcknowledgedPTS ? (latest - self.lastAcknowledgedPTS) / 1000 : 0
                    self.outstandingVideo.removeAll { $0.pts <= self.lastAcknowledgedPTS }
                    let pendingAge = self.outstandingVideo.first.map { max(0, Int((ProcessInfo.processInfo.systemUptime - $0.sentAt) * 1000)) } ?? 0
                    self.maximumPendingAge = max(self.maximumPendingAge, pendingAge)
                    self.maximumAckLag = max(self.maximumAckLag, lag)
                    print("PROBE: receiver rendered=\(self.frames) dropped=\(self.dropped) audioPlayed=\(self.audioFrames) audioWritten=\(self.audioFramesWritten) ackLagMs=\(lag) pendingAgeMs=\(pendingAge)")
                case "requestKeyframe": self.encoder?.requestKeyframe()
                case "stopped":
                    if self.stopping { self.sessionFinished() }
                    else { self.finish(false, "Receiver stopped unexpectedly") }
                case "error": self.finish(false, object["message"] as? String ?? "Receiver rejected session")
                default: break
                }
            }
        }
        transport.onCongestion = { [weak self] in
            self?.queue.async {
                guard let self, self.generation == current, !self.stopping else { return }
                self.encoder?.requestKeyframe()
                let now = ProcessInfo.processInfo.systemUptime
                if now - self.lastReduction >= 1 {
                    self.lastReduction = now
                    self.targetBitrate = max(600_000, self.targetBitrate * 3 / 4)
                    self.encoder?.updateBitrate(self.targetBitrate)
                    print("PROBE: congestion; requested IDR, bitrate=\(self.targetBitrate)")
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
            expectedFingerprint: pairing?.fingerprint ?? (code == "interactive" ? nil : code), pinned: pairing != nil,
            clientID: clientID, name: "Miraya diagnostic", token: pairing?.token)
    }

    // Diagnostic-only NAT/impairment relay. Never used by the normal application.
    private func relaySignal(_ object: [String: Any], local: Bool) -> [String: Any]? {
        let env = ProcessInfo.processInfo.environment
        guard let up = env["MIRAYA_PROBE_UDP_UP"].flatMap(UInt16.init), up > 0,
              let down = env["MIRAYA_PROBE_UDP_DOWN"].flatMap(UInt16.init), down > 0 else { return object }
        var result = object
        if let candidate = object["candidate"] as? String {
            var fields = candidate.split(separator: " ").map(String.init)
            guard fields.count >= 8, fields[4].split(separator: ".").count == 4 else { return nil }
            fields[4] = local ? "10.0.2.2" : "127.0.0.1"
            fields[5] = String(local ? down : up)
            result["candidate"] = fields.joined(separator: " ")
        }
        if let sdp = object["sdp"] as? String {
            result["sdp"] = sdp.components(separatedBy: "\r\n").filter { !$0.hasPrefix("a=candidate:") && $0 != "a=end-of-candidates" }.joined(separator: "\r\n")
        }
        return result
    }

    private func beginMedia(generation current: Int) throws {
        started = true
        lastRenderProgress = ProcessInfo.processInfo.systemUptime
        basePTS = DispatchTime.now().uptimeNanoseconds / 1000
        let bitrate = max(1_500_000, min(10_000_000, width * height * fps / 10))
        targetBitrate = bitrate
        if !useRTC {
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
                    self.latestVideoPTS = packet.pts
                    self.outstandingVideo.append((packet.pts, ProcessInfo.processInfo.systemUptime))
                    self.sent += 1
                } catch { self.finish(false, error.localizedDescription) }
            }
        }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / fps), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
        print("PROBE: transport=\(useRTC ? "WebRTC UDP / H.264 + Opus" : "legacy TCP / H.264 + PCM")")
        print("PROBE: streaming real H.264 \(width)×\(height)/\(fps) and 48 kHz stereo PCM for \(duration) seconds")
        if testControls {
            for (after, phase) in [(3.0, 1), (12.0, 2), (20.0, 3), (30.0, 4), (34.0, 5)] {
                queue.asyncAfter(deadline: .now() + after) { [weak self] in
                    guard let self, self.generation == current, !self.finished, !self.stopping else { return }
                    self.controlPhase = phase
                    switch phase {
                    case 1:
                        self.rtc?.update(quality: .balanced, audio: true, paused: true)
                        self.connection?.sendControl(["op":"pause"])
                    case 2: self.connection?.sendControl(["op":"resume", "audio":false, "volume":0.5])
                    case 3: self.connection?.sendControl(["op":"reconfigure", "audio":true, "volume":0.5])
                    case 4: self.connection?.sendControl(["op":"setVolume", "volume":0.0])
                    default: self.connection?.sendControl(["op":"setVolume", "volume":0.8])
                    }
                    print("PROBE: live control phase \(phase), same native media session")
                }
            }
        }
        queue.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.generation == current, !self.finished else { return }
            self.stopping = true
            self.timer?.cancel(); self.timer = nil
            self.encoder?.close(); self.encoder = nil
            self.rtc?.finishInput()
            // Let the last generated frames and periodic stats catch up before
            // closing. Otherwise a stale 250ms snapshot loses up to 15 frames
            // from the benchmark despite successful real presentation.
            self.queue.asyncAfter(deadline: .now() + 0.5) {
                guard self.generation == current, !self.finished else { return }
                self.connection?.sendControl(["op": "stop"])
                self.queue.asyncAfter(deadline: .now() + 1) {
                    guard self.generation == current, !self.finished else { return }
                    self.sessionFinished()
                }
            }
        }
    }

    private func tick() {
        guard !stopping, !finished else { return }
        defer { index += 1 }
        let elapsed = Double(index) / Double(fps)
        if testControls && controlPhase == 1 { pauseFrames += 1; return }
        if pauseFor > 0 && elapsed >= pauseAt && elapsed < pauseAt + pauseFor { pauseFrames += 1; return }
        targetFrames += Double(useRTC ? adaptiveFPS : fps) / Double(fps)
        guard inFlight < 3, connection?.shouldEncode == true else { return }
        do {
            let width = testControls && controlPhase == 2 ? 1280 : self.width
            let height = testControls && controlPhase == 2 ? 720 : self.height
            let buffer: CVPixelBuffer
            if useRTC { buffer = try makeNV12Frame(width: width, height: height) }
            else {
            var optional: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &optional)
            guard status == kCVReturnSuccess, let generated = optional else { throw CaptureFailure.encoding(status) }
            buffer = generated
            CVPixelBufferLockBaseAddress(buffer, [])
            let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
            guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
                CVPixelBufferUnlockBaseAddress(buffer, [])
                throw CaptureFailure.invalidVideo("could not generate diagnostic pixels")
            }
            if sceneChanges {
                let scene = index / (fps * 2)
                if backgroundScene != scene {
                    var random = UInt32(truncatingIfNeeded: scene + 1)
                    for y in stride(from: 0, to: height, by: 12) {
                        for x in stride(from: 0, to: width, by: 12) {
                            random = random &* 1_664_525 &+ 1_013_904_223
                            context.setFillColor(CGColor(red: Double(random & 255) / 255,
                                green: Double((random >> 8) & 255) / 255, blue: Double((random >> 16) & 255) / 255, alpha: 1))
                            context.fill(CGRect(x: x, y: y, width: 12, height: 12))
                        }
                    }
                    background = context.makeImage(); backgroundScene = scene
                    encoder?.requestKeyframe()
                } else if let background { context.draw(background, in: CGRect(x: 0, y: 0, width: width, height: height)) }
            } else {
                for bar in 0..<8 {
                    context.setFillColor(CGColor(red: Double(bar & 1), green: Double((bar >> 1) & 1), blue: Double((bar >> 2) & 1), alpha: 1))
                    context.fill(CGRect(x: bar * width / 8, y: 0, width: width / 8 + 1, height: height))
                }
            }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: (index * max(2, width / 128)) % max(1, width - width / 8), y: height / 3,
                width: max(1, width / 8), height: max(1, height / 3)))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            }
            let pts = useRTC ? DispatchTime.now().uptimeNanoseconds / 1000 : basePTS + UInt64(index) * 1_000_000 / UInt64(fps)
            if useRTC {
                rtc?.submitVideo(buffer, pts: CMTime(value: Int64(pts), timescale: 1_000_000)); sent += 1
            } else {
                inFlight += 1
                try encoder?.encode(buffer, pts: CMTime(value: Int64(pts), timescale: 1_000_000))
            }
            let sampleCount = 48_000 / fps
            var audio = [Int16](repeating: 0, count: sampleCount * 2)
            for sample in 0..<sampleCount {
                let phase = Double(index * sampleCount + sample) * 2 * Double.pi * 220 / 48_000
                let value = Int16((sin(phase) * 820).rounded()).littleEndian
                audio[sample * 2] = value
                audio[sample * 2 + 1] = Int16((sin(phase * 1.5) * 820).rounded()).littleEndian
            }
            let pcm = audio.withUnsafeBytes { Data($0) }
            if useRTC { rtc?.submitAudio(pcm, pts: pts) } else { connection?.send(type: .audio, payload: pcm, pts: pts) }
        } catch { finish(false, error.localizedDescription) }
    }

    /// Match the shipping ScreenCaptureKit NV12 path. Generating a BGRA canvas
    /// would benchmark extra color conversion and surface allocation absent from
    /// normal screen capture. Cached planes keep diagnostic work out of timing.
    private func makeNV12Frame(width: Int, height: Int) throws -> CVPixelBuffer {
        var optional: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &optional)
        guard status == kCVReturnSuccess, let buffer = optional else { throw CaptureFailure.encoding(status) }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let y = CVPixelBufferGetBaseAddressOfPlane(buffer, 0), let uv = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else { throw CaptureFailure.invalidVideo("Missing NV12 planes") }
        let ys = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0), uvs = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        let scene = sceneChanges ? index / (fps * 2) : 0
        if nv12Background?.scene != scene || nv12Background?.width != width || nv12Background?.height != height || nv12Background?.y.count != ys * height || nv12Background?.uv.count != uvs * height / 2 {
            memset(y, 16, ys * height); memset(uv, 128, uvs * height / 2)
            var random = UInt32(truncatingIfNeeded: scene + 1)
            let tile = sceneChanges ? 12 : max(2, width / 8 / 2 * 2)
            for top in stride(from: 0, to: height, by: tile) {
                for left in stride(from: 0, to: width, by: tile) {
                    random = random &* 1_664_525 &+ 1_013_904_223
                    let luma = sceneChanges ? UInt8(16 + random % 220) : UInt8(32 + (left / tile) * 26)
                    let cb = sceneChanges ? UInt8(16 + ((random >> 8) % 225)) : 128
                    let cr = sceneChanges ? UInt8(16 + ((random >> 16) % 225)) : 128
                    let right = min(width, left + tile), bottom = min(height, top + tile)
                    for row in top..<bottom { memset(y.advanced(by: row * ys + left), Int32(luma), right - left) }
                    for row in top / 2..<bottom / 2 {
                        let pixels = uv.advanced(by: row * uvs).assumingMemoryBound(to: UInt8.self)
                        for column in stride(from: left, to: right, by: 2) { pixels[column] = cb; pixels[column + 1] = cr }
                    }
                }
            }
            nv12Background = (scene, width, height, Data(bytes: y, count: ys * height), Data(bytes: uv, count: uvs * height / 2))
        } else if let cached = nv12Background {
            _ = cached.y.withUnsafeBytes { memcpy(y, $0.baseAddress!, cached.y.count) }
            _ = cached.uv.withUnsafeBytes { memcpy(uv, $0.baseAddress!, cached.uv.count) }
        }
        let boxWidth = max(2, width / 8 / 2 * 2), boxHeight = max(2, height / 3 / 2 * 2)
        let left = ((index * max(2, width / 128)) % max(1, width - boxWidth)) / 2 * 2
        let top = height / 3 / 2 * 2
        for row in top..<top + boxHeight { memset(y.advanced(by: row * ys + left), 235, boxWidth) }
        for row in top / 2..<(top + boxHeight) / 2 { memset(uv.advanced(by: row * uvs + left), 128, boxWidth) }
        return buffer
    }

    private func sessionFinished() {
        guard !finished, stopping else { return }
        guard frames > 0 else { finish(false, "No rendered frame statistics arrived from the receiver"); return }
        guard frames >= Int(targetFrames * 0.5) else {
            finish(false, "The receiver rendered only \(frames) frames in \(duration) seconds at \(fps) fps; sustained playback did not keep up")
            return
        }
        guard audioFrames > 0, audioFramesWritten > 0 else { finish(false, "No confirmed AudioTrack playback arrived from the receiver"); return }
        guard liveAcknowledgements > 0, useRTC || lastAcknowledgedPTS >= basePTS else { finish(false, "No live presentation timestamp acknowledgements arrived from the receiver"); return }
        if useRTC && (!udpConfirmed || !codecsConfirmed || !rtcAudioPlaying || !rtcAudioSignal || !rtcStereoSignal) {
            finish(false, "Native media was not confirmed as UDP, H.264, stereo Opus and active AudioTrack"); return
        }
        if useRTC {
            let activeAudio = duration - (testControls ? 17 : 0)
            guard rtcAudioPackets >= Int(activeAudio * 35) else {
                finish(false, "The native audio clock ran too slowly: \(rtcAudioPackets) packets in \(activeAudio)s"); return
            }
            print("PROBE: native audio packets=\(rtcAudioPackets), capturedSeconds=\(rtcAudioSamplesDuration)")
        }
        guard maximumRenderGapMs < 3000 else { finish(false, "Presentation stopped progressing for \(maximumRenderGapMs)ms while generating motion"); return }
        if testControls {
            guard pausedConfirmed, pausedFrames != nil, controlReadies == 2, smallVideoConfirmed, fullVideoConfirmed, muteConfirmed, levelConfirmed else {
                finish(false, "Live controls failed: pause=\(pausedConfirmed), ready=\(controlReadies), 720p=\(smallVideoConfirmed), 1080p=\(fullVideoConfirmed), mute=\(muteConfirmed), level=\(levelConfirmed)"); return
            }
            print("PROBE: nine-second pause, resume, 720p/audio off, 1080p/audio on, mute and gain verified on one peer")
        }
        print("PROBE: session passed; sent=\(sent), rendered=\(frames), dropped=\(dropped), targetFrames=\(Int(targetFrames)), audioPlayed=\(audioFrames), liveAcks=\(liveAcknowledgements), maxRenderGapMs=\(maximumRenderGapMs), maxAckLagMs=\(maximumAckLag), maxPendingAgeMs=\(maximumPendingAge)")
        rtc?.close(); rtc = nil
        connection?.close(); connection = nil
        // Invalidate the old session's already scheduled end timer before the
        // second session begins, keeping explicit reconnect verification isolated.
        generation += 1
        if reconnect && !didReconnect {
            didReconnect = true
            print("PROBE: reconnecting with the fully pinned certificate and saved token")
            queue.asyncAfter(deadline: .now() + 1) { self.connect() }
        } else { finish(true, "TLS/authentication, H.264 playback, audio playback, statistics and clean stop verified") }
    }

    private func finish(_ success: Bool, _ message: String) {
        guard !finished else { return }
        finished = true; timer?.cancel(); timer = nil; encoder?.close(); encoder = nil; rtc?.close(); rtc = nil; connection?.close()
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
            // Diagnostics must not hang behind an ad-hoc rebuild's Keychain UI.
            // If access needs approval, pair visibly with the TV again instead.
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
