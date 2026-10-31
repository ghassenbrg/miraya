package dev.miraya.tv

import android.content.Context
import androidx.test.core.app.ActivityScenario
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.DataInputStream
import java.io.DataOutputStream
import java.security.MessageDigest
import java.security.cert.X509Certificate
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

/** Runs against the real foreground Activity, AndroidKeyStore TLS listener, codec and audio sink. */
@RunWith(AndroidJUnit4::class)
class ReceiverIntegrationTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.targetContext
    private val device = UiDevice.getInstance(instrumentation)
    private lateinit var scenario: ActivityScenario<MainActivity>
    private lateinit var identity: Identity

    @Before fun launch() {
        scenario = ActivityScenario.launch(MainActivity::class.java)
        assertTrue("Receiver UI did not start", device.wait(Until.hasObject(By.text("Ready for your Mac")), 15000))
        identity = Identity(context)
        Thread.sleep(750)
    }
    @After fun finish() { scenario.close(); identity.revokeAll(); Thread.sleep(300) }

    private inner class Client(port: Int = 7421) : AutoCloseable {
        val socket: SSLSocket
        private val input: DataInputStream
        private val output: DataOutputStream
        private var sequence = 0
        init {
            val expected = identity.pairingCode.replace("-", "")
            val trust = object : X509TrustManager {
                override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
                override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) = Unit
                override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                    val actual = MessageDigest.getInstance("SHA-256").digest(chain.first().encoded).joinToString("") { "%02X".format(it) }
                    check(actual.startsWith(expected)) { "TLS certificate does not match physical TV code" }
                }
            }
            val ssl = SSLContext.getInstance("TLS").apply { init(null, arrayOf<TrustManager>(trust), null) }
            socket = ssl.socketFactory.createSocket("127.0.0.1", port) as SSLSocket
            socket.soTimeout = 7000; socket.startHandshake()
            input = DataInputStream(socket.inputStream); output = DataOutputStream(socket.outputStream)
        }
        fun send(json: JSONObject) = packet(Wire.CONTROL, json.toString().toByteArray())
        fun packet(type: Int, payload: ByteArray, pts: Long = 0, flags: Int = 0) { Wire.write(output, Packet(type, flags, pts, payload, sequence++)) }
        fun next(): JSONObject {
            while (true) {
                val packet = Wire.read(input)
                assertEquals(Wire.CONTROL, packet.type)
                val json = JSONObject(String(packet.payload))
                if (json.optString("op") == "ping") {
                    try { send(JSONObject().put("op", "pong").put("nonce", json.optLong("nonce"))) } catch (_: java.io.IOException) { /* Read a final stopped/error already buffered before TLS close. */ }
                    continue
                }
                return json
            }
        }
        fun operation(expected: String): JSONObject {
            repeat(40) {
                val reply = next()
                if (reply.optString("op") != "stats" && reply.optString("op") != "requestKeyframe") {
                    assertEquals(expected, reply.optString("op")); return reply
                }
            }
            throw AssertionError("No $expected reply")
        }
        fun hello(clientId: String, token: String? = null, version: Int = 1) {
            send(JSONObject().put("op", "hello").put("version", version).put("clientId", clientId).put("name", "Integration test Mac").apply { if (token != null) put("token", token) })
        }
        override fun close() { socket.close() }
    }
    private fun trusted(): Pair<String, String> { val id = UUID.randomUUID().toString(); return id to identity.approve(id) }

    @Test fun directFilePlaybackRendersSeeksPausesAndSelectsSubtitlesOverTLS() {
        val bytes = instrumentation.context.assets.open("direct-playback.mp4").use { it.readBytes() }
        val subtitles = "WEBVTT\n\n00:00.000 --> 00:19.000\nMiraya subtitle fixture\n".toByteArray()
        val videoId = UUID.randomUUID().toString(); val subtitleId = UUID.randomUUID().toString(); val loadId = UUID.randomUUID().toString()
        val assets = mapOf(videoId to bytes, subtitleId to subtitles)
        val (id, token) = trusted()
        Client().use { client ->
            client.hello(id, token); assertTrue(client.operation("welcome").getJSONArray("features").toString().contains("direct-media-v1"))
            client.send(JSONObject().put("op", "mediaLoad").put("loadId", loadId).put("url", "miraya-file:///$videoId").put("mime", "video/mp4")
                .put("assets", JSONArray(assets.map { (assetId, data) -> JSONObject().put("id", assetId).put("size", data.size) }))
                .put("subtitle", JSONObject().put("url", "miraya-file:///$subtitleId").put("mime", "text/vtt")))
            var reads = 0
            fun next(): JSONObject {
                while (true) {
                    val reply = client.next()
                    if (reply.optString("op") == "mediaRead") {
                        val data = assets[reply.getString("id")] ?: throw AssertionError("Unselected file requested")
                        val offset = reply.getLong("offset"); val count = reply.getInt("count")
                        assertTrue(DirectMediaPolicy.validRead(offset, count, data.size.toLong()))
                        reads++
                        client.send(JSONObject().put("op", "mediaChunk").put("request", reply.getString("request"))
                            .put("data", android.util.Base64.encodeToString(data.copyOfRange(offset.toInt(), minOf(data.size, offset.toInt() + count)), android.util.Base64.NO_WRAP)))
                        continue
                    }
                    return reply
                }
            }
            fun state(predicate: (JSONObject) -> Boolean): JSONObject {
                val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20)
                var last = JSONObject()
                while (System.nanoTime() < deadline) {
                    last = next()
                    assertNotEquals("Unexpected playback error: $last", "error", last.optString("op"))
                    if (last.optString("op") == "mediaState") {
                        assertEquals(loadId, last.getString("loadId"))
                        if (predicate(last)) return last
                    }
                }
                throw AssertionError("Playback did not reach expected state: $last")
            }
            val playing = state { it.optBoolean("firstPicture") && it.optInt("frames") >= 10 && it.optInt("audioBuffers") > 0 && it.optLong("positionMs") > 500 }
            assertEquals(640, playing.getInt("width")); assertEquals(360, playing.getInt("height")); assertTrue(playing.getBoolean("seekable")); assertTrue(reads > 0)
            assertTrue("External subtitle track missing", playing.getJSONArray("tracks").toString().contains("External subtitles"))
            // Exercise the real TV overlay against a decoded file, not a mock player.
            if (device.findObject(By.desc("Pause")) == null) device.pressDPadCenter()
            val tvPause = device.wait(Until.findObject(By.desc("Pause")), 3000)
            assertNotNull("Native TV pause control is missing", tvPause); tvPause.click()
            state { it.optString("state") == "paused" }
            val tvResume = device.wait(Until.findObject(By.desc("Resume")), 3000)
            assertNotNull("TV pause did not become Resume", tvResume)
            val screen = java.io.File(context.getExternalFilesDir(null), "beam-tv-direct-paused.png")
            assertTrue(device.takeScreenshot(screen))
            device.executeShellCommand("mkdir -p /sdcard/Download/miraya-beam-review")
            device.executeShellCommand("cp ${screen.absolutePath} /sdcard/Download/miraya-beam-review/${screen.name}")
            tvResume.click(); state { it.optString("state") == "playing" }
            val playback = device.wait(Until.findObject(By.desc("Playback")), 3000)
            assertNotNull(playback); playback.click()
            assertNotNull(device.wait(Until.findObject(By.text("Playback controls")), 3000))
            assertNotNull(device.findObject(By.desc("Video playback position")))
            device.pressBack()
            assertNotNull("Closing playback settings stopped the stream", device.wait(Until.findObject(By.desc("Pause")), 3000))
            fun command(action: String, extra: JSONObject = JSONObject()) { client.send(extra.put("op", "mediaCommand").put("loadId", loadId).put("action", action)) }
            command("pause"); val paused = state { it.optString("state") == "paused" }
            val held = state { it.optString("state") == "paused" && it.optLong("positionMs") >= paused.getLong("positionMs") }
            assertTrue("Paused playback kept advancing", held.getLong("positionMs") - paused.getLong("positionMs") < 200)
            command("seek", JSONObject().put("positionMs", 7000)); state { it.optLong("positionMs") in 6800..7500 && it.optString("state") == "paused" }
            command("track", JSONObject().put("kind", "text").put("track", "off"))
            state { message -> (0 until message.getJSONArray("tracks").length()).none { index -> val track = message.getJSONArray("tracks").getJSONObject(index); track.optString("kind") == "text" && track.optBoolean("selected") } }
            command("track", JSONObject().put("kind", "text").put("track", "auto"))
            state { message -> (0 until message.getJSONArray("tracks").length()).any { index -> val track = message.getJSONArray("tracks").getJSONObject(index); track.optString("kind") == "text" && track.optBoolean("selected") } }
            command("volume", JSONObject().put("volume", 0.25)); command("play")
            state { it.optString("state") == "playing" && it.optLong("positionMs") > 7500 }
            client.send(JSONObject().put("op", "stop"))
            var stopped = false
            // Stop closes the TLS stream after its acknowledgement. Do not
            // answer an earlier buffered range request after that close.
            repeat(20) { if (!stopped) stopped = client.next().optString("op") == "stopped" }
            assertTrue("Direct playback did not acknowledge stop", stopped)
        }
        assertTrue(device.wait(Until.hasObject(By.text("Ready for your Mac")), 5000))
    }

    @Test fun directPlaybackRejectsUnsafeAddressesAndUnselectedFiles() {
        for (address in listOf("file:///data/data/dev.miraya.tv/shared_prefs/identity.xml", "content://settings/system", "http://example.com/video.mp4", "miraya-file:///${UUID.randomUUID()}")) {
            val (id, token) = trusted()
            Client().use { client ->
                client.hello(id, token); client.operation("welcome")
                client.send(JSONObject().put("op", "mediaLoad").put("loadId", UUID.randomUUID().toString()).put("url", address))
                assertEquals("protocol", client.operation("error").getString("code"))
            }
            Thread.sleep(300)
        }
    }

    @Test fun directPlaybackRequiresAuthentication() {
        Client().use { client ->
            client.send(JSONObject().put("op", "mediaLoad").put("loadId", UUID.randomUUID().toString()).put("url", "https://example.com/video.mp4"))
            assertEquals("protocol", client.operation("error").getString("code"))
        }
    }

    @Test fun reportsTVViewportAndAppliesPictureControlsWithoutMediaRestart() {
        val (id, token) = trusted()
        Client().use { client ->
            client.hello(id, token)
            val welcome = client.operation("welcome")
            val display = welcome.getJSONObject("display")
            assertTrue(display.getInt("width") > 0); assertTrue(display.getInt("height") > 0)
            client.send(JSONObject().put("op", "start").put("transport", RtcSignaling.TRANSPORT).put("audio", false))
            val session = client.operation("ready").getString("session")
            for (mode in listOf("fit", "fill", "stretch", "fit")) {
                client.send(JSONObject().put("op", "setPresentation").put("mode", mode).put("edgeInsetPercent", if (mode == "fit") 0 else 5))
                val applied = client.operation("presentation").getJSONObject("display")
                assertEquals(mode, applied.getString("mode"))
            }
            client.send(JSONObject().put("op", "pause")); client.operation("paused")
            client.send(JSONObject().put("op", "resume")); assertEquals(session, client.operation("ready").getString("session"))
            client.send(JSONObject().put("op", "stop")); client.operation("stopped")
        }
    }

    @Test fun rejectsInvalidPictureModeAndMargin() {
        for ((mode, margin) in listOf("execute" to 0, "fit" to 11, "fit" to -1)) {
            val (id, token) = trusted()
            Client().use { client ->
                client.hello(id, token); client.operation("welcome")
                client.send(JSONObject().put("op", "setPresentation").put("mode", mode).put("edgeInsetPercent", margin))
                assertEquals("protocol", client.operation("error").getString("code"))
            }
            Thread.sleep(250)
        }
    }

    @Test fun nativeMediaControlsRetainSessionAndRejectStaleSignals() {
        val (id, token) = trusted()
        Client().use { client ->
            client.hello(id, token)
            assertTrue(client.operation("welcome").getJSONArray("transports").toString().contains(RtcSignaling.TRANSPORT))
            client.send(JSONObject().put("op", "start").put("transport", RtcSignaling.TRANSPORT).put("audio", false))
            val session = client.operation("ready").getString("session")
            assertNotNull(UUID.fromString(session))
            client.send(JSONObject().put("op", "pause")); client.operation("paused")
            client.send(JSONObject().put("op", "resume").put("audio", true).put("volume", 0.5))
            assertEquals(session, client.operation("ready").getString("session"))
            client.send(JSONObject().put("op", "reconfigure").put("audio", false))
            assertEquals(session, client.operation("ready").getString("session"))
            client.send(JSONObject().put("op", "rtcCandidate").put("session", UUID.randomUUID().toString())
                .put("candidate", "candidate:1 1 udp 1 127.0.0.1 5678 typ host").put("mid", "0").put("index", 0))
            assertEquals("protocol", client.operation("error").getString("code"))
        }
    }

    @Test fun nativeSessionRejectsReliableMediaPackets() {
        val (id, token) = trusted()
        Client().use { client ->
            client.hello(id, token); client.operation("welcome")
            client.send(JSONObject().put("op", "start").put("transport", RtcSignaling.TRANSPORT).put("audio", false)); client.operation("ready")
            client.packet(Wire.VIDEO, byteArrayOf(0, 0, 0, 1, 0x65), flags = 1)
            assertEquals("protocol", client.operation("error").getString("code"))
        }
    }

    @Test fun rejectsNativeSignalingBeforeStart() {
        val (id, token) = trusted()
        Client().use { client ->
            client.hello(id, token); client.operation("welcome")
            client.send(JSONObject().put("op", "rtcOffer").put("session", UUID.randomUUID().toString()).put("sdp", "invalid"))
            assertEquals("protocol", client.operation("error").getString("code"))
        }
    }

    @Test fun sixDigitPairingRequiresComparisonThenRemoteApprovalAndSupportsIndividualRevocation() {
        val id = UUID.randomUUID().toString()
        val senderNonce = PairingSession.nonce()
        var token = ""
        Client().use { client ->
            client.send(JSONObject().put("op", "hello").put("version", 1).put("clientId", id).put("name", "Six-digit Mac")
                .put("pairing", PairingSession.METHOD).put("commitment", PairingSession.commitment(senderNonce)))
            val challenge = client.next(); assertEquals("pairChallenge", challenge.getString("op"))
            val code = PairingSession.code(identity.fingerprint, id, senderNonce, challenge.getString("nonce"))
            assertEquals(6, code.length)
            client.send(JSONObject().put("op", "pairReveal").put("nonce", senderNonce))
            assertEquals("code", client.next().getString("stage"))
            assertNotNull("TV did not display the same six-digit code", device.wait(Until.findObject(By.text(code.chunked(3).joinToString(" "))), 3000))
            assertNull("Approval appeared before comparison confirmation", device.findObject(By.text("Allow")))
            assertNull("Unconfirmed client was trusted", identity.tokenFor(id))
            client.send(JSONObject().put("op", "pairConfirm"))
            assertEquals("approval", client.next().getString("stage"))
            val allow = device.wait(Until.findObject(By.text("Allow")), 3000)
            assertNotNull(allow); allow.click()
            val welcome = client.next(); assertEquals("welcome", welcome.getString("op")); token = welcome.getString("token")
            client.send(JSONObject().put("op", "stop")); assertEquals("stopped", client.next().getString("op"))
        }
        assertEquals("Six-digit Mac", identity.trustedMacs().first { it.id == id }.name)
        Thread.sleep(300)
        Client().use { it.hello(id, token); assertEquals("welcome", it.next().getString("op")) }
        Thread.sleep(300)
        val (otherId, otherToken) = trusted()
        identity.revoke(id)
        assertNull(identity.tokenFor(id)); assertEquals(otherToken, identity.tokenFor(otherId))
        Client().use { it.hello(id, token); assertEquals("auth", it.next().getString("code")) }
    }

    @Test fun rejectsChangedPairingCommitmentBeforeTrustOrApproval() {
        val id = UUID.randomUUID().toString()
        Client().use { client ->
            client.send(JSONObject().put("op", "hello").put("version", 1).put("clientId", id).put("name", "Invalid reveal")
                .put("pairing", PairingSession.METHOD).put("commitment", PairingSession.commitment("01".repeat(32))))
            assertEquals("pairChallenge", client.next().getString("op"))
            client.send(JSONObject().put("op", "pairReveal").put("nonce", "02".repeat(32)))
            assertEquals("protocol", client.next().getString("code"))
            assertNull(identity.tokenFor(id)); assertNull(device.findObject(By.text("Allow")))
        }
    }

    @Test fun liveAudioVolumePauseAndReconfigureKeepTheAuthorizedSession() {
        val (id, token) = trusted()
        Client().use { client ->
            client.hello(id, token); client.operation("welcome")
            client.send(JSONObject().put("op", "start").put("audio", false)); client.operation("ready")
            client.send(JSONObject().put("op", "setVolume").put("volume", 0.35))
            client.send(JSONObject().put("op", "pause")); client.operation("paused")
            client.send(JSONObject().put("op", "resume").put("audio", true).put("volume", 0.5)); client.operation("ready")
            client.send(JSONObject().put("op", "reconfigure").put("audio", false).put("volume", 0.0)); client.operation("ready")
            client.send(JSONObject().put("op", "pause")); client.operation("paused")
            client.send(JSONObject().put("op", "resume").put("audio", true)); client.operation("ready")
            client.send(JSONObject().put("op", "stop")); client.operation("stopped")
        }
    }

    @Test fun liveQualityChangeRendersNewResolutionAndEnablesAudio() {
        val assets = instrumentation.context.assets
        assumeTrue("Generate the 720p fixture first", assets.list("720p")?.contains("config.json") == true)
        val (id, token) = trusted()
        Client().use { client ->
            client.hello(id, token); client.operation("welcome")
            client.send(JSONObject().put("op", "start").put("audio", false)); client.operation("ready")
            fun play(folder: String, offset: Long, count: Int, audio: Boolean) {
                client.packet(Wire.CONFIG, assets.open(folder + "config.json").readBytes())
                val frames = JSONArray(String(assets.open(folder + "frames.json").readBytes()))
                val start = System.nanoTime()
                repeat(count) { index ->
                    val frame = frames.getJSONObject(index)
                    val pts = frame.getLong("pts")
                    val delay = start + pts * 1000 - System.nanoTime()
                    if (delay > 0) TimeUnit.NANOSECONDS.sleep(delay)
                    client.packet(Wire.VIDEO, assets.open(folder + frame.getString("file")).readBytes(), offset + pts, if (frame.getBoolean("keyframe")) 1 else 0)
                    if (audio) client.packet(Wire.AUDIO, ByteArray(6400), offset + pts)
                }
                val until = System.nanoTime() + 4_000_000_000L
                while (System.nanoTime() < until) {
                    val reply = client.next()
                    assertNotEquals("error", reply.optString("op"))
                    if (reply.optString("op") == "stats" && reply.optLong("lastPts", -1) >= offset + (count - 3) * 1_000_000 / 30 && (!audio || reply.optLong("audioFrames") > 0)) return
                }
                throw AssertionError("New media configuration did not play")
            }
            play("", 1_000_000, 30, false)
            client.send(JSONObject().put("op", "reconfigure").put("audio", true).put("volume", 0.25)); client.operation("ready")
            play("720p/", 10_000_000, 75, true)
            client.send(JSONObject().put("op", "setVolume").put("volume", 0.0))
            client.send(JSONObject().put("op", "pause")); client.operation("paused")
            client.send(JSONObject().put("op", "resume").put("audio", false)); client.operation("ready")
            play("", 20_000_000, 30, false)
            client.send(JSONObject().put("op", "stop")); client.operation("stopped")
        }
    }

    @Test fun rejectsMediaBeforeAuthenticationAndIncompatibleVersion() {
        Client().use { it.packet(Wire.VIDEO, byteArrayOf(0, 0, 0, 1, 0x65), flags = 1); assertEquals("protocol", it.next().getString("code")) }
        Client().use { it.hello(UUID.randomUUID().toString(), version = 9); assertEquals("version", it.next().getString("code")) }
    }
    @Test fun rejectsInvalidTokenAndMediaBeforeStart() {
        val (id, token) = trusted()
        Client().use { it.hello(id, "incorrect"); assertEquals("auth", it.next().getString("code")) }
        Client().use {
            it.hello(id, token); assertEquals("welcome", it.next().getString("op"))
            it.packet(Wire.VIDEO, byteArrayOf(0, 0, 0, 1, 0x65), flags = 1)
            assertEquals("protocol", it.next().getString("code"))
        }
    }
    @Test fun tvRemoteApprovesNewMacThenReusesAuthorization() {
        val id = UUID.randomUUID().toString()
        var token = ""
        Client().use {
            it.hello(id); assertEquals("pending", it.next().getString("op"))
            val allow = device.wait(Until.findObject(By.text("Allow")), 5000)
            assertNotNull("TV approval did not appear", allow); allow.click()
            val welcome = it.next(); assertEquals("welcome", welcome.getString("op")); token = welcome.getString("token")
            assertTrue(token.length >= 40)
            it.send(JSONObject().put("op", "stop")); assertEquals("stopped", it.next().getString("op"))
        }
        Thread.sleep(300)
        Client().use { it.hello(id, token); assertEquals("welcome", it.next().getString("op")) }
    }
    @Test fun nativeVideoAudioDecodeAndRemoteStop() {
        val assets = instrumentation.context.assets
        assumeTrue("Generate fixture first with tools/capture/test-capture.sh", assets.list("")?.contains("config.json") == true)
        val (id, token) = trusted()
        Client().use { client ->
            client.hello(id, token); assertEquals("welcome", client.next().getString("op"))
            client.send(JSONObject().put("op", "start").put("audio", true)); assertEquals("ready", client.next().getString("op"))
            client.packet(Wire.CONFIG, assets.open("config.json").readBytes())
            val frames = JSONArray(String(assets.open("frames.json").readBytes()))
            val start = System.nanoTime()
            repeat(minOf(frames.length(), 75)) { index ->
                val frame = frames.getJSONObject(index); val pts = frame.getLong("pts")
                val wait = start + pts * 1000 - System.nanoTime(); if (wait > 0) Thread.sleep(wait / 1_000_000, (wait % 1_000_000).toInt())
                client.packet(Wire.VIDEO, assets.open(frame.getString("file")).readBytes(), pts, if (frame.getBoolean("keyframe")) 1 else 0)
                client.packet(Wire.AUDIO, ByteArray(6400), pts)
            }
            var rendered = 0L; var audioPlayed = 0L
            val deadline = System.nanoTime() + 5_000_000_000L
            while ((rendered == 0L || audioPlayed == 0L) && System.nanoTime() < deadline) {
                val stats = client.next()
                if (stats.optString("op") == "requestKeyframe") continue // fixture has periodic IDRs; the native sender responds immediately.
                assertEquals("stats", stats.getString("op"))
                rendered = maxOf(rendered, stats.getLong("frames")); audioPlayed = maxOf(audioPlayed, stats.optLong("audioFrames"))
            }
            assertTrue("Decoder did not render frames", rendered > 0)
            assertTrue("AudioTrack did not play PCM frames", audioPlayed > 0)
            device.pressBack()
            var stopped = false
            repeat(20) { if (!stopped) stopped = client.next().optString("op") == "stopped" }
            assertTrue("Remote Back did not stop sharing", stopped)
        }
        assertTrue(device.wait(Until.hasObject(By.text("Ready for your Mac")), 4000))
    }
    @Test fun receiverRejectsUnsupportedResolutionAndStaysAvailable() {
        val (id, token) = trusted()
        Client().use {
            it.hello(id, token); assertEquals("welcome", it.next().getString("op"))
            it.send(JSONObject().put("op", "start").put("audio", false)); assertEquals("ready", it.next().getString("op"))
            it.packet(Wire.CONFIG, JSONObject().put("width", 3840).put("height", 2160).put("fps", 30).put("sps", "AA==").put("pps", "AA==").toString().toByteArray())
            assertEquals("error", it.next().getString("op"))
        }
        Thread.sleep(300)
        Client().use { it.hello(id, token); assertEquals("welcome", it.next().getString("op")) }
    }
    @Test fun playbackRecoversFromJitterOverflowAndIdleWithoutReconnecting() {
        val assets = instrumentation.context.assets
        assumeTrue("Generate fixture first with tools/capture/test-capture.sh", assets.list("")?.contains("config.json") == true)
        val fixture = JSONArray(String(assets.open("frames.json").readBytes()))
        val packets = (0 until fixture.length()).map { index ->
            val frame = fixture.getJSONObject(index)
            Packet(Wire.VIDEO, if (frame.getBoolean("keyframe")) 1 else 0, frame.getLong("pts"), assets.open(frame.getString("file")).readBytes())
        }
        val (id, token) = trusted()
        Client().use { client ->
            client.hello(id, token); assertEquals("welcome", client.next().getString("op"))
            client.send(JSONObject().put("op", "start").put("audio", false)); assertEquals("ready", client.next().getString("op"))
            client.packet(Wire.CONFIG, assets.open("config.json").readBytes())
            fun play(offset: Long, jitter: Boolean = false) {
                val start = System.nanoTime()
                for ((index, packet) in packets.withIndex()) {
                    if (jitter && index == 15) Thread.sleep(350)
                    val target = start + packet.pts * 1000 + if (jitter && index >= 15) 350_000_000L else 0
                    val delay = target - System.nanoTime()
                    if (delay > 0) TimeUnit.NANOSECONDS.sleep(delay)
                    client.packet(Wire.VIDEO, packet.payload, offset + packet.pts, packet.flags)
                }
            }
            fun awaitProgress(target: Long): JSONObject {
                val end = System.nanoTime() + 4_000_000_000L
                var lastStats = "No statistics received"
                while (System.nanoTime() < end) {
                    val reply = client.next()
                    assertNotEquals("Unexpected disconnect/error: $reply", "error", reply.optString("op"))
                    if (reply.optString("op") == "stats") lastStats = reply.toString()
                    if (reply.optString("op") == "stats" && reply.optLong("lastPts", -1) >= target) return reply
                }
                throw AssertionError("Video did not recover to PTS $target: $lastStats")
            }
            play(0, jitter = true)
            val afterJitter = awaitProgress(2_800_000)
            assertTrue("Jitter permanently suppressed presentation", afterJitter.getLong("frames") > 60)
            // Keep the authenticated session alive through an unchanged desktop.
            val until = System.nanoTime() + 6_000_000_000L
            while (System.nanoTime() < until) {
                client.send(JSONObject().put("op", "ping").put("nonce", 1))
                assertNotEquals("error", client.next().optString("op"))
                Thread.sleep(200)
            }
            // Deliver a burst to force bounded-queue IDR recovery, then resume
            // paced playback on the very same TLS session and decoder Surface.
            for (packet in packets) client.packet(Wire.VIDEO, packet.payload, 10_000_000 + packet.pts, packet.flags)
            play(13_000_000)
            val recovered = awaitProgress(15_800_000)
            assertTrue("No frames presented after idle/overflow", recovered.getLong("frames") > afterJitter.getLong("frames") + 50)
            client.send(JSONObject().put("op", "stop"))
            var stopped = false
            repeat(20) { if (!stopped) stopped = client.next().optString("op") == "stopped" }
            assertTrue("Receiver did not confirm stop", stopped)
        }
    }
    @Test fun tvRemoteDeclinesAndConcurrentConnectionIsBusy() {
        Client().use { first ->
            first.hello(UUID.randomUUID().toString()); assertEquals("pending", first.next().getString("op"))
            Client().use { other -> other.hello(UUID.randomUUID().toString()); assertEquals("busy", other.next().getString("code")) }
            val decline = device.wait(Until.findObject(By.text("Decline")), 5000)
            assertNotNull(decline); decline.click()
            assertEquals("denied", first.next().getString("code"))
        }
    }
    @Test fun backgroundClosesSessionAndRestartRetainsTrust() {
        val (id, token) = trusted()
        val code = identity.pairingCode
        Client().use {
            it.hello(id, token); assertEquals("welcome", it.next().getString("op"))
            scenario.moveToState(Lifecycle.State.CREATED)
            try { it.next(); fail("Background receiver left session alive") } catch (_: java.io.IOException) { }
        }
        scenario.moveToState(Lifecycle.State.RESUMED)
        Thread.sleep(750)
        assertEquals(code, Identity(context).pairingCode)
        Client().use { it.hello(id, token); assertEquals("welcome", it.next().getString("op")) }
    }
    @Test fun roomNamePersistsAndAppearsInWelcome() {
        val original = identity.name
        val rename = device.wait(Until.findObject(By.text("Rename TV")), 3000)
        assertNotNull(rename); rename.click()
        val bedroom = device.wait(Until.findObject(By.text("Bedroom TV")), 3000)
        assertNotNull(bedroom); bedroom.click()
        assertTrue(device.wait(Until.hasObject(By.text("Bedroom TV")), 3000))
        Thread.sleep(500)
        assertEquals("Bedroom TV", Identity(context).name)
        val (id, token) = trusted()
        Client().use { it.hello(id, token); assertEquals("Bedroom TV", it.next().getString("name")) }
        Identity(context).rename(original)
    }
}
