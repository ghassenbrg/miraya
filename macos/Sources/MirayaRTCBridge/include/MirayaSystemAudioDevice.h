#import <Foundation/Foundation.h>
#import <WebRTC/WebRTC.h>

NS_ASSUME_NONNULL_BEGIN
/// Input-only WebRTC device. Its only input is ScreenCaptureKit PCM, never a microphone.
@interface MirayaSystemAudioDevice : NSObject
- (void)submitPCM:(NSData *)pcm timestampNs:(uint64_t)timestampNs;
- (void)clear;
- (void)shutdown;
@end

FOUNDATION_EXPORT RTCPeerConnectionFactory *MirayaCreatePeerFactory(
    id<RTCVideoEncoderFactory> encoder, id<RTCVideoDecoderFactory> decoder,
    MirayaSystemAudioDevice *audio);
FOUNDATION_EXPORT BOOL MirayaSetCodecPreferences(RTCRtpTransceiver *transceiver, NSArray<RTCRtpCodecCapability *> *codecs);
NS_ASSUME_NONNULL_END
