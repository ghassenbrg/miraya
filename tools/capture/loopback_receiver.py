#!/usr/bin/env python3
"""Exercise the shipping Swift TLS transport/encoder against a software receiver.

This diagnostic binds only loopback and automatically authorizes its test sender.
It is not a replacement for testing the Android MediaCodec/TV application.
Requires Python 3, openssl, ffmpeg, and a built Miraya binary with --probe support.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import ssl
import struct
import subprocess
import tempfile
import threading
import time

HEADER = struct.Struct(">4sBBHIQI")


class Receiver:
    def __init__(self, cert: Path, key: Path, mode: str, sessions: int = 1):
        self.mode = mode
        self.sessions = sessions
        self.context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.context.minimum_version = ssl.TLSVersion.TLSv1_2
        self.context.load_cert_chain(cert, key)
        self.listener = socket.socket()
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(4)
        self.listener.settimeout(25)
        self.port = self.listener.getsockname()[1]
        self.token = secrets.token_urlsafe(32)
        self.client = None
        self.errors: list[str] = []
        self.results: list[dict] = []
        self.hellos = 0
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self):
        try:
            for _ in range(self.sessions):
                raw, _ = self.listener.accept()
                raw.settimeout(10)
                try:
                    with self.context.wrap_socket(raw, server_side=True) as stream:
                        self.session(stream)
                except ssl.SSLError:
                    if self.mode != "wrong-pin":
                        raise
                except (EOFError, BrokenPipeError, ConnectionResetError):
                    if self.mode == "success":
                        raise
        except Exception as error:
            self.errors.append(str(error))
        finally:
            self.listener.close()

    @staticmethod
    def read_exact(stream: ssl.SSLSocket, size: int) -> bytes:
        result = bytearray()
        while len(result) < size:
            chunk = stream.recv(size - len(result))
            if not chunk:
                raise EOFError("Sender closed its TLS stream")
            result.extend(chunk)
        return bytes(result)

    def session(self, stream: ssl.SSLSocket):
        sequence = 0
        send_lock = threading.Lock()

        def send(obj: dict, fragmented: bool = False):
            nonlocal sequence
            data = json.dumps(obj, separators=(",", ":")).encode()
            packet = HEADER.pack(b"MRY1", 1, 0, 0, len(data), 0, sequence) + data
            sequence += 1
            with send_lock:
                if fragmented:
                    for start in range(0, len(packet), 7):
                        stream.sendall(packet[start:start + 7])
                else:
                    stream.sendall(packet)

        decoder = None
        decoded = [0]
        decoder_reader = None
        frames = audio_bytes = 0
        nonzero_audio = False
        previous_sequence = -1
        state = "hello"
        last_stats = time.monotonic()
        keyframe_requested = False
        keyframe_received = False
        pts = 0
        video_format = {}
        received_pts: list[int] = []

        def decoded_pts():
            return received_pts[min(decoded[0], len(received_pts)) - 1] if decoded[0] and received_pts else -1
        try:
            while True:
                magic, kind, flags, reserved, size, timestamp, incoming_sequence = HEADER.unpack(self.read_exact(stream, 24))
                maximum = 65536 if kind in (1, 2) else (19200 if kind == 4 else 4 * 1024 * 1024)
                if magic != b"MRY1" or reserved or kind not in (1, 2, 3, 4) or flags & ~1 or (flags and kind != 3) or not 0 < size <= maximum:
                    raise ValueError("Sender produced an invalid packet header")
                if incoming_sequence != previous_sequence + 1:
                    raise ValueError("Sender sequence was not contiguous")
                previous_sequence = incoming_sequence
                payload = self.read_exact(stream, size)
                if kind == 1:
                    control = json.loads(payload)
                    op = control.get("op")
                    if op == "hello":
                        self.hellos += 1
                        if state != "hello" or control.get("version") != 1:
                            raise ValueError("Invalid sender handshake")
                        if self.mode == "reject":
                            send({"op": "error", "code": "denied", "message": "Diagnostic receiver denied pairing"})
                            return
                        if self.mode == "malformed":
                            stream.sendall(b"NOPE" + bytes(20))
                            return
                        if self.client is not None and (control.get("clientId") != self.client or not secrets.compare_digest(control.get("token", ""), self.token)):
                            raise ValueError("Reconnect did not authenticate with the saved token")
                        self.client = control["clientId"]
                        send({"op": "pending"})
                        send({"op": "welcome", "version": 2 if self.mode == "version" else 1,
                              "receiverId": "ad31322a-ec01-48d6-ad0a-ab1f7b1de497", "name": "Loopback diagnostic",
                              "token": self.token, "maxWidth": 1920, "maxHeight": 1080}, fragmented=True)
                        if self.mode == "version":
                            return
                        state = "authorized"
                    elif op == "start":
                        if state != "authorized" or control.get("audio") is not True:
                            raise ValueError("Media started before authorization or without diagnostic audio")
                        state = "started"
                        decoder = subprocess.Popen(["ffmpeg", "-hide_banner", "-loglevel", "error",
                            "-threads", "1", "-flags", "low_delay", "-probesize", "32", "-analyzeduration", "0", "-f", "h264", "-i", "pipe:0",
                            "-progress", "pipe:1", "-stats_period", "0.1", "-f", "null", "-"],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

                        def read_progress():
                            for line in decoder.stdout:
                                if line.startswith(b"frame="):
                                    decoded[0] = int(line.split(b"=", 1)[1])

                        decoder_reader = threading.Thread(target=read_progress, daemon=True)
                        decoder_reader.start()
                        send({"op": "ready"})
                    elif op == "ping":
                        send({"op": "pong", "nonce": control.get("nonce", 0)})
                    elif op == "stop":
                        if decoder:
                            decoder.stdin.close()
                            decoder.wait(timeout=5)
                            decoder_reader.join(timeout=2)
                            stderr = decoder.stderr.read().decode()
                            if decoder.returncode != 0 or stderr.strip():
                                raise ValueError("Independent FFmpeg decoder failed: " + stderr[:500])
                        if not decoded[0] or not audio_bytes or not nonzero_audio or not keyframe_received:
                            raise ValueError("Missing decoded video, audible PCM, or requested IDR")
                        send({"op": "stats", "frames": decoded[0], "dropped": 0, "lastPts": decoded_pts(),
                              "audioFrames": audio_bytes // 4, "audioFramesWritten": audio_bytes // 4})
                        send({"op": "stopped"})
                        self.results.append({"encodedFrames": frames, "decodedFrames": decoded[0], "format": video_format,
                            "audioBytes": audio_bytes, "keyframeRequestHonored": keyframe_received})
                        return
                    elif op != "pong":
                        raise ValueError("Unexpected sender control: " + str(op))
                else:
                    if state != "started" or decoder is None:
                        raise ValueError("Media arrived before ready")
                    if kind == 2:
                        config = json.loads(payload)
                        if not (2 <= config["width"] <= 1920 and 2 <= config["height"] <= 1080 and config["fps"] in (30, 60)):
                            raise ValueError("Unexpected diagnostic format")
                        video_format = {name: config[name] for name in ("width", "height", "fps")}
                        for parameter in ("sps", "pps"):
                            decoder.stdin.write(b"\x00\x00\x00\x01" + base64.b64decode(config[parameter], validate=True))
                        decoder.stdin.flush()
                    elif kind == 3:
                        if not payload.startswith(b"\x00\x00\x00\x01"):
                            raise ValueError("H.264 access unit was not Annex B")
                        decoder.stdin.write(payload)
                        decoder.stdin.flush()
                        frames += 1
                        pts = timestamp
                        received_pts.append(timestamp)
                        if self.mode == "disconnect" and frames == 10:
                            return
                        if frames >= 10 and not keyframe_requested:
                            send({"op": "requestKeyframe"})
                            keyframe_requested = True
                        elif keyframe_requested and flags & 1:
                            keyframe_received = True
                    else:
                        if len(payload) % 4:
                            raise ValueError("Audio was not stereo PCM16")
                        audio_bytes += len(payload)
                        nonzero_audio |= any(payload)
                if state == "started" and time.monotonic() - last_stats > 0.25:
                    send({"op": "stats", "frames": decoded[0], "dropped": 0, "lastPts": decoded_pts(),
                          "audioFrames": audio_bytes // 4, "audioFramesWritten": audio_bytes // 4})
                    last_stats = time.monotonic()
        finally:
            if decoder and decoder.poll() is None:
                decoder.kill()
                decoder.wait(timeout=3)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sender", type=Path, help="Built sender executable; default is SwiftPM's actual debug output path")
    parser.add_argument("--output", type=Path, default=Path("build/loopback-report.json"))
    parser.add_argument("--case", choices=("all", "success", "wrong-pin", "reject", "version", "malformed", "disconnect"), default="all")
    args = parser.parse_args()
    for binary in ("ffmpeg", "openssl"):
        if not shutil.which(binary):
            parser.error(binary + " must be installed")
    if args.sender is None:
        root = Path(__file__).resolve().parents[2]
        try:
            output = subprocess.run(["swift", "build", "--package-path", str(root / "macos"), "--show-bin-path"],
                                    check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            args.sender = Path(output.stdout.strip()) / "Miraya"
        except (OSError, subprocess.CalledProcessError):
            parser.error("Cannot locate SwiftPM output; pass --sender /path/to/Miraya")
    if not args.sender.is_file():
        parser.error("Build the sender first: swift build --package-path macos")
    outcomes = []
    with tempfile.TemporaryDirectory(prefix="miraya-loopback-") as temporary:
        cert, key = Path(temporary) / "cert.pem", Path(temporary) / "key.pem"
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", str(key),
                        "-out", str(cert), "-days", "1", "-subj", "/CN=Miraya loopback diagnostic"],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        der = ssl.PEM_cert_to_DER_cert(cert.read_text())
        code = hashlib.sha256(der).hexdigest()[:16]
        cases = ["success", "wrong-pin", "reject", "version", "malformed", "disconnect"] if args.case == "all" else [args.case]
        for mode in cases:
            receiver = Receiver(cert, key, mode, sessions=2 if mode == "success" else 1)
            env = os.environ.copy()
            for name in ("MIRAYA_PROBE_TOKEN", "MIRAYA_PROBE_FINGERPRINT", "MIRAYA_PROBE_CLIENT_ID"):
                env.pop(name, None)
            env["MIRAYA_PROBE_RECONNECT"] = "1" if mode == "success" else "0"
            attempted_code = ("f" if code[0] != "f" else "e") + code[1:] if mode == "wrong-pin" else code
            run = subprocess.run([str(args.sender.resolve()), "--probe", "127.0.0.1", str(receiver.port), attempted_code, "4"],
                                 env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=35)
            receiver.thread.join(timeout=2)
            passed = not receiver.errors and (run.returncode == 0 if mode == "success" else run.returncode != 0)
            if mode == "wrong-pin":
                passed &= receiver.hellos == 0 and "identity" in run.stdout.lower()
            if mode == "success":
                passed &= len(receiver.results) == 2 and receiver.hellos == 2
            result = {"case": mode, "passed": bool(passed), "senderExit": run.returncode,
                      "receiverErrors": receiver.errors, "sessions": receiver.results, "senderLog": run.stdout}
            outcomes.append(result)
            print(("PASS" if passed else "FAIL") + ": " + mode, flush=True)
            if not passed:
                print(run.stdout, receiver.errors, flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"receiver": "Loopback TLS, independent FFmpeg software video decode, PCM byte validation; no Android AudioTrack or display surface", "tests": outcomes}, indent=2) + "\n")
    print("Report: " + str(args.output.resolve()))
    raise SystemExit(0 if all(item["passed"] for item in outcomes) else 1)


if __name__ == "__main__":
    main()
