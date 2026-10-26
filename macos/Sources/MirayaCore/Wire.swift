import Foundation

public enum WireError: Error, LocalizedError {
    case invalidHeader, oversized, invalidControl
    public var errorDescription: String? {
        switch self {
        case .invalidHeader: return "The receiver sent an invalid protocol packet. Update both Miraya apps."
        case .oversized: return "The receiver exceeded Miraya's packet size limit."
        case .invalidControl: return "The receiver sent an invalid control message."
        }
    }
}

public enum PacketType: UInt8 { case control = 1, videoConfig = 2, video = 3, audio = 4 }

public struct Packet {
    public let type: PacketType
    public let flags: UInt8
    public let pts: UInt64
    public let sequence: UInt32
    public let payload: Data
    public init(type: PacketType, flags: UInt8 = 0, pts: UInt64 = 0, sequence: UInt32 = 0, payload: Data) {
        self.type = type; self.flags = flags; self.pts = pts; self.sequence = sequence; self.payload = payload
    }
    public func encoded() throws -> Data {
        try Self.validate(type: type, flags: flags, size: payload.count, pts: pts)
        var result = Data([0x4d, 0x52, 0x59, 0x31, type.rawValue, flags, 0, 0])
        result.appendBE(UInt32(payload.count)); result.appendBE(pts); result.appendBE(sequence)
        result.append(payload)
        return result
    }
    static func validate(type: PacketType, flags: UInt8, size: Int, pts: UInt64) throws {
        guard flags == 0 || (type == .video && flags == 1) else { throw WireError.invalidHeader }
        guard pts <= UInt64(Int64.max) else { throw WireError.invalidHeader }
        let maxSize = type == .control || type == .videoConfig ? 65_536 : type == .audio ? 19_200 : 4_194_304
        guard size > 0, size <= maxSize else { throw WireError.oversized }
        if type == .audio && size % 4 != 0 { throw WireError.invalidHeader }
    }
    public var control: [String: Any] {
        get throws {
            guard type == .control, let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any], object["op"] is String else { throw WireError.invalidControl }
            return object
        }
    }
}

/// Streaming parser handles arbitrary TCP segmentation, never allocates from an unchecked length.
public struct PacketParser {
    private var buffer = Data()
    public init() {}
    public mutating func append(_ data: Data) throws -> [Packet] {
        // Network reads are capped to 64KiB. Buffered bytes may contain one maximum-size media packet.
        guard buffer.count + data.count <= 4_194_304 + 65_536 + 24 else { throw WireError.oversized }
        buffer.append(data)
        var packets: [Packet] = []
        var offset = 0
        while buffer.count - offset >= 24 {
            let b = buffer
            guard b[offset] == 0x4d, b[offset+1] == 0x52, b[offset+2] == 0x59, b[offset+3] == 0x31,
                  let type = PacketType(rawValue: b[offset+4]), b[offset+6] == 0, b[offset+7] == 0 else { throw WireError.invalidHeader }
            let flags = b[offset+5]
            let length = Int(b.readBE(at: offset+8, as: UInt32.self))
            let pts = b.readBE(at: offset+12, as: UInt64.self)
            try Packet.validate(type: type, flags: flags, size: length, pts: pts)
            guard buffer.count - offset >= length + 24 else { break }
            packets.append(Packet(type: type, flags: flags, pts: pts, sequence: b.readBE(at: offset+20, as: UInt32.self), payload: Data(b[(offset+24)..<(offset+24+length)])))
            offset += 24 + length
        }
        if offset > 0 { buffer = Data(buffer.dropFirst(offset)) }
        return packets
    }
}

extension Data {
    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }
    func readBE<T: FixedWidthInteger>(at index: Int, as: T.Type) -> T {
        var value: T = 0
        for b in self[index..<(index + MemoryLayout<T>.size)] { value = (value << 8) | T(b) }
        return value
    }
}

public struct VideoSize: Equatable {
    public let width: Int
    public let height: Int
    public static func fit(width: Int, height: Int, maxWidth: Int, maxHeight: Int) -> VideoSize {
        guard width > 0, height > 0 else { return VideoSize(width: 2, height: 2) }
        let ratio = min(1, min(Double(maxWidth) / Double(width), Double(maxHeight) / Double(height)))
        return VideoSize(width: max(2, Int(Double(width) * ratio) / 2 * 2), height: max(2, Int(Double(height) * ratio) / 2 * 2))
    }
}

public enum PairingCode {
    public static func normalize(_ input: String) -> String? {
        let s = input.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "").lowercased()
        guard s.count == 16, s.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
        return s
    }
}
