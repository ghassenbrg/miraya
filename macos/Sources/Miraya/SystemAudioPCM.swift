import Foundation
import AVFoundation
import CoreMedia

/// ScreenCaptureKit is configured for 48 kHz stereo. It normally delivers planar
/// Float32, but older releases and device routes can deliver interleaved PCM.
/// Decode the declared layout rather than assuming a particular AudioBufferList.
enum SystemAudioPCM {
    static func convert(_ sample: CMSampleBuffer) throws -> Data {
        guard let format = CMSampleBufferGetFormatDescription(sample),
              let pointer = CMAudioFormatDescriptionGetStreamBasicDescription(format) else {
            throw CaptureFailure.audioFormat("missing PCM format")
        }
        let asbd = pointer.pointee
        guard asbd.mFormatID == kAudioFormatLinearPCM,
              abs(asbd.mSampleRate - 48_000) < 1,
              (1...2).contains(asbd.mChannelsPerFrame) else {
            throw CaptureFailure.audioFormat("the audio route did not supply 48 kHz mono or stereo PCM")
        }
        let frames = CMSampleBufferGetNumSamples(sample)
        guard frames > 0, frames <= 48_000 else { return Data() }
        return try sample.withAudioBufferList { list, _ in
            try convert(buffers: list, format: asbd, frames: frames)
        }
    }

    static func convert(buffers: UnsafeMutableAudioBufferListPointer, format: AudioStreamBasicDescription, frames: Int) throws -> Data {
        let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let floating = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let signed = format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0
        let bigEndian = format.mFormatFlags & kAudioFormatFlagIsBigEndian != 0
        let bits = Int(format.mBitsPerChannel)
        let channels = Int(format.mChannelsPerFrame)
        let bytesPerSample = bits / 8
        guard (1...2).contains(channels), frames >= 0, frames <= 48_000,
              (floating && (bits == 32 || bits == 64)) || (signed && (bits == 16 || bits == 32)),
              Int(format.mBytesPerFrame) == bytesPerSample * (planar ? 1 : channels),
              buffers.count >= (planar ? channels : 1) else {
            throw CaptureFailure.audioFormat("unsupported linear PCM layout")
        }
        for index in 0..<(planar ? channels : 1) {
            guard buffers[index].mData != nil,
                  Int(buffers[index].mDataByteSize) >= frames * Int(format.mBytesPerFrame) else {
                throw CaptureFailure.audioFormat("truncated PCM buffer")
            }
        }
        var pcm = [Int16](repeating: 0, count: frames * 2)
        for frame in 0..<frames {
            for outputChannel in 0..<2 {
                let channel = min(outputChannel, channels - 1)
                let buffer = buffers[planar ? channel : 0]
                let offset = frame * Int(format.mBytesPerFrame) + (planar ? 0 : channel * bytesPerSample)
                let source = buffer.mData!.advanced(by: offset)
                let value: Double
                if floating && bits == 32 {
                    let word = source.loadUnaligned(as: UInt32.self)
                    value = Double(Float(bitPattern: bigEndian ? UInt32(bigEndian: word) : UInt32(littleEndian: word)))
                } else if floating {
                    let word = source.loadUnaligned(as: UInt64.self)
                    value = Double(bitPattern: bigEndian ? UInt64(bigEndian: word) : UInt64(littleEndian: word))
                } else if bits == 16 {
                    let word = source.loadUnaligned(as: UInt16.self)
                    value = Double(Int16(bitPattern: bigEndian ? UInt16(bigEndian: word) : UInt16(littleEndian: word))) / 32768
                } else {
                    let word = source.loadUnaligned(as: UInt32.self)
                    value = Double(Int32(bitPattern: bigEndian ? UInt32(bigEndian: word) : UInt32(littleEndian: word))) / 2147483648
                }
                let bounded = value.isFinite ? min(1, max(-1, value)) : 0
                pcm[frame * 2 + outputChannel] = Int16(max(-32768, min(32767, Int((bounded * 32768).rounded())))).littleEndian
            }
        }
        return pcm.withUnsafeBytes { Data($0) }
    }
}
