import Foundation
import CoreFoundation

public enum PictureMode: String, CaseIterable, Identifiable {
    case fit, fill, stretch
    public var id: String { rawValue }
    public var label: String {
        switch self { case .fit: return "Fit · whole screen"; case .fill: return "Fill · crop edges"; case .stretch: return "Stretch · fill TV" }
    }
}

/// The TV's app viewport may be 1080p even when its physical output mode is 4K.
/// These are presentation dimensions, independent of encoder/decoder limits.
public struct TVDisplay: Equatable {
    public let width: Int, height: Int, panelWidth: Int, panelHeight: Int
    public let refreshRate: Double
    public let mode: PictureMode
    public let edgeInsetPercent: Int
    public init?(json: [String: Any]) {
        func dimension(_ key: String) -> Int? {
            guard let value = json[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite, (16...16384).contains(value.intValue), value.doubleValue == Double(value.intValue) else { return nil }
            return value.intValue
        }
        guard let width = dimension("width"), let height = dimension("height"),
              let panelWidth = dimension("panelWidth"), let panelHeight = dimension("panelHeight"),
              let refresh = json["refreshRate"] as? Double, refresh.isFinite, (1...360).contains(refresh),
              let name = json["mode"] as? String, let mode = PictureMode(rawValue: name),
              let inset = json["edgeInsetPercent"] as? NSNumber, CFGetTypeID(inset) != CFBooleanGetTypeID(),
              (0...10).contains(inset.intValue), inset.doubleValue == Double(inset.intValue) else { return nil }
        self.width = width; self.height = height; self.panelWidth = panelWidth; self.panelHeight = panelHeight
        self.refreshRate = refresh; self.mode = mode; self.edgeInsetPercent = inset.intValue
    }
}
