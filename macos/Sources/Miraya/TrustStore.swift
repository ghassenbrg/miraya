import Foundation
import MirayaCore

struct TrustedReceiver: Codable, Identifiable {
    let id: String
    let name: String
    let fingerprint: String
    let token: String
    let clientID: String
    var serviceName: String?
    var domain: String?
    var host: String?
    var port: UInt16
    var receiver: Receiver? {
        if let host, let p = NWEndpoint.Port(rawValue: port) { return Receiver(id: id, name: name, endpoint: .hostPort(host: .init(host), port: p), host: host, port: port) }
        if let serviceName, let domain { return Receiver(id: id, name: name, endpoint: .service(name: serviceName, type: "_miraya._tcp", domain: domain, interface: nil), serviceName: serviceName, domain: domain) }
        return nil
    }
}

import Network

enum TrustStore {
    private static let vault = KeychainVault(service: "app.miraya.sender.paired-tv")
    static func all() throws -> [TrustedReceiver] {
        try vault.records().map { try JSONDecoder().decode(TrustedReceiver.self, from: $0) }.sorted { $0.name < $1.name }
    }
    static func save(_ receiver: TrustedReceiver) throws {
        try vault.save(JSONEncoder().encode(receiver), account: receiver.id)
    }
    static func remove(_ id: String) throws { try vault.remove(account: id) }
}
