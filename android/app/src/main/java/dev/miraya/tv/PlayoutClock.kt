package dev.miraya.tv

/** Sender PTS is a different clock domain. Re-anchor after jitter or a capture
 * pause instead of dropping every subsequent frame against an obsolete epoch. */
internal class PlayoutClock {
    private var basePts: Long? = null
    private var baseTime = 0L

    @Synchronized fun deadline(pts: Long, now: Long): Long {
        val base = basePts
        // Compare in microseconds first so even a valid Int64 wire timestamp
        // cannot overflow when converting the delta to nanoseconds.
        val deltaUs = if (base == null) 0 else pts - base
        val result = if (base == null || deltaUs !in -10_000_000L..10_000_000L) null else baseTime + deltaUs * 1000
        if (result == null || result < now - 100_000_000L || result > now + 200_000_000L) {
            basePts = pts; baseTime = now + 40_000_000L
            return baseTime
        }
        return result
    }
}
