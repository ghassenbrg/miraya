import Foundation
import MirayaCore

final class Diagnostics: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.miraya.diagnostics", qos: .utility)
    private var history = DiagnosticHistory()
    private var lastSample = Date.distantPast
    private let url: URL?
    init() {
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Miraya/diagnostics.json")
        if let url, let data = try? Data(contentsOf: url), data.count <= 1_000_000, let saved = try? JSONDecoder().decode(DiagnosticHistory.self, from: data) {
            // Reapply the allowlist and retention policy even to on-disk data.
            let cutoff = Date().addingTimeInterval(-72 * 3600)
            for entry in saved.events.suffix(2000) where entry.time >= cutoff && entry.time <= Date() { history.record(entry.event, values: entry.values, now: entry.time) }
        }
    }
    func record(_ event: String, values: [String: Double] = [:]) {
        queue.async {
            if event == "sample" {
                guard Date().timeIntervalSince(self.lastSample) >= 5 else { return }; self.lastSample = Date()
            }
            self.history.record(event, values: values)
            guard let url = self.url, let data = try? JSONEncoder().encode(self.history) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        }
    }
    func export(to url: URL) throws {
        try queue.sync {
            var fresh = DiagnosticHistory()
            for event in history.events where Date().timeIntervalSince(event.time) <= 72 * 3600 { fresh.record(event.event, values: event.values, now: event.time) }
            struct Report: Encodable { let version: String; let platform: String; let history: DiagnosticHistory }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            let report = Report(version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0", platform: ProcessInfo.processInfo.operatingSystemVersionString, history: fresh)
            try encoder.encode(report).write(to: url, options: .atomic)
        }
    }
}
