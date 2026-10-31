package dev.miraya.tv

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.Surface
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** A bounded range reader carried inside the already authenticated TLS session. */
internal class SelectedFileBridge(private val send: (JSONObject) -> Unit) : AutoCloseable {
    private val pending = ConcurrentHashMap<String, CompletableFuture<ByteArray>>()
    private val closed = AtomicBoolean()
    private val slots = java.util.concurrent.Semaphore(4)
    fun read(id: String, offset: Long, count: Int): ByteArray {
        if (closed.get() || !slots.tryAcquire()) throw IOException("Media transfer unavailable")
        val request = UUID.randomUUID().toString(); val result = CompletableFuture<ByteArray>()
        pending[request] = result
        try {
            if (closed.get()) throw IOException("Media transfer closed")
            send(JSONObject().put("op", "mediaRead").put("request", request).put("id", id).put("offset", offset).put("count", count))
            return result.get(8, TimeUnit.SECONDS)
        } catch (error: Exception) { throw IOException("Selected media transfer interrupted", error) }
        finally { pending.remove(request); slots.release() }
    }
    fun accept(json: JSONObject) {
        val result = pending[json.optString("request")] ?: return
        if (json.has("error")) { result.completeExceptionally(IOException("Selected media is unavailable")); return }
        val encoded = json.optString("data")
        if (encoded.length > 43700) { result.completeExceptionally(IOException("Media chunk exceeded limit")); return }
        try {
            val data = Base64.decode(encoded, Base64.NO_WRAP)
            if (data.size > DirectMediaPolicy.CHUNK) throw IOException("Media chunk exceeded limit")
            result.complete(data)
        } catch (error: Exception) { result.completeExceptionally(error) }
    }
    override fun close() { closed.set(true); pending.values.forEach { it.completeExceptionally(IOException("Media transfer closed")) }; pending.clear() }
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
private class SelectedFileSource(private val bridge: SelectedFileBridge, private val sizes: Map<String, Long>) : BaseDataSource(true) {
    private var uri: Uri? = null
    private var position = 0L
    private var remaining = 0L
    private var buffer = ByteArray(0)
    private var cursor = 0
    private var opened = false
    override fun open(dataSpec: DataSpec): Long {
        transferInitializing(dataSpec)
        val id = dataSpec.uri.lastPathSegment ?: throw IOException("Invalid selected media")
        val size = sizes[id] ?: throw IOException("Selected media is not authorized")
        if (dataSpec.position !in 0..size) throw IOException("Media position out of range")
        uri = dataSpec.uri; position = dataSpec.position
        remaining = if (dataSpec.length == C.LENGTH_UNSET.toLong()) size - position else minOf(dataSpec.length, size - position)
        buffer = ByteArray(0); cursor = 0; opened = true; transferStarted(dataSpec); return remaining
    }
    override fun read(target: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (remaining == 0L) return C.RESULT_END_OF_INPUT
        if (cursor == buffer.size) {
            val wanted = minOf(DirectMediaPolicy.CHUNK.toLong(), remaining).toInt()
            buffer = bridge.read(uri!!.lastPathSegment!!, position, wanted); cursor = 0
            if (buffer.isEmpty() || buffer.size > wanted) throw IOException("Selected media changed or ended unexpectedly")
        }
        val count = minOf(length, buffer.size - cursor, remaining.toInt().coerceAtLeast(0).let { if (remaining > Int.MAX_VALUE) Int.MAX_VALUE else it })
        buffer.copyInto(target, offset, cursor, cursor + count); cursor += count; position += count; remaining -= count
        bytesTransferred(count); return count
    }
    override fun getUri(): Uri? = uri
    override fun close() { uri = null; buffer = ByteArray(0); if (opened) { opened = false; transferEnded() } }
}

/** Player/renderer commands are serialized on Android's application looper. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class DirectMediaReceiver(
    context: Context, surface: Surface, private val view: () -> PlayerView?, specification: JSONObject,
    private val send: (JSONObject) -> Unit, private val onSize: (Int, Int) -> Unit,
    private val onFailure: (String) -> Unit
) : AutoCloseable {
    private val main = Handler(Looper.getMainLooper())
    private val closed = AtomicBoolean()
    val loadId: String = specification.getString("loadId")
    private val bridge = SelectedFileBridge(send)
    private var player: ExoPlayer? = null
    private var tracks = JSONArray()
    private var firstPicture = false
    private var width = 0
    private var height = 0
    private val sender = java.util.concurrent.Executors.newSingleThreadExecutor()
    private val sendingState = AtomicBoolean()
    private val ticker = object : Runnable { override fun run() { if (!closed.get()) { publish(); main.postDelayed(this, 500) } } }
    init {
        require(DirectMediaPolicy.validId(loadId)) { "Invalid playback identity" }
        val assets = specification.optJSONArray("assets") ?: JSONArray()
        require(assets.length() <= 4) { "Too many media assets" }
        val sizes = mutableMapOf<String, Long>()
        for (index in 0 until assets.length()) {
            val asset = assets.getJSONObject(index); val id = asset.getString("id"); val size = asset.getLong("size")
            require(DirectMediaPolicy.validId(id) && size in 1..1_099_511_627_776L && !sizes.containsKey(id)) { "Invalid selected media" }; sizes[id] = size
        }
        fun validateAddress(value: String): Uri {
            val uri = Uri.parse(value)
            require(DirectMediaPolicy.validRemote(value) || (uri.scheme == "miraya-file" && uri.host.isNullOrEmpty() && sizes.containsKey(uri.lastPathSegment))) { "Use a selected file or HTTPS media URL" }
            return uri
        }
        val address = validateAddress(specification.getString("url"))
        val item = MediaItem.Builder().setUri(address)
        val mime = specification.optString("mime")
        if (mime in listOf("video/mp4", "video/x-matroska", "video/webm", "application/x-mpegURL", "application/dash+xml", "audio/mpeg", "audio/mp4")) item.setMimeType(mime)
        specification.optJSONObject("subtitle")?.let {
            val subtitleMime = it.getString("mime"); require(subtitleMime in listOf("text/vtt", "application/x-subrip")) { "Unsupported subtitles" }
            item.setSubtitleConfigurations(listOf(MediaItem.SubtitleConfiguration.Builder(validateAddress(it.getString("url")))
                .setMimeType(subtitleMime).setLabel("External subtitles").setSelectionFlags(C.SELECTION_FLAG_DEFAULT).build()))
        }
        val volume = specification.optDouble("volume", 1.0)
        require(volume.isFinite() && volume in 0.0..1.0) { "Invalid volume" }
        val http = DefaultHttpDataSource.Factory().setAllowCrossProtocolRedirects(false).setConnectTimeoutMs(8000).setReadTimeoutMs(8000)
        val factory = DataSource.Factory {
            object : DataSource {
                private var actual: DataSource? = null
                private val listeners = mutableListOf<androidx.media3.datasource.TransferListener>()
                override fun addTransferListener(listener: androidx.media3.datasource.TransferListener) { listeners.add(listener); actual?.addTransferListener(listener) }
                override fun open(spec: DataSpec): Long {
                    val selected = spec.uri.scheme == "miraya-file"
                    if (!selected && !DirectMediaPolicy.validRemote(spec.uri.toString())) throw IOException("Only HTTPS media is supported")
                    return (if (selected) SelectedFileSource(bridge, sizes) else http.createDataSource()).also { source -> actual = source; listeners.forEach(source::addTransferListener) }.open(spec)
                }
                override fun read(buffer: ByteArray, offset: Int, length: Int) = actual?.read(buffer, offset, length) ?: throw IOException("Media source closed")
                override fun getUri(): Uri? = actual?.uri
                override fun getResponseHeaders(): Map<String, List<String>> = actual?.responseHeaders ?: emptyMap()
                override fun close() { actual?.close(); actual = null }
            }
        }
        main.post {
            if (closed.get()) return@post
            try {
                val loadControl = DefaultLoadControl.Builder().setBufferDurationsMs(15000, 30000, 1500, 3000).build()
                val engine = ExoPlayer.Builder(context).setMediaSourceFactory(DefaultMediaSourceFactory(factory)).setLoadControl(loadControl).build()
                player = engine
                val output = view()
                if (output != null) { output.player = engine; output.setShowSubtitleButton(true) } else engine.setVideoSurface(surface)
                engine.volume = volume.toFloat()
                engine.setAudioAttributes(androidx.media3.common.AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true)
                engine.addListener(object : Player.Listener {
                    override fun onRenderedFirstFrame() { firstPicture = true; publish() }
                    override fun onVideoSizeChanged(videoSize: VideoSize) { width = videoSize.width; height = videoSize.height; if (width > 0 && height > 0) onSize(width, height) }
                    override fun onTracksChanged(value: Tracks) { tracks = trackList(value); publish() }
                    override fun onPlaybackStateChanged(playbackState: Int) { publish() }
                    override fun onIsPlayingChanged(isPlaying: Boolean) { publish() }
                    override fun onPlayerError(error: PlaybackException) { if (!closed.get()) onFailure("The TV could not play this media (${error.errorCodeName}). Check its format, availability and TV compatibility.") }
                })
                engine.setMediaItem(item.build()); engine.prepare(); engine.play(); main.post(ticker)
            } catch (_: Exception) { if (!closed.get()) onFailure("The TV could not initialize video playback.") }
        }
    }
    private fun trackList(value: Tracks): JSONArray = JSONArray().apply {
        value.groups.take(32).forEachIndexed { groupIndex, group ->
            if (group.type == C.TRACK_TYPE_AUDIO || group.type == C.TRACK_TYPE_TEXT) for (index in 0 until minOf(group.length, 32)) {
                if (length() >= 64) break
                val format = group.getTrackFormat(index)
                if (group.isTrackSupported(index)) put(JSONObject().put("id", "$groupIndex:$index").put("kind", if (group.type == C.TRACK_TYPE_AUDIO) "audio" else "text")
                    .put("label", (format.label ?: format.language ?: if (group.type == C.TRACK_TYPE_AUDIO) "Audio ${index + 1}" else "Subtitles ${index + 1}").take(80)).put("selected", group.isTrackSelected(index)))
            }
        }
    }
    private fun publish() {
        val engine = player ?: return
        if (closed.get()) return
        val duration = engine.duration.takeIf { it != C.TIME_UNSET && it >= 0 } ?: 0
        val state = when (engine.playbackState) { Player.STATE_BUFFERING -> "buffering"; Player.STATE_ENDED -> "ended"; Player.STATE_READY -> if (engine.isPlaying) "playing" else "paused"; else -> "preparing" }
        val message = JSONObject().put("op", "mediaState").put("loadId", loadId).put("state", state).put("firstPicture", firstPicture)
            .put("hasVideo", engine.currentTracks.groups.any { it.type == C.TRACK_TYPE_VIDEO })
            .put("positionMs", engine.currentPosition.coerceAtLeast(0)).put("durationMs", duration).put("bufferedMs", engine.bufferedPosition.coerceAtLeast(0))
            .put("seekable", engine.isCurrentMediaItemSeekable).put("width", width).put("height", height).put("tracks", tracks)
            .put("frames", engine.videoDecoderCounters?.renderedOutputBufferCount ?: 0)
            .put("dropped", engine.videoDecoderCounters?.droppedBufferCount ?: 0)
            .put("audioBuffers", engine.audioDecoderCounters?.renderedOutputBufferCount ?: 0)
        // Socket writes must not block the player/UI looper.
        stateSender(message)
    }
    private fun stateSender(message: JSONObject) {
        if (!sendingState.compareAndSet(false, true) || closed.get()) return
        try { sender.execute { try { if (!closed.get()) send(message) } catch (_: Exception) { } finally { sendingState.set(false) } } }
        catch (_: java.util.concurrent.RejectedExecutionException) { sendingState.set(false) }
    }
    fun acceptChunk(json: JSONObject) { bridge.accept(json) }
    fun command(json: JSONObject) {
        require(json.optString("loadId") == loadId) { "Playback session changed" }
        val action = json.getString("action")
        require(action in listOf("play", "pause", "seek", "volume", "track")) { "Unknown playback action" }
        val position = json.optLong("positionMs", 0)
        val gain = json.optDouble("volume", 1.0)
        require(position >= 0 && gain.isFinite() && gain in 0.0..1.0) { "Invalid playback setting" }
        main.post {
            if (closed.get()) return@post; val engine = player ?: return@post
            when (action) {
                "play" -> { if (engine.playbackState == Player.STATE_ENDED) engine.seekToDefaultPosition(); engine.play() }
                "pause" -> engine.pause()
                "seek" -> if (engine.isCurrentMediaItemSeekable) engine.seekTo(if (engine.duration > 0) minOf(position, engine.duration) else position)
                "volume" -> engine.volume = gain.toFloat()
                "track" -> {
                    val type = if (json.optString("kind") == "audio") C.TRACK_TYPE_AUDIO else C.TRACK_TYPE_TEXT
                    val id = json.optString("track")
                    val builder = engine.trackSelectionParameters.buildUpon().clearOverridesOfType(type).setTrackTypeDisabled(type, id == "off")
                    if (id != "off" && id != "auto") {
                        val parts = id.split(':').mapNotNull { it.toIntOrNull() }
                        if (parts.size == 2) engine.currentTracks.groups.getOrNull(parts[0])?.let { group ->
                            if (group.type == type && parts[1] in 0 until group.length && group.isTrackSupported(parts[1])) builder.addOverride(TrackSelectionOverride(group.mediaTrackGroup, parts[1]))
                        }
                    }
                    engine.trackSelectionParameters = builder.build()
                }
            }
            publish()
        }
    }
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        bridge.close(); sender.shutdownNow(); main.removeCallbacks(ticker)
        main.post { view()?.let { if (it.player === player) it.player = null }; player?.release(); player = null }
    }
}
