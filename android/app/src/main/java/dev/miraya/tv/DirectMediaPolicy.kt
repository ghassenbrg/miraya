package dev.miraya.tv

import java.net.URI
import java.util.UUID

internal object DirectMediaPolicy {
    const val CHUNK = 32768
    fun validId(value: String) = try { UUID.fromString(value).toString().equals(value, ignoreCase = true) } catch (_: IllegalArgumentException) { false }
    fun validRemote(value: String): Boolean = try {
        val uri = URI(value)
        value.length <= 8192 && uri.scheme.equals("https", true) && !uri.host.isNullOrBlank() && uri.userInfo == null
    } catch (_: Exception) { false }
    fun validRead(offset: Long, count: Int, size: Long) = size > 0 && offset in 0..size && count in 1..CHUNK
}
