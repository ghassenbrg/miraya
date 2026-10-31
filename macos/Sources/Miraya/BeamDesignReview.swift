#if DEBUG
import AppKit
import SwiftUI
import MirayaCore

/// Render the actual native views without discovery, capture, Keychain access or a network session.
@MainActor enum BeamDesignReview {
    static func runIfRequested() {
        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--render-beam-review=") }) else { return }
        let destination = URL(fileURLWithPath: String(argument.dropFirst("--render-beam-review=".count)), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            NSApplication.shared.setActivationPolicy(.prohibited)
            for (name, width, appearance) in [("ready",420,"light"),("compact",340,"light"),("pairing",420,"light"),("connecting",420,"light"),("live",420,"light"),("paused",420,"light"),("permission",420,"light"),("dark-live",420,"dark")] {
                let model = AppModel(designPreview: true), discovery = Discovery()
                discovery.receivers = [model.selected!]
                if name == "pairing" { model.phase = .pairing; model.pairingCode = "481729" }
                if name == "connecting" { model.phase = .authorizing }
                if ["live","dark-live","paused"].contains(name) { model.phase = name == "paused" ? .paused : .sharing; model.encodedPicture = "1662 × 1080"; model.receiverFPS = 30 }
                if name == "permission" { model.capturePermissionDenied = true; model.error = "Screen recording permission is required." }
                let view = NSHostingView(rootView: ContentView(model: model, discovery: discovery).environment(\.controlActiveState, .active).environment(\.colorScheme, appearance == "dark" ? .dark : .light))
                let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: width,height: 650), styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = view; view.frame = NSRect(x: 0, y: 0, width: width, height: 650)
                view.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
                window.layoutIfNeeded(); view.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
                view.cacheDisplay(in: view.bounds, to: image)
                guard let png = image.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to: destination.appendingPathComponent("mac-\(name).png"))
                window.orderOut(nil)
            }
            print("Native Beam views rendered to \(destination.path)")
            exit(0)
        } catch { fputs("Native Beam rendering failed: \(error)\n", stderr); exit(1) }
    }
}
#endif
