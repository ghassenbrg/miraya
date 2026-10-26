import Foundation
import CoreMedia
import CoreVideo
import VideoToolbox

enum CaptureQuality: String, CaseIterable, Identifiable {
    case balanced, motion, efficient
    var id: String { rawValue }
    var label: String {
        switch self {
        case .balanced: return "Balanced · 1080p / 30 fps"
        case .motion: return "Smooth motion · 1080p / 60 fps"
        case .efficient: return "Efficient · 720p / 30 fps"
        }
    }
    var maxWidth: Int { self == .efficient ? 1280 : 1920 }
    var maxHeight: Int { self == .efficient ? 720 : 1080 }
    var fps: Int { self == .motion ? 60 : 30 }
    var bitrate: Int { self == .motion ? 10_000_000 : (self == .efficient ? 3_000_000 : 6_000_000) }

    /// Even dimensions are required by the 4:2:0 encoder. Never upscale a display.
    func fittedSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let scale = min(1, Double(maxWidth) / Double(max(2, width)), Double(maxHeight) / Double(max(2, height)))
        return (max(2, Int(Double(width) * scale) / 2 * 2), max(2, Int(Double(height) * scale) / 2 * 2))
    }
}

enum CaptureFailure: LocalizedError {
    case displayUnavailable
    case encoding(OSStatus)
    case invalidVideo(String)
    case audioFormat(String)

    var errorDescription: String? {
        switch self {
        case .displayUnavailable: return "The selected display is no longer available. Choose a connected display and share again."
        case .encoding(let code): return "The Mac could not encode the screen (VideoToolbox \(code)). Try Balanced or Efficient quality."
        case .invalidVideo(let detail): return "The video encoder returned an invalid frame: \(detail)."
        case .audioFormat(let detail): return "System audio could not be captured: \(detail). Try sharing with system audio turned off."
        }
    }
}

/// All public methods must be called from one serial queue. VideoToolbox may call
/// the output closure on a different queue; the owner serializes delivery there.
final class H264Encoder {
    let width: Int
    let height: Int
    let fps: Int
    private var session: VTCompressionSession?
    private var forceKeyframe = true
    private var closed = false
    var output: ((Result<CMSampleBuffer?, Error>) -> Void)?

