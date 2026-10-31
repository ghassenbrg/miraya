package dev.miraya.tv

import android.content.Context
import android.media.AudioAttributes
import android.view.Surface
import org.json.JSONObject
import org.webrtc.*
import org.webrtc.audio.JavaAudioDeviceModule
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/** Native encrypted RTP tracks. Only the authenticated ReceiverServer can signal this peer. */
internal class RtcMediaReceiver(
    context: Context, surface: Surface, val sessionId: String,
    audio: Boolean, level: Float,
    private val onSize: (Int, Int) -> Unit,
    private val signal: (JSONObject) -> Unit,
    private val onError: (String) -> Unit
) : AutoCloseable {
    companion object {
        private var initialized = false
        @Synchronized private fun initialize(context: Context) {
            if (!initialized) {
                PeerConnectionFactory.initialize(PeerConnectionFactory.InitializationOptions.builder(context.applicationContext).createInitializationOptions())
                Logging.enableLogToDebugOutput(Logging.Severity.LS_WARNING)
                initialized = true
            }
        }
    }
    val frames = AtomicLong()
    val audioFramesWritten = AtomicLong()
    val audioPlaying = AtomicBoolean()
    private val audioSignal = AtomicBoolean()
    private val audioStereoSignal = AtomicBoolean()
    @Volatile private var recentAudioPeak = 0.0
    @Volatile private var lastAudioSamplesAt = 0L
    private val closed = AtomicBoolean()
    private val failed = AtomicBoolean()
    private val statsPending = AtomicBoolean()
    @Volatile private var ownerThread: Thread? = null
    private val owner = ThreadPoolExecutor(1, 1, 0, TimeUnit.MILLISECONDS, ArrayBlockingQueue(128), { runnable ->
        Thread(runnable, "Miraya RTC receiver").also { ownerThread = it }
    })
    private lateinit var egl: EglBase
    private val renderer = EglRenderer("Miraya RTC")
    private var rendererInitialized = false
    private lateinit var audioDevice: JavaAudioDeviceModule
    private lateinit var factory: PeerConnectionFactory
    private var peer: PeerConnection? = null
    private var videoTrack: VideoTrack? = null
    private var audioTrack: AudioTrack? = null
    @Volatile private var audioEnabled = audio
    @Volatile private var paused = false
    @Volatile private var volume = level.toDouble()
    private var remoteReady = false
    private var negotiating = false
    private val candidates = ArrayList<IceCandidate>()
    @Volatile private var lastWidth = 0
    @Volatile private var lastHeight = 0
    @Volatile private var dropped = 0L
    @Volatile private var decoded = 0L
    @Volatile private var videoCodec = ""
    @Volatile private var decoderImplementation = ""
    @Volatile private var audioCodec = ""
    @Volatile private var udp = false
    @Volatile private var rttMs = 0.0
    @Volatile private var jitterMs = 0.0
    @Volatile private var videoJitterMs = 0.0
    @Volatile private var packetsReceived = 0L
    @Volatile private var packetsLost = 0L
    private var previousPresented = 0L
    private var previousVideoPackets = 0L
    @Volatile private var lastPresentationProgress = System.nanoTime()
    private val sink = VideoSink { frame ->
        if (!closed.get() && !paused) {
            if (frame.rotatedWidth != lastWidth || frame.rotatedHeight != lastHeight) {
                lastWidth = frame.rotatedWidth; lastHeight = frame.rotatedHeight
                onSize(lastWidth, lastHeight)
            }
            renderer.onFrame(frame)
        }
    }
    init {
        try {
        initialize(context)
        egl = EglBase.create()
        renderer.init(egl.eglBaseContext, EglBase.CONFIG_PLAIN, GlRectDrawer())
        rendererInitialized = true
        renderer.createEglSurface(surface)
        renderer.addRenderListener { if (!closed.get() && !paused) frames.incrementAndGet() }
        renderer.setErrorCallback { fail("The TV could not render Wi-Fi video") }
        audioDevice = JavaAudioDeviceModule.builder(context.applicationContext)
            .setUseStereoOutput(true).setOutputSampleRate(48000).setUseLowLatency(true)
            .setUseHardwareAcousticEchoCanceler(false).setUseHardwareNoiseSuppressor(false)
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MOVIE).build())
            .setPlaybackSamplesReadyCallback { samples ->
                var peak = 0
                for (index in 0 until samples.data.size - 1 step 64) {
                    val value = ((samples.data[index].toInt() and 255) or (samples.data[index + 1].toInt() shl 8)).toShort().toInt()
                    peak = maxOf(peak, kotlin.math.abs(value))
                }
                recentAudioPeak = peak / 32768.0; lastAudioSamplesAt = System.nanoTime()
                if (!closed.get() && audioPlaying.get()) audioFramesWritten.addAndGet(samples.data.size.toLong() / (2 * samples.channelCount.coerceAtLeast(1)))
                if (!audioSignal.get()) {
                    val data = samples.data
                    for (index in 0 until data.size - 1 step 32) {
                        val value = ((data[index].toInt() and 255) or (data[index + 1].toInt() shl 8)).toShort().toInt()
                        if (kotlin.math.abs(value) > 32) { audioSignal.set(true); break }
                    }
                }
                if (!audioStereoSignal.get() && samples.channelCount == 2) {
                    val data = samples.data
                    for (index in 0 until data.size - 3 step 32) {
                        val left = ((data[index].toInt() and 255) or (data[index + 1].toInt() shl 8)).toShort().toInt()
                        val right = ((data[index + 2].toInt() and 255) or (data[index + 3].toInt() shl 8)).toShort().toInt()
                        if (kotlin.math.abs(left - right) > 32) { audioStereoSignal.set(true); break }
                    }
                }
            }
            .setAudioTrackStateCallback(object : JavaAudioDeviceModule.AudioTrackStateCallback {
                override fun onWebRtcAudioTrackStart() { audioPlaying.set(true) }
                override fun onWebRtcAudioTrackStop() { audioPlaying.set(false) }
            })
            .setAudioTrackErrorCallback(object : JavaAudioDeviceModule.AudioTrackErrorCallback {
                override fun onWebRtcAudioTrackInitError(message: String) { fail("TV system audio could not initialize") }
                override fun onWebRtcAudioTrackStartError(code: JavaAudioDeviceModule.AudioTrackStartErrorCode, message: String) { fail("TV system audio could not start") }
                override fun onWebRtcAudioTrackError(message: String) { fail("TV system audio playback failed") }
            }).createAudioDeviceModule()
        factory = PeerConnectionFactory.builder()
            .setAudioDeviceModule(audioDevice)
            .setVideoEncoderFactory(DefaultVideoEncoderFactory(egl.eglBaseContext, true, false))
            .setVideoDecoderFactory(ScreenDecoderFactory(egl.eglBaseContext)).createPeerConnectionFactory()
        val config = PeerConnection.RTCConfiguration(emptyList()).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE
            rtcpMuxPolicy = PeerConnection.RtcpMuxPolicy.REQUIRE
            tcpCandidatePolicy = PeerConnection.TcpCandidatePolicy.DISABLED
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
            audioJitterBufferMaxPackets = 50; audioJitterBufferFastAccelerate = true
        }
        peer = factory.createPeerConnection(config, observer)
        check(peer != null) { "TV could not initialize the Wi-Fi media engine" }
        } catch (error: Exception) {
            closed.set(true); cleanup(); owner.shutdown(); throw error
        }
    }

    private fun execute(block: () -> Unit) {
        if (closed.get()) return
        try { owner.execute { if (!closed.get()) try { block() } catch (_: Exception) { fail("TV Wi-Fi media negotiation failed") } } }
        catch (_: java.util.concurrent.RejectedExecutionException) { fail("Wi-Fi media signaling exceeded its queue limit") }
    }
    private fun fail(message: String) { if (!closed.get() && failed.compareAndSet(false, true)) onError(message) }
    fun setPicture(display: TVDisplay) {
        if (!closed.get()) renderer.setLayoutAspectRatio(if (display.presentation.mode == PictureMode.FILL) display.width.toFloat() / display.height else 0f)
    }
    private fun emit(json: JSONObject) {
        if (!closed.get()) signal(json.put("session", sessionId))
    }
    fun receive(json: JSONObject) {
        require(json.getString("session") == sessionId) { "Media session changed" }
        when (json.getString("op")) {
            "rtcOffer" -> {
                val sdp = json.getString("sdp"); RtcSignaling.validateSdp(sdp)
                execute {
                    check(!negotiating) { "Media offer already pending" }; negotiating = true
                    peer?.setRemoteDescription(object : SdpObserverAdapter() {
                        override fun onSetSuccess() { execute {
                            remoteReady = true
                            candidates.forEach { peer?.addIceCandidate(it) }; candidates.clear()
                            peer?.transceivers?.forEach { it.direction = RtpTransceiver.RtpTransceiverDirection.RECV_ONLY }
                            peer?.createAnswer(object : SdpObserverAdapter() {
                                override fun onCreateSuccess(description: SessionDescription) { execute {
                                    val answer = SessionDescription(SessionDescription.Type.ANSWER, RtcSignaling.stereoOpus(description.description))
                                    peer?.setLocalDescription(object : SdpObserverAdapter() {
                                        override fun onSetSuccess() { execute {
                                            negotiating = false
                                            emit(JSONObject().put("op", "rtcAnswer").put("sdp", answer.description))
                                        } }
                                        override fun onSetFailure(message: String) { fail("TV could not establish encrypted media") }
                                    }, answer)
                                } }
                                override fun onCreateFailure(message: String) { fail("TV could not answer the media offer") }
                            }, MediaConstraints())
                        } }
                        override fun onSetFailure(message: String) { fail("The TV does not support this media offer") }
                    }, SessionDescription(SessionDescription.Type.OFFER, sdp))
                }
            }
            "rtcCandidate" -> {
                val sdp = json.getString("candidate"); val index = json.getInt("index"); val mid = json.optString("mid", "0")
                RtcSignaling.validateCandidate(sdp, mid, index)
                execute {
                    val candidate = IceCandidate(mid, index, sdp)
                    if (remoteReady) peer?.addIceCandidate(candidate)
                    else { check(candidates.size < 64); candidates.add(candidate) }
                }
            }
            else -> throw IllegalArgumentException("Unknown media signal")
        }
    }
    fun setPlayback(audio: Boolean, paused: Boolean, volume: Float) { execute {
        if (this.paused && !paused) lastPresentationProgress = System.nanoTime()
        this.audioEnabled = audio; this.paused = paused; this.volume = volume.toDouble()
        audioTrack?.setEnabled(audio && !paused); audioTrack?.setVolume(if (paused || !audio) 0.0 else this.volume)
        if (paused) renderer.pauseVideo() else renderer.disableFpsReduction()
    } }
    private fun track(track: MediaStreamTrack?) { execute {
        when (track) {
            is VideoTrack -> if (videoTrack?.id() != track.id()) {
                videoTrack?.removeSink(sink); videoTrack = track; track.addSink(sink)
            }
            is AudioTrack -> {
                audioTrack = track; track.setEnabled(audioEnabled && !paused); track.setVolume(if (paused || !audioEnabled) 0.0 else volume)
            }
        }
    } }
    private val observer get() = object : PeerConnection.Observer {
        override fun onIceCandidate(candidate: IceCandidate) { execute {
            if (runCatching { RtcSignaling.validateCandidate(candidate.sdp, candidate.sdpMid, candidate.sdpMLineIndex) }.isSuccess)
                emit(JSONObject().put("op", "rtcCandidate").put("candidate", candidate.sdp).put("mid", candidate.sdpMid).put("index", candidate.sdpMLineIndex))
        } }
        override fun onConnectionChange(state: PeerConnection.PeerConnectionState) {
            android.util.Log.i("Miraya", "RTC peer $state")
            if (state == PeerConnection.PeerConnectionState.CONNECTED) lastPresentationProgress = System.nanoTime()
            if (state == PeerConnection.PeerConnectionState.FAILED) fail("The encrypted Wi-Fi media connection failed")
        }
        override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) { android.util.Log.i("Miraya", "RTC ICE $state"); if (state == PeerConnection.IceConnectionState.FAILED) fail("Direct UDP media could not reach the TV") }
        override fun onTrack(transceiver: RtpTransceiver) { track(transceiver.receiver.track()) }
        override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) { track(receiver.track()) }
        override fun onSignalingChange(state: PeerConnection.SignalingState) {}
        override fun onIceConnectionReceivingChange(receiving: Boolean) {}
        override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {}
        override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) {}
        override fun onAddStream(stream: MediaStream) {}
        override fun onRemoveStream(stream: MediaStream) {}
        override fun onDataChannel(channel: DataChannel) { channel.close() }
        override fun onRenegotiationNeeded() {}
    }
    fun statistics(): JSONObject {
        if (!closed.get() && statsPending.compareAndSet(false, true)) execute {
            peer?.getStats { report ->
                try {
                    val values = report.statsMap
                    values.values.forEach { stat ->
                        val members = stat.members
                        if (stat.type == "inbound-rtp") {
                            val codec = (values[members["codecId"] as? String]?.members?.get("mimeType") as? String).orEmpty()
                            when (members["kind"] ?: members["mediaType"]) {
                                "video" -> {
                                    decoderImplementation = (members["decoderImplementation"] as? String) ?: decoderImplementation
                                    packetsReceived = (members["packetsReceived"] as? Number)?.toLong() ?: packetsReceived
                                    packetsLost = (members["packetsLost"] as? Number)?.toLong()?.coerceAtLeast(0) ?: packetsLost
                                    videoJitterMs = (members["jitter"] as? Number)?.toDouble()?.times(1000) ?: videoJitterMs
                                    decoded = (members["framesDecoded"] as? Number)?.toLong() ?: decoded
                                    dropped = (members["framesDropped"] as? Number)?.toLong() ?: dropped; videoCodec = codec
                                    val presented = frames.get()
                                    val packets = (members["packetsReceived"] as? Number)?.toLong() ?: 0
                                    val now = System.nanoTime()
                                    if (paused || presented != previousPresented) lastPresentationProgress = now
                                    else if (packets > previousVideoPackets && now - lastPresentationProgress > 8_000_000_000L)
                                        fail("The TV decoder stopped presenting video. Reconnect sharing.")
                                    previousPresented = presented; previousVideoPackets = packets
                                }
                                "audio" -> audioCodec = codec
                            }
                            jitterMs = (members["jitter"] as? Number)?.toDouble()?.times(1000) ?: jitterMs
                        }
                        if (stat.type == "candidate-pair" && members["nominated"] == true && members["state"] == "succeeded") {
                            udp = values[members["localCandidateId"] as? String]?.members?.get("protocol") == "udp"
                            rttMs = (members["currentRoundTripTime"] as? Number)?.toDouble()?.times(1000) ?: rttMs
                        }
                    }
                } finally { statsPending.set(false) }
            }
        }
        return JSONObject().put("op", "stats").put("transport", RtcSignaling.TRANSPORT).put("protocol", if (udp) "udp" else "connecting")
            .put("frames", frames.get()).put("decoded", decoded).put("dropped", dropped).put("lastPts", -1).put("lastDecodedPts", -1)
            .put("audioFrames", audioFramesWritten.get()).put("audioFramesWritten", audioFramesWritten.get()).put("audioPlaying", audioPlaying.get())
            .put("audioSignal", audioSignal.get())
            .put("audioStereoSignal", audioStereoSignal.get())
            .put("videoWidth", lastWidth).put("videoHeight", lastHeight).put("paused", paused).put("audioEnabled", audioEnabled).put("volume", volume)
            .put("videoCodec", videoCodec).put("audioCodec", audioCodec).put("rttMs", rttMs).put("jitterMs", jitterMs)
            .put("decoderImplementation", decoderImplementation)
            .put("videoJitterMs", videoJitterMs).put("videoPacketsReceived", packetsReceived).put("videoPacketsLost", packetsLost)
            .put("audioPeak", if (audioEnabled && !paused && System.nanoTime() - lastAudioSamplesAt < 500_000_000L) recentAudioPeak else 0.0)
    }
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        try {
            owner.queue.clear()
            if (Thread.currentThread() === ownerThread) cleanup() else owner.submit { cleanup() }.get(4, TimeUnit.SECONDS)
        } catch (_: Exception) {
            android.util.Log.w("Miraya", "RTC cleanup did not finish within its deadline")
        } finally { owner.shutdown() }
    }
    private fun cleanup() {
        runCatching { videoTrack?.removeSink(sink) }; videoTrack = null; audioTrack = null
        if (rendererInitialized) runCatching { renderer.release() }
        runCatching { peer?.close() }; runCatching { peer?.dispose() }; peer = null
        if (::factory.isInitialized) runCatching { factory.dispose() }
        if (::audioDevice.isInitialized) runCatching { audioDevice.release() }
        if (::egl.isInitialized) runCatching { egl.release() }
    }
    private open class SdpObserverAdapter : SdpObserver {
        override fun onCreateSuccess(description: SessionDescription) {}
        override fun onSetSuccess() {}
        override fun onCreateFailure(message: String) {}
        override fun onSetFailure(message: String) {}
    }
}
