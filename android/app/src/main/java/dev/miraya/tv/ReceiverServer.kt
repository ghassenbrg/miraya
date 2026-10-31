package dev.miraya.tv

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.io.IOException
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.SocketTimeoutException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket

class ReceiverServer(private val context: Context, val identity: Identity, private val ui: Listener) : AutoCloseable {
    interface Listener {
        fun onListening(port: Int, addresses: String, discoveryAvailable: Boolean)
        fun onStatus(title: String, detail: String)
        fun approve(name: String, respond: (Boolean) -> Unit)
        fun onPairingCode(code: String?) {}
        fun onPaused(paused: Boolean) {}
        fun dismissApproval()
        fun surface(): Surface?
        fun onStreaming(name: String, streaming: Boolean)
        fun onVideoSize(width: Int, height: Int)
        fun directPlayerView(): androidx.media3.ui.PlayerView? = null
        fun onDirectPlayback(enabled: Boolean) {}
        fun displayInfo(): TVDisplay = TVDisplay(1920, 1080, 1920, 1080, 60.0, PresentationSettings())
        fun setPresentation(settings: PresentationSettings, respond: (TVDisplay) -> Unit) { respond(displayInfo().copy(presentation = settings)) }
    }
    private val nsd = context.getSystemService(NsdManager::class.java)
    private var registration: NsdManager.RegistrationListener? = null
    private var listener: SSLServerSocket? = null
    private val clients = ConcurrentHashMap.newKeySet<SSLSocket>()
    private val handshakes = Semaphore(2)
    private val scheduler = Executors.newScheduledThreadPool(2)
    // Never share this executor with socket writers: a peer that stops reading can block all of them.
    private val deadlines = Executors.newSingleThreadScheduledExecutor()
    @Volatile private var running = true
    @Volatile private var session: Session? = null
    private var lastPairRequest = 0L
    private val acceptThread = Thread(::acceptLoop, "Miraya listener").apply { start() }

    private fun acceptLoop() {
        try {
            val factory = identity.sslContext.serverSocketFactory
            listener = try { factory.createServerSocket(7421, 4) as SSLServerSocket }
            catch (_: IOException) { factory.createServerSocket(0, 4) as SSLServerSocket }
            val server = listener ?: return
            if (!running) { server.close(); return }
            server.enabledProtocols = server.supportedProtocols.filter { it == "TLSv1.2" || it == "TLSv1.3" }.toTypedArray()
            server.needClientAuth = false
            val addresses = localAddresses()
            ui.onListening(server.localPort, addresses, false)
            advertise(server.localPort, addresses)
            while (running) {
                val socket = server.accept() as SSLSocket
                if (!handshakes.tryAcquire()) { socket.close(); continue }
                clients.add(socket)
                Thread({
                    try {
                        socket.use {
                            socket.soTimeout = 6000; socket.tcpNoDelay = true
                            socket.receiveBufferSize = 256 * 1024; socket.sendBufferSize = 16 * 1024
                            socket.startHandshake()
                            val connection = Session(socket)
                            val claimed = synchronized(this) {
                                if (session == null && running) { session = connection; true } else false
                            }
                            if (!claimed) { connection.rejectBusy(); return@Thread }
                            try { connection.run() }
                            finally { synchronized(this) { if (session === connection) session = null }; connection.close() }
                        }
                    } catch (error: Exception) {
                        // Never emit remote payloads, names, certificates or credentials in diagnostics.
                        if (running) {
                            if (error is javax.net.ssl.SSLHandshakeException) Log.w("Miraya", "TLS handshake failed", error)
                            else Log.i("Miraya", "Client connection ended: ${error.javaClass.simpleName}")
                        }
                    } finally { clients.remove(socket); handshakes.release() }
                }, "Miraya client").start()
            }
        } catch (error: Exception) {
            if (running) ui.onStatus("Connection unavailable", error.message ?: "The TV could not open a local network listener. Reopen Miraya to try again.")
        } finally {
            try { listener?.close() } catch (_: Exception) { }
            if (running) close()
        }
    }

