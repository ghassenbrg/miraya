package dev.miraya.tv

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import android.util.Base64
import android.util.Log
import android.view.Surface
import org.json.JSONObject
import java.nio.ByteBuffer
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs
import kotlin.math.max

/** Decode and playout are isolated from the socket reader; no unbounded frame queues. */
class MediaPipeline(
    private val surface: Surface,
    private val audioEnabled: Boolean,
    private val onSize: (Int, Int) -> Unit,
    private val onError: (String) -> Unit,
    private val requestKeyframe: () -> Unit
) : AutoCloseable {
    val frames = AtomicLong()
    val dropped = AtomicLong()
    val lastPts = AtomicLong(-1)
    val lastDecodedPts = AtomicLong(-1)
    val recoveries = AtomicLong()
    val audioFrames = AtomicLong()
    val audioFramesWritten = AtomicLong()
    private val video = VideoBuffer<JSONObject>()
    private val audio = ArrayBlockingQueue<Packet>(4)
    @Volatile private var running = true
    @Volatile private var volume = 1f
    @Volatile private var scalingMode = MediaCodec.VIDEO_SCALING_MODE_SCALE_TO_FIT
    private val audioControl = Any()
    @Volatile private var audioTrack: AudioTrack? = null
    @Volatile private var firstAudioPts = -1L
    @Volatile private var lastAudioArrival = 0L
    @Volatile private var latestAudioPts = 0L
    private val clock = PlayoutClock()
    private var lastKeyframeRequest = 0L
    private val videoThread = Thread(::videoLoop, "Miraya decoder").apply { start() }
    private val audioThread = if (audioEnabled) Thread(::audioLoop, "Miraya audio").apply { start() } else null

    private fun wallDeadline(pts: Long): Long = clock.deadline(pts, System.nanoTime())
    private fun deadline(pts: Long): Long {
        val now = System.nanoTime()
        val track = audioTrack
        val base = firstAudioPts
        if (track != null && base >= 0 && now - lastAudioArrival < 250_000_000L) {
            val played = track.playbackHeadPosition.toLong() and 0xffffffffL
            val audioPts = base + played * 1_000_000L / 48000L
            val delta = pts - audioPts
            // AudioTrack's head stops during underrun. Never let a stalled or
            // restarting audio clock stop video, or overflow a nanosecond delta.
            if (delta in -100_000L..100_000L) return now + delta * 1000
        }
        return wallDeadline(pts)
    }
    @Synchronized private fun askKeyframe() {
        if (System.nanoTime() - lastKeyframeRequest > 500_000_000L) {
            lastKeyframeRequest = System.nanoTime(); requestKeyframe()
        }
    }

    fun configure(json: JSONObject) {
        val width = json.getInt("width"); val height = json.getInt("height")
        require(width in 16..1920 && height in 16..1080 && width % 2 == 0 && height % 2 == 0) { "This TV supports streams up to 1920 × 1080" }
        require(json.optInt("fps", 30) in 1..60) { "Unsupported frame rate" }
        video.configure(json)
    }
    fun video(packet: Packet) {
        if (packet.payload.isEmpty()) return
        val result = video.offer(packet)
        dropped.addAndGet(result.dropped.toLong())
        if (result.dropped > 1) recoveries.incrementAndGet()
        if (result.needsKeyframe) askKeyframe()
    }

    fun audio(packet: Packet) {
        if (!audioEnabled || packet.payload.isEmpty()) return
        lastAudioArrival = System.nanoTime()
        latestAudioPts = packet.pts
        if (!audio.offer(packet)) {
            // Keep current sound rather than allowing old audio to accumulate.
            audio.clear(); audio.offer(packet)
        }
    }
    fun setVolume(value: Float) { synchronized(audioControl) { volume = value.coerceIn(0f, 1f); audioTrack?.setVolume(volume) } }
    fun silenceAudio() { try { audioTrack?.pause() } catch (_: Exception) { } }
    fun setPicture(mode: PictureMode) { scalingMode = if (mode == PictureMode.FILL) MediaCodec.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING else MediaCodec.VIDEO_SCALING_MODE_SCALE_TO_FIT }

    private fun videoLoop() {
        var codec: MediaCodec? = null
        var configured = false
        var decoderNeedsKeyframe = true
        val info = MediaCodec.BufferInfo()
        var codecData = ByteArray(0)
        var needsCodecData = true
        var appliedScalingMode = -1
        try {
            while (running) {
                when (val command = video.poll()) {
                    is VideoBuffer.Command.Config -> {
                        codec?.stop(); codec?.release(); codec = null; configured = false
                        val json = command.value
                        val w = json.getInt("width"); val h = json.getInt("height")
                        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, w, h)
                        fun csd(key: String): ByteBuffer {
                            val nal = Base64.decode(json.getString(key), Base64.DEFAULT)
                            require(nal.size in 1..4096) { "Invalid H.264 parameter set" }
                            return ByteBuffer.wrap(byteArrayOf(0, 0, 0, 1) + nal)
                        }
                        val sps = csd("sps"); val pps = csd("pps")
                        codecData = sps.array() + pps.array()
                        format.setByteBuffer("csd-0", sps); format.setByteBuffer("csd-1", pps)
                        format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, Wire.MAX_PAYLOAD)
                        format.setInteger(MediaFormat.KEY_PRIORITY, 0)
                        val name = MediaCodecList(MediaCodecList.REGULAR_CODECS).findDecoderForFormat(format)
                            ?: throw IllegalStateException("No H.264 decoder supports ${w} × $h on this TV. Try 720p.")
                        codec = MediaCodec.createByCodecName(name)
                        if (Build.VERSION.SDK_INT >= 30 && codec.codecInfo.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC).isFeatureSupported(MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency)) {
                            format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
                        }
                        codec.configure(format, surface, null, 0); codec.start(); configured = true
                        codec.setVideoScalingMode(scalingMode); appliedScalingMode = scalingMode
                        decoderNeedsKeyframe = true; needsCodecData = true; onSize(w, h)
                    }
                    VideoBuffer.Command.Reset -> { if (configured) codec?.flush(); decoderNeedsKeyframe = true; needsCodecData = true }
                    is VideoBuffer.Command.Frame -> {
                        if (decoderNeedsKeyframe && command.packet.flags and 1 == 0) { dropped.incrementAndGet(); continue }
                        val decoder = codec ?: throw IllegalStateException("Video arrived before decoder configuration")
                        // Drain before feeding to avoid the classic synchronous MediaCodec deadlock.
                        drain(decoder, info)
                        // A 5ms miss means backpressure, not a broken decoder.
                        // Keep draining while waiting briefly for its input slot.
                        val until = System.nanoTime() + 120_000_000L
                        var index = decoder.dequeueInputBuffer(0)
                        while (running && index < 0 && System.nanoTime() < until) {
                            drain(decoder, info)
                            index = decoder.dequeueInputBuffer(2_000)
                        }
                        if (index < 0) {
                            dropped.addAndGet(1 + video.recover().toLong()); recoveries.incrementAndGet(); askKeyframe()
                        } else {
                            val input = decoder.getInputBuffer(index) ?: throw IllegalStateException("Decoder has no input buffer")
                            val prefix = if (needsCodecData) codecData else ByteArray(0)
                            require(command.packet.payload.size + prefix.size <= input.capacity()) { "TV decoder input buffer too small. Try a lower quality mode." }
                            input.clear(); input.put(prefix); input.put(command.packet.payload)
                            decoder.queueInputBuffer(index, 0, prefix.size + command.packet.payload.size, command.packet.pts, 0)
                            decoderNeedsKeyframe = false; needsCodecData = false
                        }
                    }
                    null -> Thread.sleep(2)
                }
                if (configured) codec?.let {
                    if (appliedScalingMode != scalingMode) { it.setVideoScalingMode(scalingMode); appliedScalingMode = scalingMode }
                    drain(it, info)
                }
            }
        } catch (_: InterruptedException) {
        } catch (error: Exception) {
            if (running) { Log.w("Miraya", "Video decoder failed", error); onError(error.message ?: "The TV decoder could not play this stream") }
        } finally {
            try { codec?.stop() } catch (_: Exception) { }
            try { codec?.release() } catch (_: Exception) { }
        }
    }
    private fun drain(codec: MediaCodec, info: MediaCodec.BufferInfo) {
        while (running) {
            val index = codec.dequeueOutputBuffer(info, 0)
            if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                codec.setVideoScalingMode(scalingMode)
                val f = codec.outputFormat
                // Stream dimensions already determine aspect; crop keys may indicate codec padding.
                if (f.containsKey(MediaFormat.KEY_WIDTH) && f.containsKey(MediaFormat.KEY_HEIGHT)) {
                    val w = if (f.containsKey("crop-right")) f.getInteger("crop-right") - f.getInteger("crop-left") + 1 else f.getInteger(MediaFormat.KEY_WIDTH)
                    val h = if (f.containsKey("crop-bottom")) f.getInteger("crop-bottom") - f.getInteger("crop-top") + 1 else f.getInteger(MediaFormat.KEY_HEIGHT)
                    onSize(w, h)
                }
            } else if (index == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED) {
                codec.setVideoScalingMode(scalingMode)
            } else if (index >= 0) {
                if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                    lastDecodedPts.updateAndGet { max(it, info.presentationTimeUs) }
                }
                val whenNs = deadline(info.presentationTimeUs)
                if (System.nanoTime() - whenNs > 150_000_000L || info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                    codec.releaseOutputBuffer(index, false); dropped.incrementAndGet()
                } else {
                    codec.releaseOutputBuffer(index, max(System.nanoTime(), whenNs).coerceAtMost(System.nanoTime() + 100_000_000L))
                    frames.incrementAndGet(); lastPts.set(info.presentationTimeUs)
                }
            } else return
        }
    }

    private fun audioLoop() {
        var track: AudioTrack? = null
        var expectedPts = -1L
        var playedOffset = 0L
        try {
            val minimum = AudioTrack.getMinBufferSize(48000, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
            require(minimum > 0) { "TV does not support stereo system audio" }
            track = AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MOVIE).build())
                .setAudioFormat(AudioFormat.Builder().setSampleRate(48000).setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                .setBufferSizeInBytes(max(minimum, 15360)).setTransferMode(AudioTrack.MODE_STREAM)
                .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY).build()
            track.setVolume(volume)
            require(track.state == AudioTrack.STATE_INITIALIZED) { "TV audio output could not initialize" }
            while (running) {
                val packet = audio.poll(100, TimeUnit.MILLISECONDS) ?: continue
                if (latestAudioPts - packet.pts > 120_000) continue
                if (expectedPts < 0 || abs(packet.pts - expectedPts) > 60_000) {
                    audioTrack = null
                    playedOffset += track.playbackHeadPosition.toLong() and 0xffffffffL
                    track.pause(); track.flush()
                    val delay = wallDeadline(packet.pts) - System.nanoTime()
                    if (delay > 0) TimeUnit.NANOSECONDS.sleep(delay.coerceAtMost(200_000_000L))
                    firstAudioPts = packet.pts
                    synchronized(audioControl) { track.setVolume(volume); track.play(); audioTrack = track }
                }
                var offset = 0
                while (running && offset < packet.payload.size) {
                    val written = track.write(packet.payload, offset, packet.payload.size - offset, AudioTrack.WRITE_NON_BLOCKING)
                    if (written < 0) throw IllegalStateException("TV audio output disconnected")
                    if (written == 0) Thread.sleep(2) else offset += written
                }
                audioFramesWritten.addAndGet(offset / 4L)
                audioFrames.set(playedOffset + (track.playbackHeadPosition.toLong() and 0xffffffffL))
                expectedPts = packet.pts + packet.payload.size / 4 * 1_000_000L / 48000L
            }
        } catch (_: InterruptedException) {
        } catch (error: Exception) {
            if (running) { Log.w("Miraya", "Audio output failed", error); onError(error.message ?: "TV audio output failed. Disable system audio and try again.") }
        } finally {
            synchronized(audioControl) {
                audioTrack = null
                try { track?.pause(); track?.flush(); track?.release() } catch (_: Exception) { }
            }
        }
    }
    override fun close() {
        running = false
        videoThread.interrupt(); audioThread?.interrupt()
        if (Thread.currentThread() !== videoThread) videoThread.join(1500)
        if (Thread.currentThread() !== audioThread) audioThread?.join(1500)
    }
}
