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
        assertTrue("Receiver UI did not start", device.wait(Until.hasObject(By.textContains("Enter this TV code")), 15000))
        identity = Identity(context)
        Thread.sleep(750)
    }
    @After fun finish() { scenario.close(); identity.revokeAll(); Thread.sleep(300) }

    private inner class Client : AutoCloseable {
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
            socket = ssl.socketFactory.createSocket("127.0.0.1", 7421) as SSLSocket
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
        fun hello(clientId: String, token: String? = null, version: Int = 1) {
            send(JSONObject().put("op", "hello").put("version", version).put("clientId", clientId).put("name", "Integration test Mac").apply { if (token != null) put("token", token) })
        }
        override fun close() { socket.close() }
    }
    private fun trusted(): Pair<String, String> { val id = UUID.randomUUID().toString(); return id to identity.approve(id) }

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
        assertTrue(device.wait(Until.hasObject(By.textContains("Enter this TV code")), 4000))
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
