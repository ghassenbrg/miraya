import Foundation

public struct DiagnosticEvent: Codable {
    public let time: Date
    public let event: String
    public let values: [String: Double]
}

/// Allowlisted numeric metadata only: never titles, URLs, paths, credentials,
/// remote payloads, or screen/audio content.
public struct DiagnosticHistory: Codable {
    public private(set) var events: [DiagnosticEvent] = []
    public init() {}
    public mutating func record(_ event: String, values: [String: Double] = [:], now: Date = Date()) {
        let names: Set<String> = ["idle", "connecting", "permissions", "pairing", "authorizing", "starting", "sharing", "pausing", "paused", "reconnecting", "sample", "connectionFailure", "mediaReady", "mediaError", "mediaEnded"]
        let fields: Set<String> = ["fps", "drops", "rttMs", "jitterMs", "lossPercent", "bitrate", "width", "height", "frameCap", "receiverScale", "cpuLimited", "bandwidthLimited", "direct", "bufferedMs", "positionMs"]
        guard names.contains(event) else { return }
        events.removeAll { now.timeIntervalSince($0.time) > 72 * 3600 || $0.time > now.addingTimeInterval(60) }
        events.append(DiagnosticEvent(time: now, event: event, values: values.filter { fields.contains($0.key) && $0.value.isFinite }))
        if events.count > 2000 { events.removeFirst(events.count - 2000) }
    }
}
