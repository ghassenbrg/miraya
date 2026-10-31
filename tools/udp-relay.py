#!/usr/bin/env python3
"""Disposable emulator UDP relay: untouched STUN/DTLS/SRTP, bounded impairment.

Not a production relay. No decryption or media recording. Used by emulator-smoke
because adb TCP forwarding cannot forward WebRTC's UDP media through emulator NAT.
"""
from __future__ import annotations

import heapq
import json
import random
import select
import socket
import threading
import time


class UdpRelay:
    def __init__(self, loss: float = 0, delay_ms: float = 0, jitter_ms: float = 0,
                 rate_mbps: float = 0, stall_at: float = -1, stall_for: float = 0, ordered: bool = False):
        self.up = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.up.bind(("127.0.0.1", 0))
        self.down = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.down.bind(("0.0.0.0", 0))
        self.up_port, self.down_port = self.up.getsockname()[1], self.down.getsockname()[1]
        self.loss, self.delay, self.jitter = loss, delay_ms / 1000, jitter_ms / 1000
        self.rate = rate_mbps * 1_000_000 / 8
        self.stall_at, self.stall_for = stall_at, stall_for
        self.ordered = ordered
        self.rng = random.Random(42)
        self.running = True
        self.reset_requested = threading.Event()
        self.report = dict(received=0, forwarded=0, dropped=0, bytes=0, maxQueued=0, up=0, down=0, ignored=0, packetTypes={})
        self.thread = threading.Thread(target=self.run, name="Miraya test UDP relay", daemon=True)
        self.thread.start()

    def run(self):
        peers = [None, None]
        sources = [set(), set()]
        active = [None, None]
        sockets = [self.up, self.down]
        pending: list[tuple] = []
        early = [[], []]
        next_at = [0.0, 0.0]
        last_due = [0.0, 0.0]
        began = None
        sequence = 0

        def stalled(now):
            return began is not None and self.stall_at >= 0 and self.stall_at <= now - began < self.stall_at + self.stall_for

        quiet_until = 0.0
        while self.running:
            now = time.monotonic()
            if self.reset_requested.is_set():
                self.reset_requested.clear()
                peers = [None, None]; sources = [set(), set()]; active = [None, None]
                pending.clear(); early = [[], []]; next_at = [0.0, 0.0]; began = None
                last_due = [0.0, 0.0]
                quiet_until = now + .75
            while pending and pending[0][0] <= now:
                _, _, direction, data = heapq.heappop(pending)
                stun = len(data) >= 8 and data[4:8] == bytes.fromhex("2112a442")
                targets = sources[1 - direction] if stun or active[1 - direction] is None else [active[1 - direction]]
                if targets and not stalled(now):
                    for target in list(targets):
                        try:
                            sockets[1 - direction].sendto(data, target)
                            self.report["forwarded"] += 1
                            self.report["bytes"] += len(data)
                        except OSError:
                            self.report["dropped"] += 1
                else:
                    self.report["dropped"] += 1
            readable, _, _ = select.select(sockets, [], [], .005)
            for sock in readable:
                direction = sockets.index(sock)
                data, source = sock.recvfrom(65536)
                if time.monotonic() < quiet_until: continue
                # ICE can probe multiple local sockets before BUNDLE selects
                # one. Forward STUN to those bounded endpoints; pin encrypted
                # media to the source actually completing DTLS, not an early probe.
                if source not in sources[direction] and len(sources[direction]) >= 8:
                    self.report["ignored"] += 1
                    continue
                sources[direction].add(source)
                peers[direction] = source
                if not (len(data) >= 8 and data[4:8] == bytes.fromhex("2112a442")):
                    active[direction] = source
                self.report["up" if direction == 0 else "down"] += 1
                kind = ("stun_%04x" % int.from_bytes(data[:2], "big")) if len(data) >= 8 and data[4:8] == bytes.fromhex("2112a442") else "wire_%02x" % data[0]
                self.report["packetTypes"][kind] = self.report["packetTypes"].get(kind, 0) + 1
                now = time.monotonic()
                if began is None:
                    began = now
                self.report["received"] += 1
                if peers[1 - direction] is None:
                    if len(early[direction]) < 32:
                        early[direction].append(data)
                    continue
                items = early[direction] + [data]
                early[direction].clear()
                # The peer just became reachable; release its other direction's
                # small initial STUN backlog as well.
                for other in (0, 1):
                    if peers[1 - other] is not None and early[other]:
                        for packet in early[other]:
                            sequence += 1
                            heapq.heappush(pending, (now, sequence, other, packet))
                        early[other].clear()
                for packet in items:
                    if stalled(now) or self.rng.random() < self.loss:
                        self.report["dropped"] += 1
                        continue
                    next_at[direction] = max(next_at[direction], now) + (len(packet) / self.rate if self.rate else 0)
                    due = next_at[direction] + max(0, self.delay + self.rng.uniform(-self.jitter, self.jitter))
                    if self.ordered: due = max(due, last_due[direction] + .000001)
                    # Keep bounded memory/delay under load: drop, don't accumulate
                    # seconds of encrypted media inside the diagnostic itself.
                    if due - now > .2 or len(pending) >= 1024:
                        self.report["dropped"] += 1
                        next_at[direction] = min(next_at[direction], now + .2)
                        continue
                    sequence += 1
                    last_due[direction] = due
                    heapq.heappush(pending, (due, sequence, direction, packet))
                    self.report["maxQueued"] = max(self.report["maxQueued"], len(pending))

    def reset(self):
        self.reset_requested.set()

    def close(self, output=None):
        self.running = False
        self.thread.join(timeout=2)
        self.up.close(); self.down.close()
        if output:
            output.write_text(json.dumps(self.report, indent=2) + "\n")
        return self.report
