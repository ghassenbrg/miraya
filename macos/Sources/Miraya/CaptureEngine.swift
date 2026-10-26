import Foundation
@preconcurrency import ScreenCaptureKit
import CoreGraphics
import CoreMedia
import CoreVideo

/// Native display and system-audio capture. Lifecycle methods are called by the
/// UI actor; samples, encoder state and callbacks are confined to captureQueue.
final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onVideoConfig: ((Data) -> Void)?
    var onVideo: ((Data, UInt64, Bool) -> Void)?
    var onAudio: ((Data, UInt64) -> Void)?
    var onError: ((Error) -> Void)?
    var shouldEncode: (() -> Bool)?

    private let captureQueue = DispatchQueue(label: "app.miraya.capture", qos: .userInteractive)
    private var captureStream: SCStream?
    private var encoder: H264Encoder?
    private var running = false
    private var generation = UUID()
    private var encoderGeneration = UUID()
    private var inFlightFrames = 0
    private var sentConfig: Data?
    private var displayID: CGDirectDisplayID = 0
    private var quality: CaptureQuality = .balanced
    private var capturesAudio = false
    private var configuredSize = (width: 0, height: 0)
    private var lastDisplayCheck: UInt64 = 0
    private var changingConfiguration = false

    static func displays() async throws -> [SCDisplay] {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true).displays
    }

    func start(displayID: CGDirectDisplayID, quality: CaptureQuality, audio: Bool) async throws {
        await stop()
        let displays = try await Self.displays()
        try Task.checkCancellation()
        guard let display = displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureFailure.displayUnavailable
        }
        let bounds = CGDisplayBounds(displayID)
        // SCDisplay width/height may be logical pixels on Retina displays. Use
        // native pixel dimensions while taking rotation from display bounds.
        let size = Self.displaySize(displayID, fallbackWidth: display.width, fallbackHeight: display.height, bounds: bounds)
        let fitted = quality.fittedSize(width: size.width, height: size.height)
        let config = Self.configuration(width: fitted.width, height: fitted.height, quality: quality, audio: audio)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        if audio { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue) }
        await withCheckedContinuation { continuation in
            captureQueue.async {
                self.displayID = displayID
                self.quality = quality
                self.capturesAudio = audio
                self.configuredSize = fitted
                self.captureStream = stream
                self.running = true
                self.generation = UUID()
                self.lastDisplayCheck = 0
                self.sentConfig = nil
                self.changingConfiguration = false
                continuation.resume()
            }
        }
        do {
            try await stream.startCapture()
            try Task.checkCancellation()
            let stillCurrent: Bool = await withCheckedContinuation { continuation in
                captureQueue.async { continuation.resume(returning: self.running && self.captureStream === stream) }
            }
            guard stillCurrent else {
                try? await stream.stopCapture()
                throw CancellationError()
            }
        } catch {
            // An overlapping user stop/new start must not let this old operation
            // tear down the newer stream when its asynchronous start completes.
            let stillCurrent: Bool = await withCheckedContinuation { continuation in
                captureQueue.async { continuation.resume(returning: self.captureStream === stream) }
            }
            if stillCurrent { await stop() }
            throw error
        }
    }

    func stop() async {
        let previous: SCStream? = await withCheckedContinuation { continuation in
            captureQueue.async {
                let previous = self.captureStream
                self.running = false
                self.generation = UUID()
                self.encoderGeneration = UUID()
                self.captureStream = nil
                self.encoder?.close()
                self.encoder = nil
                self.sentConfig = nil
                self.inFlightFrames = 0
                continuation.resume(returning: previous)
            }
        }
        if let previous { try? await previous.stopCapture() }
    }

    func requestKeyframe() {
        captureQueue.async { self.encoder?.requestKeyframe() }
    }

    func updateBitrate(_ bitsPerSecond: Int) {
        captureQueue.async { self.encoder?.updateBitrate(bitsPerSecond) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard running, stream === captureStream, CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer) else { return }
        do {
            switch type {
            case .screen: try video(sampleBuffer)
            case .audio: if capturesAudio { try audio(sampleBuffer) }
            default: break
            }
        } catch { fail(error) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        captureQueue.async {
            guard stream === self.captureStream, self.running else { return }
            self.fail(error)
        }
    }

    private func video(_ sample: CMSampleBuffer) throws {
        let now = DispatchTime.now().uptimeNanoseconds
        if now - lastDisplayCheck > 1_000_000_000 {
            lastDisplayCheck = now
            checkDisplay()
        }
        guard running, shouldEncode?() != false, inFlightFrames < 3 else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: raw), status != .complete { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return }
        if encoder?.width != width || encoder?.height != height {
            encoderGeneration = UUID()
            encoder?.close()
            encoder = nil
            inFlightFrames = 0
            sentConfig = nil
            let instance = try H264Encoder(width: width, height: height, fps: quality.fps, bitrate: quality.bitrate)
            let expectedCapture = generation
            let expectedEncoder = encoderGeneration
            instance.output = { [weak self] result in
                guard let self else { return }
                self.captureQueue.async {
                    guard self.running, self.generation == expectedCapture, self.encoderGeneration == expectedEncoder else { return }
                    self.inFlightFrames = max(0, self.inFlightFrames - 1)
                    do {
                        guard let encoded = try result.get() else { return }
                        let packet = try H264Encoder.packet(from: encoded, width: width, height: height, fps: self.quality.fps)
                        if let config = packet.config, config != self.sentConfig {
                            self.onVideoConfig?(config)
                            self.sentConfig = config
                        }
                        guard self.sentConfig != nil else { return }
                        self.onVideo?(packet.data, packet.pts, packet.keyframe)
                    } catch { self.fail(error) }
                }
            }
            encoder = instance
        }
        inFlightFrames += 1
        do { try encoder?.encode(buffer, pts: CMSampleBufferGetPresentationTimeStamp(sample)) }
        catch {
            inFlightFrames = max(0, inFlightFrames - 1)
            throw error
        }
    }

    private func audio(_ sample: CMSampleBuffer) throws {
        // Audio is allowed to skip while transport is congested. Its independent
        // timestamp lets the receiver discard gaps without creating video drift.
        guard shouldEncode?() != false else { return }
        let data = try SystemAudioPCM.convert(sample)
        let start = H264Encoder.microseconds(CMSampleBufferGetPresentationTimeStamp(sample))
        var offset = 0
        while offset < data.count {
            let count = min(19_200, data.count - offset)
            let pts = start + UInt64(offset / 4) * 1_000_000 / 48_000
            onAudio?(Data(data[offset..<offset + count]), pts)
            offset += count
        }
    }

    private func fail(_ error: Error) {
        guard running else { return }
        running = false
        onError?(error)
    }

    private func checkDisplay() {
        guard CGDisplayIsActive(displayID) != 0 else { fail(CaptureFailure.displayUnavailable); return }
        guard !changingConfiguration, let stream = captureStream else { return }
        let bounds = CGDisplayBounds(displayID)
        let native = Self.displaySize(displayID, fallbackWidth: configuredSize.width, fallbackHeight: configuredSize.height, bounds: bounds)
        let fitted = quality.fittedSize(width: native.width, height: native.height)
        guard fitted != configuredSize else { return }
        changingConfiguration = true
        let expected = generation
        let config = Self.configuration(width: fitted.width, height: fitted.height, quality: quality, audio: capturesAudio)
        Task {
            do {
                try await stream.updateConfiguration(config)
                captureQueue.async {
                    guard self.generation == expected else { return }
                    self.configuredSize = fitted
                    self.changingConfiguration = false
                }
            } catch {
                captureQueue.async {
                    guard self.generation == expected else { return }
                    self.changingConfiguration = false
                    self.fail(error)
                }
            }
        }
    }

    private static func displaySize(_ id: CGDirectDisplayID, fallbackWidth: Int, fallbackHeight: Int, bounds: CGRect) -> (width: Int, height: Int) {
        // CGDisplayPixelsWide/High can report the logical mode dimensions on a
        // Retina display. The display mode's pixel dimensions describe backing
        // pixels and preserve the available detail when fitting to 1080p.
        let mode = CGDisplayCopyDisplayMode(id)
        let nativeWidth = mode?.pixelWidth ?? CGDisplayPixelsWide(id)
        let nativeHeight = mode?.pixelHeight ?? CGDisplayPixelsHigh(id)
        let landscape = bounds.width >= bounds.height
        let width = nativeWidth > 0 ? nativeWidth : fallbackWidth
        let height = nativeHeight > 0 ? nativeHeight : fallbackHeight
        return landscape ? (max(width, height), min(width, height)) : (min(width, height), max(width, height))
    }

    private static func configuration(width: Int, height: Int, quality: CaptureQuality, audio: Bool) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(quality.fps))
        config.queueDepth = 3
        config.showsCursor = true
        config.scalesToFit = true
        config.backgroundColor = CGColor.black
        config.colorSpaceName = CGColorSpace.sRGB
        if #available(macOS 14.0, *) { config.preservesAspectRatio = true }
        config.capturesAudio = audio
        config.sampleRate = 48_000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true
        return config
    }
}
