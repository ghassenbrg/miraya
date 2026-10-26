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
        fun dismissApproval()
        fun surface(): Surface?
        fun onStreaming(name: String, streaming: Boolean)
        fun onVideoSize(width: Int, height: Int)
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
    fun revokeTrust() { session?.stopByUser(); identity.revokeAll() }

    private inner class Session(private val socket: SSLSocket) : AutoCloseable {
        private val input = DataInputStream(socket.inputStream)
        private val output = DataOutputStream(socket.outputStream)
        private val sequence = AtomicInteger()
        @Volatile private var closed = false
        @Volatile private var lastReceive = System.nanoTime()
        @Volatile private var streaming = false
        private var media: MediaPipeline? = null
        private var timer: java.util.concurrent.ScheduledFuture<*>? = null
        private var statsTimer: java.util.concurrent.ScheduledFuture<*>? = null
        private var watchdog: java.util.concurrent.ScheduledFuture<*>? = null
        @Volatile private var writeStarted = 0L
        private var approvedName = "Mac"
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
                            media?.silenceAudio()
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
                val clientId = UUID.fromString(hello.getString("clientId")).toString()
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
                    send(JSONObject().put("op", "pending"))
                    ui.approve(approvedName) { allow -> accepted = allow; approval.countDown() }
                    val answered = approval.await(30, TimeUnit.SECONDS)
                    ui.dismissApproval()
                    if (!running || closed) return
                    if (!answered) { error("timeout", "TV approval timed out. Try again and choose Allow on your TV."); return }
                    if (!accepted) { error("denied", "The TV declined this connection."); return }
                    token = identity.approve(clientId)
                }
                send(JSONObject().put("op", "welcome").put("version", 1).put("receiverId", identity.receiverId)
                    .put("name", identity.name).put("token", token).put("maxWidth", 1920).put("maxHeight", 1080))
                socket.soTimeout = 10000; lastReceive = System.nanoTime()
                timer = scheduler.scheduleWithFixedDelay({ heartbeat() }, 2, 2, TimeUnit.SECONDS)
                while (running && !closed) {
                    val packet = Wire.read(input); lastReceive = System.nanoTime()
                    when (packet.type) {
                        Wire.CONTROL -> if (!control(JSONObject(String(packet.payload, Charsets.UTF_8)))) return
                        Wire.CONFIG -> {
                            require(streaming) { "Stream has not started" }
                            media!!.configure(JSONObject(String(packet.payload, Charsets.UTF_8))); configReceived = true
                        }
                        Wire.VIDEO -> { require(streaming && configReceived) { "Video arrived before configuration" }; media!!.video(packet) }
                        Wire.AUDIO -> { require(streaming) { "Audio arrived before start" }; media!!.audio(packet) }
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

        private fun control(json: JSONObject): Boolean {
            when (json.getString("op")) {
                "ping" -> send(JSONObject().put("op", "pong").put("nonce", json.optLong("nonce")))
                "pong" -> Unit
                "start" -> {
                    require(!streaming) { "Stream already started" }
                    val surface = ui.surface()
                    if (surface == null || !surface.isValid) { error("decoder", "TV display is not ready. Reopen Miraya and try again."); return false }
                    val audioEnabled = json.optBoolean("audio", false)
                    if (audioEnabled && !requestAudioFocus()) return false
                    media = MediaPipeline(surface, audioEnabled, ui::onVideoSize, { message ->
                        if (!failureReported) {
                            failureReported = true; stopMessage = message; error("decoder", message); closeSocket()
                        }
                    }, { try { send(JSONObject().put("op", "requestKeyframe")) } catch (_: Exception) { closeSocket() } })
                    streaming = true
                    statsTimer = scheduler.scheduleWithFixedDelay({
                        try {
                            media?.let { send(JSONObject().put("op", "stats").put("frames", it.frames.get()).put("dropped", it.dropped.get())
                                .put("lastPts", it.lastPts.get()).put("audioFrames", it.audioFrames.get()).put("audioFramesWritten", it.audioFramesWritten.get())) }
                        } catch (_: Exception) { closeSocket() }
                    }, 250, 250, TimeUnit.MILLISECONDS)
                    ui.onStreaming(approvedName, true)
                    send(JSONObject().put("op", "ready"))
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
            media?.close(); media = null
            ui.dismissApproval()
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
