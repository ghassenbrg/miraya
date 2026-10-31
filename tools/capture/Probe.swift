// Compiled by scripts/test-capture.sh with the production capture codecs.
// Exercises real VideoToolbox hardware encoding without Screen Recording access.
import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

@main
struct CaptureProbe {
    static func main() throws {
        try testAudioLayouts()
        precondition(CaptureQuality.balanced.fittedSize(width: 3840, height: 2160) == (1920, 1080))
        precondition(CaptureQuality.efficient.fittedSize(width: 1920, height: 1080) == (1280, 720))
        precondition(CaptureQuality.balanced.fittedSize(width: 1080, height: 1920) == (606, 1080))
        precondition(H264Encoder.microseconds(CMTime(value: 123456789, timescale: 1000)) == 123456789000)

        let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/miraya-capture-probe", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let width = Int(ProcessInfo.processInfo.environment["MIRAYA_FIXTURE_WIDTH"] ?? "640") ?? 640
        let height = Int(ProcessInfo.processInfo.environment["MIRAYA_FIXTURE_HEIGHT"] ?? "360") ?? 360
        precondition(width >= 16 && width <= 1920 && height >= 16 && height <= 1080 && width % 2 == 0 && height % 2 == 0)
        let lock = NSLock()
        var frames: [(pts: UInt64, keyframe: Bool, data: Data)] = []
        var config: Data?
        var failures: [Error] = []
        let encoder = try H264Encoder(width: width, height: height, fps: 30, bitrate: 1_500_000)
        encoder.output = { result in
            lock.lock()
            defer { lock.unlock() }
            do {
                guard let sample = try result.get() else { return }
                let packet = try H264Encoder.packet(from: sample, width: width, height: height, fps: 30)
                if let next = packet.config { config = next }
                frames.append((packet.pts, packet.keyframe, packet.data))
            } catch { failures.append(error) }
        }
        for index in 0..<90 {
            var optional: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &optional)
            guard status == kCVReturnSuccess, let buffer = optional else { fatalError("Pixel buffer creation failed: \(status)") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * stride + x * 4
                    bytes[offset] = UInt8((x + index * 3) % 256)
                    bytes[offset + 1] = UInt8((y + index * 5) % 256)
                    bytes[offset + 2] = UInt8((index * 7) % 256)
                    bytes[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            if index == 45 { encoder.requestKeyframe(); encoder.updateBitrate(1_000_000) }
            try encoder.encode(buffer, pts: CMTime(value: Int64(index), timescale: 30))
            Thread.sleep(forTimeInterval: 1.0 / 30.0)
        }
        encoder.close()
        lock.lock()
        let ordered = frames.sorted { $0.pts < $1.pts }
        let errors = failures
        let configuration = config
        lock.unlock()
        guard errors.isEmpty else { throw errors[0] }
        guard ordered.count == 90, let configuration,
              ordered.first?.keyframe == true,
              ordered.filter({ $0.keyframe }).count >= 2 else {
            fatalError("Expected 90 frames and requested IDR, received \(ordered.count)")
        }
        let json = try JSONSerialization.jsonObject(with: configuration) as! [String: Any]
        let sps = Data(base64Encoded: json["sps"] as! String)!
        let pps = Data(base64Encoded: json["pps"] as! String)!
        var elementary = Data()
        var manifest: [[String: Any]] = []
        for (index, frame) in ordered.enumerated() {
            if frame.keyframe {
                elementary.append(contentsOf: [0, 0, 0, 1]); elementary.append(sps)
                elementary.append(contentsOf: [0, 0, 0, 1]); elementary.append(pps)
            }
            elementary.append(frame.data)
            let filename = String(format: "frame-%03d.h264", index)
            try frame.data.write(to: directory.appendingPathComponent(filename))
            manifest.append(["pts": frame.pts, "keyframe": frame.keyframe, "file": filename])
        }
        try elementary.write(to: directory.appendingPathComponent("video.h264"))
        try configuration.write(to: directory.appendingPathComponent("config.json"))
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("frames.json"))
        print("PASS: planar/interleaved PCM conversion, mono duplication, clipping, timestamps and aspect fitting")
        print("PASS: VideoToolbox encoded \(ordered.count) frames / \(ordered.filter { $0.keyframe }.count) IDRs; Annex B fixture: \(directory.path)")
    }

    private static func testAudioLayouts() throws {
        var left: [Float] = [0, 0.5, -1, 2, .nan]
        var right: [Float] = [-0.5, 1, 0, -2, 0.25]
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(list.unsafeMutablePointer) }
        var format = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        let data = try left.withUnsafeMutableBytes { leftRaw in
            try right.withUnsafeMutableBytes { rightRaw in
                list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(leftRaw.count), mData: leftRaw.baseAddress)
                list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(rightRaw.count), mData: rightRaw.baseAddress)
                return try SystemAudioPCM.convert(buffers: list, format: format, frames: 5)
            }
        }
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        precondition(samples == [0, -16384, 16384, 32767, -32768, 0, 32767, -32768, 0, 8192])
        var interleaved: [Int16] = [Int16.min, Int16.max, 0, -1]
        format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        format.mBitsPerChannel = 16
        format.mBytesPerFrame = 4
        format.mBytesPerPacket = 4
        let integerData = try interleaved.withUnsafeMutableBytes { raw in
            list[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress)
            return try SystemAudioPCM.convert(buffers: list, format: format, frames: 2)
        }
        precondition(integerData == interleaved.withUnsafeBytes { Data($0) })
        format.mChannelsPerFrame = 1
        format.mBytesPerFrame = 2
        format.mBytesPerPacket = 2
        let monoData = try interleaved.withUnsafeMutableBytes { raw in
            list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress)
            return try SystemAudioPCM.convert(buffers: list, format: format, frames: 4)
        }
        precondition(monoData.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) } == [-32768, -32768, 32767, 32767, 0, 0, -1, -1])
    }
}
