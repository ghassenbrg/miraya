import SwiftUI
import MirayaCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var discovery: Discovery
    @State private var showHelp = false
    private let accent = MirayaTheme.cyan
    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 9) {
                    MirayaWordmark()
                    Text("YOUR SCREEN, ON THE BIG SCREEN.").font(.system(size: 10, weight: .medium)).tracking(2.3).foregroundStyle(MirayaTheme.soft)
                }
                Spacer()
                ConnectionArtwork().frame(width: 160, height: 102)
                Button { showHelp.toggle() } label: { Image(systemName: "questionmark.circle").font(.title3).foregroundStyle(MirayaTheme.soft) }
                    .buttonStyle(.plain).help("Connection help").popover(isPresented: $showHelp) { helpPanel }
            }.padding(.top, 16)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        Text("Available TVs").font(.headline).foregroundStyle(MirayaTheme.soft)
                        Spacer()
                        Button { discovery.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).foregroundStyle(MirayaTheme.soft).help("Find TVs again").disabled(model.busy)
                    }
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(discovery.receivers) { receiver in receiverRow(receiver, nearby: true) }
                            ForEach(model.remembered.filter { trust in !discovery.receivers.contains(where: { $0.id == trust.id }) }) { trust in
                                if let receiver = trust.receiver { receiverRow(receiver, nearby: false) }
                            }
                            if let selected = model.selected, selected.host != nil, !model.remembered.contains(where: { $0.id == selected.id }) { receiverRow(selected, nearby: false) }
                            if discovery.receivers.isEmpty && model.remembered.isEmpty && model.selected == nil {
                                VStack(spacing: 15) {
                                    Image(systemName: "wifi").font(.system(size: 30, weight: .light)).foregroundStyle(accent).padding(.top, 25)
                                    Text("Looking for your TV").fontWeight(.medium)
                                    Text("Open Miraya on your TV. It appears here automatically when both devices are on the same network.").font(.callout).foregroundStyle(MirayaTheme.soft).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                                }.padding(12)
                            }
                        }
                    }.frame(minHeight: 225, maxHeight: .infinity)
                    Text(discovery.message).font(.caption).foregroundStyle(MirayaTheme.soft.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                    Divider().overlay(MirayaTheme.border)
                    Button("Connect by address…", systemImage: "network") { model.showManual = true }.buttonStyle(.plain).font(.callout).foregroundStyle(MirayaTheme.soft).disabled(model.busy)
                }.padding(20).frame(width: 295).frame(maxHeight: .infinity).background(panel)
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 15) {
                        Image(systemName: "tv").font(.system(size: 28, weight: .light)).foregroundStyle(accent)
                            .frame(width: 62, height: 62).background(MirayaTheme.flow.opacity(0.10), in: RoundedRectangle(cornerRadius: 17))
                            .overlay(RoundedRectangle(cornerRadius: 17).stroke(MirayaTheme.border))
                        VStack(alignment: .leading, spacing: 7) {
                            Text(model.selected?.name ?? "Choose your TV").font(.title3.weight(.semibold)).lineLimit(2)
                            HStack(spacing: 7) {
                                Circle().fill(model.phase == .sharing ? Color.green : model.selected != nil ? accent : MirayaTheme.soft.opacity(0.4)).frame(width: 6, height: 6)
                                Text(connectionStatus).font(.caption).foregroundStyle(MirayaTheme.soft)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    if model.busy && model.phase != .sharing {
                        HStack(spacing: 12) { ProgressView().controlSize(.small); Text(model.phase.title).font(.callout) }.padding(.vertical, 5)
                    }
                    Divider().overlay(MirayaTheme.border)
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Share display").font(.callout).foregroundStyle(MirayaTheme.soft)
                            Picker("Share display", selection: $model.displayID) { ForEach(model.displays) { Text($0.name).tag($0.id) } }.labelsHidden().frame(maxWidth:.infinity).controlSize(.large)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quality").font(.callout).foregroundStyle(MirayaTheme.soft)
                            Picker("Quality", selection: $model.quality) { ForEach(CaptureQuality.allCases) { Text($0.label).tag($0) } }.labelsHidden().frame(maxWidth:.infinity).controlSize(.large)
                        }
                        HStack(spacing: 12) {
                            Image(systemName: "speaker.wave.2").font(.title3).foregroundStyle(MirayaTheme.soft)
                            VStack(alignment: .leading, spacing: 4) { Text("Include system audio").font(.callout); Text("Share what you hear").font(.caption).foregroundStyle(MirayaTheme.soft.opacity(0.7)) }
                            Spacer()
                            Toggle("Include system audio", isOn: $model.audio).labelsHidden().toggleStyle(.switch).tint(MirayaTheme.blue)
                        }.padding(.top, 3)
                    }.disabled(model.busy)
                    Spacer(minLength: 0)
                    if model.busy {
                        Button { model.stop() } label: { Label("Stop Sharing", systemImage: "stop.fill").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 11) }
                            .buttonStyle(.plain).background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 11)).keyboardShortcut(".")
                    } else {
                        Button { model.start() } label: { Label("Start Sharing", systemImage: "play.fill").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 11) }
                            .buttonStyle(.plain).foregroundStyle(.white).background(MirayaTheme.flow, in: RoundedRectangle(cornerRadius: 11))
                            .overlay(RoundedRectangle(cornerRadius: 11).stroke(accent.opacity(0.85)))
                            .shadow(color: accent.opacity(model.selected == nil ? 0 : 0.18), radius: 10, y: 3)
                            .opacity(model.selected == nil || model.displays.isEmpty ? 0.45 : 1).disabled(model.selected == nil || model.displays.isEmpty).keyboardShortcut(.return, modifiers: [])
                    }
                    HStack {
                        Label("Local & encrypted", systemImage: "lock.shield").font(.caption).foregroundStyle(MirayaTheme.soft.opacity(0.8))
                        Spacer()
                        if model.trustedSelection != nil { Button("Forget TV") { model.forgetSelected() }.buttonStyle(.plain).font(.caption).foregroundStyle(MirayaTheme.soft.opacity(0.8)).disabled(model.busy) }
                    }
                }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity).background(panel)
            }
            if let error = model.error {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.callout).textSelection(.enabled)
                        if error.contains("Screen & System Audio Recording") || error.contains("recording permission") {
                            Button("Open Screen Recording Settings…") { model.openRecordingSettings() }.buttonStyle(.link)
                        }
                    }
                    Spacer(); Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.padding(14).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            } else if let info = model.information {
                Text(info).font(.callout).foregroundStyle(MirayaTheme.soft).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(model.phase == .sharing ? "Your selected display and optional audio are visible on the TV." : model.busy ? "Your screen will appear when the secure connection is ready." : "Your display may include notifications. Microphone audio is never captured.").font(.caption).foregroundStyle(MirayaTheme.soft.opacity(0.65))
            }
        }.padding(.horizontal, 28).padding(.bottom, 22)
        .frame(minWidth: 850, minHeight: 680)
        .background(LinearGradient(colors: [Color(red: 0.025,green: 0.07,blue: 0.135), MirayaTheme.midnight], startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showPairing) { pairingSheet }
        .sheet(isPresented: $model.showManual) { manualSheet }
        .onAppear { model.discoveredReceiversChanged(discovery.receivers) }
        .onChange(of: discovery.receivers) { model.discoveredReceiversChanged($0) }
    }
    private var panel: some View { RoundedRectangle(cornerRadius: 16).fill(MirayaTheme.panel.opacity(0.75)).overlay(RoundedRectangle(cornerRadius:16).stroke(MirayaTheme.border.opacity(0.75))) }
    private var connectionStatus: String {
        if model.busy { return model.phase == .sharing ? "Sharing now" : model.phase.title }
        guard let selected = model.selected else { return "TVs appear automatically on your network" }
        return discovery.receivers.contains(where: { $0.id == selected.id }) ? "Android TV · Nearby" : selected.host != nil ? "Connect by address" : "Saved TV"
    }
    private func receiverRow(_ receiver: Receiver, nearby: Bool) -> some View {
        let selected = model.selected?.id == receiver.id
        return Button { model.selected = receiver; model.pairingCode = ""; model.error = nil } label: {
            HStack(spacing: 13) {
                Image(systemName: "tv").font(.system(size: 23, weight: .light)).foregroundStyle(selected ? accent : MirayaTheme.soft)
                VStack(alignment: .leading, spacing: 7) {
                    Text(receiver.name).font(.callout.weight(.medium)).foregroundStyle(.white).lineLimit(2)
                    HStack(spacing: 6) {
                        Circle().fill(nearby ? Color.green : MirayaTheme.soft.opacity(0.4)).frame(width:6,height:6)
                        Text(nearby ? "Android TV" : model.remembered.contains(where: { $0.id == receiver.id }) ? "Saved TV" : "Manual address").font(.caption).foregroundStyle(MirayaTheme.soft)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark" : "chevron.right").font(.caption).foregroundStyle(selected ? accent : MirayaTheme.soft.opacity(0.6))
            }.padding(15).frame(maxWidth:.infinity, alignment:.leading)
                .background(selected ? MirayaTheme.blue.opacity(0.16) : Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius:12).stroke(selected ? accent : MirayaTheme.border,lineWidth: selected ? 1.2 : 0.7))
        }.buttonStyle(.plain).disabled(model.busy)
    }
    private var pairingSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(accent)
            Text("Pair with \(model.selected?.name ?? "your TV")").font(.title2.weight(.semibold))
            Text("Enter the 16-character pairing code shown in Miraya on your TV. Then choose Allow using your TV remote.").fixedSize(horizontal: false, vertical: true)
            TextField("XXXX-XXXX-XXXX-XXXX", text: $model.pairingCode).textFieldStyle(.roundedBorder).font(.system(.title3,design:.monospaced)).onSubmit { if PairingCode.normalize(model.pairingCode) != nil { model.start() } }
            Text("Your Mac remembers this TV. Next time, select its name and start sharing.").font(.callout).foregroundStyle(MirayaTheme.soft)
            HStack { Button("Cancel") { model.showPairing = false }.keyboardShortcut(.cancelAction); Spacer(); Button("Pair & Share") { model.start() }.buttonStyle(.borderedProminent).tint(MirayaTheme.blue).disabled(PairingCode.normalize(model.pairingCode) == nil).keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 430).background(MirayaTheme.midnight)
    }
    private var manualSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Connect by address").font(.title2.weight(.semibold))
            Text("TVs normally appear automatically. If yours doesn’t, open Connection details on the TV and enter its address here.")
            TextField("TV address, e.g. 192.168.1.50",text:$model.manualHost).textFieldStyle(.roundedBorder)
            TextField("Port",text:$model.manualPort).textFieldStyle(.roundedBorder)
            HStack { Button("Cancel") { model.showManual = false }.keyboardShortcut(.cancelAction); Spacer(); Button("Use Address") { model.useManual() }.buttonStyle(.borderedProminent).tint(MirayaTheme.blue).keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width:430).background(MirayaTheme.midnight)
    }
    private var helpPanel: some View {
        VStack(alignment:.leading,spacing:15) {
            Text("Ready to share").font(.headline)
            Text("Open Miraya on your TV, then select its name here. Both devices need to be on the same local network. Name each TV from its Miraya settings.")
            Text("For first pairing, enter the TV code and approve with the remote. No account or internet connection is needed.")
            Divider()
            Button("Screen Recording Settings…") { model.openRecordingSettings() }
            Button("Local Network Settings…") { model.openNetworkSettings() }
        }.font(.callout).padding(22).frame(width:330)
    }
}
