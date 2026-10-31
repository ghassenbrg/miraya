import Foundation

/// Transport liveness uses elapsed time, not the distance between media PTSs:
/// ScreenCaptureKit may produce no video at all while the desktop is unchanged.
/// The owner serializes access (StreamConnection uses its pressure lock).
public struct StreamFlowControl {
    private var latest: UInt64?
    private var acknowledged: UInt64?
    private var progressAt: TimeInterval = 0
    private var probeAt: TimeInterval = -.infinity
    private var behindSince: TimeInterval?

    public init() {}
    public mutating func sent(pts: UInt64, now: TimeInterval) {
        if latest == nil || latest == acknowledged { progressAt = now }
        latest = max(latest ?? pts, pts)
    }
    public mutating func acknowledge(pts: UInt64, now: TimeInterval) {
        guard let latest, pts <= latest, acknowledged == nil || pts > acknowledged! else { return }
        acknowledged = pts
        progressAt = now
        if !isBehind { behindSince = nil }
    }
    private var isBehind: Bool {
        guard let latest, let acknowledged else { return false }
        return latest > acknowledged && latest - acknowledged > 400_000
    }
    public mutating func congested(now: TimeInterval) -> Bool {
        if isBehind || (latest != nil && latest != acknowledged && now - progressAt > 0.7) {
            if behindSince == nil { behindSince = now }
        } else { behindSince = nil }
        return behindSince.map { now - $0 > 0.5 } ?? false
    }
    public mutating func shouldEncode(bufferedBytes: Int, now: TimeInterval) -> Bool {
        guard bufferedBytes < 256_000 else { return false }
        if isBehind || (latest != nil && latest != acknowledged && now - progressAt > 0.7) {
            // Never starve the decoder of the IDR needed to recover.
            guard now - probeAt >= 0.25 else { return false }
            probeAt = now
        }
        return true
    }
    public func stalled(now: TimeInterval) -> Bool {
        latest != nil && latest != acknowledged && now - progressAt > 8
    }
}

/// Only packets not yet handed to TCP can be discarded. If a video dependency
/// is removed, drop its dependent frames until an IDR arrives. Control and codec
/// configuration keep their order. A large individual IDR is valid, not a reason
/// to tear down TLS. The queue is bounded by one wire-size frame plus controls.
public struct MediaSendQueue {
    public struct Entry {
        public let packet: Packet
        public let queuedAt: TimeInterval
        public var byteCount: Int { packet.payload.count + 24 }
    }
    private var entries: [Entry] = []
    private var awaitingKeyframe = false
    public private(set) var byteCount = 0
    public var isEmpty: Bool { entries.isEmpty }
    public var needsKeyframe: Bool { awaitingKeyframe }
    public init() {}

    @discardableResult public mutating func append(_ packet: Packet, now: TimeInterval) -> Bool {
        var recovering = false
        if packet.type == .video || packet.type == .audio {
            let stale = entries.first(where: { $0.packet.type == .video || $0.packet.type == .audio }).map { now - $0.queuedAt > 0.2 } ?? false
            if stale || (!entries.isEmpty && byteCount + packet.payload.count + 24 > 512_000) {
                discardMedia(); recovering = true
            }
            if packet.type == .video && awaitingKeyframe && packet.flags & 1 == 0 { return recovering }
            if packet.type == .video && packet.flags & 1 != 0 { awaitingKeyframe = false }
        }
        entries.append(Entry(packet: packet, queuedAt: now))
        byteCount += packet.payload.count + 24
        return recovering
    }
    public mutating func discardMedia() {
        entries.removeAll { $0.packet.type == .video || $0.packet.type == .audio }
        byteCount = entries.reduce(0) { $0 + $1.byteCount }
        awaitingKeyframe = true
    }
    public mutating func pop() -> Entry? {
        guard !entries.isEmpty else { return nil }
        let entry = entries.removeFirst(); byteCount -= entry.byteCount
        return entry
    }
}
