import SwiftUI
import AppKit
import CoreGraphics
import Network
import MirayaCore
import IOKit.pwr_mgt

struct DisplayChoice: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
}

enum SharePhase: String {
    case idle, permissions, connecting, authorizing, starting, sharing, reconnecting
    var title: String {
        switch self {
        case .idle: return "Ready when you are"
        case .permissions: return "Allow screen recording on your Mac"
        case .connecting: return "Connecting to your TV…"
        case .authorizing: return "Choose Allow on your TV"
        case .starting: return "Starting screen sharing…"
        case .sharing: return "Your screen is on the TV"
        case .reconnecting: return "Reconnecting to your TV…"
        }
    }
}

@MainActor final class AppModel: ObservableObject {
    @Published var phase = SharePhase.idle
    @Published var selected: Receiver?
    @Published var remembered: [TrustedReceiver] = []
    @Published var displays: [DisplayChoice] = []
    @Published var displayID: CGDirectDisplayID = CGMainDisplayID()
    @Published var quality: CaptureQuality = .balanced
    @Published var audio = true
    @Published var error: String?
    @Published var information: String?
    @Published var showPairing = false
    @Published var pairingCode = ""
    @Published var showManual = false
    @Published var manualHost = ""
    @Published var manualPort = "7421"
    @Published var transmittedFrames = 0
    @Published var receiverFrames = 0
    private var connection: StreamConnection?
    private var capture: CaptureEngine?
    private var activeReceiver: Receiver?
    private var retryTask: Task<Void, Never>?
    private var lifecycleTask: Task<Void, Never>?
    private var attempts = 0
    private var lastDropped = 0
    private var targetBitrate = 6_000_000
    private var cleanStats = 0
    private var runID = UUID()
    private var pairingClientID = UUID().uuidString
    private var activeClientID = ""
    private var powerAssertion: IOPMAssertionID = 0
    private var screenObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var nearbyReceivers: [Receiver] = []
    var busy: Bool { phase != .idle }
    var trustedSelection: TrustedReceiver? { selected.flatMap { selected in remembered.first { $0.id == selected.id || (selected.host != nil && $0.host == selected.host && $0.port == selected.port) } } }
    init() {
        do { remembered = try TrustStore.all() } catch { self.error = error.localizedDescription }
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
        if let selected, let updated = receivers.first(where: { $0.id == selected.id }) { self.selected = updated }
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
        error = nil; information = nil
        if trustedSelection == nil && PairingCode.normalize(pairingCode) == nil { showPairing = true; return }
        showPairing = false; attempts = 0; activeReceiver = selected; runID = UUID(); pairingClientID = UUID().uuidString
        let generation = runID
        let display = displayID
        phase = .permissions
        // ScreenCaptureKit is the authority for its own permission. The legacy
        // CG preflight can return false for an allowed SCK app after OS/build
        // changes, and must not prevent the framework from requesting access.
        lifecycleTask = Task {
            do {
                let available = try await CaptureEngine.displays()
                guard !Task.isCancelled, self.runID == generation else { return }
                guard available.contains(where: { $0.displayID == display }) else { throw CaptureFailure.displayUnavailable }
                self.connect(receiver: selected, generation: generation)
            } catch {
                guard !Task.isCancelled, self.runID == generation else { return }
                self.phase = .idle
                self.error = "Couldn’t prepare screen sharing: \(error.localizedDescription). Allow Miraya in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen if asked. After rebuilding a local app, remove its old permission entry and request access again."
            }
        }
    }
    private func connect(receiver requested: Receiver, generation: UUID) {
        guard runID == generation else { return }
        // The TV can re-advertise under a new name or port while a dropped
        // session is reconnecting. Its stable ID selects the current endpoint.
        let receiver = nearbyReceivers.first(where: { $0.id == requested.id }) ?? requested
        activeReceiver = receiver
        if selected?.id == receiver.id { selected = receiver }
        phase = attempts == 0 ? .connecting : .reconnecting
        let trusted = remembered.first { $0.id == receiver.id || (receiver.host != nil && $0.host == receiver.host && $0.port == receiver.port) }
        guard let expected = trusted?.fingerprint ?? PairingCode.normalize(pairingCode) else { phase = .idle; showPairing = true; return }
        let session = StreamConnection(); connection = session
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
        activeClientID = trusted?.clientID ?? pairingClientID
        session.connect(to: receiver.endpoint, expectedFingerprint: expected, pinned: trusted != nil, clientID: activeClientID, name: Host.current().localizedName ?? "Mac", token: trusted?.token)
    }
    private func handle(_ message: [String: Any], session: StreamConnection, receiver: Receiver, generation: UUID) {
        switch message["op"] as? String {
        case "pending":
            guard [.connecting, .reconnecting].contains(phase) else {
                failed(ConnectionFailure(message: "The TV sent an unexpected pairing request. Update both Miraya apps.", retryable: false), receiver: receiver, generation: generation); return
            }
            phase = .authorizing
        case "welcome":
            guard [.connecting, .authorizing, .reconnecting].contains(phase) else {
                failed(ConnectionFailure(message: "The TV repeated its connection handshake. Update both Miraya apps.", retryable: false), receiver: receiver, generation: generation); return
            }
            guard (message["version"] as? Int) == 1, let id = message["receiverId"] as? String, UUID(uuidString: id) != nil,
                  let token = message["token"] as? String, token.count >= 32, token.count <= 256,
                  let name = message["name"] as? String else { failed(ConnectionFailure(message: "This TV uses an incompatible Miraya version.", retryable: false), receiver: receiver, generation: generation); return }
            let known = remembered.first { $0.id == id }
            if let known, known.fingerprint != session.fingerprint { failed(ConnectionFailure(message: "This TV's identity changed. Forget its old pairing and check the new code on the TV.", retryable: false), receiver: receiver, generation: generation); return }
            do {
                let trust = TrustedReceiver(id: id, name: name, fingerprint: session.fingerprint, token: token, clientID: activeClientID, serviceName: receiver.serviceName ?? known?.serviceName, domain: receiver.domain ?? known?.domain, host: receiver.host ?? known?.host, port: receiver.port)
                try TrustStore.save(trust); remembered = try TrustStore.all()
                // Preserve the stable ID for reconnects made through manual address.
                activeReceiver = Receiver(id: id, name: name, endpoint: receiver.endpoint, serviceName: receiver.serviceName, domain: receiver.domain, host: receiver.host, port: receiver.port)
                selected = activeReceiver; pairingCode = ""
                phase = .starting; session.sendControl(["op":"start", "audio":audio])
            } catch { failed(ConnectionFailure(message: error.localizedDescription, retryable: false), receiver: receiver, generation: generation) }
        case "ready":
            guard phase == .starting, capture == nil else { return }; startCapture(session: session, generation: generation)
        case "requestKeyframe": capture?.requestKeyframe()
        case "stats":
            receiverFrames = message["frames"] as? Int ?? 0
            let dropped = max(0, message["dropped"] as? Int ?? 0)
            let newlyDropped = dropped >= lastDropped ? dropped - lastDropped : 0
            if newlyDropped >= 3 {
                targetBitrate = max(1_200_000, targetBitrate * 4 / 5)
                capture?.updateBitrate(targetBitrate); cleanStats = 0
                information = "Video quality adjusted for this connection. For a weak network, choose Efficient before sharing again."
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
            failed(ConnectionFailure(message: detail + extra, retryable: false), receiver: receiver, generation: generation)
        default:
            failed(ConnectionFailure(message: "The TV sent an unsupported command. Update both Miraya apps.", retryable: false), receiver: receiver, generation: generation)
        }
    }
    private func startCapture(session: StreamConnection, generation: UUID) {
        lastDropped = 0; cleanStats = 0; targetBitrate = quality.bitrate
        let engine = CaptureEngine(); capture = engine
        engine.shouldEncode = { [weak session] in session?.shouldEncode ?? false }
        engine.onVideoConfig = { [weak session] in session?.send(type: .videoConfig, payload: $0) }
        engine.onVideo = { [weak session] data, pts, key in session?.send(type: .video, payload: data, pts: pts, keyframe: key) }
        engine.onAudio = { [weak session] data, pts in session?.send(type: .audio, payload: data, pts: pts) }
        engine.onError = { [weak self, weak engine] failure in Task { @MainActor in
            guard let self, let engine, self.runID == generation, self.capture === engine else { return }
            self.stop(); self.error = "Screen capture stopped: \(failure.localizedDescription). Check that the selected display is still connected and recording permission is allowed."
        } }
        let display = displayID, quality = quality, audio = audio
        lifecycleTask = Task {
            do {
                try await engine.start(displayID: display, quality: quality, audio: audio)
                guard !Task.isCancelled, self.runID == generation, self.connection === session, self.capture === engine else { await engine.stop(); return }
                self.phase = .sharing; self.information = nil
                IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Miraya screen sharing" as CFString, &self.powerAssertion)
            } catch {
                // A network failure can cancel startCapture while keeping the
                // same run ID for a retry. That old task must not cancel the
                // replacement connection or overwrite its reconnecting state.
                guard !Task.isCancelled, self.runID == generation, self.connection === session, self.capture === engine else {
                    await engine.stop(); return
                }
                self.stop(); self.error = "Couldn’t start screen sharing: \(error.localizedDescription)"
            }
        }
    }
    private func failed(_ failure: ConnectionFailure, receiver: Receiver, generation: UUID) {
        connection?.close(); connection = nil
        let engine = capture; capture = nil
        lifecycleTask?.cancel(); lifecycleTask = nil; releasePower()
        let target = activeReceiver ?? receiver
        let known = remembered.contains { $0.id == target.id }
        if failure.retryable && known && attempts < 3 {
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
    func stop() {
        runID = UUID(); retryTask?.cancel(); retryTask = nil; lifecycleTask?.cancel(); lifecycleTask = nil
        connection?.close(gracefully: true); connection = nil
        let engine = capture; capture = nil; Task { await engine?.stop() }
        phase = .idle; information = nil; releasePower()
    }
    private func releasePower() { if powerAssertion != 0 { IOPMAssertionRelease(powerAssertion); powerAssertion = 0 } }
    private func displayChanged() {
        let previous = displayID; refreshDisplays()
        guard busy else { return }
        if !displays.contains(where: { $0.id == previous }) {
            stop(); error = "The shared display was disconnected. Choose another display and share again."
        }
    }
    func forgetSelected() {
        guard let trust = trustedSelection, !busy else { return }
        do {
            try TrustStore.remove(trust.id); remembered = try TrustStore.all(); pairingCode = ""
            information = "Pairing forgotten on this Mac. Enter the code on your TV and approve with its remote to pair again."
        } catch { self.error = error.localizedDescription }
    }
    func openRecordingSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
    func openNetworkSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!) }
}
