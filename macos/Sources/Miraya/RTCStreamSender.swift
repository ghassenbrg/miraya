import Foundation
import CoreMedia
import CoreVideo
import WebRTC
import MirayaCore
import MirayaRTCBridge

/// Upstream's macOS factory hardcodes level 3.1 (720p30). VideoToolbox on
/// supported Macs encodes 1080p60, which requires level 4.2. Advertise that
/// capacity instead of sending oversized frames to a level-3.1 encoder.
private final class ScreenEncoderFactory: RTCVideoEncoderFactoryH264 {
    override func supportedCodecs() -> [RTCVideoCodecInfo] {
        ["640c2a", "42e02a"].map {
            RTCVideoCodecInfo(name: "H264", parameters: ["profile-level-id":$0, "level-asymmetry-allowed":"1", "packetization-mode":"1"])
        }
    }
}

/// Native media tracks, never a reliable data channel. Signaling is supplied by
/// the authenticated TLS connection. No STUN/TURN servers or TCP ICE candidates.
final class RTCStreamSender: NSObject, RTCPeerConnectionDelegate, @unchecked Sendable {
    private static let initialized: Void = {
        // Bound M150's default 2875ms screen-sharing pacer queue for live
        // viewing, retaining ALR probes that rediscover capacity after idle.
        RTCInitFieldTrialDictionary(["WebRTC-ProbingScreenshareBwe":"1.5,200,80,40,-60,3"])
        RTCInitializeSSL()
        if ProcessInfo.processInfo.environment["MIRAYA_PROBE_NETWORK_DEBUG"] == "1" { RTCSetMinDebugLogLevel(.info) }
    }()
    private let queue = DispatchQueue(label: "app.miraya.rtc", qos: .userInteractive)
    private let frameLock = NSLock()
    private let audioDevice = MirayaSystemAudioDevice()
    private var factory: RTCPeerConnectionFactory?
    private var peer: RTCPeerConnection?
    private var source: RTCVideoSource?
    private var capturer: RTCVideoCapturer?
    private var videoTrack: RTCVideoTrack?
    private var audioTrack: RTCAudioTrack?
    private var videoSender: RTCRtpSender?
    private var audioSender: RTCRtpSender?
    private var candidates: [RTCIceCandidate] = []
    private var remoteReady = false
    private var offering = false
    private var offerGeneration = 0
    private var started = false
    private var closed = false
    private var reportedConnected = false
    private var paused = false
    private var audioEnabled: Bool
    private var quality: CaptureQuality
    private var prioritizeDetail: Bool
    private var frameEnabled = true
    private var dimensions = (width: 0, height: 0)
    private var receiveLimit = (width: 1920, height: 1080, fps: 60)
    private var latestFrame: CVPixelBuffer?
    private var lastFrameAt = ProcessInfo.processInfo.systemUptime
    private var lastFramePTS: Int64 = -1
    private var lastStatsRequest = 0.0
    private var timer: DispatchSourceTimer?
    private var previousEncoded = 0
    private var previousSentBytes = 0
    private var diagnosticLogger: RTCCallbackLogger?
    private var previousStatsTime = ProcessInfo.processInfo.systemUptime
    private var lastEncodedProgress = ProcessInfo.processInfo.systemUptime
    private var healthyQualitySamples = 0
    private var lastQualityProbe: TimeInterval = -.infinity
    private var capacity = PlaybackCapacity(maximumFPS: 60)
    private var inputFrames = 0
    private var lastInputFrames = 0
    private var lastInputSample = ProcessInfo.processInfo.systemUptime
    private var inputFPS = 0.0
    private var lastPresentedFrames = 0
    private var lastPresentedAt = ProcessInfo.processInfo.systemUptime
    let sessionID: String
    private let signal: ([String: Any]) -> Void
    private let connected: () -> Void
    private let failure: (ConnectionFailure) -> Void
    private let stats: ([String: Any]) -> Void

