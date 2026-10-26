import Foundation
import Network
import Combine

struct Receiver: Identifiable, Hashable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
    var serviceName: String?
    var domain: String?
    var host: String?
    var port: UInt16 = 7421
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.endpoint == rhs.endpoint && lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// NetService and its delegates are scheduled on the main run loop. Construct
/// and call this object only from the UI, keeping published changes on that loop.
final class Discovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published var receivers: [Receiver] = []
    @Published var message = "Looking for TVs on your local network…"
    private let browser = NetServiceBrowser()
    private var services: [String: NetService] = [:]
    private struct Resolution { let receiver: Receiver; let order: UInt64 }
    private var resolved: [String: Resolution] = [:]
    private var resolutionOrder: UInt64 = 0
    private var resolutionAttempts: [String: Int] = [:]
    private var timeoutTask: Task<Void, Never>?
    private var started = false
    override init() { super.init(); browser.delegate = self }
    func start() {
        guard !started else { return }; started = true
        browser.searchForServices(ofType: "_miraya._tcp.", inDomain: "local.")
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            guard let self, self.receivers.isEmpty else { return }
            self.message = "Open Miraya on your TV. Use the same Wi-Fi or Ethernet network. If your TV doesn’t appear, enter its address below."
        }
    }
    func refresh() {
        timeoutTask?.cancel(); timeoutTask = nil
        browser.stop(); started = false; services.values.forEach { $0.stop() }; services.removeAll(); resolved.removeAll(); resolutionAttempts.removeAll(); receivers = []
        message = "Looking for TVs on your local network…"; start()
    }
    private func key(_ service: NetService) -> String { service.name + "." + service.domain }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services[key(service)]?.stop()
        services[key(service)] = service; service.delegate = self; service.resolve(withTimeout: 5)
        resolutionAttempts[key(service)] = 1
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard services[key(sender)] === sender else { return }
        guard let txt = sender.txtRecordData() else { return }
        let dict = NetService.dictionary(fromTXTRecord: txt)
        guard dict["v"].flatMap({ String(data: $0, encoding: .utf8) }) == "1",
              let rawID = dict["id"].flatMap({ String(data: $0, encoding: .utf8) }), let uuid = UUID(uuidString: rawID),
              (1...65535).contains(sender.port) else {
            resolved.removeValue(forKey: key(sender)); publish()
            message = "A TV has an incompatible Miraya version. Update both apps."; return
        }
        resolutionOrder &+= 1
        resolved[key(sender)] = Resolution(receiver: Receiver(id: uuid.uuidString.lowercased(), name: sender.name,
            endpoint: .service(name: sender.name, type: "_miraya._tcp", domain: sender.domain, interface: nil),
            serviceName: sender.name, domain: sender.domain, port: UInt16(sender.port)), order: resolutionOrder)
        publish()
    }
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        let serviceKey = key(sender)
        guard services[serviceKey] === sender, resolutionAttempts[serviceKey, default: 0] < 2 else { return }
        resolutionAttempts[serviceKey, default: 0] += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak sender] in
            guard let self, let sender, self.started, self.services[serviceKey] === sender else { return }
            sender.resolve(withTimeout: 5)
        }
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeValue(forKey: key(service))?.stop(); resolved.removeValue(forKey: key(service)); publish()
        resolutionAttempts.removeValue(forKey: key(service))
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        started = false
        message = "Local discovery is unavailable. Allow Miraya in System Settings → Privacy & Security → Local Network, or enter the TV address."
    }
    private func publish() {
        // During a rename or a network-interface change, old and new Bonjour
        // service names may overlap. Publish one row per stable receiver UUID,
        // preferring the most recently resolved service, not two duplicate IDs.
        var newest: [String: Resolution] = [:]
        for entry in resolved.values where newest[entry.receiver.id] == nil || newest[entry.receiver.id]!.order < entry.order {
            newest[entry.receiver.id] = entry
        }
        receivers = newest.values.map(\.receiver).sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        message = receivers.isEmpty ? "Open Miraya on your TV and connect both devices to the same network." : "Choose a TV to share your screen."
    }
    deinit { timeoutTask?.cancel(); browser.stop(); services.values.forEach { $0.stop() } }
}
