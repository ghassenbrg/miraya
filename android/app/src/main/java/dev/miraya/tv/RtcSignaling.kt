package dev.miraya.tv

/** Only DTLS-SRTP media and direct UDP ICE candidates, carried by authenticated TLS. */
internal object RtcSignaling {
    const val TRANSPORT = "webrtc-udp-v1"
    /** Opus stereo is directional: the receiver must request it in its answer. */
    fun stereoOpus(sdp: String): String {
        val lines = sdp.split("\r\n")
        val payloads = lines.filter { it.startsWith("a=rtpmap:") && it.contains(" opus/48000/", true) }
            .map { it.removePrefix("a=rtpmap:").substringBefore(' ') }
        return lines.joinToString("\r\n") { line ->
            val payload = payloads.firstOrNull { line.startsWith("a=fmtp:$it ") }
            if (payload == null) line else {
                val prefix = "a=fmtp:$payload "
                val values = line.removePrefix(prefix).split(';').filter { it.substringBefore('=').trim() !in listOf("stereo", "sprop-stereo", "maxaveragebitrate", "usedtx") }
                prefix + (values + listOf("stereo=1", "sprop-stereo=1", "maxaveragebitrate=192000", "usedtx=0")).joinToString(";")
            }
        }
    }
    fun validateSdp(sdp: String) {
        require(sdp.toByteArray(Charsets.UTF_8).size <= 32768 && (sdp.startsWith("v=0\r\n") || sdp.startsWith("v=0\n"))) { "Invalid media description" }
        val lines = sdp.lines()
        val media = lines.filter { it.startsWith("m=") }
        val fingerprints = lines.filter { it.startsWith("a=fingerprint:") }
        require(media.isNotEmpty() && media.size <= 2 && media.all {
            (it.startsWith("m=video ") || it.startsWith("m=audio ")) && it.contains("UDP/TLS/RTP/SAVPF")
        } && media.count { it.startsWith("m=video ") } == 1 && media.count { it.startsWith("m=audio ") } <= 1 &&
            fingerprints.isNotEmpty() && fingerprints.all { it.matches(Regex("a=fingerprint:sha-256 ([0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}")) } &&
            lines.any { it.startsWith("a=ice-ufrag:") } && lines.any { it.startsWith("a=ice-pwd:") }) { "Encrypted audio/video required" }
        lines.filter { it.startsWith("a=candidate:") }.forEach { validateCandidate(it.drop(2), null, 0) }
    }
    fun validateCandidate(sdp: String, mid: String?, index: Int) {
        val fields = sdp.split(Regex("[ \\t]+"))
        require(sdp.toByteArray(Charsets.UTF_8).size <= 4096 && !sdp.contains('\r') && !sdp.contains('\n') && index in 0..1 && (mid?.length ?: 0) <= 64 && (mid == null || mid.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '-' || it == '_' }) &&
            fields.size >= 8 && fields[0].startsWith("candidate:") && fields[2].equals("udp", true) &&
            (fields[5].toIntOrNull() ?: 0) in 1..65535 && fields[6] == "typ" && fields[7] in listOf("host", "prflx")) { "Only direct UDP media candidates are supported" }
    }
}
