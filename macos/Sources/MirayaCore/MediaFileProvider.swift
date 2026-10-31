import Foundation

/// Only explicitly selected, open files are readable. There is no file server,
/// directory traversal, public port, or plaintext LAN transfer.
public final class MediaFileProvider: @unchecked Sendable {
    private struct Asset { let file: FileHandle; let size: Int64 }
    private let queue = DispatchQueue(label: "app.miraya.selected-media", qos: .userInitiated)
    private var assets: [String: Asset] = [:]
    public init() {}
    public func authorize(_ url: URL) throws -> [String: Any] {
        try queue.sync {
            guard assets.count < 4 else { throw CocoaError(.fileReadTooLarge) }
            let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard properties.isRegularFile == true, let size = properties.fileSize, size > 0, size <= 1_099_511_627_776 else { throw CocoaError(.fileReadUnsupportedScheme) }
            let id = UUID().uuidString.lowercased()
            assets[id] = Asset(file: try FileHandle(forReadingFrom: url), size: Int64(size))
            return ["id":id, "size":size]
        }
    }
    public func respond(_ request: [String: Any], send: @escaping ([String: Any]) -> Void) {
        queue.async {
            guard let requestID = request["request"] as? String, UUID(uuidString: requestID) != nil else { return }
            var reply: [String: Any] = ["op":"mediaChunk", "request":requestID]
            do {
                guard let id = request["id"] as? String, let asset = self.assets[id],
                      let offsetNumber = request["offset"] as? NSNumber, let countNumber = request["count"] as? NSNumber,
                      offsetNumber.doubleValue == Double(offsetNumber.int64Value), countNumber.doubleValue == Double(countNumber.intValue),
                      DirectMedia.validRead(offset: offsetNumber.int64Value, count: countNumber.intValue, size: asset.size) else { throw WireError.invalidControl }
                try asset.file.seek(toOffset: UInt64(offsetNumber.int64Value))
                let data = try asset.file.read(upToCount: min(countNumber.intValue, Int(asset.size - offsetNumber.int64Value))) ?? Data()
                reply["data"] = data.base64EncodedString()
            } catch { reply["error"] = "Selected media is no longer available." }
            send(reply)
        }
    }
    public func close() { queue.sync { assets.values.forEach { try? $0.file.close() }; assets.removeAll() } }
    deinit { assets.values.forEach { try? $0.file.close() } }
}