    init(sessionID: String, quality: CaptureQuality, audio: Bool, prioritizeDetail: Bool = false,
         signal: @escaping ([String: Any]) -> Void, connected: @escaping () -> Void,
         failure: @escaping (ConnectionFailure) -> Void, stats: @escaping ([String: Any]) -> Void = { _ in }) throws {
        self.sessionID = sessionID; self.quality = quality; self.audioEnabled = audio; self.prioritizeDetail = prioritizeDetail
        self.capacity = PlaybackCapacity(maximumFPS: quality.fps, preservesDetail: prioritizeDetail)
        self.signal = signal; self.connected = connected; self.failure = failure; self.stats = stats
        super.init()
        _ = Self.initialized
        if ProcessInfo.processInfo.environment["MIRAYA_PROBE_NETWORK_DEBUG"] == "1" {
            let logger = RTCCallbackLogger()
            logger.severity = .info
            logger.start { line in
                if line.contains("EncoderH264") || line.contains("compression session") || line.contains("VideoToolbox") || line.contains("RTCRtpSender") || line.contains("Updating sink restrictions") {
                    fputs("RTC_ENCODER: \(line)\n", stderr)
                }
            }
            diagnosticLogger = logger
        }
        do {
            guard RTCSignaling.validSession(sessionID) else { throw WireError.invalidControl }
            let factory = MirayaCreatePeerFactory(ScreenEncoderFactory(), RTCDefaultVideoDecoderFactory(), audioDevice)
            self.factory = factory
            let configuration = RTCConfiguration()
            configuration.iceServers = []
            configuration.sdpSemantics = .unifiedPlan
            configuration.bundlePolicy = .maxBundle
            configuration.rtcpMuxPolicy = .require
            configuration.tcpCandidatePolicy = .disabled
            configuration.continualGatheringPolicy = .gatherContinually
            configuration.audioJitterBufferMaxPackets = 50
            configuration.audioJitterBufferFastAccelerate = true
            guard let peer = factory.peerConnection(with: configuration, constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: self) else {
                throw ConnectionFailure(message: "Could not initialize the Wi-Fi media engine.", retryable: false)
            }
            self.peer = peer
            peer.setBweMinBitrateBps(250_000, currentBitrateBps: NSNumber(value: min(3_000_000, quality.bitrate)), maxBitrateBps: NSNumber(value: quality.bitrate))
            let source = factory.videoSource(forScreenCast: true)
            self.source = source; self.capturer = RTCVideoCapturer(delegate: source)
            let video = factory.videoTrack(with: source, trackId: "screen")
            videoTrack = video
            let videoInit = RTCRtpTransceiverInit(); videoInit.direction = .sendOnly; videoInit.streamIds = ["miraya"]
            guard let videoTransceiver = peer.addTransceiver(with: video, init: videoInit) else { throw WireError.invalidControl }
            videoSender = videoTransceiver.sender
            let audioSource = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: [
                "googEchoCancellation":"false", "googAutoGainControl":"false", "googNoiseSuppression":"false", "googHighpassFilter":"false"]))
            let audioTrack = factory.audioTrack(with: audioSource, trackId: "system-audio")
            self.audioTrack = audioTrack; audioTrack.isEnabled = audio
            let audioInit = RTCRtpTransceiverInit(); audioInit.direction = .sendOnly; audioInit.streamIds = ["miraya"]
            guard let transceiver = peer.addTransceiver(with: audioTrack, init: audioInit) else { throw WireError.invalidControl }
            audioSender = transceiver.sender
            let opus = factory.rtpSenderCapabilities(forKind: "audio").codecs.filter { $0.name.lowercased() == "opus" }
            guard !opus.isEmpty else { throw WireError.invalidControl }
            guard MirayaSetCodecPreferences(transceiver, opus) else { throw WireError.invalidControl }
            applyParameters()
        } catch {
            peer?.close(); peer = nil; factory = nil; audioDevice.shutdown(); throw error
        }
    }

    func start() { queue.async { [weak self] in self?.started = true; self?.offer(restart: false) } }
    func submitVideo(_ buffer: CVPixelBuffer, pts: CMTime) {
        let time = CMTimeConvertScale(pts, timescale: 1_000_000_000, method: .roundTowardZero)
        guard time.isValid, time.value >= 0 else { return }
        frameLock.lock()
        defer { frameLock.unlock() }
        guard frameEnabled, time.value > lastFramePTS, let source, let capturer else { return }
        lastFramePTS = time.value; lastFrameAt = ProcessInfo.processInfo.systemUptime; latestFrame = buffer
        inputFrames += 1
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        if dimensions != (width, height) {
            dimensions = (width, height)
            let scale = min(1.0, Double(receiveLimit.width) / Double(width), Double(receiveLimit.height) / Double(height)) * capacity.scale
            let fittedWidth = max(2, Int(Double(width) * scale) / 2 * 2)
            let fittedHeight = max(2, Int(Double(height) * scale) / 2 * 2)
            source.adaptOutputFormat(toWidth: Int32(fittedWidth), height: Int32(fittedHeight), fps: Int32(min(quality.fps, receiveLimit.fps, capacity.maximumFPS)))
        }
        source.capturer(capturer, didCapture: RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: buffer), rotation: ._0, timeStampNs: time.value))
    }
    func submitAudio(_ data: Data, pts: UInt64) { audioDevice.submitPCM(data, timestampNs: pts * 1000) }
    /// Diagnostic drain: finish generated input while allowing already encoded
    /// frames to reach presentation. Normal user stop still closes immediately.
    func finishInput() { queue.async { [weak self] in
        guard let self else { return }
        self.frameLock.lock(); self.frameEnabled = false; self.latestFrame = nil; self.frameLock.unlock()
        self.audioDevice.clear()
    } }
    func update(quality: CaptureQuality, audio: Bool, paused: Bool = false, prioritizeDetail: Bool? = nil) {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            let nextDetail = prioritizeDetail ?? self.prioritizeDetail
            let qualityChanged = self.quality != quality || self.prioritizeDetail != nextDetail
            self.prioritizeDetail = nextDetail
            let refreshVideo = qualityChanged || (self.paused && !paused)
            if qualityChanged { self.frameLock.lock(); self.capacity = PlaybackCapacity(maximumFPS: quality.fps, preservesDetail: nextDetail); self.frameLock.unlock() }
            self.frameLock.lock(); self.quality = quality; self.dimensions = (0, 0); self.frameEnabled = !paused; self.frameLock.unlock()
            if paused { self.frameLock.lock(); self.latestFrame = nil; self.frameLock.unlock() }
            self.audioEnabled = audio; self.paused = paused
            self.lastEncodedProgress = ProcessInfo.processInfo.systemUptime
            self.lastPresentedAt = ProcessInfo.processInfo.systemUptime
            if refreshVideo { self.healthyQualitySamples = 0; self.lastQualityProbe = -.infinity }
            if refreshVideo, !paused, let factory = self.factory {
                // A long pause can leave the old source's adaptation restricted
                // to a tiny picture even after capacity recovers. A fresh source
                // resets that history while replaceTrack preserves RTP/DTLS/ICE.
                let source = factory.videoSource(forScreenCast: true)
                let track = factory.videoTrack(with: source, trackId: "screen")
                self.frameLock.lock()
                self.source = source; self.capturer = RTCVideoCapturer(delegate: source)
                self.latestFrame = nil; self.dimensions = (0, 0)
                self.frameLock.unlock()
                self.videoTrack = track; self.videoSender?.track = track
                // Temporarily stop quality scaling to remove its stale resource
                // restrictions, then restore frame priority in applyParameters.
                // An explicit quality change/resume re-evaluates the picture.
                self.clearAdaptationRestrictions()
                self.peer?.setBweMinBitrateBps(250_000, currentBitrateBps: NSNumber(value: min(3_000_000, quality.bitrate)), maxBitrateBps: NSNumber(value: quality.bitrate))
            }
            self.videoTrack?.isEnabled = !paused; self.audioTrack?.isEnabled = audio && !paused
            self.audioDevice.clear(); self.applyParameters()
        }
    }
    private func applyParameters() {
        if let sender = videoSender {
            let parameters = sender.parameters
            parameters.degradationPreference = NSNumber(value: (prioritizeDetail ? RTCDegradationPreference.maintainResolution : RTCDegradationPreference.maintainFramerate).rawValue)
            for encoding in parameters.encodings {
                encoding.maxBitrateBps = NSNumber(value: quality.bitrate)
                encoding.minBitrateBps = 250_000
                encoding.maxFramerate = NSNumber(value: min(quality.fps, receiveLimit.fps, capacity.maximumFPS))
            }
            sender.parameters = parameters
        }
        if let sender = audioSender {
            let parameters = sender.parameters
            for encoding in parameters.encodings { encoding.maxBitrateBps = 192_000; encoding.bitratePriority = 2 }
            sender.parameters = parameters
        }
    }
    private func clearAdaptationRestrictions() {
        guard let sender = videoSender else { return }
        let reset = sender.parameters
        reset.degradationPreference = NSNumber(value: RTCDegradationPreference.maintainFramerateAndResolution.rawValue)
        sender.parameters = reset
    }
    func playback(frames: Int, drops: Int, paused: Bool) {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.frameLock.lock()
            let expectingVideo = self.frameEnabled && self.latestFrame != nil
            if now - self.lastInputSample >= 1 {
                self.inputFPS = Double(self.inputFrames - self.lastInputFrames) / (now - self.lastInputSample)
                self.lastInputSample = now; self.lastInputFrames = self.inputFrames
            }
            let target = min(self.quality.fps, self.receiveLimit.fps, self.capacity.maximumFPS)
            let changed = self.capacity.observe(frames: frames, drops: drops, inputFPS: self.inputFPS, targetFPS: target, paused: paused || self.paused, now: now)
            if changed { self.dimensions = (0, 0) }
            self.frameLock.unlock()
            if paused || self.paused || !expectingVideo || frames != self.lastPresentedFrames { self.lastPresentedAt = now }
            self.lastPresentedFrames = frames
            if expectingVideo && !paused && !self.paused && now - self.lastPresentedAt > 8 {
                self.fail("The TV stopped presenting video. Reconnecting Wi-Fi sharing…"); return
            }
            if changed {
                self.applyParameters()
                self.stats(["playbackAdapted":true, "maxFPS":min(self.quality.fps, self.receiveLimit.fps, self.capacity.maximumFPS), "receiverScale":self.capacity.scale])
            }
        }
    }
    private func recoverPictureQuality(_ result: [String: Any]) {
        // VideoToolbox can leave startup/paused bandwidth restrictions in place
        // after capacity returns. Probe an upscale only after two healthy
        // samples, at most once every ten seconds. Native BWE/CPU adaptation
        // remains authoritative and can immediately reduce output again.
        frameLock.lock()
        let wanted = VideoSize.fit(width: Int(Double(dimensions.width) * capacity.scale), height: Int(Double(dimensions.height) * capacity.scale), maxWidth: receiveLimit.width, maxHeight: receiveLimit.height)
        frameLock.unlock()
        let area = ((result["videoWidth"] as? NSNumber)?.intValue ?? 0) * ((result["videoHeight"] as? NSNumber)?.intValue ?? 0)
        let target = (result["targetBitrate"] as? NSNumber)?.doubleValue ?? 0
        let capacity = (result["availableBitrate"] as? NSNumber)?.doubleValue ?? 0
        let rtt = (result["rttMs"] as? NSNumber)?.doubleValue ?? .infinity
        if !paused && area > 0 && Double(area) < Double(wanted.width * wanted.height) * 0.8 &&
            result["qualityLimit"] as? String == "bandwidth" && target >= Double(quality.bitrate) * 0.6 &&
            capacity >= Double(quality.bitrate) * 0.7 && rtt < 80 {
            healthyQualitySamples += 1
        } else { healthyQualitySamples = 0 }
        let now = ProcessInfo.processInfo.systemUptime
        if healthyQualitySamples >= 2 && now - lastQualityProbe >= 10 {
            lastQualityProbe = now; healthyQualitySamples = 0
            clearAdaptationRestrictions(); applyParameters()
            stats(["qualityRecovery":true])
        }
    }
    func receive(_ message: [String: Any]) {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            do {
                guard message["session"] as? String == self.sessionID else { throw WireError.invalidControl }
                switch message["op"] as? String {
                case "rtcAnswer":
                    guard self.offering, let sdp = message["sdp"] as? String else { throw WireError.invalidControl }
                    try RTCSignaling.validateSDP(sdp)
                    self.peer?.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp)) { [weak self] error in
                        self?.queue.async {
                            guard let self, !self.closed else { return }
                            if let error { self.fail("The TV rejected media negotiation: \(error.localizedDescription)"); return }
                            self.offering = false; self.remoteReady = true
                            self.frameLock.lock()
                            self.receiveLimit = RTCSignaling.h264ReceiveLimit(sdp); self.dimensions = (0, 0)
                            self.frameLock.unlock()
                            for candidate in self.candidates { self.peer?.add(candidate, completionHandler: { _ in }) }
                            self.candidates.removeAll(); self.applyParameters()
                        }
                    }
                case "rtcCandidate":
                    guard let sdp = message["candidate"] as? String, let index = message["index"] as? Int else { throw WireError.invalidControl }
                    let mid = message["mid"] as? String
                    try RTCSignaling.validateCandidate(sdp, mid: mid, index: index)
                    let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: Int32(index), sdpMid: mid)
                    if self.remoteReady { self.peer?.add(candidate, completionHandler: { _ in }) }
                    else { guard self.candidates.count < 64 else { throw WireError.oversized }; self.candidates.append(candidate) }
                default: throw WireError.invalidControl
                }
            } catch { self.fail("Invalid Wi-Fi media negotiation. Update both Miraya apps.") }
        }
    }
    private func offer(restart: Bool) {
        guard started, !closed, !offering, let peer else { return }
        offering = true
        offerGeneration += 1
        let generation = offerGeneration
        peer.offer(for: RTCMediaConstraints(mandatoryConstraints: restart ? ["IceRestart":"true"] : nil, optionalConstraints: nil)) { [weak self] description, error in
            self?.queue.async {
                guard let self, !self.closed else { return }
                guard let description, error == nil else { self.fail("Could not create the Wi-Fi media offer."); return }
                let offer = RTCSessionDescription(type: .offer, sdp: RTCSignaling.stereoOpus(description.sdp))
                self.peer?.setLocalDescription(offer) { [weak self] error in
                    self?.queue.async {
                        guard let self, !self.closed else { return }
                        if error != nil { self.fail("Could not prepare Wi-Fi media."); return }
                        self.signal(["op":"rtcOffer", "session":self.sessionID, "sdp":offer.sdp])
                    }
                }
            }
        }
        queue.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, !self.closed, self.offerGeneration == generation else { return }
            if self.offering || !self.reportedConnected { self.fail("The TV could not establish direct UDP media. Check local-network permission, VPN and Wi-Fi client isolation.") }
        }
    }
    private func installStats() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.frameLock.lock()
            let repeatFrame = self.frameEnabled && ProcessInfo.processInfo.systemUptime - self.lastFrameAt > 0.5 ? self.latestFrame : nil
            self.frameLock.unlock()
            // SCK does not deliver complete frames for an unchanged desktop.
            // A sparse repeat lets a lost scene/PLI recover without user motion.
            if let repeatFrame { self.submitVideo(repeatFrame, pts: CMClockGetTime(CMClockGetHostTimeClock())) }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - self.lastStatsRequest >= 1 else { return }; self.lastStatsRequest = now
            self.peer?.statistics { [weak self] report in
                self?.queue.async {
                    guard let self, !self.closed else { return }
                    var result: [String: Any] = ["transport":RTCSignaling.transport]
                    result["receiverScale"] = self.capacity.scale
                    result["decoderMaxFPS"] = self.receiveLimit.fps
                    result["decoderMaxWidth"] = self.receiveLimit.width
                    result["decoderMaxHeight"] = self.receiveLimit.height
                    result["inputFPS"] = self.inputFPS
                    if let parameters = self.videoSender?.parameters {
                        result["degradation"] = parameters.degradationPreference
                        result["maxBitrate"] = parameters.encodings.first?.maxBitrateBps
                        result["maxFPS"] = parameters.encodings.first?.maxFramerate
                    }
                    for value in report.statistics.values {
                        let values = value.values
                        if value.type == "outbound-rtp", values["kind"] as? String == "video" {
                            let encoded = (values["framesEncoded"] as? NSNumber)?.intValue ?? 0
                            let now = ProcessInfo.processInfo.systemUptime
                            let bytes = (values["bytesSent"] as? NSNumber)?.intValue ?? self.previousSentBytes
                            result["actualBitrate"] = Double(max(0, bytes - self.previousSentBytes)) * 8 / max(0.1, now - self.previousStatsTime)
                            self.previousSentBytes = bytes
                            result["encodedFPS"] = Double(max(0, encoded - self.previousEncoded)) / max(0.1, now - self.previousStatsTime)
                            if self.paused || encoded != self.previousEncoded { self.lastEncodedProgress = now }
                            self.frameLock.lock(); let hasFrames = self.latestFrame != nil; self.frameLock.unlock()
                            if hasFrames && !self.paused && now - self.lastEncodedProgress > 8 {
                                self.fail("The screen encoder stopped making progress. Reconnecting Wi-Fi sharing…"); return
                            }
                            self.previousEncoded = encoded; self.previousStatsTime = now
                            result["encoder"] = values["encoderImplementation"]
                            result["targetBitrate"] = values["targetBitrate"]
                            result["videoWidth"] = values["frameWidth"]
                            result["videoHeight"] = values["frameHeight"]
                            result["qualityLimit"] = values["qualityLimitationReason"]
                        }
                        if value.type == "outbound-rtp", values["kind"] as? String == "audio" { result["audioPackets"] = values["packetsSent"] }
                        if value.type == "media-source", values["kind"] as? String == "audio" { result["audioSamplesDuration"] = values["totalSamplesDuration"] }
                        if value.type == "candidate-pair", values["nominated"] as? Bool == true, values["state"] as? String == "succeeded" {
                            result["availableBitrate"] = values["availableOutgoingBitrate"]
                            if let rtt = values["currentRoundTripTime"] as? NSNumber { result["rttMs"] = rtt.doubleValue * 1000 }
                        }
                    }
                    self.recoverPictureQuality(result)
                    self.stats(result)
                }
            }
        }
        self.timer = timer; timer.resume()
    }
    private func fail(_ detail: String) { guard !closed else { return }; closeOnQueue(); failure(ConnectionFailure(message: detail)) }
    func close() { queue.async { [self] in closeOnQueue() } }
    private func closeOnQueue() {
        guard !closed else { return }; closed = true; timer?.cancel(); timer = nil
        frameLock.lock(); frameEnabled = false; source = nil; capturer = nil; latestFrame = nil; frameLock.unlock()
        audioDevice.clear(); peer?.close(); peer = nil; videoTrack = nil; audioTrack = nil
        videoSender = nil; audioSender = nil; factory = nil; audioDevice.shutdown()
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) { queue.async { [weak self] in self?.offer(restart: false) } }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            self.stats(["iceState":newState.rawValue])
            if newState == .failed { self.fail("Wi-Fi media connection failed. Check the TV and network.") }
            if newState == .disconnected {
                self.queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, !self.closed, self.peer?.iceConnectionState == .disconnected else { return }
                    self.offer(restart: true)
                }
                self.queue.asyncAfter(deadline: .now() + 12) { [weak self] in
                    guard let self, !self.closed, self.peer?.iceConnectionState == .disconnected else { return }
                    self.fail("Wi-Fi media did not recover. Check the TV and network.")
                }
            }
        }
    }
    @objc(peerConnection:didChangeConnectionState:)
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            self.stats(["peerState":newState.rawValue])
            if newState == .connected {
                self.lastEncodedProgress = ProcessInfo.processInfo.systemUptime
                self.lastPresentedAt = ProcessInfo.processInfo.systemUptime
                if !self.reportedConnected { self.reportedConnected = true; self.installStats(); self.connected() }
            }
            if newState == .failed { self.fail("The encrypted Wi-Fi media connection failed.") }
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            guard (try? RTCSignaling.validateCandidate(candidate.sdp, mid: candidate.sdpMid, index: Int(candidate.sdpMLineIndex))) != nil else { return }
            self.signal(["op":"rtcCandidate", "session":self.sessionID, "candidate":candidate.sdp, "mid":candidate.sdpMid ?? "0", "index":Int(candidate.sdpMLineIndex)])
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) { dataChannel.close() }
    deinit { timer?.cancel(); audioDevice.shutdown(); peer?.close() }
}
