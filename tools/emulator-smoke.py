#!/usr/bin/env python3
"""Exercise the shipping Mac sender against a real Android TV emulator.

This intentionally resets ONLY Miraya's data on an emulator, never a physical TV.
It reads the code displayed in the TV UI and uses D-pad events for approval.
No private receiver storage, credentials or protocol bypasses are used.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import queue
import re
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "dev.miraya.tv"


def run(command: list[str], timeout: float = 30) -> str:
    result = subprocess.run(command, check=True, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=timeout)
    return result.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", help="adb emulator serial; defaults to the only running emulator")
    parser.add_argument("--reset", action="store_true", required=True,
                        help="Acknowledge clearing Miraya app data on the selected emulator")
    parser.add_argument("--duration", type=int, default=8, choices=range(4, 61), metavar="4..60")
    parser.add_argument("--port", type=int, default=17421, help="Host TCP forwarding port")
    parser.add_argument("--receiver-port", type=int, default=7421)
    parser.add_argument("--bandwidth", action="store_true", help="Also test 1080p30 at 64KiB/s upload, then direct recovery")
    parser.add_argument("--sender", type=Path, default=ROOT / "dist/Miraya.app/Contents/MacOS/Miraya")
    parser.add_argument("--apk", type=Path, default=ROOT / "dist/Miraya-TV-debug.apk")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("The native Mac probe needs macOS.")
    if not args.sender.is_file() or not args.apk.is_file():
        parser.error("Build the Mac app and debug APK first (scripts/build-macos.sh; scripts/build-android.sh).")
    if not all(1 <= port <= 65535 for port in [args.port, args.receiver_port]) or args.port > 63535:
        parser.error("Use ports in 1..65535, with host --port no higher than 63535")
    devices = run(["adb", "devices"]).splitlines()
    emulators = [line.split()[0] for line in devices if line.startswith("emulator-") and "\tdevice" in line]
    serial = args.serial or (emulators[0] if len(emulators) == 1 else None)
    if not serial or serial not in emulators:
        parser.error("Select a running emulator with --serial; physical devices are intentionally unsupported.")
    adb = ["adb", "-s", serial]
    report_dir = ROOT / "build/emulator-smoke"
    report_dir.mkdir(parents=True, exist_ok=True)

    def shell(*command: str) -> str:
        return run(adb + ["shell", *command])

    def hierarchy() -> ET.Element:
        shell("uiautomator", "dump", "/sdcard/miraya-window.xml")
        return ET.fromstring(run(adb + ["exec-out", "cat", "/sdcard/miraya-window.xml"]))

    def approve_remote() -> None:
        # The dialog deliberately focuses Decline first. Move with the actual
        # remote direction key; inspect focus before issuing the select key.
        for _ in range(6):
            tree = hierarchy()
            focused = next((n for n in tree.iter("node") if n.get("focused") == "true"), None)
            if focused is not None and focused.get("text", "").casefold() == "allow":
                shell("input", "keyevent", "KEYCODE_DPAD_CENTER")
                print("SMOKE: approved the displayed request using TV remote focus", flush=True)
                return
            shell("input", "keyevent", "KEYCODE_DPAD_RIGHT")
            time.sleep(0.2)
        raise RuntimeError("Could not focus the TV's Allow button; no approval was issued")

    child: subprocess.Popen[str] | None = None
    shaper: subprocess.Popen[str] | None = None
    forwarded = False
    alternate_forward = False
    try:
        run(adb + ["install", "-r", str(args.apk)], timeout=90)
        shell("am", "force-stop", PACKAGE)
        shell("pm", "clear", PACKAGE)
        shell("am", "start", "-n", f"{PACKAGE}/.MainActivity")
        deadline = time.monotonic() + 30
        code = None
        while time.monotonic() < deadline:
            tree = hierarchy()
            text = " ".join(node.get("text", "") for node in tree.iter("node"))
            match = re.search(r"\b[0-9A-Fa-f]{4}(?:-[0-9A-Fa-f]{4}){3}\b", text)
            if match:
                code = match.group(0)
                (report_dir / "ready.xml").write_bytes(ET.tostring(tree))
                (report_dir / "ready.png").write_bytes(subprocess.check_output(adb + ["exec-out", "screencap", "-p"]))
                break
            time.sleep(0.5)
        if not code:
            raise RuntimeError("TV did not display its fingerprint code within 30 seconds")
        print("SMOKE: read the pairing code from the visible TV UI", flush=True)
        run(adb + ["forward", f"tcp:{args.port}", f"tcp:{args.receiver_port}"])
        forwarded = True
        bad_code = ("0" if code[0] != "0" else "1") + code[1:]
        wrong = subprocess.run([str(args.sender), "--probe", "127.0.0.1", str(args.port), bad_code, "4"],
                               text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
        (report_dir / "wrong-code.log").write_text(wrong.stdout)
        if wrong.returncode == 0 or "TLS identity verified" in wrong.stdout:
            raise RuntimeError("Wrong TV code was not rejected before authentication")
        print("SMOKE: wrong certificate code rejected before application authentication", flush=True)

        env = os.environ.copy()
        env["MIRAYA_PROBE_RECONNECT"] = "1"
        child = subprocess.Popen([str(args.sender), "--probe", "127.0.0.1", str(args.port), code, str(args.duration)],
                                 text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 bufsize=1, env=env)
        lines: queue.Queue[str | None] = queue.Queue()

        def read_output() -> None:
            assert child is not None and child.stdout is not None
            for line in child.stdout:
                lines.put(line)
            lines.put(None)

        threading.Thread(target=read_output, daemon=True).start()
        output: list[str] = []
        captured_stream = False
        deadline = time.monotonic() + args.duration * 2 + 60
        while time.monotonic() < deadline:
            try:
                line = lines.get(timeout=1)
            except queue.Empty:
                if child.poll() is not None:
                    break
                continue
            if line is None:
                break
            output.append(line)
            print(line.rstrip(), flush=True)
            if "approve Miraya diagnostic" in line:
                approve_remote()
            if "streaming real H.264" in line and not captured_stream:
                time.sleep(0.5)
                (report_dir / "streaming.png").write_bytes(subprocess.check_output(adb + ["exec-out", "screencap", "-p"]))
                captured_stream = True
        if child.poll() is None:
            child.wait(timeout=3)
        transcript = "".join(output)
        (report_dir / "sender.log").write_text(transcript)
        logcat = run(adb + ["logcat", "-d", "-t", "1200", "-s", "Miraya", "AndroidRuntime", "MediaCodec"])
        (report_dir / "receiver.log").write_text(logcat)
        if child.returncode != 0 or "PASS:" not in transcript or transcript.count("session passed;") != 2:
            raise RuntimeError("Native media/reconnect probe failed; inspect build/emulator-smoke logs")
        counts = [int(n) for n in re.findall(r"session passed; sent=\d+, rendered=(\d+)", transcript)]
        if any(n < 30 for n in counts):
            raise RuntimeError(f"Too few frames rendered for a useful smoke test: {counts}")
        print(f"PASS: certificate rejection, remote pairing, native H.264/PCM, stop and pinned reconnect; rendered={counts}")
        if args.bandwidth:
            # Rebind the SAME host port through a bounded raw-TLS proxy so the
            # native probe can reuse its saved TV pin/token without changing trust.
            alternate = args.port + 2000
            run(adb + ["forward", "--remove", f"tcp:{args.port}"])
            forwarded = False
            run(adb + ["forward", f"tcp:{alternate}", f"tcp:{args.receiver_port}"])
            alternate_forward = True
            shaper = subprocess.Popen([sys.executable, str(ROOT / "tools/network-shaper.py"), "--listen", str(args.port),
                                       "--target", str(alternate), "--upload", "65536"],
                                      text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            assert shaper.stdout is not None
            banner = shaper.stdout.readline()
            if not banner.startswith("SHAPER:"):
                raise RuntimeError("Bandwidth shaper failed to bind")
            print(banner.rstrip(), flush=True)

            def additional_probe(label: str, duration: int, impaired: bool) -> None:
                nonlocal child
                probe_env = os.environ.copy()
                probe_env.pop("MIRAYA_PROBE_RECONNECT", None)
                probe_env.update({"MIRAYA_PROBE_WIDTH": "1920", "MIRAYA_PROBE_HEIGHT": "1080", "MIRAYA_PROBE_FPS": "30"})
                child = subprocess.Popen([str(args.sender), "--probe", "127.0.0.1", str(args.port), code, str(duration)],
                                         text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=probe_env, bufsize=1)
                extra: queue.Queue[str | None] = queue.Queue()
                process = child

                def drain() -> None:
                    assert process.stdout is not None
                    for item in process.stdout: extra.put(item)
                    extra.put(None)

                threading.Thread(target=drain, daemon=True).start()
                transcript: list[str] = []
                max_rss = 0
                began = time.monotonic()
                while time.monotonic() - began < duration + 45:
                    if process.poll() is None:
                        sample = subprocess.run(["ps", "-o", "rss=", "-p", str(process.pid)], text=True, stdout=subprocess.PIPE, check=False).stdout.strip()
                        if sample.isdigit(): max_rss = max(max_rss, int(sample))
                    try: item = extra.get(timeout=0.2)
                    except queue.Empty: continue
                    if item is None: break
                    transcript.append(item); print(item.rstrip(), flush=True)
                    if "approve Miraya diagnostic" in item: approve_remote()
                result = process.wait(timeout=3)
                content = "".join(transcript)
                elapsed = time.monotonic() - began
                (report_dir / f"{label}.log").write_text(content + f"\nElapsed={elapsed:.2f}s peakRSS={max_rss}KiB\n")
                if max_rss > 512 * 1024:
                    raise RuntimeError(f"Probe exceeded bounded smoke-test memory budget: {max_rss}KiB")
                if impaired:
                    if result == 0 or "FAIL:" not in content or not any(word in content.lower() for word in ["stalled", "keep up", "frames", "replying"]):
                        raise RuntimeError("64KiB/s test did not produce a controlled media failure")
                    print(f"PASS: 64KiB/s impairment ended cleanly after {elapsed:.2f}s; peak probe RSS={max_rss}KiB", flush=True)
                elif result != 0 or "PASS:" not in content:
                    raise RuntimeError("Direct connection did not recover after bandwidth impairment")

            additional_probe("bandwidth-64k", 10, True)
            shaper.terminate(); shaper.wait(timeout=5); shaper = None
            run(adb + ["forward", f"tcp:{args.port}", f"tcp:{args.receiver_port}"])
            forwarded = True
            time.sleep(1)
            additional_probe("recovered-direct", 5, False)
            print("PASS: direct 1080p30 sharing recovered after the impaired session", flush=True)
        print(f"Logs: {report_dir}")
        return 0
    finally:
        if child is not None and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
        if shaper is not None and shaper.poll() is None:
            shaper.terminate(); shaper.wait(timeout=5)
        if forwarded:
            run(adb + ["forward", "--remove", f"tcp:{args.port}"])
        if alternate_forward:
            run(adb + ["forward", "--remove", f"tcp:{args.port + 2000}"])


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.SubprocessError, ET.ParseError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
