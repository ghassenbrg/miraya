package dev.miraya.tv

import org.junit.Assert.*
import org.junit.Test

class RtcSignalingTest {
    @Test fun receiverRequestsStereoAndPreservesPayloadIds() {
        val sdp = "a=rtpmap:111 opus/48000/2\r\na=fmtp:111 minptime=10;useinbandfec=1\r\na=fmtp:96 packetization-mode=1\r\n"
        val result = RtcSignaling.stereoOpus(sdp)
        assertTrue(result.contains("a=fmtp:111 minptime=10;useinbandfec=1;stereo=1;sprop-stereo=1;maxaveragebitrate=192000;usedtx=0"))
        assertTrue(result.contains("a=fmtp:96 packetization-mode=1"))
        assertEquals(result, RtcSignaling.stereoOpus(result))
    }
    private fun rejects(block: () -> Unit) { try { block(); fail("Invalid media signal accepted") } catch (_: IllegalArgumentException) {} }
    @Test fun onlyEncryptedMediaDescriptions() {
        val sdp = "v=0\r\na=ice-ufrag:example\r\na=ice-pwd:example\r\na=fingerprint:sha-256 AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\n"
        RtcSignaling.validateSdp(sdp)
        rejects { RtcSignaling.validateSdp(sdp.replace("UDP/TLS/RTP/SAVPF", "RTP/AVP")) }
        rejects { RtcSignaling.validateSdp(sdp.replace("m=video", "m=application")) }
        rejects { RtcSignaling.validateSdp(sdp + "x".repeat(32768)) }
    }
    @Test fun onlyDirectUdpCandidatesAndValidMlines() {
        val candidate = "candidate:1 1 udp 2122260223 192.168.1.10 54321 typ host generation 0"
        RtcSignaling.validateCandidate(candidate, "0", 0)
        RtcSignaling.validateCandidate(candidate.replace("typ host", "typ prflx"), "1", 1)
        rejects { RtcSignaling.validateCandidate(candidate.replace(" udp ", " tcp "), "0", 0) }
        rejects { RtcSignaling.validateCandidate(candidate.replace("typ host", "typ relay"), "0", 0) }
        rejects { RtcSignaling.validateCandidate(candidate + "\r\ninjected", "0", 0) }
        rejects { RtcSignaling.validateCandidate(candidate, "2", 2) }
    }
}
