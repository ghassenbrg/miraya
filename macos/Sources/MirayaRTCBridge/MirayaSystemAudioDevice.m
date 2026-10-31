#import "MirayaSystemAudioDevice.h"
#import "RTCAudioDevice.h"
#import <mach/mach_time.h>
#import <CoreAudio/HostTime.h>

@interface MirayaSystemAudioDevice () <RTCAudioDevice> {
    NSCondition *_condition;
    NSMutableData *_pcm;
    NSThread *_thread;
    id<RTCAudioDeviceDelegate> _delegate;
    BOOL _recording, _playing, _initialized, _recordInitialized, _playInitialized;
    BOOL _shutdown, _exited, _delivering;
    double _lastArrival;
    uint64_t _firstPTS;
}
@end

@implementation MirayaSystemAudioDevice
- (instancetype)init {
    if ((self = [super init])) {
        _condition = [[NSCondition alloc] init]; _pcm = [[NSMutableData alloc] init];
        // A dedicated thread satisfies WebRTC's fixed audio-callback-thread contract.
        _thread = [[NSThread alloc] initWithTarget:self selector:@selector(pump) object:nil];
        _thread.name = @"Miraya system audio"; _thread.qualityOfService = NSQualityOfServiceUserInteractive;
        [_thread start];
    }
    return self;
}
- (void)submitPCM:(NSData *)pcm timestampNs:(uint64_t)timestampNs {
    if (pcm.length % 4 != 0) return;
    [_condition lock];
    if (!_shutdown && _recording) {
        _lastArrival = NSProcessInfo.processInfo.systemUptime;
        // At most 60ms of captured stereo PCM; discard stale audio after a pause.
        const NSUInteger limit = 48000 * 4 * 60 / 1000;
        uint64_t expected = _firstPTS + _pcm.length / 4 * 1000000000ULL / 48000;
        if (_pcm.length && timestampNs && llabs((int64_t)timestampNs - (int64_t)expected) > 30000000) [_pcm setLength:0];
        if (!_pcm.length) _firstPTS = timestampNs;
        if (pcm.length >= limit) {
            [_pcm setData:[pcm subdataWithRange:NSMakeRange(pcm.length - limit, limit)]];
            _firstPTS = timestampNs + (pcm.length - limit) / 4 * 1000000000ULL / 48000;
        }
        else {
            if (_pcm.length + pcm.length > limit) {
                NSUInteger discarded = _pcm.length + pcm.length - limit;
                [_pcm replaceBytesInRange:NSMakeRange(0, discarded) withBytes:NULL length:0];
                _firstPTS += discarded / 4 * 1000000000ULL / 48000;
            }
            [_pcm appendData:pcm];
        }
    }
    [_condition unlock];
}
- (void)clear { [_condition lock]; [_pcm setLength:0]; [_condition unlock]; }
- (void)pump {
    double next = NSProcessInfo.processInfo.systemUptime;
    double sampleTime = 0;
    while (YES) {
        @autoreleasepool {
            [_condition lock];
            while (!_shutdown && !_recording) { [_condition wait]; next = NSProcessInfo.processInfo.systemUptime; }
            if (_shutdown) { _exited = YES; [_condition broadcast]; [_condition unlock]; return; }
            double now = NSProcessInfo.processInfo.systemUptime;
            if (now < next) { [_condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:next - now]]; [_condition unlock]; continue; }
            // Do not emit a burst after scheduling jitter.
            next = now - next > 0.02 ? now + 0.01 : next + 0.01;
            int16_t samples[480 * 2] = {0};
            if (now - _lastArrival > 0.1) [_pcm setLength:0];
            NSUInteger count = MIN(sizeof(samples), _pcm.length);
            uint64_t capturePTS = count ? _firstPTS : 0;
            if (count) { memcpy(samples, _pcm.bytes, count); [_pcm replaceBytesInRange:NSMakeRange(0, count) withBytes:NULL length:0]; }
            _firstPTS += count / 4 * 1000000000ULL / 48000;
            id<RTCAudioDeviceDelegate> delegate = _delegate;
            _delivering = delegate != nil;
            [_condition unlock];
            if (delegate) {
                AudioTimeStamp timestamp = {0};
                timestamp.mHostTime = capturePTS ? AudioConvertNanosToHostTime(capturePTS) : mach_absolute_time(); timestamp.mSampleTime = sampleTime;
                timestamp.mFlags = kAudioTimeStampHostTimeValid | kAudioTimeStampSampleTimeValid;
                AudioUnitRenderActionFlags flags = 0;
                // M150's direct inputData branch constructs a sample span of
                // frameCount rather than frameCount * channels, halving stereo
                // input and its media clock. The documented render-block path
                // allocates and forwards the complete interleaved stereo buffer.
                delegate.deliverRecordedData(&flags, &timestamp, 0, 480, NULL, samples,
                    ^OSStatus(AudioUnitRenderActionFlags *actionFlags, const AudioTimeStamp *time,
                              NSInteger bus, UInt32 frameCount, AudioBufferList *output, void *context) {
                        if (output->mNumberBuffers != 1 || output->mBuffers[0].mNumberChannels != 2 ||
                            frameCount != 480 || output->mBuffers[0].mDataByteSize < 480 * 2 * sizeof(int16_t)) return kAudio_ParamError;
                        memcpy(output->mBuffers[0].mData, context, 480 * 2 * sizeof(int16_t));
                        return noErr;
                    });
                sampleTime += 480;
            }
            [_condition lock]; _delivering = NO; [_condition broadcast]; [_condition unlock];
        }
    }
}
- (double)deviceInputSampleRate { return 48000; }
- (double)deviceOutputSampleRate { return 48000; }
- (NSTimeInterval)inputIOBufferDuration { return 0.01; }
- (NSTimeInterval)outputIOBufferDuration { return 0.01; }
- (NSInteger)inputNumberOfChannels { return 2; }
- (NSInteger)outputNumberOfChannels { return 2; }
- (NSTimeInterval)inputLatency { return 0.01; }
- (NSTimeInterval)outputLatency { return 0; }
- (BOOL)isInitialized { [_condition lock]; BOOL value = _initialized; [_condition unlock]; return value; }
- (BOOL)isRecordingInitialized { [_condition lock]; BOOL value = _recordInitialized; [_condition unlock]; return value; }
- (BOOL)isPlayoutInitialized { [_condition lock]; BOOL value = _playInitialized; [_condition unlock]; return value; }
- (BOOL)isRecording { [_condition lock]; BOOL value = _recording; [_condition unlock]; return value; }
- (BOOL)isPlaying { [_condition lock]; BOOL value = _playing; [_condition unlock]; return value; }
- (BOOL)initializeWithDelegate:(id<RTCAudioDeviceDelegate>)delegate {
    [_condition lock]; _delegate = delegate; _initialized = YES; [_condition unlock]; return YES;
}
- (BOOL)initializeRecording { [_condition lock]; _recordInitialized = YES; [_condition unlock]; return YES; }
- (BOOL)initializePlayout { [_condition lock]; _playInitialized = YES; [_condition unlock]; return YES; }
- (BOOL)startRecording { [_condition lock]; _recording = YES; [_pcm setLength:0]; [_condition broadcast]; [_condition unlock]; return YES; }
- (BOOL)stopRecording {
    [_condition lock]; _recording = NO; [_pcm setLength:0];
    while (_delivering) [_condition wait];
    [_condition unlock]; return YES;
}
- (BOOL)startPlayout { [_condition lock]; _playing = YES; [_condition unlock]; return YES; }
- (BOOL)stopPlayout { [_condition lock]; _playing = NO; [_condition unlock]; return YES; }
- (BOOL)terminateDevice {
    [self stopRecording]; [_condition lock]; _delegate = nil; _initialized = NO;
    _recordInitialized = NO; _playInitialized = NO; _playing = NO; [_condition unlock]; return YES;
}
- (void)shutdown {
    [self stopRecording]; [_condition lock]; _shutdown = YES; _delegate = nil; [_condition broadcast];
    if (NSThread.currentThread != _thread) while (!_exited) [_condition wait];
    [_condition unlock];
}
@end

RTCPeerConnectionFactory *MirayaCreatePeerFactory(id<RTCVideoEncoderFactory> encoder,
    id<RTCVideoDecoderFactory> decoder, MirayaSystemAudioDevice *audio) {
    return [[RTCPeerConnectionFactory alloc] initWithEncoderFactory:encoder decoderFactory:decoder audioDevice:audio];
}
BOOL MirayaSetCodecPreferences(RTCRtpTransceiver *transceiver, NSArray<RTCRtpCodecCapability *> *codecs) {
    return [transceiver setCodecPreferences:codecs error:nil];
}
