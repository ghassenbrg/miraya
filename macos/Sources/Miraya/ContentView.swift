import SwiftUI
import MirayaCore

private enum SharingSheet: String, Identifiable {
    case destination, source, quality, picture, trusted, manual, help
    var id: String { rawValue }
    var title: String {
        switch self {
        case .destination: return "Choose a TV"
        case .source: return "What would you like to share?"
        case .quality: return "Picture & playback"
        case .picture: return "TV picture"
        case .trusted: return "Trusted TVs"
        case .manual: return "Connect by address"
        case .help: return "Connection help"
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var discovery: Discovery
    @Environment(\.openWindow) private var openWindow
    @State private var sheet: SharingSheet?
    @State private var forgetting: TrustedReceiver?
    @FocusState private var focusedRow: String?
    private var live: Bool { model.phase == .sharing || model.phase == .paused || model.phase == .pausing }
    private var pairing: Bool { model.phase == .pairing }
    private var failure: Bool { model.error != nil && !model.busy }
    private var beamState: String { failure ? "error" : pairing ? "pairing" : model.phase == .paused ? "paused" : live ? "connected" : model.busy ? "connecting" : "idle" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    brandHeader
                    if failure { recovery }
                    else if pairing { comparison }
                    else if model.busy && !live { connectionProgress }
                    else { sharingContent }
                }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer.padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 16)
        }
        .frame(minWidth: 340, idealWidth: 420, maxWidth: 540, minHeight: 620, idealHeight: 650, maxHeight: 900)
        .background(MirayaTheme.background).tint(MirayaTheme.blue)
        .sheet(item: $sheet) { sheetView($0) }
        .onAppear { model.discoveredReceiversChanged(discovery.receivers) }
        .onChange(of: discovery.receivers) { model.discoveredReceiversChanged($0) }
        .onChange(of: model.showManual) { if $0 { sheet = .manual; model.showManual = false } }
        .onChange(of: model.showDeviceManager) { if $0 { sheet = .trusted; model.showDeviceManager = false } }
        .onChange(of: model.phase) { if $0 == .pairing { sheet = nil } }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            MirayaWordmark(state: beamState)
            Spacer(minLength: 8)
            Label(status, systemImage: failure ? "exclamationmark.triangle" : live ? "lock" : model.selected == nil ? "magnifyingglass" : "checkmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(failure ? MirayaTheme.destructive : live ? MirayaTheme.success : MirayaTheme.soft)
                .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var status: String {
        if failure { return "Needs attention" }
        if pairing { return "Verify TV" }
        if model.phase == .authorizing { return "Waiting for TV" }
        if model.phase == .paused { return "Paused" }
        if live { return "Sharing" }
        if !model.busy && model.selected == nil { return discovery.isSearching ? "Looking for TVs" : "No TV found" }
        return model.busy ? "Connecting" : "Ready"
    }
    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 23, weight: .semibold)).tracking(-0.6).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(MirayaTheme.soft).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
        }
    }
    private var sharingContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading(live ? (model.phase == .paused ? "Sharing paused" : model.playbackMode == .media ? "Playing on\n\(tvName)" : "Sharing to\n\(tvName)") : "Share your screen",
                    model.phase == .paused ? "The TV may retain its last picture. Resume when you’re ready." : live ? (model.playbackMode == .media ? "The TV plays the original media. Your desktop stays private." : model.audio ? "Your selected screen and system audio are being shared." : "Your selected screen is being shared. TV audio is off.") : "Choose a TV and what you want to share.")
            VStack(spacing: 0) {
                if !live {
                    sourceRow("Destination TV", name: model.selected?.name ?? "Choose a TV", detail: destinationDetail, symbol: "tv", action: .destination)
                    Divider().padding(.leading, 16)
                }
                sourceRow("Sharing source", name: sourceName, detail: sourceDetail, symbol: sourceSymbol, action: .source, disabled: model.busy && model.phase != .paused)
            }.background(MirayaTheme.surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(MirayaTheme.border, lineWidth: 0.7))
            if live && model.playbackMode == .mirror { deliveredPicture }
            if model.playbackMode == .mirror { preferences }
            else { DirectPlaybackControls(model: model).controlSize(.regular) }
            if let error = model.error { notice(error, warning: true) }
            else if let information = model.information { notice(information) }
        }
    }
    private var tvName: String { model.selected?.name ?? "your TV" }
    private var sourceName: String {
        if model.playbackMode == .media { return "Play original media" }
        switch model.sourceKind {
        case .display: return model.displays.first(where: { $0.id == model.displayID })?.name.components(separatedBy: " · ").first ?? "Choose a display"
        case .window: return model.windows.first(where: { $0.id == model.windowID })?.name ?? "Choose a window"
        case .area: return "Selected area"
        }
    }
    private var sourceDetail: String {
        if model.playbackMode == .media { return "Video / audio file or direct HTTPS media" }
        if model.sourceKind == .window { return "Single window · application audio" }
        if model.sourceKind == .area { return model.selectedRegion.map { "\(Int($0.width)) × \(Int($0.height)) screen points" } ?? "Select an area before sharing" }
        return model.displays.first(where: { $0.id == model.displayID })?.name.components(separatedBy: " · ").dropFirst().joined(separator: " · ") ?? "Entire display"
    }
    private var sourceSymbol: String { model.playbackMode == .media ? "play.rectangle" : model.sourceKind == .window ? "macwindow" : model.sourceKind == .area ? "viewfinder" : "display" }
    private var destinationDetail: String {
        guard let receiver = model.selected else { return discovery.receivers.isEmpty ? (discovery.isSearching ? "Looking for TVs on your local network" : "No TV found · Refresh or enter an address") : "\(discovery.receivers.count) nearby TVs" }
        let nearby = discovery.receivers.contains { $0.id == receiver.id }
        let trusted = model.trustedSelection != nil
        return (trusted ? "Trusted TV · " : "") + (nearby ? "Nearby" : receiver.host != nil && !trusted ? "Manual address" : "Currently offline")
    }
    private func sourceRow(_ label: String, name: String, detail: String, symbol: String, action: SharingSheet, disabled: Bool = false) -> some View {
        Button { sheet = action } label: {
            HStack(spacing: 13) {
                Image(systemName: symbol).font(.system(size: 18, weight: .regular)).frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text(detail).font(.system(size: 11)).foregroundStyle(MirayaTheme.soft).lineLimit(2)
                }
                Spacer(minLength: 0)
                if action == .destination && model.trustedSelection != nil { Image(systemName: "lock").font(.system(size: 11)).foregroundStyle(MirayaTheme.soft) }
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(MirayaTheme.soft)
            }.padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, minHeight: 62, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(disabled).focused($focusedRow, equals: action.rawValue)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(focusedRow == action.rawValue ? MirayaTheme.blue : .clear, lineWidth: 2))
            .accessibilityLabel("\(label), \(name), \(detail)").accessibilityHint("Opens \(action.title)")
    }
    private var deliveredPicture: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().padding(.bottom, 8)
            Text(model.phase == .paused ? "Last delivered picture" : "Sending now").font(.system(size: 10)).foregroundStyle(MirayaTheme.soft)
            HStack { Text(model.encodedPicture).font(.system(size: 14, weight: .semibold)); if model.receiverFPS > 0 { Text("· \(Int(model.receiverFPS.rounded())) fps").font(.system(size: 13, weight: .medium)) } }
            Text("Selected: \(qualityLabel). Output may adapt.").font(.system(size: 10)).foregroundStyle(MirayaTheme.soft)
        }.accessibilityElement(children: .combine)
    }
    private var qualityLabel: String { model.quality.label }
    private var preferences: some View {
        VStack(spacing: 0) {
            settingRow("Quality ceiling") { Button { sheet = .quality } label: { HStack(spacing: 4) { Text(qualityLabel); Image(systemName: "chevron.down").font(.system(size: 9)) } }.buttonStyle(.plain).foregroundStyle(MirayaTheme.blue).disabled(model.busy && !live) }
            Divider()
            settingRow("System audio", symbol: "speaker.wave.2") {
                Toggle("Send system audio to TV", isOn: Binding(get: { model.audio }, set: { model.audioDestination = $0 ? .both : .mac })).labelsHidden().toggleStyle(BeamAudioToggleStyle()).controlSize(.small).disabled(model.busy && !live)
            }
            Divider()
            HStack {
                Text("Audio plays on").foregroundStyle(MirayaTheme.soft)
                Spacer()
                Picker("Audio destination", selection: $model.audioDestination) { ForEach(AudioDestination.allCases) { Text($0.label).tag($0) } }.labelsHidden().fixedSize().disabled(model.busy && !live)
            }.font(.system(size: 12)).padding(.top, 12).padding(.bottom, 8)
            if model.audioDestination == .tv {
                Text(model.routingAudio ? "Routing audio…" : "Temporarily mutes this Mac’s entire output. Stop or quit restores it.").font(.system(size: 11)).foregroundStyle(MirayaTheme.soft).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
            }
            Text("System audio only. Your microphone is never captured.").font(.system(size: 11)).foregroundStyle(MirayaTheme.soft).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
            if live && model.audio {
                HStack(spacing: 10) {
                    Image(systemName: model.audioVolume == 0 ? "speaker.slash" : "speaker.wave.2").font(.system(size: 12)).foregroundStyle(MirayaTheme.soft)
                    Slider(value: $model.audioVolume, in: 0...1).accessibilityLabel("TV playback volume")
                    Text(model.audioVolume == 0 ? "Muted" : "\(Int(model.audioVolume * 100))%").monospacedDigit().font(.system(size: 11)).frame(width: 38, alignment: .trailing)
                }.padding(.bottom, 8)
            }
            settingRow("TV picture") {
                if model.busy && model.supportsPresentation { Button { sheet = .picture } label: { HStack(spacing: 4) { Text(model.pictureMode.rawValue.capitalized); Image(systemName: "chevron.down").font(.system(size: 9)) } }.buttonStyle(.plain).foregroundStyle(MirayaTheme.blue) }
                else { Text("Available after connection").font(.system(size: 10)).foregroundStyle(MirayaTheme.soft) }
            }
            Divider()
        }.font(.system(size: 12))
    }
    private func settingRow<T: View>(_ name: String, symbol: String? = nil, @ViewBuilder value: () -> T) -> some View {
        HStack(spacing: 6) { if let symbol { Image(systemName: symbol).font(.system(size: 12)) }; Text(name).fontWeight(.medium); Spacer(minLength: 8); value() }.frame(minHeight: 43)
    }
    private func notice(_ message: String, warning: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) { Image(systemName: warning ? "exclamationmark.triangle" : "info.circle"); Text(message).fixedSize(horizontal: false, vertical: true) }
            .font(.system(size: 11)).foregroundStyle(warning ? Color(nsColor: .systemOrange) : MirayaTheme.soft).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(MirayaTheme.surface, in: RoundedRectangle(cornerRadius: 9))
    }
    private var comparison: some View {
        VStack(spacing: 16) {
            heading("Compare with your TV", "Make sure these numbers match what you see on \(tvName).")
            Text(model.pairingCode.prefix(3) + " " + model.pairingCode.suffix(3)).font(.system(size: 42, weight: .semibold, design: .monospaced)).tracking(3).lineLimit(1).minimumScaleFactor(0.8).padding(.top, 8).accessibilityLabel("Comparison code \(model.pairingCode.map(String.init).joined(separator: " "))")
            BeamMark(state: "pairing").frame(width: 76, height: 76).padding(.vertical, 5)
            Text("No typing. Compare all six digits.").font(.system(size: 12)).foregroundStyle(MirayaTheme.soft)
            Text("Then explicitly approve with your TV remote.\nThe code expires after 90 seconds.").font(.system(size: 11)).foregroundStyle(MirayaTheme.soft).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }
    private var connectionProgress: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading(model.phase == .authorizing ? "Approve on your TV" : model.phase == .reconnecting ? "Reconnecting to your TV" : "Preparing your share", model.phase == .authorizing ? "The numbers matched. Choose Allow on your TV using its remote." : "Your request was received. Miraya is preparing the connection.")
            BeamMark(state: "connecting").frame(width: 76, height: 76).frame(maxWidth: .infinity).padding(.vertical, 10)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) { ProgressView().controlSize(.small); Text(model.progressTitle).fontWeight(.medium); Spacer(); Text("\(max(0, Int(context.date.timeIntervalSince(model.stepStartedAt)))) s").monospacedDigit().foregroundStyle(MirayaTheme.soft) }
                    Text(model.progressDetail).font(.system(size: 12)).foregroundStyle(MirayaTheme.soft).fixedSize(horizontal: false, vertical: true)
                }.font(.system(size: 12)).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(MirayaTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            Text("Sharing begins only after the TV presents the first picture. You can cancel at any time.").font(.system(size: 11)).foregroundStyle(MirayaTheme.soft)
        }
    }
    private var recoveryKind: String {
        let error = (model.error ?? "").lowercased()
        if model.capturePermissionDenied { return "recording" }
        if error.contains("certificate") || (error.contains("identity") && error.contains("changed")) || error.contains("no longer trusted") { return "trust" }
        if error.contains("choose a video") || (model.playbackMode == .media && (error.contains("format") || error.contains("media"))) { return "media" }
        if error.contains("choose the window") || error.contains("choose the area") || error.contains("selected display") { return "source" }
        if error.contains("decoder") || error.contains("could not encode") { return "quality" }
        return "retry"
    }
    private var recoveryTitle: String {
        switch recoveryKind {
        case "recording": return "Allow screen sharing"
        case "trust": return "Verify this TV’s identity"
        case "media": return "Choose compatible media"
        case "source": return "Choose what to share"
        case "quality": return "The picture needs attention"
        default: return (model.error ?? "").contains("numbers did not match") ? "The numbers don’t match" : "Sharing needs attention"
        }
    }
    private var recoveryDetail: String {
        switch recoveryKind {
        case "recording": return "Miraya needs screen access to share the display, window or area you choose."
        case "trust": return "Review the saved pairing. If you reset or reinstalled Miraya on this TV, forget its old permission and compare a fresh code. Unexpected changes should be checked on the TV."
        case "media": return "Choose a supported local video or direct HTTPS media address. Website pages and browser login sessions are not direct media."
        case "source": return "Select an available display, window or area before starting again."
        case "quality": return "Try a lower frame-rate or resolution ceiling, then reconnect. Check that Miraya is current on both devices."
        default: return "Nothing is being shared. Check Miraya on your TV and try again. Technical details below explain the reported failure."
        }
    }
    private var recoveryAction: String {
        switch recoveryKind { case "recording": return "Open System Settings"; case "trust": return "Review saved pairing"; case "source": return "Choose source"; case "media": return "Choose media"; case "quality": return "Adjust quality"; default: return "Try again" }
    }
    private func recover() {
        switch recoveryKind {
        case "recording": model.openRecordingSettings()
        case "trust": sheet = .trusted
        case "source": model.error = nil; sheet = .source
        case "media": model.error = nil
        case "quality": model.error = nil; sheet = .quality
        default: model.start()
        }
    }
    private var recovery: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 24)).foregroundStyle(MirayaTheme.destructive).padding(15).background(MirayaTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            heading(recoveryTitle, recoveryDetail)
            if model.capturePermissionDenied {
                Text("1. Open Screen & System Audio Recording.\n2. Enable Miraya. Your microphone stays private.\n3. Reopen Miraya if macOS asks, then check access.").font(.system(size: 12)).foregroundStyle(MirayaTheme.soft).lineSpacing(7)
            }
            DisclosureGroup("Technical details") { Text(model.error ?? "").font(.system(size: 11)).foregroundStyle(MirayaTheme.soft).textSelection(.enabled).padding(.top, 8) }.font(.system(size: 11))
            Button("Connection help…") { sheet = .help }.buttonStyle(.link)
        }
    }
    private var footer: some View {
        VStack(spacing: 12) {
            if failure {
                Button(recoveryAction) { recover() }.buttonStyle(BeamActionStyle()).controlSize(.large).frame(maxWidth: .infinity)
                if model.capturePermissionDenied { Button(model.checkingScreenAccess ? "Checking access…" : "Check access again") { model.checkScreenAccess() }.buttonStyle(.link).disabled(model.checkingScreenAccess) }
                else { Button("Back to sharing") { model.error = nil }.buttonStyle(.link) }
            } else if pairing {
                Button { model.confirmPairing() } label: { Text("Numbers match").frame(maxWidth: .infinity) }.buttonStyle(BeamActionStyle()).controlSize(.large).keyboardShortcut(.defaultAction)
                Button { model.stopByUser() } label: { Text("Cancel").frame(maxWidth: .infinity) }.controlSize(.large).keyboardShortcut(.cancelAction)
                Button("The numbers don’t match") { model.stopByUser(); model.error = "The pairing numbers did not match. Check the selected TV and start a fresh attempt. No new trust was created." }.buttonStyle(.link).font(.system(size: 11))
            } else if live {
                HStack(spacing: 10) {
                    Button { model.phase == .paused ? model.resume() : model.pause() } label: { Label(model.phase == .paused ? "Resume" : "Pause", systemImage: model.phase == .paused ? "play.fill" : "pause.fill").frame(maxWidth: .infinity) }.controlSize(.large).disabled(model.phase == .pausing)
                    Button { model.stopByUser() } label: { Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity) }.buttonStyle(BeamActionStyle(destructive: true)).controlSize(.large).keyboardShortcut(".")
                }
            } else if model.busy {
                Button { model.stopByUser() } label: { Text("Cancel connection").frame(maxWidth: .infinity) }.controlSize(.large).keyboardShortcut(.cancelAction)
            } else {
                Button { model.start() } label: { Label(model.trustedSelection == nil ? "Pair & share" : model.playbackMode == .media ? "Play on TV" : "Share to TV", systemImage: "play").fontWeight(.semibold).frame(maxWidth: .infinity) }.buttonStyle(BeamActionStyle()).controlSize(.large).disabled(model.selected == nil).keyboardShortcut(.defaultAction)
            }
            HStack {
                Label(pairing ? "Then approve on the TV" : model.busy ? "Local · encrypted" : "Pair securely on first use", systemImage: "lock").font(.system(size: 10)).foregroundStyle(MirayaTheme.soft)
                Spacer(minLength: 5)
                Button(live ? "Connection details ›" : "Connection help ›") { if live { openWindow(id: "sharing-metrics") } else { sheet = .help } }.buttonStyle(.link).font(.system(size: 11))
            }
        }
    }

    private func sheetView(_ active: SharingSheet) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(active.title).font(.system(size: 18, weight: .semibold)); Spacer(); Button { sheet = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(MirayaTheme.soft) }.buttonStyle(.plain).accessibilityLabel("Close dialog") }
            ScrollView { sheetContent(active).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4) }
            HStack { Spacer(); Button("Done") { sheet = nil }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 360).frame(maxHeight: 580).background(MirayaTheme.background)
