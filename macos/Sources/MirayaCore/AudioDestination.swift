public enum AudioDestination: String, CaseIterable, Identifiable {
    case mac, tv, both
    public var id: String { rawValue }
    public var label: String { switch self { case .mac: return "Mac only"; case .tv: return "TV only"; case .both: return "Both" } }
    public var sendsToTV: Bool { self != .mac }
    public var mutesMac: Bool { self == .tv }
}
