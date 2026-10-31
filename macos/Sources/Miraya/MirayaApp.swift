import SwiftUI
import AppKit

@main struct MirayaApp: App {
    init() {
        #if DEBUG
        BeamDesignReview.runIfRequested()
        #endif
        LocalAudioGuardian.runIfRequested(); TransportProbe.runIfRequested(); CaptureSourceProbe.runIfRequested() }
    @StateObject private var model = AppModel()
    @StateObject private var discovery = Discovery()
    @NSApplicationDelegateAdaptor(MirayaAppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("Miraya") {
            ContentView(model: model, discovery: discovery)
                .onAppear { delegate.model = model; discovery.start(); delegate.adoptBeamWindowSize() }
        }
        .defaultSize(width: 420, height: 680)
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) { Button("Screen Recording Settings…") { model.openRecordingSettings() } }
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Sharing") { Button("Stop Sharing") { model.stop() }.keyboardShortcut(".").disabled(!model.busy) }
        }
        Window("Live sharing metrics", id: "sharing-metrics") { SharingMetricsView(model: model) }.defaultSize(width: 540, height: 740)
        MenuBarExtra {
            Text(model.statusTitle)
            if let receiver = model.selected { Text(receiver.name) }
            Divider()
            Button("Show Miraya") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first?.makeKeyAndOrderFront(nil) }
            if model.phase == .sharing { Button("Pause Sharing") { model.pause() } }
            if model.phase == .paused { Button("Resume Sharing") { model.resume() } }
            Button("Stop Sharing") { model.stop() }.disabled(!model.busy).keyboardShortcut(".")
            Divider()
            Button("Quit Miraya") { model.stop(); NSApp.terminate(nil) }
        } label: {
            if let icon = BeamAssets.menuBarIcon {
                Image(nsImage: icon).renderingMode(.template).accessibilityLabel("Miraya")
            } else { Image(systemName: "tv").accessibilityLabel("Miraya") }
        }
    }
}

@MainActor final class MirayaAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func adoptBeamWindowSize() {
        guard !UserDefaults.standard.bool(forKey: "beamCompactWindowV1") else { return }
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.title == "Miraya" }) else { return }
            window.setContentSize(NSSize(width: 420, height: 650))
            UserDefaults.standard.set(true, forKey: "beamCompactWindowV1")
        }
    }
    func applicationWillTerminate(_ notification: Notification) { model?.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