.alert("Forget \(forgetting?.name ?? "TV")?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } })) {
            Button("Cancel", role: .cancel) { forgetting = nil }
            Button("Forget TV", role: .destructive) { if let tv = forgetting { model.forget(tv.id) }; forgetting = nil }
        } message: { Text("This removes its saved permission from this Mac. It will need to pair again before sharing.") }
    }
    @ViewBuilder private func sheetContent(_ active: SharingSheet) -> some View {
        switch active {
        case .destination: destinations
        case .source:
            VStack(alignment: .leading, spacing: 16) {
                if !model.busy { Picker("Mode", selection: $model.playbackMode) { ForEach(PlaybackMode.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented) }
                if model.playbackMode == .mirror { CaptureSourceControls(model: model) }
                else { Text("Original media plays on the TV. Screen sharing is needed for browser extensions.").font(.callout).foregroundStyle(MirayaTheme.soft) }
                Text("Your microphone is never captured.").font(.caption).foregroundStyle(MirayaTheme.soft)
            }
        case .quality:
            VStack(alignment: .leading, spacing: 15) {
                Picker("Maximum quality", selection: $model.quality) { ForEach(CaptureQuality.allCases) { Text($0.label).tag($0) } }
                Text("Resolution and frame rate are maximums. The stream may adapt downward automatically.").font(.caption).foregroundStyle(MirayaTheme.soft)
                Divider()
                Picker("Profile", selection: $model.profile) { ForEach(SharingProfile.allCases) { Text($0.label).tag($0) } }
                Text(model.profile.detail).font(.caption).foregroundStyle(MirayaTheme.soft)
                Picker("Priority", selection: $model.prioritizeDetail) { Text("Picture detail · reduce fps first").tag(true); Text("Motion · reduce size first").tag(false) }
                Toggle("Follow TV resolution", isOn: $model.followTVResolution).toggleStyle(.switch)
                Text("Uses the TV’s app viewport within this ceiling and preserves the source’s shape. It does not change the Mac display mode or enable 4K mirroring.").font(.caption).foregroundStyle(MirayaTheme.soft)
            }
        case .picture:
            VStack(alignment: .leading, spacing: 16) {
                Picker("Presentation", selection: $model.pictureMode) { ForEach(PictureMode.allCases) { Text($0.rawValue.capitalized).tag($0) } }.pickerStyle(.segmented)
                Text(model.pictureMode == .fit ? "Everything stays visible. Bars may appear. No cropping." : model.pictureMode == .fill ? "Fills the TV by deliberately cropping edges." : "Fills the TV by changing proportions. The image may distort.").font(.callout).foregroundStyle(MirayaTheme.soft)
                Divider()
                HStack { Text("Edge Margin"); Spacer(); Text("\(model.edgeInsetPercent)%").monospacedDigit() }
                Slider(value: Binding(get: { Double(model.edgeInsetPercent) }, set: { model.edgeInsetPercent = Int($0.rounded()) }), in: 0...10, step: 1).accessibilityLabel("Symmetric edge margin from zero to ten percent")
                Text("One value adjusts every edge equally to compensate for TV overscan.").font(.caption).foregroundStyle(MirayaTheme.soft)
                if let display = model.tvDisplay { Text("\(display.width) × \(display.height) app viewport\n\(display.panelWidth) × \(display.panelHeight) · \(Int(display.refreshRate)) Hz physical output").font(.caption).foregroundStyle(MirayaTheme.soft) }
            }
        case .trusted:
            VStack(alignment: .leading, spacing: 14) {
                Text("Remove permission for one TV at a time. Pair again to reconnect after removal.").font(.callout).foregroundStyle(MirayaTheme.soft)
                if model.remembered.isEmpty { Text("No trusted TVs yet.").padding(.vertical, 16) }
                ForEach(model.remembered) { tv in
                    HStack { Image(systemName: "tv"); VStack(alignment: .leading, spacing: 4) { Text(tv.name).fontWeight(.medium); Text(discovery.receivers.contains { $0.id == tv.id } ? "Nearby" : "Currently offline").font(.caption).foregroundStyle(MirayaTheme.soft) }; Spacer(); Button("Forget…", role: .destructive) { forgetting = tv } }.padding(.vertical, 8)
                }
            }
        case .manual:
            VStack(alignment: .leading, spacing: 15) {
                Text("Open Connection details on the TV and enter its address. This bypasses discovery, not pairing.").font(.callout).foregroundStyle(MirayaTheme.soft)
                TextField("IP address or hostname", text: $model.manualHost).textFieldStyle(.roundedBorder)
                TextField("Port", text: $model.manualPort).textFieldStyle(.roundedBorder)
                Button("Use address") { model.useManual(); if model.selected != nil && model.error == nil { sheet = nil } }.buttonStyle(BeamActionStyle())
                if let error = model.error { Text(error).font(.caption).foregroundStyle(MirayaTheme.destructive) }
            }
        case .help:
            VStack(alignment: .leading, spacing: 14) {
                Text("Keep Miraya open on your TV. Both devices must be able to reach each other on the local network; guest Wi-Fi or a VPN may block discovery.").font(.callout)
                Button("Refresh nearby TVs") { discovery.refresh() }.disabled(model.busy)
                Button("Enter TV address…") { sheet = .manual }.disabled(model.busy)
                Button("Manage trusted TVs…") { sheet = .trusted }.disabled(model.busy)
                Divider()
                Text("Screen access lets Miraya capture the source you choose and optional system audio. It never captures your microphone.").font(.callout).foregroundStyle(MirayaTheme.soft)
                Button(model.checkingScreenAccess ? "Checking screen access…" : "Check screen access") { model.checkScreenAccess() }.disabled(model.busy || model.checkingScreenAccess)
                if let status = model.screenAccessStatus { Text(status).font(.caption).foregroundStyle(MirayaTheme.soft) }
                Button("Recording settings…") { model.openRecordingSettings() }
                Button("Local Network settings…") { model.openNetworkSettings() }
                DisclosureGroup("App information") { Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")\n\(Bundle.main.bundleURL.path)").font(.caption).textSelection(.enabled) }
            }
        }
    }
    private var destinations: some View {
        VStack(alignment: .leading, spacing: 14) {
            if discovery.receivers.isEmpty { Text(discovery.message).font(.callout).foregroundStyle(MirayaTheme.soft) }
            ForEach(discovery.receivers) { receiver in receiverChoice(receiver, nearby: true) }
            ForEach(model.remembered.filter { saved in !discovery.receivers.contains { $0.id == saved.id } }) { saved in if let receiver = saved.receiver { receiverChoice(receiver, nearby: false) } }
            if let selected = model.selected, selected.host != nil, model.trustedSelection == nil, !discovery.receivers.contains(where: { $0.id == selected.id }) { receiverChoice(selected, nearby: false) }
            Divider()
            HStack { Button("Refresh") { discovery.refresh() }; Button("Enter address…") { sheet = .manual } }
            Button("Manage trusted TVs…") { sheet = .trusted }.buttonStyle(.link)
        }
    }
    private func receiverChoice(_ receiver: Receiver, nearby: Bool) -> some View {
        Button { model.selected = receiver; model.pairingCode = ""; model.error = nil; sheet = nil } label: {
            HStack(spacing: 12) { Image(systemName: "tv"); VStack(alignment: .leading, spacing: 4) { Text(receiver.name).fontWeight(.medium); Text(nearby ? "Nearby" : "Saved · Currently offline").font(.caption).foregroundStyle(MirayaTheme.soft) }; Spacer(); if model.selected?.id == receiver.id { Image(systemName: "checkmark").foregroundStyle(MirayaTheme.blue) } }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(MirayaTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}
