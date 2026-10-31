import AppKit
import MirayaCore

/// A local selection overlay. No screenshots or screen pixels are retained.
@MainActor final class AreaSelection {
    private var panel: NSPanel?
    func choose(displayID: CGDirectDisplayID, completion: @escaping (CaptureRegion?) -> Void) {
        guard panel == nil, let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == displayID }) else { completion(nil); return }
        let panel = SelectionPanel(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        panel.level = .screenSaver; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.completed = { [weak self] rect in
            self?.panel?.orderOut(nil); self?.panel?.close(); self?.panel = nil
            NSCursor.arrow.set()
            completion(rect.map { CaptureRegion(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height) })
        }
        panel.contentView = view; self.panel = panel
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(view)
        NSCursor.crosshair.set()
    }
}

private final class SelectionPanel: NSPanel { override var canBecomeKey: Bool { true } }

private final class SelectionView: NSView {
    var completed: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var selection = CGRect.zero
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.45).setFill(); bounds.fill()
        if !selection.isEmpty {
            NSColor.white.withAlphaComponent(0.16).setFill(); selection.fill()
            NSColor.systemCyan.setStroke(); let path = NSBezierPath(rect: selection); path.lineWidth = 2; path.stroke()
        }
        let instruction = "Drag to choose an area · Esc to cancel"
        instruction.draw(at: CGPoint(x: 24, y: 24), withAttributes: [.foregroundColor:NSColor.white, .font:NSFont.systemFont(ofSize: 20, weight: .semibold)])
    }
    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil) }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }; let end = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x-end.x), height: abs(start.y-end.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { mouseDragged(with: event); completed?(selection.width >= 32 && selection.height >= 32 ? selection : nil) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { completed?(nil) } else { super.keyDown(with: event) } }
}
