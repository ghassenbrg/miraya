import Foundation
@preconcurrency import ScreenCaptureKit
import CoreGraphics
import CoreMedia
import CoreVideo
import MirayaCore

/// Native display and system-audio capture. Lifecycle methods are called by the
/// UI actor; samples, encoder state and callbacks are confined to captureQueue.
final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    var onVideoConfig: ((Data) -> Void)?
    var onVideo: ((Data, UInt64, Bool) -> Void)?
    var onAudio: ((Data, UInt64) -> Void)?
    var onError: ((Error) -> Void)?
    var shouldEncode: (() -> Bool)?
    var shouldSendAudio: (() -> Bool)?

    private let captureQueue = DispatchQueue(label: "app.miraya.capture", qos: .userInteractive)
    private var captureStream: SCStream?
    private var encoder: H264Encoder?
    private var running = false
    private var generation = UUID()
    private var encoderGeneration = UUID()
    private var inFlightFrames = 0
    private var sentConfig: Data?
    private var latestBuffer: CVPixelBuffer?
    private var lastSubmittedPTS = CMTime.invalid
    private var displayID: CGDirectDisplayID = 0
    private var maximumOutputSize: (width: Int, height: Int)?
    private var quality: CaptureQuality = .balanced
    private var targetBitrate = CaptureQuality.balanced.bitrate
    private var capturesAudio = false
    private var configuredSize = (width: 0, height: 0)
    private var lastDisplayCheck: UInt64 = 0
    private var changingConfiguration = false
    private var sourceKind = CaptureSourceKind.display
    private var region: CaptureRegion?
    private var sourceSize = (width: 0, height: 0)

    static func displays() async throws -> [SCDisplay] {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true).displays
    }
    static func isPermissionDenied(_ failure: Error) -> Bool {
        let error = failure as NSError
        return error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue
    }

    func start(displayID: CGDirectDisplayID, quality: CaptureQuality, audio: Bool, maximumOutputSize: (width: Int, height: Int)? = nil, source: CaptureSourceKind = .display, windowID: UInt32? = nil, region: CaptureRegion? = nil) async throws {
        await stop()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displays = content.displays
        try Task.checkCancellation()
        guard let display = displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureFailure.displayUnavailable
        }
        let bounds = CGDisplayBounds(displayID)
        // SCDisplay width/height may be logical pixels on Retina displays. Use
        // native pixel dimensions while taking rotation from display bounds.
        var size = Self.displaySize(displayID, fallbackWidth: display.width, fallbackHeight: display.height, bounds: bounds)
        let filter: SCContentFilter
        if source == .window {
            guard let window = content.windows.first(where: { $0.windowID == windowID }), window.frame.width > 0, window.frame.height > 0 else { throw CaptureFailure.displayUnavailable }
            filter = SCContentFilter(desktopIndependentWindow: window)
            let containing = displays.max { $0.frame.intersection(window.frame).width * $0.frame.intersection(window.frame).height < $1.frame.intersection(window.frame).width * $1.frame.intersection(window.frame).height } ?? display
            let scale = Double(CGDisplayCopyDisplayMode(containing.displayID)?.pixelWidth ?? containing.width) / max(1, containing.frame.width)
            size = (Int(window.frame.width * scale), Int(window.frame.height * scale))
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
            if source == .area {
                guard let region, region.validated(displayWidth: bounds.width, displayHeight: bounds.height) else { throw CaptureFailure.displayUnavailable }
                size = (Int(region.width * Double(size.width) / bounds.width), Int(region.height * Double(size.height) / bounds.height))
            }
        }
        let fitted = Self.outputSize(width: size.width, height: size.height, quality: quality, limit: maximumOutputSize)
        let config = Self.configuration(width: fitted.width, height: fitted.height, quality: quality, audio: audio)
        if source == .area, let region { config.sourceRect = CGRect(x: region.x, y: region.y, width: region.width, height: region.height) }
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        if audio { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue) }
        await withCheckedContinuation { continuation in
            captureQueue.async {
                self.displayID = displayID
                self.sourceKind = source; self.region = region; self.sourceSize = size
                self.maximumOutputSize = maximumOutputSize
                self.quality = quality
                self.targetBitrate = quality.bitrate
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
                self.latestBuffer = nil
                self.lastSubmittedPTS = .invalid
                self.inFlightFrames = 0
                continuation.resume(returning: previous)
            }
        }
        if let previous { try? await previous.stopCapture() }
    }

    func requestKeyframe() {
        captureQueue.async {
            self.encoder?.requestKeyframe()
            // A static desktop may not emit another complete SCK frame. Recovery
            // must still be able to send its current image with a fresh timestamp.
            guard self.running, let buffer = self.latestBuffer, self.encoder != nil,
                  self.encoder?.width == CVPixelBufferGetWidth(buffer), self.encoder?.height == CVPixelBufferGetHeight(buffer),
                  self.inFlightFrames < 3, self.shouldEncode?() != false else { return }
            do { try self.submit(buffer, pts: CMClockGetTime(CMClockGetHostTimeClock())) }
            catch { self.fail(error) }
        }
    }

    func updateBitrate(_ bitsPerSecond: Int) {
        captureQueue.async { self.targetBitrate = bitsPerSecond; self.encoder?.updateBitrate(bitsPerSecond) }
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
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: raw), status != .complete { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        latestBuffer = buffer
        if let onFrame { onFrame(buffer, CMSampleBufferGetPresentationTimeStamp(sample)); return }
        guard running, inFlightFrames < 3, shouldEncode?() != false else { return }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return }
        if encoder?.width != width || encoder?.height != height {
            encoderGeneration = UUID()
            encoder?.close()
            encoder = nil
            inFlightFrames = 0
            lastSubmittedPTS = .invalid
            sentConfig = nil
            let instance = try H264Encoder(width: width, height: height, fps: quality.fps, bitrate: targetBitrate)
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
        try submit(buffer, pts: CMSampleBufferGetPresentationTimeStamp(sample))
    }

    private func submit(_ buffer: CVPixelBuffer, pts: CMTime) throws {
        // A synthetic recovery IDR can precede an already queued SCK sample.
        guard !lastSubmittedPTS.isValid || CMTimeCompare(pts, lastSubmittedPTS) > 0 else { return }
        lastSubmittedPTS = pts
        inFlightFrames += 1
        do { try encoder?.encode(buffer, pts: pts) }
        catch {
            inFlightFrames = max(0, inFlightFrames - 1)
            throw error
        }
    }

    private func audio(_ sample: CMSampleBuffer) throws {
        // Audio is allowed to skip while transport is congested. Its independent
        // timestamp lets the receiver discard gaps without creating video drift.
        guard shouldSendAudio?() != false else { return }
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
        // A desktop-independent window may move to another screen or Space.
        // ScreenCaptureKit scales it within the fixed output configuration.
        guard sourceKind != .window else { return }
        guard CGDisplayIsActive(displayID) != 0 else { fail(CaptureFailure.displayUnavailable); return }
        guard !changingConfiguration, let stream = captureStream else { return }
        let bounds = CGDisplayBounds(displayID)
        var native = Self.displaySize(displayID, fallbackWidth: configuredSize.width, fallbackHeight: configuredSize.height, bounds: bounds)
        if sourceKind == .area, let region {
            guard region.validated(displayWidth: bounds.width, displayHeight: bounds.height) else { fail(CaptureFailure.displayUnavailable); return }
            native = (Int(region.width * Double(native.width) / bounds.width), Int(region.height * Double(native.height) / bounds.height))
        }
        let fitted = Self.outputSize(width: native.width, height: native.height, quality: quality, limit: maximumOutputSize)
        guard fitted != configuredSize else { return }
        changingConfiguration = true
        let expected = generation
        let config = Self.configuration(width: fitted.width, height: fitted.height, quality: quality, audio: capturesAudio)
        if sourceKind == .area, let region { config.sourceRect = CGRect(x: region.x, y: region.y, width: region.width, height: region.height) }
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

    private static func outputSize(width: Int, height: Int, quality: CaptureQuality, limit: (width: Int, height: Int)?) -> (width: Int, height: Int) {
        let maximumWidth = min(quality.maxWidth, limit?.width ?? quality.maxWidth)
        let maximumHeight = min(quality.maxHeight, limit?.height ?? quality.maxHeight)
        let size = VideoSize.fit(width: width, height: height, maxWidth: maximumWidth, maxHeight: maximumHeight)
        return (size.width, size.height)
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
