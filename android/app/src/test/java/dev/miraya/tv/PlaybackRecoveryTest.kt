package dev.miraya.tv

import org.junit.Assert.*
import org.junit.Test

class PlaybackRecoveryTest {
    @Test fun clockRecoversAfterBriefJitterAndStaticDesktop() {
        val clock = PlayoutClock()
        assertEquals(40_000_000L, clock.deadline(0, 0))
        // Previously a 300ms slip caused all outputs to be dropped, then sender starvation.
        assertEquals(373_000_000L, clock.deadline(33_000, 333_000_000))
        assertEquals(407_000_000L, clock.deadline(67_000, 367_000_000))
        val resumed = clock.deadline(60_000_000, 60_000_000_000)
        assertTrue(resumed in 60_000_000_000L..60_200_000_000L)
    }
    @Test fun clockHandlesTimestampDiscontinuitiesWithoutOverflow() {
        val clock = PlayoutClock()
        clock.deadline(1, 1_000_000_000)
        assertEquals(2_040_000_000L, clock.deadline(Long.MAX_VALUE, 2_000_000_000))
        assertEquals(3_040_000_000L, clock.deadline(0, 3_000_000_000))
    }
    private fun frame(key: Boolean = false) = Packet(Wire.VIDEO, if (key) 1 else 0, payload = byteArrayOf(1))
    @Test fun overflowKeepsConfigurationUntilConsumerTakesIt() {
        val queue = VideoBuffer<String>(3)
        queue.configure("SPS/PPS")
        queue.offer(frame(true)); queue.offer(frame())
        val overflow = queue.offer(frame(true))
        assertEquals(2, overflow.dropped)
        assertFalse(overflow.needsKeyframe)
        assertEquals(VideoBuffer.Command.Config("SPS/PPS"), queue.poll())
        assertTrue((queue.poll() as VideoBuffer.Command.Frame).packet.flags == 1)
        assertNull(queue.poll())
    }
    @Test fun runningDecoderFlushesOnceAndWaitsForNewIDR() {
        val queue = VideoBuffer<String>(3)
        queue.configure("format"); queue.poll()
        queue.offer(frame(true)); queue.offer(frame()); queue.offer(frame())
        assertTrue(queue.offer(frame()).needsKeyframe)
        assertEquals(VideoBuffer.Command.Reset, queue.poll())
        assertTrue(queue.offer(frame()).needsKeyframe)
        assertNull(queue.poll())
        assertFalse(queue.offer(frame(true)).needsKeyframe)
        assertTrue(queue.poll() is VideoBuffer.Command.Frame)
    }
    @Test fun inputBackpressureCannotLoseNewFormat() {
        val queue = VideoBuffer<String>()
        queue.configure("old"); queue.poll()
        queue.configure("new"); queue.offer(frame(true))
        assertEquals(1, queue.recover())
        assertEquals(VideoBuffer.Command.Config("new"), queue.poll())
        assertTrue(queue.offer(frame()).needsKeyframe)
        queue.offer(frame(true))
        assertTrue(queue.poll() is VideoBuffer.Command.Frame)
    }
}
