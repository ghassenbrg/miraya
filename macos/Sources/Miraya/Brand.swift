import SwiftUI
import AppKit

/// Beam's neutral native surfaces keep the warm/cool identity meaningful.
enum MirayaTheme {
    static let midnight = Color(red: 11/255, green: 19/255, blue: 35/255)
    static let blue = Color(red: 21/255, green: 93/255, blue: 221/255)
    static let amber = Color(red: 1, green: 150/255, blue: 81/255)
    static let destructive = Color(red: 190/255, green: 44/255, blue: 60/255)
    static let soft = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(srgbRed: 180/255, green: 192/255, blue: 209/255, alpha: 1) : NSColor(srgbRed: 89/255, green: 100/255, blue: 116/255, alpha: 1) })
    static let success = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(srgbRed: 134/255, green: 213/255, blue: 167/255, alpha: 1) : NSColor(srgbRed: 35/255, green: 115/255, blue: 72/255, alpha: 1) })
    static let border = Color(nsColor: .separatorColor)
    static let surface = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(srgbRed: 32/255, green: 44/255, blue: 61/255, alpha: 1) : .white })
    static let background = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(srgbRed: 23/255, green: 32/255, blue: 46/255, alpha: 1) : NSColor(srgbRed: 246/255, green: 247/255, blue: 249/255, alpha: 1) })
}

enum BeamAssets {
    private static var cache: [String: NSImage] = [:]
    /// MenuBarExtra bridges this image to NSStatusItem. Mark the NSImage itself
    /// as a template so AppKit tints it for the menu bar's background, which can
    /// differ from the app's light/dark appearance.
    static let menuBarIcon: NSImage? = {
        guard let image = image("beam-menu")?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
    static func image(_ name: String) -> NSImage? {
        if let image = cache[name] { return image }
        let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Beam")
            ?? Bundle.module.url(forResource: name, withExtension: "png")
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }
}

struct BeamMark: View {
    var state = "connected"
    var body: some View {
        Group {
            if let image = BeamAssets.image("beam-\(state)") { Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit) }
            else {
                HStack(spacing: 3) {
                    BeamPlane().fill(LinearGradient(colors: [MirayaTheme.amber, .white], startPoint: .leading, endPoint: .trailing))
                    BeamPlane().fill(LinearGradient(colors: [.white, MirayaTheme.blue], startPoint: .leading, endPoint: .trailing)).scaleEffect(x: -1, y: 1)
                }
            }
        }.accessibilityHidden(true)
    }
}
private struct BeamPlane: Shape {
    func path(in r: CGRect) -> Path { Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: r.width, y: r.height * 0.23)); p.addLine(to: CGPoint(x: r.width, y: r.height * 0.77)); p.addLine(to: CGPoint(x: 0, y: r.height)); p.closeSubpath() } }
}
struct MirayaWordmark: View {
    var state = "connected"
    var body: some View {
        HStack(spacing: 10) {
            BeamMark(state: state).frame(width: 36, height: 36)
            Text("Miraya").font(.system(size: 28, weight: .semibold)).tracking(-0.9)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Miraya")
    }
}

struct BeamActionStyle: ButtonStyle {
    var destructive = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        let color = destructive ? MirayaTheme.destructive : MirayaTheme.blue
        configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 13).padding(.vertical, 11).frame(maxWidth: .infinity, minHeight: 38)
            .background(color.opacity(enabled ? (configuration.isPressed ? 0.82 : 1) : 0.45), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? color : .clear, lineWidth: 2).padding(-3))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
struct BeamAudioToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule().fill(configuration.isOn ? MirayaTheme.blue : Color(nsColor: .systemGray)).frame(width: 33, height: 19)
                .overlay(Circle().fill(.white).frame(width: 15, height: 15).shadow(color: .black.opacity(0.12), radius: 1).offset(x: configuration.isOn ? 7 : -7))
        }.buttonStyle(.plain).accessibilityRepresentation {
            Toggle("Send system audio to TV", isOn: configuration.$isOn).toggleStyle(.switch)
        }
    }
}
