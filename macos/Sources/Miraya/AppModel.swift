import SwiftUI
import AppKit
import CoreGraphics
import Network
import MirayaCore
import IOKit.pwr_mgt
import ScreenCaptureKit
import UniformTypeIdentifiers

struct DisplayChoice: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
}
struct WindowChoice: Identifiable { let id: UInt32; let name: String }
struct MediaTrackChoice: Identifiable { let id: String; let kind: String; let label: String }

enum SharePhase: String {
    case idle, permissions, connecting, pairing, authorizing, starting, sharing, pausing, paused, reconnecting
    var title: String {
        switch self {
        case .idle: return "Ready when you are"
        case .permissions: return "Checking screen recording access…"
        case .connecting: return "Connecting to your TV…"
        case .pairing: return "Compare the six-digit code on your TV"
        case .pausing: return "Pausing sharing…"
        case .paused: return "Sharing paused"
        case .authorizing: return "Choose Allow on your TV"
        case .starting: return "Starting screen sharing…"
        case .sharing: return "Your screen is on the TV"
        case .reconnecting: return "Reconnecting to your TV…"
        }
    }
}

@MainActor final class AppModel: ObservableObject {
    @Published var phase = SharePhase.idle { didSet { if oldValue != phase { stepStartedAt = Date(); diagnostics.record(phase.rawValue) } } }
    private let diagnostics = Diagnostics()
    private let selectedFiles = MediaFileProvider()
    private let areaSelection = AreaSelection()
    @Published var playbackMode = PlaybackMode.mirror
    @Published var sourceKind = CaptureSourceKind.display { didSet { if sourceKind == .window { refreshWindows() } } }
    @Published var windows: [WindowChoice] = []
    @Published var windowID: UInt32 = 0
    @Published var selectedRegion: CaptureRegion?
    @Published private(set) var refreshingWindows = false
    @Published var profile = SharingProfile.video { didSet {
        UserDefaults.standard.set(profile.rawValue, forKey: "profile")
        quality = profile == .desktop ? .motion : .balanced
        prioritizeDetail = profile == .video
    } }
    @Published var mediaURL = ""
    @Published private(set) var mediaFileName = "No video selected"
    @Published private(set) var subtitleFileName = "No external subtitles"
    private var mediaFile: URL?
    private var subtitleFile: URL?
    private var mediaLoadID = ""
    @Published private(set) var mediaState = "Not playing"
    @Published private(set) var mediaPosition = 0.0
    @Published private(set) var mediaDuration = 0.0
    @Published private(set) var mediaBuffered = 0.0
    @Published private(set) var mediaSeekable = false
    @Published private(set) var mediaTracks: [MediaTrackChoice] = []
    @Published var mediaAudioTrack = "auto" { didSet { if mediaAudioTrack != oldValue { mediaCommand("track", extra: ["kind":"audio", "track":mediaAudioTrack]) } } }
    @Published var mediaSubtitleTrack = "auto" { didSet { if mediaSubtitleTrack != oldValue { mediaCommand("track", extra: ["kind":"text", "track":mediaSubtitleTrack]) } } }
    private var supportsDirectMedia = false
    var hasMediaFile: Bool { mediaFile != nil }
    var hasExternalSubtitle: Bool { subtitleFile != nil }
    @Published private(set) var connectionStep = ConnectionStep.contactingTV
    @Published private(set) var stepStartedAt = Date()
    private var firstPictureBaseline = 0
    private var captureIsRunning = false
    @Published var selected: Receiver? { didSet {
        if let selected { UserDefaults.standard.set(selected.id, forKey: "lastTV") }
        if oldValue?.id != selected?.id && !busy {
            tvDisplay = nil; metricsUpdatedAt = nil; receiverMetricsUpdatedAt = nil; fpsHistory = []
            encodedPicture = "Waiting for video"; encoderImplementation = "Waiting for encoder"; tvDecoder = "Waiting for decoder"
            decoderPictureLimit = "Waiting for negotiation"; availableBitrate = 0; roundTripMs = 0; hasPacketLossSample = false
            mediaState = "Not playing"; mediaPosition = 0; mediaDuration = 0; mediaBuffered = 0; mediaTracks = []
            information = nil
        }
    } }
    @Published var remembered: [TrustedReceiver] = []
    @Published var displays: [DisplayChoice] = []
    @Published var displayID: CGDirectDisplayID = CGMainDisplayID() { didSet { UserDefaults.standard.set(Int(displayID), forKey: "display"); if oldValue != displayID { selectedRegion = nil } } }
    @Published var quality: CaptureQuality = .balanced { didSet { UserDefaults.standard.set(quality.rawValue, forKey: "quality"); settingsChanged() } }
    @Published var prioritizeDetail = true { didSet { UserDefaults.standard.set(prioritizeDetail, forKey: "prioritizeDetail"); settingsChanged() } }
    @Published var followTVResolution = true { didSet { UserDefaults.standard.set(followTVResolution, forKey: "followTVResolution"); settingsChanged() } }
    @Published var audio = true { didSet { UserDefaults.standard.set(audio, forKey: "audio"); if oldValue != audio { settingsChanged() } } }
    @Published var audioDestination = AudioDestination.both { didSet {
        UserDefaults.standard.set(audioDestination.rawValue, forKey: "audioDestination")
        audio = audioDestination.sendsToTV; synchronizeLocalAudio()
    } }
    @Published private(set) var routingAudio = false
    private let localAudio = MacAudioRouter()
    private var audioRoutingTask: Task<Void, Never>?
    @Published var audioVolume: Double = 1 { didSet {
        UserDefaults.standard.set(audioVolume, forKey: "volume")
        if playbackMode == .media { mediaCommand("volume", extra: ["volume":audioVolume]) }
        else if phase == .sharing || phase == .paused { connection?.sendControl(["op":"setVolume", "volume":audioVolume]) }
    } }
    private var settingsTask: Task<Void, Never>?
    @Published var error: String? { didSet { if error != nil { showErrorAlert = true } } }
    @Published var showErrorAlert = false
    @Published var capturePermissionDenied = false
    @Published private(set) var checkingScreenAccess = false
    @Published private(set) var screenAccessStatus: String?
    @Published var information: String?
    @Published var showPairing = false
    @Published var pairingCode = ""
    @Published var showDeviceManager = false
    @Published var receiverFPS = 0.0
    @Published var receiverDrops = 0
    @Published var sessionStartedAt: Date?
    @Published var showManual = false
    @Published var manualHost = ""
    @Published var manualPort = "7421"
    @Published var transmittedFrames = 0
    @Published var receiverFrames = 0
    private var connection: StreamConnection?
    private var capture: CaptureEngine?
    private var rtc: RTCStreamSender?
    @Published var transportStatus = "Direct LAN · UDP"
    @Published var roundTripMs = 0.0
    @Published var availableBitrate = 0
    @Published var encodedPicture = "Waiting for video"
    @Published private(set) var encoderLimit = "none"
    @Published private(set) var encoderImplementation = "Waiting for encoder"
    @Published private(set) var actualBitrate = 0.0
    @Published private(set) var captureFPS = 0.0
    @Published private(set) var frameRateCap = 0
    @Published private(set) var decoderFrameRateCap = 0
    @Published private(set) var decoderPictureLimit = "Waiting for negotiation"
    @Published private(set) var tvDecoder = "Waiting for decoder"
    @Published private(set) var receiverScale = 1.0
    @Published private(set) var videoJitterMs = 0.0
    @Published private(set) var packetLossPercent = 0.0
    @Published private(set) var hasPacketLossSample = false
    @Published private(set) var tvAudioLevel = 0.0
    @Published private(set) var metricsUpdatedAt: Date?
    @Published private(set) var receiverMetricsUpdatedAt: Date?
    private var recentDropRate = 0.0
    @Published private(set) var fpsHistory: [Double] = []
    private var lastPacketSample: (time: Double, received: Int, lost: Int)?
    @Published private(set) var tvDisplay: TVDisplay?
    @Published private(set) var supportsPresentation = false
    @Published var pictureMode = PictureMode.fit { didSet { presentationChanged() } }
    @Published var edgeInsetPercent = 0 { didSet { presentationChanged() } }
    private var applyingPresentation = false
    private var awaitingPresentation = false
    private var activeReceiver: Receiver?
    private var retryTask: Task<Void, Never>?
    private var lifecycleTask: Task<Void, Never>?
    private var readyWaitTask: Task<Void, Never>?
    private var attempts = 0
    private var lastDropped = 0
    @Published private(set) var targetBitrate = 6_000_000
    private var lastStatsAt = ProcessInfo.processInfo.systemUptime
    private var previousFrames = 0
    private var cleanStats = 0
    private var runID = UUID()
    private var pairingClientID = UUID().uuidString
    private var activeClientID = ""
    private var powerAssertion: IOPMAssertionID = 0
    private var activity: NSObjectProtocol?
    private var lastBitrateReduction: TimeInterval = -.infinity
    private var screenObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var nearbyReceivers: [Receiver] = []
    var busy: Bool { phase != .idle }
    var statusTitle: String {
        if playbackMode == .media {
            if phase == .sharing { return mediaState == "buffering" ? "Buffering video on TV…" : "Video playing on TV" }
            if phase == .paused { return mediaState == "ended" ? "Playback finished" : "Playback paused" }
            if phase == .starting { return progressTitle }
        }
        return phase.title
    }
    var trustedSelection: TrustedReceiver? { selected.flatMap { selected in remembered.first { $0.id == selected.id || (selected.host != nil && $0.host == selected.host && $0.port == selected.port) } } }
    init(designPreview: Bool = false) {
        #if DEBUG
        if designPreview {
            displays = [DisplayChoice(id: 1, name: "Built-in Display · 3024 × 1964")]
            displayID = 1
            _quality = Published(initialValue: .motion)
            _audioVolume = Published(initialValue: 0.7)
            _supportsPresentation = Published(initialValue: true)
            _tvDisplay = Published(initialValue: TVDisplay(json: ["width":1920, "height":1080, "panelWidth":3840, "panelHeight":2160, "refreshRate":60, "mode":"fit", "edgeInsetPercent":0]))
            _remembered = Published(initialValue: [TrustedReceiver(id: "beam-preview", name: "Living Room TV", fingerprint: "preview-only", token: "preview-only", clientID: "preview-only", host: "192.0.2.42", port: 7421)])
            selected = Receiver(id: "beam-preview", name: "Living Room TV", endpoint: .hostPort(host: "192.0.2.42", port: 7421), host: "192.0.2.42")
            return
        }
        #endif
        do { remembered = try TrustStore.all() } catch { self.error = error.localizedDescription }
        quality = CaptureQuality(rawValue: UserDefaults.standard.string(forKey: "quality") ?? "") ?? .motion
        prioritizeDetail = UserDefaults.standard.object(forKey: "prioritizeDetail") as? Bool ?? true
        followTVResolution = UserDefaults.standard.object(forKey: "followTVResolution") as? Bool ?? true
        _profile = Published(initialValue: SharingProfile(rawValue: UserDefaults.standard.string(forKey: "profile") ?? "") ?? .video)
        audio = UserDefaults.standard.object(forKey: "audio") as? Bool ?? true
        audioDestination = AudioDestination(rawValue: UserDefaults.standard.string(forKey: "audioDestination") ?? "") ?? (audio ? .both : .mac)
        audio = audioDestination.sendsToTV
        localAudio.onFailure = { [weak self] message in self?.audioDestination = .both; self?.error = message }
        audioVolume = UserDefaults.standard.object(forKey: "volume") as? Double ?? 1
        selected = remembered.first { $0.id == UserDefaults.standard.string(forKey: "lastTV") }?.receiver
        if let saved = UserDefaults.standard.object(forKey: "display") as? Int, let id = UInt32(exactly: saved) { displayID = id }
        refreshDisplays()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.displayChanged() } }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.stop(); self?.information = "Sharing stopped because your Mac went to sleep." } }
    }
    func refreshDisplays() {
        displays = NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
            let mode = CGDisplayCopyDisplayMode(id)
            return DisplayChoice(id: id, name: "\(screen.localizedName) · \(mode?.pixelWidth ?? CGDisplayPixelsWide(id)) × \(mode?.pixelHeight ?? CGDisplayPixelsHigh(id))")
        }
        if !displays.contains(where: { $0.id == displayID }), let first = displays.first { displayID = first.id }
    }
    func discoveredReceiversChanged(_ receivers: [Receiver]) {
        nearbyReceivers = receivers
        guard !busy else { return }
        if let selected, selected.host == nil, let updated = receivers.first(where: { $0.id == selected.id }) { self.selected = updated }
        else if selected == nil && receivers.count == 1 { selected = receivers.first }
    }
    func useManual() {
        let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !host.contains("/"), !host.contains(" "), let port = UInt16(manualPort), port > 0, let p = NWEndpoint.Port(rawValue: port) else {
            error = "Enter the IP address or hostname shown on the TV and a port between 1 and 65535."; return
        }
        let trusted = remembered.first { $0.host == host && $0.port == port }
        selected = Receiver(id: trusted?.id ?? "manual:\(host):\(port)", name: trusted?.name ?? host, endpoint: .hostPort(host: .init(host), port: p), host: host, port: port)
        showManual = false; error = nil
    }
    func start() {
        guard !busy, let selected else { return }
        if playbackMode == .media && mediaFile == nil && !DirectMedia.validRemoteURL(mediaURL.trimmingCharacters(in: .whitespacesAndNewlines)) { error = "Choose a video file or enter a direct HTTPS media URL. Website page links and protected-service links are not supported."; return }
        if playbackMode == .mirror && sourceKind == .window && windowID == 0 { error = "Refresh the window list and choose the window you want to share."; return }
        if playbackMode == .mirror && sourceKind == .area && selectedRegion == nil { error = "Choose the area you want to share first."; return }
        error = nil; information = nil; showErrorAlert = false; capturePermissionDenied = false
        if playbackMode == .media {
            mediaState = "preparing"; mediaPosition = 0; mediaDuration = 0; mediaBuffered = 0; mediaTracks = []
            receiverFrames = 0; receiverFPS = 0; receiverDrops = 0; receiverMetricsUpdatedAt = nil; encodedPicture = "Waiting for TV player"
        }
        showPairing = false; attempts = 0; activeReceiver = selected; runID = UUID(); pairingClientID = UUID().uuidString
        let generation = runID
        phase = .connecting; setConnectionStep(.contactingTV)
        // Pairing and screen recording are separate permissions. Contact the TV
        // first so a denied/stale Mac capture grant cannot hide the pairing flow.
        lifecycleTask = Task {
            // Give SwiftUI a frame to acknowledge the tap before setup starts.
            do { try await Task.sleep(nanoseconds: 30_000_000) } catch { return }
            guard self.runID == generation, !Task.isCancelled else { return }
            self.connect(receiver: selected, generation: generation)
        }
    }
    private func setConnectionStep(_ step: ConnectionStep) {
        connectionStep = step; stepStartedAt = Date()
    }
    private func prepareCaptureAndStart(session: StreamConnection, generation: UUID) {
        if playbackMode == .media, let receiver = activeReceiver ?? selected { startDirectMedia(session: session, receiver: receiver, generation: generation); return }
        phase = .permissions
        setConnectionStep(.checkingCapture)
        lifecycleTask = Task {
            do {
                let available = try await CaptureEngine.displays()
                guard !Task.isCancelled, self.runID == generation, self.connection === session else { return }
                self.refreshDisplays()
                guard available.contains(where: { $0.displayID == self.displayID }) else { throw CaptureFailure.displayUnavailable }
                self.phase = .starting
                self.setConnectionStep(.preparingTV)
                session.sendControl(["op":"start", "transport":RTCSignaling.transport, "audio":self.audio, "volume":self.audioVolume])
                self.expectReady(session)
            } catch {
                guard !Task.isCancelled, self.runID == generation, self.connection === session else { return }
                self.captureFailed(error)
            }
        }
    }
    private func captureFailed(_ failure: Error) {
        stop()
        capturePermissionDenied = CaptureEngine.isPermissionDenied(failure)
        if capturePermissionDenied {
            error = "Your TV is paired, but macOS is blocking screen recording for this copy of Miraya. Enable Miraya in System Settings → Privacy & Security → Screen & System Audio Recording. If it is already on, its permission may belong to an older build. Quit Miraya, remove and re-add its entry using the copy in Applications, then reopen it."
        } else { error = "Couldn’t prepare your display: \(failure.localizedDescription)" }
    }
    private func connect(receiver requested: Receiver, generation: UUID) {
        guard runID == generation else { return }
        // The TV can re-advertise under a new name or port while a dropped
        // session is reconnecting. Its stable ID selects the current endpoint.
        let receiver = requested.host == nil ? (nearbyReceivers.first(where: { $0.id == requested.id }) ?? requested) : requested
        activeReceiver = receiver
        if selected?.id == receiver.id { selected = receiver }
        phase = attempts == 0 ? .connecting : .reconnecting
        setConnectionStep(.contactingTV)
        let trusted = remembered.first { $0.id == receiver.id || (receiver.host != nil && $0.host == receiver.host && $0.port == receiver.port) }
        let expected = trusted?.fingerprint
        let session = StreamConnection(); connection = session
        supportsPresentation = false; tvDisplay = nil; awaitingPresentation = false
        session.onConnected = { [weak self, weak session] in Task { @MainActor in
            guard let self, let session, self.runID == generation, self.connection === session else { return }
            if (self.phase == .connecting || self.phase == .reconnecting) && self.connectionStep == .contactingTV { self.setConnectionStep(.verifyingTV) }
        } }
        session.onControl = { [weak self, weak session] message in
            Task { @MainActor in
                guard let self, let session, self.runID == generation, self.connection === session else { return }
                self.handle(message, session: session, receiver: receiver, generation: generation)
            }
        }
        session.onFailure = { [weak self, weak session] failure in
            Task { @MainActor in
                guard let self, let session, self.runID == generation, self.connection === session else { return }
                self.failed(failure, receiver: receiver, generation: generation)
            }
        }
        session.onPairingRequired = { [weak self, weak session] code in
            Task { @MainActor in
                guard let self, let session, self.runID == generation, self.connection === session else { return }
                self.pairingCode = code; self.phase = .pairing; self.showPairing = true
            }
        }
        session.onCongestion = { [weak self, weak session] in
            Task { @MainActor in
                guard let self, let session, self.runID == generation, self.connection === session else { return }
                if self.rtc == nil { self.reduceBitrate(); self.capture?.requestKeyframe() }
            }
        }
        activeClientID = trusted?.clientID ?? pairingClientID
        session.connect(to: receiver.endpoint, expectedFingerprint: expected, pinned: trusted != nil, clientID: activeClientID, name: Host.current().localizedName ?? "Mac", token: trusted?.token)
    }
    private func handle(_ message: [String: Any], session: StreamConnection, receiver: Receiver, generation: UUID) {
        switch message["op"] as? String {
        case "pending":
            guard [.connecting, .pairing, .authorizing, .reconnecting].contains(phase) else {
                failed(ConnectionFailure(message: "The TV sent an unexpected pairing request. Update both Miraya apps.", retryable: false), receiver: receiver, generation: generation); return
            }
            phase = .authorizing; showPairing = false
        case "welcome":
            guard [.connecting, .authorizing, .reconnecting].contains(phase) else {
                failed(ConnectionFailure(message: "The TV repeated its connection handshake. Update both Miraya apps.", retryable: false), receiver: receiver, generation: generation); return
            }
            guard (message["version"] as? Int) == 1, let id = message["receiverId"] as? String, UUID(uuidString: id) != nil,
                  let token = message["token"] as? String, token.count >= 32, token.count <= 256,
                  let name = message["name"] as? String else { failed(ConnectionFailure(message: "This TV uses an incompatible Miraya version.", retryable: false), receiver: receiver, generation: generation); return }
            guard (message["transports"] as? [String])?.contains(RTCSignaling.transport) == true else {
                failed(ConnectionFailure(message: "Update Miraya on your TV to use the new Wi-Fi streaming engine.", retryable: false), receiver: receiver, generation: generation); return
            }
            let known = remembered.first { $0.id == id }
            if let known, known.fingerprint != session.fingerprint { failed(ConnectionFailure(message: "This TV's identity changed. Forget its old pairing and check the new code on the TV.", retryable: false), receiver: receiver, generation: generation); return }
            setConnectionStep(.savingPairing)
            lifecycleTask = Task { do {
                let trust = TrustedReceiver(id: id, name: name, fingerprint: session.fingerprint, token: token, clientID: activeClientID, serviceName: receiver.serviceName ?? known?.serviceName, domain: receiver.domain ?? known?.domain, host: receiver.host ?? known?.host, port: receiver.port)
                if known != trust {
                    let records = try await Task.detached(priority: .userInitiated) { try TrustStore.save(trust); return try TrustStore.all() }.value
                    guard !Task.isCancelled, self.runID == generation, self.connection === session else { return }
                    remembered = records
                }
                guard !Task.isCancelled, self.runID == generation, self.connection === session else { return }
                // Preserve the stable ID for reconnects made through manual address.
                activeReceiver = Receiver(id: id, name: name, endpoint: receiver.endpoint, serviceName: receiver.serviceName, domain: receiver.domain, host: receiver.host, port: receiver.port)
                selected = activeReceiver; pairingCode = ""
                let features = message["features"] as? [String] ?? []
                supportsPresentation = features.contains("presentation-v1")
                supportsDirectMedia = features.contains("direct-media-v1")
                updateTVDisplay(message)
                prepareCaptureAndStart(session: session, generation: generation)
            } catch {
                guard !Task.isCancelled, self.runID == generation, self.connection === session else { return }
                failed(ConnectionFailure(message: error.localizedDescription, retryable: false), receiver: receiver, generation: generation)
            } }
        case "presentation": updateTVDisplay(message)
        case "mediaRead":
            guard playbackMode == .media, !mediaLoadID.isEmpty else { return }
            selectedFiles.respond(message) { [weak session] in session?.sendControl($0) }
        case "mediaState":
            guard playbackMode == .media, message["loadId"] as? String == mediaLoadID else { return }
            updateDirectState(message)
        case "paused":
            guard phase == .pausing else { return }
            phase = .paused; releasePower()
        case "ready":
            readyWaitTask?.cancel(); readyWaitTask = nil
            guard phase == .starting, capture == nil, message["transport"] as? String == RTCSignaling.transport,
                  let mediaID = message["session"] as? String, RTCSignaling.validSession(mediaID) else {
                failed(ConnectionFailure(message: "The TV sent an incompatible media response. Update both Miraya apps.", retryable: false), receiver: receiver, generation: generation); return
            }
            if let rtc {
                guard rtc.sessionID == mediaID else { failed(ConnectionFailure(message: "The TV media session changed.", retryable: false), receiver: receiver, generation: generation); return }
                rtc.update(quality: quality, audio: audio, prioritizeDetail: prioritizeDetail)
                startCapture(session: session, generation: generation)
            } else { startMedia(session: session, receiver: receiver, generation: generation, mediaID: mediaID) }
        case "rtcAnswer", "rtcCandidate":
            guard let rtc else { failed(ConnectionFailure(message: "Unexpected media negotiation.", retryable: false), receiver: receiver, generation: generation); return }
            rtc.receive(message)
        case "requestKeyframe": capture?.requestKeyframe()
        case "stats":
            receiverMetricsUpdatedAt = Date()
            updateTVDisplay(message)
            tvAudioLevel = min(1, max(0, (message["audioPeak"] as? NSNumber)?.doubleValue ?? 0))
            tvDecoder = message["decoderImplementation"] as? String ?? tvDecoder
            videoJitterMs = (message["videoJitterMs"] as? NSNumber)?.doubleValue ?? videoJitterMs
            if let packets = message["videoPacketsReceived"] as? Int, let lost = message["videoPacketsLost"] as? Int {
                let now = ProcessInfo.processInfo.systemUptime
                if let old = lastPacketSample {
                    if now - old.time >= 1 {
                        let receivedDelta = max(0, packets - old.received), lostDelta = max(0, lost - old.lost)
                        packetLossPercent = receivedDelta + lostDelta > 0 ? Double(lostDelta) * 100 / Double(receivedDelta + lostDelta) : 0
                        hasPacketLossSample = receivedDelta + lostDelta > 0
                        lastPacketSample = (now, packets, lost)
                    }
                } else { lastPacketSample = (now, packets, lost) }
            }
            receiverFrames = message["frames"] as? Int ?? 0
            confirmFirstPicture()
            let now = ProcessInfo.processInfo.systemUptime
            let interval = now - lastStatsAt
            if interval > 0.1 { receiverFPS = Double(max(0, receiverFrames - previousFrames)) / interval }
            previousFrames = receiverFrames; lastStatsAt = now
            let drops = max(0, message["dropped"] as? Int ?? 0)
            if interval > 0.1 { recentDropRate = Double(max(0, drops - receiverDrops)) / interval }
            receiverDrops = drops
            diagnostics.record("sample", values: ["fps":receiverFPS, "drops":Double(receiverDrops), "rttMs":roundTripMs, "jitterMs":videoJitterMs, "lossPercent":packetLossPercent, "bitrate":actualBitrate, "frameCap":Double(frameRateCap), "receiverScale":receiverScale, "cpuLimited":encoderLimit == "cpu" ? 1 : 0, "bandwidthLimited":encoderLimit == "bandwidth" ? 1 : 0])
            if let rtc { rtc.playback(frames: receiverFrames, drops: receiverDrops, paused: phase == .paused || phase == .pausing); return }
            let dropped = max(0, message["dropped"] as? Int ?? 0)
            let newlyDropped = dropped >= lastDropped ? dropped - lastDropped : 0
            if newlyDropped >= 3 {
                reduceBitrate()
            } else {
                cleanStats += 1
                if cleanStats >= 40 && targetBitrate < quality.bitrate {
                    targetBitrate = min(quality.bitrate, targetBitrate * 11 / 10)
                    capture?.updateBitrate(targetBitrate); cleanStats = 0
                    if targetBitrate == quality.bitrate { information = nil }
                }
            }
            lastDropped = dropped
        case "stopped":
            stop(); information = "Sharing ended on the TV."
        case "error":
            let code = message["code"] as? String ?? "protocol"
            let detail = message["message"] as? String ?? "The TV rejected the connection."
            let extra = code == "auth" ? " Forget this TV on your Mac, then pair again using the code on the TV." : ""
            failed(ConnectionFailure(message: detail + extra, retryable: code == "media" || code == "timeout"), receiver: receiver, generation: generation)
        default:
            failed(ConnectionFailure(message: "The TV sent an unsupported command. Update both Miraya apps.", retryable: false), receiver: receiver, generation: generation)
        }
    }
    private func reduceBitrate() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastBitrateReduction >= 1 else { return }
        lastBitrateReduction = now
        targetBitrate = max(600_000, targetBitrate * 3 / 4)
        capture?.updateBitrate(targetBitrate); cleanStats = 0
        information = "Video quality adjusted to keep sharing responsive."
    }
    private func expectReady(_ session: StreamConnection) {
        readyWaitTask?.cancel()
        let generation = runID
        readyWaitTask = Task { [weak self, weak session] in
            do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
            guard let self, let session, self.runID == generation, self.connection === session,
                  self.phase == .starting, let receiver = self.activeReceiver else { return }
            self.failed(ConnectionFailure(message: "The TV did not prepare sharing in time. Reconnecting…"), receiver: receiver, generation: generation)
        }
    }
    private func startMedia(session: StreamConnection, receiver: Receiver, generation: UUID, mediaID: String) {
        receiverFrames = 0; previousFrames = 0; receiverDrops = 0
        lastPacketSample = nil; packetLossPercent = 0; hasPacketLossSample = false; fpsHistory = []; receiverScale = 1
        decoderFrameRateCap = 0; frameRateCap = 0; encoderLimit = "none"; metricsUpdatedAt = nil
        receiverMetricsUpdatedAt = nil; decoderPictureLimit = "Waiting for negotiation"
        tvDecoder = "Waiting for decoder"; encoderImplementation = "Waiting for encoder"
        actualBitrate = 0; captureFPS = 0; videoJitterMs = 0; tvAudioLevel = 0
        transportStatus = "Connecting direct UDP media…"
        roundTripMs = 0; availableBitrate = 0; encodedPicture = "Waiting for video"
        setConnectionStep(.preparingMedia)
        readyWaitTask?.cancel()
        readyWaitTask = Task {
            do { try await Task.sleep(nanoseconds: 12_000_000_000) } catch { return }
            guard self.runID == generation, self.connection === session, self.phase == .starting else { return }
            self.failed(ConnectionFailure(message: "The Mac media engine took too long to initialize. Try sharing again.", retryable: false), receiver: receiver, generation: generation)
        }
        let chosenQuality = quality, includeAudio = audio, chosenDetail = prioritizeDetail
        lifecycleTask = Task { [self, session] in
            do {
                // Native factory/audio-device construction can take seconds.
                // Keep it off the UI actor so progress and Cancel stay usable.
                let stream = try await Task.detached(priority: .userInitiated) { [weak self, weak session] in
                    try RTCStreamSender(sessionID: mediaID, quality: chosenQuality, audio: includeAudio, prioritizeDetail: chosenDetail,
                        signal: { [weak session] in session?.sendControl($0) }, connected: { [weak self, weak session] in
                            Task { @MainActor in
                                guard let self, let session, self.runID == generation, self.connection === session, self.phase == .starting, self.capture == nil else { return }
                                self.transportStatus = "Direct LAN · encrypted UDP"
                                self.startCapture(session: session, generation: generation)
                            }
                        }, failure: { [weak self, weak session] failure in
                            Task { @MainActor in
                                guard let self, let session, self.runID == generation, self.connection === session else { return }
                                self.failed(failure, receiver: receiver, generation: generation)
                            }
                        }, stats: { [weak self, weak session] stats in
                            Task { @MainActor in
                                guard let self, let session, self.runID == generation, self.connection === session else { return }
                                if let bitrate = stats["targetBitrate"] as? NSNumber, bitrate.intValue > 0 { self.targetBitrate = bitrate.intValue }
                                self.availableBitrate = (stats["availableBitrate"] as? NSNumber)?.intValue ?? self.availableBitrate
                                self.roundTripMs = (stats["rttMs"] as? NSNumber)?.doubleValue ?? self.roundTripMs
                                self.encoderLimit = stats["qualityLimit"] as? String ?? self.encoderLimit
                                self.encoderImplementation = stats["encoder"] as? String ?? self.encoderImplementation
                                self.actualBitrate = (stats["actualBitrate"] as? NSNumber)?.doubleValue ?? self.actualBitrate
                                self.captureFPS = (stats["inputFPS"] as? NSNumber)?.doubleValue ?? self.captureFPS
                                self.frameRateCap = (stats["maxFPS"] as? NSNumber)?.intValue ?? self.frameRateCap
                                self.decoderFrameRateCap = (stats["decoderMaxFPS"] as? NSNumber)?.intValue ?? self.decoderFrameRateCap
                                if let width = stats["decoderMaxWidth"] as? Int, let height = stats["decoderMaxHeight"] as? Int {
                                    self.decoderPictureLimit = "\(width) × \(height)"
                                }
                                self.receiverScale = (stats["receiverScale"] as? NSNumber)?.doubleValue ?? self.receiverScale
                                if self.metricsUpdatedAt == nil || Date().timeIntervalSince(self.metricsUpdatedAt!) >= 0.9 {
                                    self.fpsHistory.append(self.receiverFPS)
                                    if self.fpsHistory.count > 60 { self.fpsHistory.removeFirst(self.fpsHistory.count - 60) }
                                }
                                self.metricsUpdatedAt = Date()
                                if let width = (stats["videoWidth"] as? NSNumber)?.intValue,
                                   let height = (stats["videoHeight"] as? NSNumber)?.intValue, width > 0, height > 0 {
                                    self.encodedPicture = "\(width) × \(height)"
                                }
                            }
                        })
                }.value
                guard !Task.isCancelled, self.runID == generation, self.connection === session else { stream.close(); return }
                self.readyWaitTask?.cancel(); self.readyWaitTask = nil
                self.rtc = stream; self.setConnectionStep(.negotiatingMedia); stream.start()
            } catch {
                guard !Task.isCancelled, self.runID == generation, self.connection === session else { return }
                self.failed(ConnectionFailure(message: "Could not start Wi-Fi sharing: \(error.localizedDescription)", retryable: false), receiver: receiver, generation: generation)
            }
        }
    }
    private func startCapture(session: StreamConnection, generation: UUID) {
        setConnectionStep(.startingCapture)
        firstPictureBaseline = receiverFrames; captureIsRunning = false
        previousFrames = receiverFrames; lastStatsAt = ProcessInfo.processInfo.systemUptime
        lastDropped = 0; cleanStats = 0; targetBitrate = quality.bitrate; lastBitrateReduction = -.infinity
        let engine = CaptureEngine(); capture = engine
        engine.onFrame = { [weak rtc] buffer, pts in rtc?.submitVideo(buffer, pts: pts) }
        engine.onAudio = { [weak rtc] data, pts in rtc?.submitAudio(data, pts: pts) }
        engine.onError = { [weak self, weak engine] failure in Task { @MainActor in
            guard let self, let engine, self.runID == generation, self.capture === engine else { return }
            self.captureFailed(failure)
        } }
        let display = displayID, quality = quality, audio = audio
        let outputLimit = followTVResolution ? tvDisplay.map { (width: $0.width, height: $0.height) } : nil
        lifecycleTask = Task {
            do {
                try await engine.start(displayID: display, quality: quality, audio: audio, maximumOutputSize: outputLimit, source: self.sourceKind, windowID: self.windowID, region: self.selectedRegion)
                guard !Task.isCancelled, self.runID == generation, self.connection === session, self.capture === engine else { await engine.stop(); return }
                self.captureIsRunning = true; self.setConnectionStep(.waitingForPicture)
                self.activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Miraya live screen sharing")
                IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Miraya screen sharing" as CFString, &self.powerAssertion)
                self.confirmFirstPicture()
                if self.phase == .starting {
                    self.readyWaitTask?.cancel()
                    self.readyWaitTask = Task {
                        do { try await Task.sleep(nanoseconds: 12_000_000_000) } catch { return }
                        guard self.runID == generation, self.connection === session, self.phase == .starting else { return }
                        if let receiver = self.activeReceiver ?? self.selected {
                            self.failed(ConnectionFailure(message: "The TV connected but has not displayed a picture. Check Wi-Fi and try again."), receiver: receiver, generation: generation)
                        } else { self.stop(); self.error = "Choose a TV and try again." }
                    }
                }
            } catch {
                // A network failure can cancel startCapture while keeping the
                // same run ID for a retry. That old task must not cancel the
                // replacement connection or overwrite its reconnecting state.
                guard !Task.isCancelled, self.runID == generation, self.connection === session, self.capture === engine else {
                    await engine.stop(); return
                }
                self.captureFailed(error)
            }
        }
    }
    private func failed(_ failure: ConnectionFailure, receiver: Receiver, generation: UUID) {
        diagnostics.record("connectionFailure"); selectedFiles.close(); mediaLoadID = ""
        captureIsRunning = false
        localAudio.restore(); audioRoutingTask?.cancel(); routingAudio = false
        readyWaitTask?.cancel(); readyWaitTask = nil
        settingsTask?.cancel(); settingsTask = nil
        showPairing = false; pairingCode = ""
        rtc?.close(); rtc = nil
        connection?.close(); connection = nil
        let engine = capture; capture = nil
        lifecycleTask?.cancel(); lifecycleTask = nil; releasePower()
        let target = activeReceiver ?? receiver
        let known = remembered.contains { $0.id == target.id }
        if failure.retryable && known && attempts < 3 && playbackMode == .mirror {
            attempts += 1; phase = .reconnecting; information = "\(failure.message) Attempt \(attempts) of 3."
            retryTask?.cancel()
            retryTask = Task {
                await engine?.stop()
                try? await Task.sleep(nanoseconds: UInt64(attempts * 1_000_000_000))
                guard !Task.isCancelled, runID == generation else { return }
                connect(receiver: target, generation: generation)
            }
        } else {
            Task { await engine?.stop() }; phase = .idle; error = failure.message; information = nil
        }
    }
    private func settingsChanged() {
        guard phase == .sharing, playbackMode == .mirror else { return }
        settingsTask?.cancel()
        settingsTask = Task {
            do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            guard phase == .sharing, let session = connection else { return }
            let generation = runID
            rtc?.update(quality: quality, audio: audio, paused: true, prioritizeDetail: prioritizeDetail)
            let engine = capture; capture = nil; captureIsRunning = false; phase = .starting; setConnectionStep(.preparingTV)
            releasePower()
            await engine?.stop()
            guard !Task.isCancelled, runID == generation, connection === session else { return }
            session.sendControl(["op":"reconfigure", "audio":audio, "volume":audioVolume])
            expectReady(session)
        }
    }
    func confirmPairing() {
        guard phase == .pairing else { return }
        connection?.confirmPairing(code: pairingCode)
        showPairing = false; phase = .authorizing
    }
    func pause() {
        if playbackMode == .media { mediaCommand("pause"); return }
        guard phase == .sharing, let session = connection else { return }
        rtc?.update(quality: quality, audio: audio, paused: true, prioritizeDetail: prioritizeDetail)
        let engine = capture; capture = nil; captureIsRunning = false; phase = .pausing
        let generation = runID
        lifecycleTask = Task {
            await engine?.stop()
            guard !Task.isCancelled, runID == generation, connection === session else { return }
            session.sendControl(["op":"pause"])
        }
    }
    func resume() {
        if playbackMode == .media { mediaCommand("play"); return }
        guard phase == .paused else { return }
        captureIsRunning = false; phase = .starting; setConnectionStep(.preparingTV)
        connection?.sendControl(["op":"resume", "audio":audio, "volume":audioVolume])
        if let connection { expectReady(connection) }
    }
    func forget(_ id: String) {
        guard !busy else { return }
        do {
            try TrustStore.remove(id); remembered = try TrustStore.all()
            if selected?.id == id { pairingCode = "" }
            information = "TV forgotten. Compare a fresh code next time you connect."
        } catch { self.error = error.localizedDescription }
    }
    func stop() {
        selectedFiles.close(); mediaLoadID = ""
        captureIsRunning = false
        localAudio.restore(); audioRoutingTask?.cancel(); routingAudio = false
        readyWaitTask?.cancel(); readyWaitTask = nil
        settingsTask?.cancel(); settingsTask = nil
        runID = UUID(); retryTask?.cancel(); retryTask = nil; lifecycleTask?.cancel(); lifecycleTask = nil
        rtc?.close(); rtc = nil
        connection?.close(gracefully: true); connection = nil
        let engine = capture; capture = nil; Task { await engine?.stop() }
        phase = .idle; information = nil; showPairing = false; pairingCode = ""; sessionStartedAt = nil; receiverFPS = 0; releasePower()
    }
    private func confirmFirstPicture() {
        guard phase == .starting, captureIsRunning, receiverFrames > firstPictureBaseline else { return }
        readyWaitTask?.cancel(); readyWaitTask = nil
        phase = .sharing; information = nil
        synchronizeLocalAudio()
        if sessionStartedAt == nil { sessionStartedAt = Date() }
    }
    var progressTitle: String {
        if playbackMode == .media && phase == .starting { return mediaState == "buffering" ? "Buffering video on your TV…" : "Preparing video playback…" }
        return [.pairing, .authorizing, .pausing, .reconnecting].contains(phase) ? phase.title : connectionStep.title
    }
    var healthDiagnosis: String {
        StreamHealth.diagnosis(encoderReason: encoderLimit, receiverScale: receiverScale, decoderFPS: decoderFrameRateCap, frameCap: frameRateCap, requestedFPS: quality.fps, rttMs: roundTripMs, lossPercent: packetLossPercent, inputFPS: captureFPS, playbackFPS: receiverFPS, droppedFPS: recentDropRate)
    }
    var progressDetail: String {
        if playbackMode == .media && phase == .starting { return "The TV is opening and buffering the original media. You can cancel while it prepares." }
        switch phase {
        case .pairing: return "Compare the six digits on both screens, then confirm the match."
        case .authorizing: return "Choose Allow on the TV with its remote. Your Mac is waiting for that approval."
        case .pausing: return "Stopping capture and waiting for the TV to confirm the pause."
        case .reconnecting: return information ?? "Your connection dropped. Retrying the same verified TV."
        default: return connectionStep.detail
        }
    }
    func stopByUser() {
        let connecting = phase != .sharing && phase != .paused
        stop(); information = connecting ? "Connection cancelled." : playbackMode == .media ? "Playback stopped." : "Sharing stopped."
    }
    private func synchronizeLocalAudio() {
        audioRoutingTask?.cancel()
        guard playbackMode == .mirror, audioDestination.mutesMac, [.sharing, .paused, .starting].contains(phase) else {
            localAudio.restore(); routingAudio = false; return
        }
        routingAudio = true
        audioRoutingTask = Task {
            do { try await localAudio.setTVOnly(true) }
            catch {
                guard !Task.isCancelled else { return }
                self.audioDestination = .both; self.error = error.localizedDescription
            }
            if !Task.isCancelled { routingAudio = false }
        }
    }
    private func releasePower() {
        if powerAssertion != 0 { IOPMAssertionRelease(powerAssertion); powerAssertion = 0 }
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
    }
    private func displayChanged() {
        let previous = displayID; refreshDisplays()
        guard busy else { return }
        if playbackMode == .mirror && sourceKind != .window && !displays.contains(where: { $0.id == previous }) {
            stop(); error = "The shared display was disconnected. Choose another display and share again."
        }
    }
    func refreshWindows() {
        guard !refreshingWindows, !busy || phase == .paused else { return }
        refreshingWindows = true
        Task {
            defer { refreshingWindows = false }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                windows = content.windows.filter { $0.windowLayer == 0 && $0.frame.width >= 32 && $0.frame.height >= 32 && $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier }
                    .map { WindowChoice(id: $0.windowID, name: "\($0.owningApplication?.applicationName ?? "App") · \($0.title?.isEmpty == false ? $0.title! : "Untitled window")") }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if !windows.contains(where: { $0.id == windowID }) { windowID = windows.first?.id ?? 0 }
            } catch { self.error = "Could not list windows. Allow Miraya in Screen & System Audio Recording, then refresh the list." }
        }
    }
    func chooseArea() {
        guard !busy || phase == .paused else { return }
        let target = displayID
        areaSelection.choose(displayID: target) { [weak self] region in
            guard let self, self.displayID == target else { return }
            if let region { self.selectedRegion = region }
        }
    }
    func chooseMediaFile() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .audio]; panel.message = "Choose a video or audio file to play on the paired TV."
        if panel.runModal() == .OK, let url = panel.url { mediaFile = url; mediaFileName = url.lastPathComponent; mediaURL = "" }
    }
    func useMediaURL() { guard !busy else { return }; mediaFile = nil; mediaFileName = "No video selected" }
    func chooseSubtitleFile() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "srt"), UTType(filenameExtension: "vtt")].compactMap { $0 }
        panel.message = "Choose SRT or WebVTT subtitles for direct video playback."
        if panel.runModal() == .OK, let url = panel.url { subtitleFile = url; subtitleFileName = url.lastPathComponent }
    }
    func clearSubtitleFile() { guard !busy else { return }; subtitleFile = nil; subtitleFileName = "No external subtitles" }
    private func startDirectMedia(session: StreamConnection, receiver: Receiver, generation: UUID) {
        guard supportsDirectMedia else { failed(ConnectionFailure(message: "Update Miraya on the TV to enable direct video playback.", retryable: false), receiver: receiver, generation: generation); return }
        selectedFiles.close(); mediaLoadID = UUID().uuidString.lowercased()
        mediaPosition = 0; mediaDuration = 0; mediaBuffered = 0; mediaSeekable = false; mediaTracks = []
        mediaState = "preparing"; mediaAudioTrack = "auto"; mediaSubtitleTrack = "auto"
        metricsUpdatedAt = nil; receiverMetricsUpdatedAt = nil; fpsHistory = []; receiverFPS = 0; receiverDrops = 0
        encodedPicture = "Waiting for TV player"; actualBitrate = 0
        var message: [String: Any] = ["op":"mediaLoad", "loadId":mediaLoadID, "volume":audioVolume]
        var assets: [[String: Any]] = []
        do {
            if let mediaFile {
                let asset = try selectedFiles.authorize(mediaFile); assets.append(asset)
                message["url"] = "miraya-file:///\(asset["id"]!)"
                let types = ["mp4":"video/mp4", "m4v":"video/mp4", "mkv":"video/x-matroska", "webm":"video/webm", "mp3":"audio/mpeg", "m4a":"audio/mp4"]
                message["mime"] = types[mediaFile.pathExtension.lowercased()]
            } else {
                let text = mediaURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard DirectMedia.validRemoteURL(text) else { throw WireError.invalidControl }; message["url"] = text
            }
            if let subtitleFile {
                guard ["srt", "vtt"].contains(subtitleFile.pathExtension.lowercased()) else { throw WireError.invalidControl }
                let asset = try selectedFiles.authorize(subtitleFile); assets.append(asset)
                message["subtitle"] = ["url":"miraya-file:///\(asset["id"]!)", "mime":subtitleFile.pathExtension.lowercased() == "srt" ? "application/x-subrip" : "text/vtt"]
            }
            message["assets"] = assets
            phase = .starting; setConnectionStep(.preparingTV); transportStatus = mediaFile == nil ? "TV fetches HTTPS media" : "Original file · encrypted LAN"
            session.sendControl(message)
            readyWaitTask?.cancel(); readyWaitTask = Task {
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                guard self.runID == generation, self.connection === session, self.phase == .starting else { return }
                self.failed(ConnectionFailure(message: "The TV did not start playback within 30 seconds. Check the media format and address.", retryable: false), receiver: receiver, generation: generation)
            }
        } catch { failed(ConnectionFailure(message: "Could not open the selected media. Choose the file or HTTPS media URL again.", retryable: false), receiver: receiver, generation: generation) }
    }
    private func updateDirectState(_ message: [String: Any]) {
        guard [.starting, .sharing, .paused].contains(phase), let state = message["state"] as? String, ["preparing", "buffering", "playing", "paused", "ended"].contains(state) else { return }
        func seconds(_ key: String) -> Double { let value = (message[key] as? NSNumber)?.doubleValue ?? 0; return value.isFinite ? min(31_536_000, max(0, value / 1000)) : 0 }
        mediaState = state; mediaPosition = seconds("positionMs"); mediaDuration = seconds("durationMs"); mediaBuffered = seconds("bufferedMs")
        mediaSeekable = message["seekable"] as? Bool ?? false
        mediaTracks = ((message["tracks"] as? [[String: Any]]) ?? []).prefix(64).compactMap { item in
            guard let id = item["id"] as? String, id.count <= 12, let kind = item["kind"] as? String, ["audio", "text"].contains(kind), let label = item["label"] as? String else { return nil }
            return MediaTrackChoice(id: id, kind: kind, label: String(label.prefix(80)))
        }
        let width = min(16384, max(0, message["width"] as? Int ?? 0)), height = min(16384, max(0, message["height"] as? Int ?? 0))
        encodedPicture = width > 0 && height > 0 ? "\(width) × \(height) · original media" : "Audio / waiting for picture"
        let frames = max(0, message["frames"] as? Int ?? 0)
        if let last = receiverMetricsUpdatedAt, Date().timeIntervalSince(last) > 0.1 { receiverFPS = Double(max(0, frames - receiverFrames)) / Date().timeIntervalSince(last) }
        receiverFrames = frames; receiverDrops = max(0, message["dropped"] as? Int ?? 0)
        receiverMetricsUpdatedAt = Date()
        if phase == .starting && (message["firstPicture"] as? Bool == true || state == "playing" && message["hasVideo"] as? Bool == false) {
            readyWaitTask?.cancel(); readyWaitTask = nil; phase = .sharing; sessionStartedAt = Date(); diagnostics.record("mediaReady")
        }
        if phase != .starting { phase = state == "paused" || state == "ended" ? .paused : .sharing }
        diagnostics.record("sample", values: ["direct":1, "width":Double(width), "height":Double(height), "positionMs":mediaPosition * 1000, "bufferedMs":max(0, mediaBuffered - mediaPosition) * 1000])
    }
    func mediaCommand(_ action: String, extra: [String: Any] = [:]) {
        guard playbackMode == .media, !mediaLoadID.isEmpty, [.sharing, .paused].contains(phase) else { return }
        var message = extra; message["op"] = "mediaCommand"; message["loadId"] = mediaLoadID; message["action"] = action
        connection?.sendControl(message)
    }
    func seekMedia(_ seconds: Double) {
        guard mediaSeekable, seconds.isFinite else { return }
        mediaCommand("seek", extra: ["positionMs":Int64(max(0, min(mediaDuration, seconds)) * 1000)])
    }
    func exportDiagnostics() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Miraya-diagnostics.json"
        panel.message = "Saves local technical measurements from up to the last 72 hours. No screen/audio content, media URLs, file names, pairing secrets or device names. Nothing is uploaded."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do { try await Task.detached { [diagnostics] in try diagnostics.export(to: url) }.value; information = "Diagnostic report saved." }
            catch { self.error = "Could not save the diagnostic report. Try another location." }
        }
    }
    func forgetSelected() {
        guard let trust = trustedSelection, !busy else { return }
        do {
            try TrustStore.remove(trust.id); remembered = try TrustStore.all(); pairingCode = ""
            information = "Pairing forgotten on this Mac. Compare a fresh code on both screens and approve with the TV remote to pair again."
        } catch { self.error = error.localizedDescription }
    }
    private func updateTVDisplay(_ message: [String: Any]) {
        guard let json = message["display"] as? [String: Any], let display = TVDisplay(json: json) else { return }
        tvDisplay = display
        guard !awaitingPresentation || (display.mode == pictureMode && display.edgeInsetPercent == edgeInsetPercent) else { return }
        awaitingPresentation = false; applyingPresentation = true
        pictureMode = display.mode; edgeInsetPercent = display.edgeInsetPercent
        applyingPresentation = false
    }
    private func presentationChanged() {
        guard !applyingPresentation, supportsPresentation, [.sharing, .paused].contains(phase), (0...10).contains(edgeInsetPercent) else { return }
        awaitingPresentation = true
        connection?.sendControl(["op":"setPresentation", "mode":pictureMode.rawValue, "edgeInsetPercent":edgeInsetPercent])
    }
    func checkScreenAccess() {
        guard !busy, !checkingScreenAccess else { return }
        checkingScreenAccess = true
        screenAccessStatus = "Checking screen access…"
        Task {
            defer { self.checkingScreenAccess = false }
            do {
                let available = try await CaptureEngine.displays()
                self.screenAccessStatus = available.isEmpty ? "Screen access is allowed, but no display is available." : "Screen access verified. Your display is available for sharing."
                if self.capturePermissionDenied { self.error = nil; self.capturePermissionDenied = false; self.showErrorAlert = false }
            } catch {
                self.screenAccessStatus = CaptureEngine.isPermissionDenied(error) ? "macOS is blocking screen access. Open Screen Recording Settings below. If Miraya is already enabled, remove and re-add the copy in Applications, then quit and reopen it." : "Screen access check failed: \(error.localizedDescription)"
            }
        }
    }
    func openRecordingSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
    func openNetworkSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!) }
}
