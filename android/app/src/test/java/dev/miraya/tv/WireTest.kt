package dev.miraya.tv

import org.junit.Assert.*
import org.junit.Test
import java.io.*

class WireTest {
    private fun encoded(packet: Packet): ByteArray = ByteArrayOutputStream().also { Wire.write(DataOutputStream(it), packet) }.toByteArray()
    private fun decode(bytes: ByteArray) = Wire.read(DataInputStream(ByteArrayInputStream(bytes)))
    private fun rejects(bytes: ByteArray) { try { decode(bytes); fail("Malformed packet accepted") } catch (_: IOException) { } }
    @Test fun preservesTimestampFlagsSequenceAndPayload() {
        val original = Packet(Wire.VIDEO, 1, 123456789012L, byteArrayOf(0, 0, 0, 1, 0x65), 9001)
        val decoded = decode(encoded(original))
        assertEquals(original.type, decoded.type); assertEquals(original.flags, decoded.flags)
        assertEquals(original.pts, decoded.pts); assertEquals(original.sequence, decoded.sequence)
        assertArrayEquals(original.payload, decoded.payload)
    }
    @Test fun readsMultiplePacketsWithoutConsumingNextHeader() {
        val bytes = encoded(Packet(Wire.CONTROL, payload = "{}".toByteArray())) + encoded(Packet(Wire.AUDIO, pts = 42, payload = ByteArray(16)))
        val stream = DataInputStream(ByteArrayInputStream(bytes))
        assertEquals(Wire.CONTROL, Wire.read(stream).type); assertEquals(42L, Wire.read(stream).pts)
        assertEquals(-1, stream.read())
    }
    @Test fun rejectsBadMagicUnknownTypeFlagsAndReserved() {
        val original = encoded(Packet(Wire.CONTROL, payload = ByteArray(0)))
        for (offset in intArrayOf(0, 4, 5, 6)) rejects(original.copyOf().apply { this[offset] = 0x7f })
    }
    @Test fun rejectsOversizedAndNegativeLengthsBeforeAllocating() {
        val header = encoded(Packet(Wire.CONTROL, payload = ByteArray(0)))
        rejects(header.copyOf().apply { this[8] = 0x7f; this[9] = 0x7f })
        rejects(header.copyOf().apply { this[8] = 0xff.toByte() })
        rejects(header.copyOf().apply { this[9] = 1; this[11] = 1 })
    }
    @Test fun rejectsPartialPayloadAndPartialHeader() {
        val bytes = encoded(Packet(Wire.VIDEO, payload = ByteArray(64)))
        rejects(bytes.copyOf(23)); rejects(bytes.copyOf(bytes.size - 1))
    }
    @Test fun rejectsAudioThatIsNotWholeStereoSamplesOrTooLong() {
        rejects(encoded(Packet(Wire.AUDIO, payload = ByteArray(3))))
        rejects(encoded(Packet(Wire.AUDIO, payload = ByteArray(19204))))
    }
    @Test fun handlesNetworkFragmentation() {
        val bytes = encoded(Packet(Wire.VIDEO, payload = ByteArray(5000) { (it % 251).toByte() }))
        val fragmented = object : ByteArrayInputStream(bytes) {
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int = super.read(buffer, offset, minOf(length, 3))
        }
        assertEquals(5000, Wire.read(DataInputStream(fragmented)).payload.size)
    }
}
