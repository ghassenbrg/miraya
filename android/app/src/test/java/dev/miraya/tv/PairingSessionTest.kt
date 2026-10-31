package dev.miraya.tv

import org.junit.Assert.*
import org.junit.Test

class PairingSessionTest {
    @Test fun sharedSwiftCommitmentAndCodeVector() {
        val nonce = "01".repeat(32)
        assertEquals("481a82c900bb670a336dbaf904a506ffea2f3763eafe716380d0c6c70bad88c2", PairingSession.commitment(nonce))
        assertEquals("447474", PairingSession.code("AB".repeat(32), "12345678-1234-1234-1234-123456789ABC", nonce, "02".repeat(32)))
    }
    @Test fun freshNoncesAndMalformedCommitments() {
        val nonces = (0..99).map { PairingSession.nonce() }
        assertEquals(100, nonces.toSet().size)
        assertTrue(nonces.all { PairingSession.validHex(it) })
        assertFalse(PairingSession.validHex("G".repeat(64)))
        assertFalse(PairingSession.validHex("123456"))
    }
}
