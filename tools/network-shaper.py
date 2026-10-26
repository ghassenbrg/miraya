#!/usr/bin/env python3
"""Bounded loopback TCP relay for reproducible Miraya bandwidth testing.

TLS is passed through untouched. This never decrypts, inspects or stores media.
Both listening and destination addresses are fixed to loopback for development.
"""
from __future__ import annotations

import argparse
import asyncio
import signal
import socket
import time


async def relay(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, rate: int) -> int:
    sent = 0
    next_at = time.monotonic()
    while True:
        chunk = await reader.read(8192)
        if not chunk:
            return sent
        # Pace before forwarding so a stalled downstream never accumulates an
        # application-side queue. Each direction retains at most one 8KiB chunk.
        next_at = max(next_at, time.monotonic()) + len(chunk) / rate
        await asyncio.sleep(max(0, next_at - time.monotonic()))
        writer.write(chunk)
        await writer.drain()
        sent += len(chunk)


def bound_socket(writer: asyncio.StreamWriter) -> None:
    sock = writer.get_extra_info("socket")
    if sock:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 32 * 1024)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 32 * 1024)
    writer.transport.set_write_buffer_limits(high=16 * 1024, low=8192)


async def serve(port: int, target: int, upload: int, download: int) -> None:
    async def connected(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        upstream: asyncio.StreamWriter | None = None
        tasks: list[asyncio.Task[int]] = []
        try:
            remote, upstream = await asyncio.wait_for(asyncio.open_connection("127.0.0.1", target, limit=16 * 1024), 5)
            bound_socket(writer); bound_socket(upstream)
            tasks = [asyncio.create_task(relay(reader, upstream, upload)),
                     asyncio.create_task(relay(remote, writer, download))]
            done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                task.result()
        except (OSError, asyncio.TimeoutError) as error:
            print(f"SHAPER: connection ended ({type(error).__name__})", flush=True)
        finally:
            for task in tasks:
                if not task.done(): task.cancel()
            if tasks: await asyncio.gather(*tasks, return_exceptions=True)
            writer.close()
            if upstream: upstream.close()

    server = await asyncio.start_server(connected, "127.0.0.1", port, limit=16 * 1024)
    print(f"SHAPER: 127.0.0.1:{port} → 127.0.0.1:{target}; upload={upload} B/s, download={download} B/s; encrypted passthrough", flush=True)
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in [signal.SIGINT, signal.SIGTERM]:
        loop.add_signal_handler(sig, stop.set)
    async with server:
        await stop.wait()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--listen", type=int, default=18421)
    parser.add_argument("--target", type=int, default=17421, help="adb-forwarded receiver port")
    parser.add_argument("--upload", type=int, default=65536, help="Mac→TV bytes/second, including TLS overhead")
    parser.add_argument("--download", type=int, default=1048576, help="TV→Mac bytes/second")
    args = parser.parse_args()
    if not all(1 <= port <= 65535 for port in [args.listen, args.target]) or args.listen == args.target:
        parser.error("Use distinct listen/target ports in 1..65535")
    if args.upload < 1024 or args.download < 1024:
        parser.error("Rates must be at least 1024 bytes/second")
    asyncio.run(serve(args.listen, args.target, args.upload, args.download))


if __name__ == "__main__":
    main()
