package dev.miraya.tv

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException

data class Packet(val type: Int, val flags: Int = 0, val pts: Long = 0, val payload: ByteArray, val sequence: Int = 0)

/** Portable framing code, deliberately independent of Android for fuzz/unit tests. */
object Wire {
    const val CONTROL = 1
    const val CONFIG = 2
    const val VIDEO = 3
    const val AUDIO = 4
    const val MAX_PAYLOAD = 4 * 1024 * 1024
    private const val MAGIC = 0x4d525931

    fun read(input: DataInputStream): Packet {
        if (input.readInt() != MAGIC) throw IOException("Invalid Miraya packet signature")
        val type = input.readUnsignedByte()
        val flags = input.readUnsignedByte()
        val reserved = input.readUnsignedShort()
        val size = input.readInt()
        val pts = input.readLong()
        val sequence = input.readInt()
        if (type !in CONTROL..AUDIO || reserved != 0 || flags != (if (type == VIDEO) flags and 1 else 0)) throw IOException("Invalid packet header")
        if (size < 0 || size > MAX_PAYLOAD || ((type == CONTROL || type == CONFIG) && size > 65536)) throw IOException("Packet exceeds size limit")
        if (type == AUDIO && (size > 19200 || size % 4 != 0)) throw IOException("Invalid stereo PCM packet")
        if (pts < 0) throw IOException("Invalid media timestamp")
        val data = ByteArray(size)
        input.readFully(data)
        return Packet(type, flags, pts, data, sequence)
    }

    fun write(output: DataOutputStream, packet: Packet) {
        require(packet.payload.size <= MAX_PAYLOAD)
        output.writeInt(MAGIC); output.writeByte(packet.type); output.writeByte(packet.flags)
        output.writeShort(0); output.writeInt(packet.payload.size); output.writeLong(packet.pts)
        output.writeInt(packet.sequence); output.write(packet.payload); output.flush()
    }
}
