package dev.miraya.tv

/** Atomic producer/consumer recovery. An overflow retains a pending format,
 * flushes the existing codec rather than recreating it, and keeps an arriving IDR. */
internal class VideoBuffer<C>(private val capacity: Int = 6) {
    sealed class Command<out C> {
        data class Config<C>(val value: C) : Command<C>()
        data class Frame(val packet: Packet) : Command<Nothing>()
        data object Reset : Command<Nothing>()
    }
    data class Result(val dropped: Int = 0, val needsKeyframe: Boolean = false)
    private val commands = ArrayDeque<Command<C>>()
    private var awaitingKeyframe = true
    private var pendingConfiguration: C? = null

    @Synchronized fun configure(config: C) {
        commands.clear(); pendingConfiguration = config; awaitingKeyframe = true
        commands.add(Command.Config(config))
    }
    @Synchronized fun offer(packet: Packet): Result {
        val key = packet.flags and 1 != 0
        if (awaitingKeyframe && !key) return Result(1, true)
        var dropped = 0
        if (commands.size >= capacity) {
            dropped = commands.count { it is Command.Frame }
            commands.clear()
            val config = pendingConfiguration
            commands.add(if (config != null) Command.Config(config) else Command.Reset)
            awaitingKeyframe = true
        }
        if (awaitingKeyframe && !key) return Result(dropped + 1, true)
        commands.add(Command.Frame(packet)); awaitingKeyframe = false
        return Result(dropped, false)
    }
    @Synchronized fun recover(): Int {
        val dropped = commands.count { it is Command.Frame }
        commands.clear()
        val config = pendingConfiguration
        commands.add(if (config != null) Command.Config(config) else Command.Reset)
        awaitingKeyframe = true
        return dropped
    }
    @Synchronized fun poll(): Command<C>? {
        val next = commands.removeFirstOrNull()
        if (next is Command.Config) pendingConfiguration = null
        return next
    }
}
