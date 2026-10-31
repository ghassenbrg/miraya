import Foundation

public enum CaptureSourceKind: String, CaseIterable, Identifiable, Sendable {
    case display, window, area
    public var id: String { rawValue }
    public var label: String { switch self { case .display: return "Entire display"; case .window: return "One window"; case .area: return "Selected area" } }
}

public struct CaptureRegion: Equatable, Codable, Sendable {
    public let x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    public func validated(displayWidth: Double, displayHeight: Double) -> Bool {
        [x, y, width, height, displayWidth, displayHeight].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width >= 32 && height >= 32 && x + width <= displayWidth + 0.5 && y + height <= displayHeight + 0.5
    }
}

public enum SharingProfile: String, CaseIterable, Identifiable {
    case desktop, video
    public var id: String { rawValue }
    public var label: String { self == .desktop ? "Desktop · responsive" : "Watching video · picture detail" }
    public var detail: String { self == .desktop ? "Favors responsive motion. Quality and playback priority remain adjustable." : "Starts at 1080p/30 and preserves detail before frame rate. Use 60 fps for high-frame-rate content." }
}

public enum PlaybackMode: String, CaseIterable, Identifiable {
    case mirror, media
    public var id: String { rawValue }
    public var label: String { self == .mirror ? "Share screen" : "Play video on TV" }
}

public enum DirectMedia {
    public static let maximumChunk = 32_768
    public static func validRemoteURL(_ text: String) -> Bool {
        guard text.count <= 8192, let parts = URLComponents(string: text), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return false }
        return true
    }
    public static func validRead(offset: Int64, count: Int, size: Int64) -> Bool {
        offset >= 0 && offset <= size && count > 0 && count <= maximumChunk && size > 0
    }
}
