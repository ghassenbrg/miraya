import AppKit
import ScreenCaptureKit
import CoreVideo
import MirayaCore

/// Opt-in local regression check. Captures only this generated test window and
/// its matching screen rectangle; never captures a user's document.
enum CaptureSourceProbe {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--probe-capture-sources") else { return }
        setbuf(stdout, nil)
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        Task { @MainActor in
            let window = NSWindow(contentRect: CGRect(x: 160, y: 200, width: 640, height: 360), styleMask: .borderless, backing: .buffered, defer: false)
            window.title = "Miraya generated capture fixture"; window.backgroundColor = .systemBlue; window.level = .floating
            window.makeKeyAndOrderFront(nil)
            let animation = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in window.backgroundColor = window.backgroundColor == NSColor.systemBlue ? .systemOrange : .systemBlue }
            defer { animation.invalidate(); window.orderOut(nil) }
            do {
                guard let screen = window.screen, let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { throw CaptureFailure.displayUnavailable }
                let region = CaptureRegion(x: window.frame.minX - screen.frame.minX, y: screen.frame.maxY - window.frame.maxY, width: 640, height: 360)
                for source in [CaptureSourceKind.window, .area] {
                    let engine = CaptureEngine(); let samples = CaptureProbeSamples()
                    engine.onFrame = { buffer, _ in samples.add(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)) }
                    try await engine.start(displayID: displayID, quality: .efficient, audio: false, source: source, windowID: UInt32(window.windowNumber), region: region)
                    for _ in 0..<80 {
                        if samples.count >= 3 { break }
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                    await engine.stop()
                    guard samples.count >= 3, samples.valid else { throw WireError.invalidControl }
                    print("PASS \(source.rawValue) capture: \(samples.count) generated frames, 1280 × 720 or 640 × 360 according to display scale")
                }
                exit(0)
            } catch { fputs("FAIL capture-source check: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        app.run(); exit(1)
    }
}

private final class CaptureProbeSamples: @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0
    private var matches = true
    var count: Int { lock.lock(); defer { lock.unlock() }; return frames }
    var valid: Bool { lock.lock(); defer { lock.unlock() }; return matches }
    func add(width: Int, height: Int) { lock.lock(); defer { lock.unlock() }; frames += 1; matches = matches && ((width == 1280 && height == 720) || (width == 640 && height == 360)) }
}
