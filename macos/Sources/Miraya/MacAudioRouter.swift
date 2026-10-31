import Foundation
import CoreAudio
import AppKit
import Darwin

/// The helper owns the temporary device mute. Parent exit/crash closes its pipe,
/// so local audio is restored even when the UI cannot run termination cleanup.
@MainActor final class MacAudioRouter {
    var onFailure: ((String) -> Void)?
    private var session: AudioMuteSession?
    private var desired = false
    private var generation = UUID()
    private var listener: AudioObjectPropertyListenerBlock?
    init() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.desired else { return }
                self.session?.stop(); self.session = nil
                do { try await self.setTVOnly(true) } catch { self.onFailure?(error.localizedDescription) }
            }
        }
        listener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
    }
    func setTVOnly(_ enabled: Bool) async throws {
        if !enabled { restore(); return }
        desired = true
        if session != nil { return }
        generation = UUID(); let current = generation
        let next = try await Task.detached(priority: .userInitiated) { try AudioMuteSession.start() }.value
        guard desired, generation == current, !Task.isCancelled else { next.stop(); return }
        session = next
    }
    func restore() {
        generation = UUID(); desired = false
        session?.stop(); session = nil
    }
    deinit {
        session?.stop()
        if let listener {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
    }
}

private final class AudioMuteSession: @unchecked Sendable {
    let process: Process
    let input: Pipe
    private init(process: Process, input: Pipe) { self.process = process; self.input = input }
    static func start() throws -> AudioMuteSession {
        guard let executable = Bundle.main.executableURL else { throw AudioRoutingFailure("Could not locate the audio helper.") }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = executable; process.arguments = ["--local-audio-guardian"]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 3000) > 0 else {
            try? input.fileHandleForWriting.close()
            throw AudioRoutingFailure("Could not confirm Mac audio routing. Returning to local audio.")
        }
        let response = String(data: output.fileHandleForReading.availableData, encoding: .utf8) ?? ""
        guard response.hasPrefix("ok") else {
            try? input.fileHandleForWriting.close()
            throw AudioRoutingFailure("This Mac output cannot be muted automatically. Use its volume control, or choose Both.")
        }
        return AudioMuteSession(process: process, input: input)
    }
    func stop() { try? input.fileHandleForWriting.close() }
    deinit { stop() }
}

private struct AudioRoutingFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum LocalAudioGuardian {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--local-audio-guardian") else { return }
        NSApplication.shared.setActivationPolicy(.prohibited)
        var defaultAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(0), size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil, &size, &device) == noErr, device != 0 else { reply("error"); exit(1) }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var writable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &writable) == noErr, writable.boolValue else { reply("error"); exit(1) }
        var original: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &original) == noErr else { reply("error"); exit(1) }
        var muted: UInt32 = 1
        guard original == 1 || AudioObjectSetPropertyData(device, &address, 0, nil, size, &muted) == noErr else { reply("error"); exit(1) }
        reply("ok")
        _ = FileHandle.standardInput.readDataToEndOfFile()
        // Respect a user who changed mute outside Miraya while it was active.
        var current: UInt32 = 0
        if original == 0, AudioObjectGetPropertyData(device, &address, 0, nil, &size, &current) == noErr, current == 1 {
            AudioObjectSetPropertyData(device, &address, 0, nil, size, &original)
        }
        exit(0)
    }
    private static func reply(_ value: String) { FileHandle.standardOutput.write(Data((value + "\n").utf8)) }
}
