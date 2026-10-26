package dev.miraya.tv

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.spec.ECGenParameterSpec
import java.util.Date
import java.util.UUID
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.security.auth.x500.X500Principal

class Identity(context: Context) {
    private val prefs = context.getSharedPreferences("identity", Context.MODE_PRIVATE)
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    val receiverId: String = prefs.getString("id", null) ?: UUID.randomUUID().toString().also { prefs.edit().putString("id", it).commit() }
    @Volatile var name: String = prefs.getString("name", null) ?: "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}".take(32)
        private set
    val hasCustomName: Boolean get() = prefs.contains("name")
    val sslContext: SSLContext
    val pairingCode: String

    init {
        if (!keyStore.containsAlias(ALIAS)) {
            val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
            generator.initialize(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                // Conscrypt hashes TLS transcripts itself and delegates a raw ECDSA signature to Keystore.
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_NONE, KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA384, KeyProperties.DIGEST_SHA512)
                .setCertificateSubject(X500Principal("CN=Miraya TV"))
                .setCertificateSerialNumber(BigInteger(128, SecureRandom()))
                .setCertificateNotBefore(Date(1577836800000L)).setCertificateNotAfter(Date(4102444800000L)).build())
            generator.generateKeyPair()
        }
        val fingerprint = MessageDigest.getInstance("SHA-256").digest(keyStore.getCertificate(ALIAS).encoded).joinToString("") { "%02X".format(it) }
        pairingCode = fingerprint.take(16).chunked(4).joinToString("-")
        val factory = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
        factory.init(keyStore, null)
        sslContext = SSLContext.getInstance("TLS").apply { init(factory.keyManagers, null, SecureRandom()) }
    }

    @Synchronized fun tokenFor(clientId: String): String? = prefs.getString("client.$clientId", null)
    @Synchronized fun approve(clientId: String): String {
        val token = Base64.encodeToString(ByteArray(32).also { SecureRandom().nextBytes(it) }, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        check(prefs.edit().putString("client.$clientId", token).commit()) { "Could not save trusted Mac" }
        return token
    }
    @Synchronized fun revokeAll() { prefs.edit().apply { prefs.all.keys.filter { it.startsWith("client.") }.forEach { remove(it) } }.commit() }
    @Synchronized fun rename(value: String) {
        val cleaned = value.trim()
        require(cleaned.length in 1..32 && cleaned.none { it.isISOControl() }) { "Choose a name between 1 and 32 characters" }
        check(prefs.edit().putString("name", cleaned).commit()) { "Could not save TV name" }
        name = cleaned
    }
    fun tokenMatches(stored: String, supplied: String): Boolean = MessageDigest.isEqual(stored.toByteArray(Charsets.UTF_8), supplied.toByteArray(Charsets.UTF_8))
    companion object { private const val ALIAS = "miraya.receiver.tls.v1.ec" }
}