    private fun advertise(port: Int, addresses: String) {
        val service = NsdServiceInfo().apply {
            serviceName = identity.name.let { name ->
                var shortened = name
                while (shortened.toByteArray(Charsets.UTF_8).size > 63) shortened = shortened.dropLast(1)
                shortened
            }; serviceType = "_miraya._tcp."
            setPort(port); setAttribute("v", "1"); setAttribute("id", identity.receiverId)
        }
        val callbacks = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) { if (running) ui.onListening(port, addresses, true) }
            override fun onRegistrationFailed(info: NsdServiceInfo, code: Int) { if (running) ui.onListening(port, addresses, false) }
            override fun onServiceUnregistered(info: NsdServiceInfo) { }
            override fun onUnregistrationFailed(info: NsdServiceInfo, code: Int) { }
        }
        registration = callbacks
        try { nsd.registerService(service, NsdManager.PROTOCOL_DNS_SD, callbacks) }
        catch (_: Exception) { ui.onListening(port, addresses, false) }
    }

    fun stopSharing() { session?.stopByUser() }
    fun updatePresentation(display: TVDisplay) { session?.updatePresentation(display) }
    fun revokeMac(clientId: String) { if (session?.clientId == clientId) session?.stopByUser(); identity.revoke(clientId) }
    fun revokeTrust() { session?.stopByUser(); identity.revokeAll() }

    private inner class Session(private val socket: SSLSocket) : AutoCloseable {
        private val input = DataInputStream(BufferedInputStream(socket.inputStream, 64 * 1024))
        private val output = DataOutputStream(BufferedOutputStream(socket.outputStream, 16 * 1024))
        private val sequence = AtomicInteger()
        @Volatile private var closed = false
        @Volatile private var lastReceive = System.nanoTime()
        @Volatile private var streaming = false
        @Volatile private var media: MediaPipeline? = null
        @Volatile private var rtc: RtcMediaReceiver? = null
        @Volatile private var direct: DirectMediaReceiver? = null
        private var transport = "tcp-v1"
        private var paused = false
        private var sessionAudio = false
        private var volume = 1f
        private var timer: java.util.concurrent.ScheduledFuture<*>? = null
        private var statsTimer: java.util.concurrent.ScheduledFuture<*>? = null
        private var watchdog: java.util.concurrent.ScheduledFuture<*>? = null
        @Volatile private var writeStarted = 0L
        private var approvedName = "Mac"
        @Volatile var clientId = ""
            private set
        private var stopMessage = "Your Mac disconnected. Open Miraya on the Mac to connect again."
        private var configReceived = false
        private val approval = CountDownLatch(1)
        private val audioManager = context.getSystemService(AudioManager::class.java)
        @Volatile private var audioFocus: AudioFocusRequest? = null
        @Volatile private var accepted = false
        @Volatile private var failureReported = false

        @Synchronized fun send(json: JSONObject) {
            if (!closed) {
                writeStarted = System.nanoTime()
                try { Wire.write(output, Packet(Wire.CONTROL, payload = json.toString().toByteArray(Charsets.UTF_8), sequence = sequence.getAndIncrement())) }
                finally { writeStarted = 0L }
            }
        }
        fun error(code: String, message: String) {
            try { send(JSONObject().put("op", "error").put("code", code).put("message", message)) } catch (_: Exception) { }
        }
        fun rejectBusy() {
            // Consume the bounded hello before closing: unread TLS bytes can otherwise reset
            // the connection and discard the busy response while the Mac is sending hello.
            val timeout = deadlines.schedule({ closeSocket() }, 2500, TimeUnit.MILLISECONDS)
            try {
                socket.soTimeout = 2000
                val hello = Wire.read(input)
                if (hello.type == Wire.CONTROL && JSONObject(String(hello.payload, Charsets.UTF_8)).optString("op") == "hello") {
                    error("busy", "This TV is already connected to another Mac")
                } else error("protocol", "Expected hello")
            } catch (_: Exception) {
            } finally { timeout.cancel(false); closeSocket() }
        }

        private fun requestAudioFocus(): Boolean {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MOVIE).build())
                .setAcceptsDelayedFocusGain(false).setWillPauseWhenDucked(true)
                .setOnAudioFocusChangeListener({ change ->
                    if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK) {
                        if (!closed && audioFocus != null) {
                            failureReported = true
                            stopMessage = "TV audio was interrupted by another app. Start sharing again from your Mac when you're ready."
                            media?.silenceAudio(); rtc?.setPlayback(false, true, 0f)
                            Thread({ try { error("audio", stopMessage) } finally { closeSocket() } }, "Miraya audio interruption").start()
                            deadlines.schedule({ closeSocket() }, 200, TimeUnit.MILLISECONDS)
                        }
                    }
                }, Handler(Looper.getMainLooper())).build()
            audioFocus = request
            if (audioManager.requestAudioFocus(request) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                audioFocus = null
                error("audio", "TV audio is busy. Close other media apps or turn off system audio on your Mac and try again.")
                return false
            }
            return !closed && !failureReported
        }
        fun run() {
            try {
                watchdog = deadlines.scheduleWithFixedDelay({
                    if (writeStarted > 0 && System.nanoTime() - writeStarted > 5_000_000_000L) closeSocket()
                }, 1, 1, TimeUnit.SECONDS)
                val helloPacket = Wire.read(input)
                require(helloPacket.type == Wire.CONTROL) { "Expected hello" }
                val hello = JSONObject(String(helloPacket.payload, Charsets.UTF_8))
                require(hello.getString("op") == "hello") { "Expected hello" }
                if (hello.optInt("version") != 1) { error("version", "This Mac and TV use different protocol versions. Update both Miraya apps."); return }
                clientId = UUID.fromString(hello.getString("clientId")).toString()
                approvedName = hello.optString("name", "Mac").replace(Regex("[\\p{Cntrl}]"), "").take(80).ifBlank { "Mac" }
                val stored = identity.tokenFor(clientId)
                val supplied = hello.optString("token", "")
                val token: String
                if (stored != null) {
                    if (!identity.tokenMatches(stored, supplied)) { error("auth", "This Mac's saved authorization is no longer valid. Forget this TV on the Mac and pair again."); return }
                    token = stored
                } else {
                    if (supplied.isNotEmpty()) { error("auth", "This TV no longer trusts this Mac. Forget this TV on the Mac and pair again."); return }
                    synchronized(this@ReceiverServer) {
                        if (System.nanoTime() - lastPairRequest < 5_000_000_000L) { error("busy", "Please wait a few seconds before pairing again."); return }
                        lastPairRequest = System.nanoTime()
                    }
                    if (hello.optString("pairing") == PairingSession.METHOD) {
                        if (!shortPairing(hello)) return
                    }
                    send(JSONObject().put("op", "pending").put("stage", "approval"))
                    ui.approve(approvedName) { allow -> accepted = allow; approval.countDown() }
                    val answered = approval.await(30, TimeUnit.SECONDS)
                    ui.dismissApproval()
                    if (!running || closed) return
                    if (!answered) { error("timeout", "TV approval timed out. Try again and choose Allow on your TV."); return }
                    if (!accepted) { error("denied", "The TV declined this connection."); return }
                    token = identity.approve(clientId, approvedName)
                }
                send(JSONObject().put("op", "welcome").put("version", 1).put("receiverId", identity.receiverId)
                    .put("name", identity.name).put("token", token).put("maxWidth", 1920).put("maxHeight", 1080)
                    .put("display", ui.displayInfo().json())
                    .put("features", org.json.JSONArray().put("presentation-v1").put("direct-media-v1"))
                    .put("transports", org.json.JSONArray().put(RtcSignaling.TRANSPORT).put("tcp-v1")))
                socket.soTimeout = 10000; lastReceive = System.nanoTime()
                timer = scheduler.scheduleWithFixedDelay({ heartbeat() }, 2, 2, TimeUnit.SECONDS)
                while (running && !closed) {
                    val packet = Wire.read(input); lastReceive = System.nanoTime()
                    when (packet.type) {
                        Wire.CONTROL -> if (!control(JSONObject(String(packet.payload, Charsets.UTF_8)))) return
                        Wire.CONFIG -> {
                            require(streaming && !paused && rtc == null && direct == null) { "This connection uses a different media transport" }
                            media!!.configure(JSONObject(String(packet.payload, Charsets.UTF_8))); configReceived = true
                        }
                        Wire.VIDEO -> { require(streaming && !paused && rtc == null && direct == null && configReceived) { "Video arrived before configuration" }; media!!.video(packet) }
                        Wire.AUDIO -> { require(streaming && !paused && rtc == null && direct == null) { "Audio arrived before start" }; media!!.audio(packet) }
                    }
                }
            } catch (_: EOFException) {
            } catch (_: SocketTimeoutException) {
                stopMessage = "The Mac stopped responding. Check both devices are on the same network, then reconnect."
                error("timeout", "No data arrived for 10 seconds. Check your local network.")
            } catch (error: Exception) {
                if (!closed) {
                    stopMessage = "Connection interrupted. Try reconnecting from your Mac."
                    error("protocol", error.message?.take(180) ?: "Invalid stream received")
                }
            } finally { close() }
        }

        private fun shortPairing(hello: JSONObject): Boolean {
            val commitment = hello.getString("commitment")
            require(PairingSession.validHex(commitment)) { "Invalid pairing commitment" }
            val nonce = PairingSession.nonce()
            send(JSONObject().put("op", "pairChallenge").put("pairing", PairingSession.METHOD).put("nonce", nonce))
            val timeout = deadlines.schedule({ closeSocket() }, 90, TimeUnit.SECONDS)
            socket.soTimeout = 10000
            try {
                fun waitFor(op: String): JSONObject {
                    while (!closed && running) {
                        val packet = Wire.read(input)
                        require(packet.type == Wire.CONTROL) { "Pairing must finish before media" }
                        val json = JSONObject(String(packet.payload, Charsets.UTF_8))
                        when (json.optString("op")) {
                            "ping" -> send(JSONObject().put("op", "pong").put("nonce", json.optLong("nonce")))
                            "pong" -> Unit
                            "stop" -> { send(JSONObject().put("op", "stopped")); throw EOFException() }
                            op -> return json
                            else -> throw IOException("Unexpected pairing message")
                        }
                    }
                    throw EOFException()
                }
                val reveal = waitFor("pairReveal").getString("nonce")
                require(PairingSession.validHex(reveal) && identity.tokenMatches(PairingSession.commitment(reveal), commitment)) { "Pairing commitment mismatch" }
                val code = PairingSession.code(identity.fingerprint, clientId, reveal, nonce)
                ui.onPairingCode(code)
                send(JSONObject().put("op", "pending").put("stage", "code").put("expiresIn", 90))
                waitFor("pairConfirm")
                return !closed && running
            } finally { timeout.cancel(false); ui.onPairingCode(null) }
        }

        private fun createMedia(audioEnabled: Boolean, surface: Surface): MediaPipeline =
            MediaPipeline(surface, audioEnabled, ui::onVideoSize, { message ->
                        if (!failureReported) {
                            failureReported = true; stopMessage = message; error("decoder", message); closeSocket()
                        }
                    }, { try { send(JSONObject().put("op", "requestKeyframe")) } catch (_: Exception) { closeSocket() } }).also { it.setPicture(ui.displayInfo().presentation.mode) }

        fun updatePresentation(display: TVDisplay) {
            rtc?.setPicture(display); media?.setPicture(display.presentation.mode)
        }

        private fun ready(): JSONObject = JSONObject().put("op", "ready").put("transport", transport).apply {
            rtc?.let { put("session", it.sessionId) }
            put("display", ui.displayInfo().json())
        }
        private fun control(json: JSONObject): Boolean {
            when (json.getString("op")) {
                "mediaLoad" -> {
                    require(!streaming) { "Stop the current session before loading media" }
                    val surface = ui.surface()
                    require(surface != null && surface.isValid) { "TV display is not ready" }
                    ui.onDirectPlayback(true)
                    direct = DirectMediaReceiver(context, surface, ui::directPlayerView, json,
                        { send(it) }, ui::onVideoSize, { message ->
                            if (!closed && !failureReported) {
                                failureReported = true
                                Thread({ try { error("mediaPlayback", message) } finally { closeSocket() } }, "Miraya media failure").start()
                            }
                        })
                    streaming = true; transport = "direct-media-v1"
                    ui.onStreaming(approvedName, true)
                }
                "mediaChunk" -> { direct?.acceptChunk(json) }
                "mediaCommand" -> { require(direct != null) { "No video is loaded" }; direct!!.command(json) }
                "ping" -> send(JSONObject().put("op", "pong").put("nonce", json.optLong("nonce")))
                "pong" -> Unit
                "setPresentation" -> {
                    val mode = PictureMode.parse(json.getString("mode")) ?: throw IllegalArgumentException("Unknown picture mode")
                    val margin = json.getDouble("edgeInsetPercent")
                    require(margin.isFinite() && margin in 0.0..10.0 && margin == margin.toInt().toDouble()) { "Invalid screen margin" }
                    ui.setPresentation(PresentationSettings(mode, margin.toInt())) { display ->
                        if (!closed && running) try { scheduler.execute {
                            try { send(JSONObject().put("op", "presentation").put("display", display.json())) } catch (_: Exception) { closeSocket() }
                        } } catch (_: java.util.concurrent.RejectedExecutionException) { }
                    }
                }
                "start" -> {
                    require(!streaming) { "Stream already started" }
                    val surface = ui.surface()
                    if (surface == null || !surface.isValid) { error("decoder", "TV display is not ready. Reopen Miraya and try again."); return false }
                    val audioEnabled = json.optBoolean("audio", false)
                    sessionAudio = audioEnabled
                    val initialVolume = json.optDouble("volume", 1.0)
                    require(initialVolume.isFinite() && initialVolume in 0.0..1.0) { "Invalid audio level" }
                    volume = initialVolume.toFloat()
                    if (audioEnabled && !requestAudioFocus()) return false
                    transport = json.optString("transport", "tcp-v1")
                    require(transport == "tcp-v1" || transport == RtcSignaling.TRANSPORT) { "Unsupported media transport" }
                    if (transport == RtcSignaling.TRANSPORT) {
                        rtc = RtcMediaReceiver(context, surface, UUID.randomUUID().toString(), audioEnabled, volume, ui::onVideoSize,
                            { signal -> send(signal) }, { message ->
                                if (!failureReported && !closed) {
                                    failureReported = true; stopMessage = message; error("media", message); closeSocket()
                                }
                            }).also { it.setPicture(ui.displayInfo()) }
                    } else media = createMedia(audioEnabled, surface).also { it.setVolume(volume) }
                    streaming = true
                    statsTimer = scheduler.scheduleWithFixedDelay({
                        try {
                            val native = rtc
                            if (native != null) send(native.statistics().put("display", ui.displayInfo().json()))
                            else media?.let { send(JSONObject().put("op", "stats").put("frames", it.frames.get()).put("dropped", it.dropped.get())
                                .put("lastPts", it.lastPts.get()).put("lastDecodedPts", it.lastDecodedPts.get()).put("recoveries", it.recoveries.get()).put("audioFrames", it.audioFrames.get()).put("audioFramesWritten", it.audioFramesWritten.get())) }
                        } catch (_: Exception) { closeSocket() }
                    }, 250, 250, TimeUnit.MILLISECONDS)
                    ui.onStreaming(approvedName, true)
                    send(ready())
                }
                "pause" -> {
                    require(streaming && !paused && direct == null) { "Stream is not playing" }
                    if (rtc != null) rtc?.setPlayback(sessionAudio, true, volume) else { media?.close(); media = null }
                    paused = true; configReceived = false
                    audioFocus?.let { audioManager.abandonAudioFocusRequest(it) }; audioFocus = null
                    ui.onPaused(true); send(JSONObject().put("op", "paused"))
                }
                "resume", "reconfigure" -> {
                    require(streaming && direct == null && (paused || json.getString("op") == "reconfigure")) { "Stream is not paused" }
                    val surface = ui.surface()
                    require(surface != null && surface.isValid) { "TV display is unavailable" }
                    val audio = json.optBoolean("audio", sessionAudio)
                    if (audio && audioFocus == null && !requestAudioFocus()) return false
                    if (!audio && sessionAudio) {
                        audioFocus?.let { audioManager.abandonAudioFocusRequest(it) }; audioFocus = null
                    }
                    sessionAudio = audio
                    val gain = json.optDouble("volume", volume.toDouble())
                    require(gain.isFinite() && gain in 0.0..1.0) { "Invalid audio level" }
                    volume = gain.toFloat()
                    if (rtc != null) rtc?.setPlayback(audio, false, volume)
                    else { media?.close(); media = createMedia(audio, surface).also { it.setVolume(volume) } }
                    paused = false; configReceived = false
                    ui.onPaused(false); send(ready())
                }
                "rtcOffer", "rtcCandidate" -> {
                    require(streaming && rtc != null) { "Start native media before signaling" }
                    rtc!!.receive(json)
                }
                "setVolume" -> {
                    require(streaming) { "Stream has not started" }
                    val gain = json.getDouble("volume")
                    require(gain.isFinite() && gain in 0.0..1.0) { "Invalid audio level" }
                    volume = gain.toFloat(); media?.setVolume(volume); rtc?.setPlayback(sessionAudio, paused, volume)
                }
                "stop" -> {
                    stopMessage = "Sharing stopped. Connect from your Mac whenever you're ready."
                    send(JSONObject().put("op", "stopped")); return false
                }
                else -> { error("protocol", "Unknown control operation"); return false }
            }
            return true
        }
        private fun heartbeat() {
            if (closed) return
            try {
                if (System.nanoTime() - lastReceive > 10_000_000_000L) { stopMessage = "The connection was lost. Check Wi-Fi, then reconnect from your Mac."; closeSocket(); return }
                send(JSONObject().put("op", "ping").put("nonce", System.nanoTime() / 1_000_000L))
            } catch (_: Exception) { closeSocket() }
        }
        fun stopByUser() {
            stopMessage = "Sharing stopped on the TV. Start a new connection from your Mac to share again."
            // Closing the socket must always remain available even if the remote peer stops reading.
            Thread({ try { send(JSONObject().put("op", "stopped")) } catch (_: Exception) { } }, "Miraya stop").start()
            Thread({ Thread.sleep(100); closeSocket() }, "Miraya stop deadline").start()
            approval.countDown()
        }
        private fun closeSocket() { try { socket.close() } catch (_: Exception) { } }
        override fun close() {
            if (closed) return
            closed = true; approval.countDown(); timer?.cancel(false); statsTimer?.cancel(false); watchdog?.cancel(false); closeSocket()
            audioFocus?.let { try { audioManager.abandonAudioFocusRequest(it) } catch (_: Exception) { } }; audioFocus = null
            direct?.close(); direct = null; ui.onDirectPlayback(false)
            rtc?.close(); rtc = null; media?.close(); media = null
            ui.dismissApproval(); ui.onPairingCode(null)
            if (streaming && running) { ui.onStreaming(approvedName, false); ui.onStatus("Ready to share", stopMessage) }
            streaming = false
        }
    }

    override fun close() {
        running = false
        session?.close()
        try { listener?.close() } catch (_: Exception) { }
        clients.forEach { try { it.close() } catch (_: Exception) { } }
        scheduler.shutdownNow()
        deadlines.shutdownNow()
        registration?.let { try { nsd.unregisterService(it) } catch (_: Exception) { } }; registration = null
    }
    companion object {
        fun localAddresses(): String = try {
            NetworkInterface.getNetworkInterfaces().toList().filter { it.isUp && !it.isLoopback }
                .flatMap { it.inetAddresses.toList() }.filterIsInstance<Inet4Address>()
                .filter { !it.isLoopbackAddress && !it.isLinkLocalAddress }.joinToString("  •  ") { it.hostAddress ?: "" }.ifBlank { "No LAN address yet — connect this TV to Wi-Fi or Ethernet" }
        } catch (_: Exception) { "Check TV network settings for its IP address" }
    }
}

private fun TVDisplay.json() = JSONObject().put("width", width).put("height", height)
    .put("panelWidth", panelWidth).put("panelHeight", panelHeight).put("refreshRate", refreshRate)
    .put("mode", presentation.mode.wire).put("edgeInsetPercent", presentation.edgeInsetPercent)
