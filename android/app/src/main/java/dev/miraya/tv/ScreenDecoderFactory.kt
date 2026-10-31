package dev.miraya.tv

import android.media.MediaCodecList
import org.webrtc.DefaultVideoDecoderFactory
import org.webrtc.EglBase
import org.webrtc.VideoCodecInfo
import org.webrtc.VideoDecoder
import org.webrtc.VideoDecoderFactory

/** WebRTC's generic Android declaration uses 3.1 irrespective of device limits.
 * Declare at most 1080p60, conservatively checking every platform AVC decoder.
 * Decoder creation remains with WebRTC's platform factory. */
internal class ScreenDecoderFactory(context: EglBase.Context) : VideoDecoderFactory {
    private val delegate = DefaultVideoDecoderFactory(context)
    private val level = runCatching {
        val capabilities = MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos
            .filter { !it.isEncoder && it.supportedTypes.any { type -> type.equals("video/avc", true) } }
            .map { it.getCapabilitiesForType("video/avc").videoCapabilities }
        when {
            capabilities.isNotEmpty() && capabilities.all { it?.areSizeAndRateSupported(1920, 1080, 60.0) == true } -> "2a"
            capabilities.isNotEmpty() && capabilities.all { it?.areSizeAndRateSupported(1920, 1080, 30.0) == true } -> "28"
            else -> "1f"
        }
    }.getOrDefault("1f")
    override fun getSupportedCodecs(): Array<VideoCodecInfo> = delegate.supportedCodecs.map { codec ->
        if (codec.name.equals("H264", true)) {
            val parameters = HashMap(codec.params)
            parameters["profile-level-id"]?.takeIf { it.length == 6 }?.let { parameters["profile-level-id"] = it.take(4) + level }
            VideoCodecInfo(codec.name, parameters, codec.scalabilityModes)
        } else codec
    }.toTypedArray()
    override fun createDecoder(info: VideoCodecInfo): VideoDecoder? = delegate.createDecoder(info)
}
