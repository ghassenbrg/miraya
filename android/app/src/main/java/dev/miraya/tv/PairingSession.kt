package dev.miraya.tv

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Locale

/** Cross-platform short authentication string with a nonce commitment. */
internal object PairingSession {
    const val METHOD = "sas6-v1"
    fun nonce(): String = ByteArray(32).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it) }
    fun validHex(value: String): Boolean = value.length == 64 && value.all { it in '0'..'9' || it in 'a'..'f' }
    private fun digest(value: String) = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
    fun commitment(nonce: String): String = digest("Miraya sender commitment v1\n$nonce").joinToString("") { "%02x".format(it) }
    fun code(fingerprint: String, clientId: String, senderNonce: String, receiverNonce: String): String {
        val bytes = digest(listOf("Miraya pairing SAS v1", fingerprint.lowercase(Locale.ROOT), clientId.lowercase(Locale.ROOT), senderNonce, receiverNonce).joinToString("\n"))
        val value = bytes.take(4).fold(0L) { result, byte -> (result shl 8) or (byte.toLong() and 255) }
        return String.format(Locale.ROOT, "%06d", value % 1_000_000)
    }
}
