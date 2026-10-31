import SwiftUI
import MirayaCore

struct CaptureSourceControls: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Picker("Share", selection: $model.sourceKind) { ForEach(CaptureSourceKind.allCases) { Text($0.label).tag($0) } }
            if model.sourceKind == .window {
                HStack {
                    Picker("Window", selection: $model.windowID) {
                        if model.windows.isEmpty { Text("Refresh to find windows").tag(UInt32(0)) }
                        ForEach(model.windows) { Text($0.name).tag($0.id) }
                    }.labelsHidden()
                    Button { model.refreshWindows() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh windows").disabled(model.refreshingWindows)
                }
                Text("Captures only this window while you use other apps. Audio includes the containing app, including its other tabs/windows.").font(.caption).foregroundStyle(MirayaTheme.soft)
            } else {
                Picker("Display", selection: $model.displayID) { ForEach(model.displays) { Text($0.name).tag($0.id) } }.labelsHidden()
                if model.sourceKind == .area {
                    Button(model.selectedRegion == nil ? "Choose area…" : "Change area…") { model.chooseArea() }
                    Text(model.selectedRegion.map { "Area: \(Int($0.width)) × \(Int($0.height)) screen points" } ?? "Drag a rectangle on the selected display. Press Esc to cancel.").font(.caption).foregroundStyle(MirayaTheme.soft)
                }
            }
        }.controlSize(.large).disabled(model.busy && model.phase != .paused)
    }
}

struct DirectPlaybackControls: View {
    @ObservedObject var model: AppModel
    @State private var seeking = false
    @State private var seekPosition = 0.0
    @State private var seekEdited = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.busy {
                Text("Play the original video on the TV, with buffering and seeking. Your Mac screen and Chrome extensions are not sent in this mode.").font(.callout).foregroundStyle(MirayaTheme.soft)
                HStack { Button("Choose video or audio…") { model.chooseMediaFile() }; if model.hasMediaFile { Button("Use URL instead") { model.useMediaURL() } } }
                Text(model.mediaFileName).font(.caption).lineLimit(2)
                if !model.hasMediaFile {
                    TextField("Direct HTTPS video / HLS / DASH URL", text: $model.mediaURL).textFieldStyle(.roundedBorder)
                    Text("Use a media address, not a website page. Login-dependent and protected-service links may not work.").font(.caption).foregroundStyle(MirayaTheme.soft)
                }
                HStack { Button("Add SRT / VTT subtitles…") { model.chooseSubtitleFile() }; if model.hasExternalSubtitle { Button("Remove") { model.clearSubtitleFile() } } }
                Text(model.subtitleFileName).font(.caption).lineLimit(2)
            } else {
                HStack { if ["buffering", "preparing"].contains(model.mediaState) { ProgressView().controlSize(.small) }; Text(model.mediaState.capitalized).font(.headline) }
                Text(model.encodedPicture).font(.callout)
                if model.mediaDuration > 0 {
                    Slider(value: Binding(get: { seekPosition }, set: { seekPosition = $0; seekEdited = true }), in: 0...max(1, model.mediaDuration), onEditingChanged: { editing in seeking = editing; if !editing { model.seekMedia(seekPosition); seekEdited = false } })
                        .accessibilityLabel("Video playback position").disabled(!model.mediaSeekable)
                    HStack { Text(time(seeking || seekEdited ? seekPosition : model.mediaPosition)); if seekEdited { Button("Seek") { model.seekMedia(seekPosition); seekEdited = false }.disabled(!model.mediaSeekable) }; Spacer(); Text(time(model.mediaDuration)) }.monospacedDigit().font(.caption)
                }
                Text("Buffered ahead: \(Int(max(0, model.mediaBuffered - model.mediaPosition))) seconds").font(.caption).foregroundStyle(MirayaTheme.soft)
                if model.mediaTracks.contains(where: { $0.kind == "audio" }) {
                    Picker("Audio track", selection: $model.mediaAudioTrack) {
                        Text("Automatic").tag("auto")
                        ForEach(model.mediaTracks.filter { $0.kind == "audio" }) { Text($0.label).tag($0.id) }
                    }
                }
                Picker("Subtitles", selection: $model.mediaSubtitleTrack) {
                    Text("Automatic").tag("auto"); Text("Off").tag("off")
                    ForEach(model.mediaTracks.filter { $0.kind == "text" }) { Text($0.label).tag($0.id) }
                }
            }
            HStack {
                Image(systemName: "speaker.wave.2")
                Slider(value: $model.audioVolume, in: 0...1).accessibilityLabel("TV media volume")
                Text("\(Int(model.audioVolume * 100))%").monospacedDigit().frame(width: 42)
            }
            Text("Audio plays on the TV. Local files stay within the encrypted connection; HTTPS media is fetched directly by the TV.").font(.caption).foregroundStyle(MirayaTheme.soft)
            if model.busy && model.supportsPresentation {
                Picker("TV picture", selection: $model.pictureMode) { ForEach(PictureMode.allCases) { Text($0.label).tag($0) } }
                HStack {
                    Text("Edge margin")
                    Slider(value: Binding(get: { Double(model.edgeInsetPercent) }, set: { model.edgeInsetPercent = Int($0.rounded()) }), in: 0...10, step: 1).accessibilityLabel("TV edge margin")
                    Text("\(model.edgeInsetPercent)%").monospacedDigit()
                }
            }
        }
        .onChange(of: model.mediaPosition) { position in if !seeking && !seekEdited { seekPosition = min(max(0, position), max(1, model.mediaDuration)) } }
    }
    private func time(_ seconds: Double) -> String { let value = max(0, Int(seconds)); return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60) }
}