    init(width: Int, height: Int, fps: Int, bitrate: Int) throws {
        self.width = width
        self.height = height
        self.fps = fps
        // Low latency rate control is available on Apple Silicon and recent Intel
        // hardware. Fall back to the same realtime configuration if unsupported.
        var created: VTCompressionSession?
        let specification: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true,
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true
        ]
        var status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault,
            width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_H264,
            encoderSpecification: specification as CFDictionary, imageBufferAttributes: nil,
            compressedDataAllocator: nil, outputCallback: nil, refcon: nil, compressionSessionOut: &created)
        if status != noErr {
            status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault,
                width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_H264,
                encoderSpecification: [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true] as CFDictionary,
                imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: nil,
                refcon: nil, compressionSessionOut: &created)
        }
        guard status == noErr, let created else { throw CaptureFailure.encoding(status) }
        session = created
        do {
            try property(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
            try property(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
            try property(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel)
            try property(kVTCompressionPropertyKey_AverageBitRate, bitrate as CFNumber)
            try property(kVTCompressionPropertyKey_ExpectedFrameRate, fps as CFNumber)
            try property(kVTCompressionPropertyKey_MaxKeyFrameInterval, (fps * 2) as CFNumber)
            try property(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, 2 as CFNumber)
            // Not every encoder supports this hint; realtime + no B frames still
            // provide the baseline low-delay behavior when it is unavailable.
            VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: 0 as CFNumber)
            let prepared = VTCompressionSessionPrepareToEncodeFrames(created)
            guard prepared == noErr else { throw CaptureFailure.encoding(prepared) }
        } catch {
            close()
            throw error
        }
    }

    private func property(_ key: CFString, _ value: CFTypeRef) throws {
        guard let session else { throw CaptureFailure.encoding(kVTInvalidSessionErr) }
        let status = VTSessionSetProperty(session, key: key, value: value)
        guard status == noErr else { throw CaptureFailure.encoding(status) }
    }

    func requestKeyframe() { forceKeyframe = true }

    func updateBitrate(_ bitrate: Int) {
        guard let session else { return }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
            value: max(500_000, min(20_000_000, bitrate)) as CFNumber)
    }

    func encode(_ pixelBuffer: CVPixelBuffer, pts: CMTime) throws {
        guard let session, !closed else { return }
        let properties: CFDictionary? = forceKeyframe ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        forceKeyframe = false
        // Capture the callback rather than self. Encoder teardown can synchronously
        // complete outstanding work without a self-retention cycle or refcon race.
        let deliver = output
        let status = VTCompressionSessionEncodeFrame(session, imageBuffer: pixelBuffer,
            presentationTimeStamp: pts, duration: CMTime(value: 1, timescale: Int32(fps)),
            frameProperties: properties, infoFlagsOut: nil) { status, flags, sampleBuffer in
                if status != noErr { deliver?(.failure(CaptureFailure.encoding(status))); return }
                if flags.contains(.frameDropped) { deliver?(.success(nil)); return }
                deliver?(.success(sampleBuffer))
            }
        guard status == noErr else { throw CaptureFailure.encoding(status) }
    }

    func close() {
        guard !closed else { return }
        closed = true
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
        session = nil
    }

    deinit { close() }

    static func packet(from sample: CMSampleBuffer, width: Int, height: Int, fps: Int) throws -> (config: Data?, data: Data, pts: UInt64, keyframe: Bool) {
        guard let format = CMSampleBufferGetFormatDescription(sample), let block = CMSampleBufferGetDataBuffer(sample) else {
            throw CaptureFailure.invalidVideo("missing format or bytes")
        }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let keyframe = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool != true
        var nalLength: Int32 = 0
        var parameterCount = 0
        var spsPointer: UnsafePointer<UInt8>?
        var spsSize = 0
        let spsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 0,
            parameterSetPointerOut: &spsPointer, parameterSetSizeOut: &spsSize,
            parameterSetCountOut: &parameterCount, nalUnitHeaderLengthOut: &nalLength)
        guard spsStatus == noErr, let spsPointer, nalLength == 4 else {
            throw CaptureFailure.invalidVideo("unsupported H.264 format")
        }
        var config: Data?
        if keyframe {
            var ppsPointer: UnsafePointer<UInt8>?
            var ppsSize = 0
            let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 1,
                parameterSetPointerOut: &ppsPointer, parameterSetSizeOut: &ppsSize,
                parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
            guard status == noErr, let ppsPointer else { throw CaptureFailure.invalidVideo("missing picture parameters") }
            config = try JSONSerialization.data(withJSONObject: ["width": width, "height": height, "fps": fps,
                "sps": Data(bytes: spsPointer, count: spsSize).base64EncodedString(),
                "pps": Data(bytes: ppsPointer, count: ppsSize).base64EncodedString()], options: [.sortedKeys])
        }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 4, length <= 4 * 1024 * 1024 else { throw CaptureFailure.invalidVideo("invalid frame size") }
        var avcc = Data(count: length)
        let copied = avcc.withUnsafeMutableBytes { raw in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
        }
        guard copied == kCMBlockBufferNoErr else { throw CaptureFailure.invalidVideo("inaccessible frame bytes") }
        var annexB = Data()
        annexB.reserveCapacity(length)
        var offset = 0
        while offset < length {
            guard offset + 4 <= length else { throw CaptureFailure.invalidVideo("truncated NAL header") }
            let nalSize = avcc[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
            offset += 4
            guard nalSize > 0, nalSize <= length - offset else { throw CaptureFailure.invalidVideo("truncated NAL payload") }
            annexB.append(contentsOf: [0, 0, 0, 1])
            annexB.append(avcc[offset..<offset + nalSize])
            offset += nalSize
        }
        return (config, annexB, microseconds(CMSampleBufferGetPresentationTimeStamp(sample)), keyframe)
    }

    static func microseconds(_ time: CMTime) -> UInt64 {
        guard time.isValid, !time.isIndefinite, time.timescale > 0 else { return 0 }
        return UInt64(max(0, CMTimeConvertScale(time, timescale: 1_000_000, method: .roundTowardZero).value))
    }
}
