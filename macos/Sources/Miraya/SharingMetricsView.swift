import SwiftUI
import MirayaCore

struct SharingMetricsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Live sharing metrics").font(.title2.bold())
                Text(model.selected?.name ?? "No TV selected").foregroundStyle(MirayaTheme.soft)
                Button("Save diagnostic report…") { model.exportDiagnostics() }
                Text("Local measurements only, retained for up to 72 hours. Reports exclude screen/audio content, media URLs, file names and pairing secrets. Nothing is sent automatically.").font(.caption).foregroundStyle(MirayaTheme.soft)
                if model.playbackMode == .media {
                    GroupBox("Direct media playback") {
                        VStack(spacing: 9) {
                            row("Player state", model.mediaState.capitalized)
                            row("Playback path", model.busy ? model.transportStatus : "Not connected")
                            row("TV picture", model.encodedPicture)
                            row("TV presentation", receiverValue(number(model.receiverFPS) + " fps"))
                            row("TV frame drops", receiverValue("\(model.receiverDrops) total this session"))
                            row("Buffered ahead", String(format: "%.1f seconds", max(0, model.mediaBuffered - model.mediaPosition)))
                            row("Seeking", model.mediaSeekable ? "Available" : "Unavailable / live")
                        }.padding(6)
                    }
                    Text("The TV decodes the original media. Mirroring encoder/FPS settings do not apply. Buffering can come from source delivery, network interruptions or device decoding limits; no cause is assumed from buffer level alone.").font(.caption).foregroundStyle(MirayaTheme.soft)
                } else {
                if model.phase == .sharing {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let status = StreamHealth.sampleStatus(senderAge: model.metricsUpdatedAt.map { context.date.timeIntervalSince($0) }, receiverAge: model.receiverMetricsUpdatedAt.map { context.date.timeIntervalSince($0) })
                        Text(status ?? model.healthDiagnosis).font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                } else {
                    Text(model.phase == .paused ? "Sharing is paused. Values below are the last measured samples." : model.busy ? model.progressTitle : "Not currently sharing. Values below are the last measured samples.").foregroundStyle(MirayaTheme.soft)
                }
                GroupBox("Picture and playback") {
                    VStack(spacing: 9) {
                        row("Requested maximum", model.quality.label)
                        row("Actually encoded", model.encodedPicture)
                        row("TV presentation", receiverValue(number(model.receiverFPS) + " fps"))
                        row("Mac screen updates", senderValue(number(model.captureFPS) + " fps"))
                        row("Active frame-rate cap", model.frameRateCap > 0 ? "\(model.frameRateCap) fps" : "Waiting")
                        row("Negotiated decoder cap", model.decoderFrameRateCap > 0 ? "\(model.decoderFrameRateCap) fps" : "Waiting")
                        row("Negotiated picture limit", model.decoderPictureLimit)
                        row("TV decoder", model.tvDecoder)
                        row("TV frame drops", receiverValue("\(model.receiverDrops) total this session"))
                        row("Encoder", model.encoderImplementation)
                        row("Encoder adaptation", senderValue(model.encoderLimit))
                    }.padding(6)
                }
                if model.fpsHistory.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recent TV playback · sampled fps").font(.caption).foregroundStyle(MirayaTheme.soft)
                        GeometryReader { geometry in
                            Path { path in
                                let values = model.fpsHistory
                                let maximum = max(60, values.max() ?? 60)
                                for (index, value) in values.enumerated() {
                                    let point = CGPoint(x: geometry.size.width * Double(index) / Double(max(1, values.count - 1)), y: geometry.size.height * (1 - min(maximum, max(0, value)) / maximum))
                                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                                }
                            }.stroke(MirayaTheme.blue, lineWidth: 2)
                        }.frame(height: 64).accessibilityLabel("Recent sampled TV playback frame rates")
                    }
                }
                GroupBox("Local network") {
                    VStack(spacing: 9) {
                        row("Transport", model.busy ? model.transportStatus : "Not connected")
                        row("Network round-trip", model.roundTripMs > 0 ? number(model.roundTripMs) + " ms" : "Waiting")
                        row("Video jitter", receiverValue(number(model.videoJitterMs) + " ms"))
                        row("Recent video packet loss", model.hasPacketLossSample ? String(format: "%.1f%%", model.packetLossPercent) : "Waiting for video packets")
                        row("Actual video traffic", senderValue(megabits(model.actualBitrate)))
                        row("Encoder target", senderValue(megabits(Double(model.targetBitrate))))
                        row("Bandwidth estimate", model.availableBitrate > 0 ? megabits(Double(model.availableBitrate)) : "Waiting")
                    }.padding(6)
                }
                if let display = model.tvDisplay {
                    GroupBox("TV display") {
                        VStack(spacing: 9) {
                            row("Sharing area", "\(display.width) × \(display.height)")
                            row("Physical output mode", "\(display.panelWidth) × \(display.panelHeight) · \(Int(display.refreshRate)) Hz")
                            row("Picture mode", model.pictureMode.label)
                            row("Audio output", model.audioDestination.label)
                            row("TV decoded audio signal", receiverValue("\(Int(model.tvAudioLevel * 100))% peak"))
                        }.padding(6)
                    }
                }
                Text("Network RTT excludes capture, decode and display latency. Bandwidth is WebRTC's estimate within the configured bitrate ceiling, not a speed test. Router distance and TV Wi-Fi signal are not measured. Fewer frames are normal on a static desktop or 24 fps movie.").font(.caption).foregroundStyle(MirayaTheme.soft)
                if let date = model.metricsUpdatedAt { Text("Last sample: \(date.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(MirayaTheme.soft) }
                }
                if let date = model.receiverMetricsUpdatedAt { Text("Last TV sample: \(date.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(MirayaTheme.soft) }
            }.padding(22)
        }.frame(minWidth: 440, minHeight: 600).background(MirayaTheme.background).tint(MirayaTheme.blue)
    }
    private func row(_ name: String, _ value: String) -> some View {
        HStack(alignment: .top) { Text(name).foregroundStyle(MirayaTheme.soft); Spacer(minLength: 18); Text(value).multilineTextAlignment(.trailing).textSelection(.enabled) }.font(.callout)
    }
    private func number(_ value: Double) -> String { String(format: "%.0f", value) }
    private func senderValue(_ value: String) -> String { model.metricsUpdatedAt == nil ? "Waiting" : value }
    private func receiverValue(_ value: String) -> String { model.receiverMetricsUpdatedAt == nil ? "Waiting" : value }
    private func megabits(_ value: Double) -> String { String(format: "%.1f Mbit/s", value / 1_000_000) }
}
