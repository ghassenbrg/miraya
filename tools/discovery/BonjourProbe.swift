import Foundation
import Network
import Combine
import Darwin

/// Uses the actual Discovery implementation and real host DNS-SD publication.
/// No sockets accept connections; the advertised identities are disposable.
final class BonjourProbe: NSObject, NetServiceDelegate, @unchecked Sendable {
    private let discovery = Discovery()
    private let firstID = UUID().uuidString.lowercased()
    private let secondID = UUID().uuidString.lowercased()
    private let incompatibleID = UUID().uuidString.lowercased()
    private let prefix = "Miraya Test \(ProcessInfo.processInfo.processIdentifier)"
    private var publishers: [NetService] = []
    private var original: NetService?
    private var bedroom: NetService?
    private var renamed: NetService?
    private var timer: Timer?
    private var stage = 0
    private var stageStarted = Date()
    private var completed: [String] = []
    private var finished = false
    private let output: URL

    init(output: URL) { self.output = output; super.init() }

    func start() {
        discovery.start()
        original = publish(name: "\(prefix) Lounge", id: firstID, port: 17421)
        bedroom = publish(name: "\(prefix) Bedroom", id: secondID, port: 17422)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.check() }
        print("Testing actual host Bonjour discovery with two disposable TV services…")
    }

    private func publish(name: String, id: String, port: Int32, version: String = "1") -> NetService {
        let service = NetService(domain: "local.", type: "_miraya._tcp.", name: name, port: port)
        service.delegate = self
        service.setTXTRecord(NetService.data(fromTXTRecord: ["v": Data(version.utf8), "id": Data(id.utf8)]))
        publishers.append(service)
        service.publish()
        return service
    }

    private var found: [Receiver] {
        discovery.receivers.filter { $0.id == firstID || $0.id == secondID }
    }

    private func advance(_ description: String) {
        completed.append(description)
        print("PASS: \(description)")
        stage += 1
        stageStarted = Date()
    }

    private func check() {
        guard !finished else { return }
        if Date().timeIntervalSince(stageStarted) > 12 {
            finish(false, "Timed out in stage \(stage). Check local network permission/mDNS. Found: \(found.map(\.name))")
            return
        }
        switch stage {
        case 0:
            guard found.count == 2, let lounge = found.first(where: { $0.id == firstID }),
                  let bed = found.first(where: { $0.id == secondID }),
                  lounge.name == "\(prefix) Lounge", bed.name == "\(prefix) Bedroom",
                  lounge.port == 17421, bed.port == 17422 else { return }
            advance("Two named receivers resolve independently with stable UUIDs and ports")
            renamed = publish(name: "\(prefix) Cinema", id: firstID, port: 27421)
        case 1:
            guard found.count == 2, let lounge = found.first(where: { $0.id == firstID }),
                  lounge.name == "\(prefix) Cinema", lounge.port == 27421 else { return }
            advance("Overlapping renamed advertisement produces one row per stable UUID and selects the new endpoint")
            original?.stop()
        case 2:
            guard Date().timeIntervalSince(stageStarted) > 0.8,
                  found.count == 2, found.first(where: { $0.id == firstID })?.name == "\(prefix) Cinema" else { return }
            advance("Removing the old service leaves the renamed receiver available")
            bedroom?.stop()
        case 3:
            guard found.count == 1, found.first?.id == firstID else { return }
            advance("Closing one receiver removes only that receiver")
            _ = publish(name: "\(prefix) Future version", id: incompatibleID, port: 37421, version: "2")
            _ = publish(name: "\(prefix) Invalid ID", id: "not-a-uuid", port: 37422)
        case 4:
            guard Date().timeIntervalSince(stageStarted) > 2 else { return }
            guard !discovery.receivers.contains(where: { $0.id == incompatibleID || $0.name == "\(prefix) Invalid ID" }) else {
                finish(false, "Incompatible or malformed service was accepted"); return
            }
            advance("Unsupported protocol version and malformed receiver UUID are excluded")
            discovery.refresh()
        case 5:
            guard found.count == 1, found.first?.id == firstID,
                  found.first?.name == "\(prefix) Cinema" else { return }
            advance("Refresh rediscovers the current receiver without resurrecting stale services")
            renamed?.stop()
        case 6:
            guard found.isEmpty else { return }
            advance("Receiver disappearance clears the discovered entry")
            _ = publish(name: "\(prefix) Cinema restarted", id: firstID, port: 47421)
        case 7:
            guard found.count == 1, found.first?.id == firstID,
                  found.first?.name == "\(prefix) Cinema restarted", found.first?.port == 47421 else { return }
            advance("A restarted receiver reuses its stable UUID with a fresh service name and port")
            finish(true, "Actual Discovery.swift host Bonjour integration passed")
        default: break
        }
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        finish(false, "Could not publish fixture service: \(errorDict)")
    }

    private func finish(_ passed: Bool, _ message: String) {
        guard !finished else { return }
        finished = true; timer?.invalidate(); timer = nil
        publishers.forEach { $0.stop() }
        let result: [String: Any] = ["passed": passed, "message": message, "checks": completed,
            "scope": "Actual macOS NetService publication and production Discovery.swift browsing on one host; does not certify mDNS across a home router or TV emulator boundary"]
        do {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        } catch { print("Could not write report: \(error)") }
        print("\(passed ? "PASS" : "FAIL"): \(message)")
        print("Report: \(output.path)")
        // Give mDNSResponder a run-loop turn to send goodbye records before exit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { exit(passed ? 0 : 1) }
    }
}

@main struct BonjourProbeMain {
    private static var retained: BonjourProbe?
    static func main() {
        setbuf(stdout, nil)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/discovery-report.json")
        let probe = BonjourProbe(output: output)
        retained = probe
        probe.start()
        RunLoop.main.run()
    }
}
