import SwiftUI
import AppKit

@main struct MirayaApp: App {
    init() { TransportProbe.runIfRequested() }
    @StateObject private var model = AppModel()
    @StateObject private var discovery = Discovery()
    @NSApplicationDelegateAdaptor(MirayaAppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("Miraya") {
            ContentView(model: model, discovery: discovery)
                .onAppear { delegate.model = model; discovery.start() }
        }
        .defaultSize(width: 820, height: 670)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) { Button("Screen Recording Settings…") { model.openRecordingSettings() } }
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Sharing") { Button("Stop Sharing") { model.stop() }.keyboardShortcut(".").disabled(!model.busy) }
        }
        MenuBarExtra("Miraya", systemImage: model.busy ? "display.and.arrow.down" : "tv") {
            Text(model.phase.title)
            if let receiver = model.selected { Text(receiver.name) }
            Divider()
            Button("Show Miraya") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first?.makeKeyAndOrderFront(nil) }
            Button("Stop Sharing") { model.stop() }.disabled(!model.busy).keyboardShortcut(".")
            Divider()
            Button("Quit Miraya") { model.stop(); NSApp.terminate(nil) }
        }
    }
}

@MainActor final class MirayaAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationWillTerminate(_ notification: Notification) { model?.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
