#!/usr/bin/env python3
"""Opt-in hardware check of temporary Mac output mute and parent-exit recovery.

Temporarily mutes the current output, never changes volume, and restores the
original state in finally. Does not capture, record or transmit audio.
"""
import ctypes as C
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


class Address(C.Structure):
    _fields_ = [("selector", C.c_uint32), ("scope", C.c_uint32), ("element", C.c_uint32)]


def fourcc(text):
    return int.from_bytes(text.encode("ascii"), "big")


def main():
    binary = Path(sys.argv[1]).resolve()
    audio = C.CDLL("/System/Library/Frameworks/CoreAudio.framework/CoreAudio")
    get = audio.AudioObjectGetPropertyData
    get.argtypes = [C.c_uint32, C.POINTER(Address), C.c_uint32, C.c_void_p, C.POINTER(C.c_uint32), C.c_void_p]
    get.restype = C.c_int32
    put = audio.AudioObjectSetPropertyData
    put.argtypes = [C.c_uint32, C.POINTER(Address), C.c_uint32, C.c_void_p, C.c_uint32, C.c_void_p]
    put.restype = C.c_int32

    def read(object_id, address):
        value = C.c_uint32(); size = C.c_uint32(4)
        result = get(object_id, C.byref(address), 0, None, C.byref(size), C.byref(value))
        if result: raise RuntimeError(f"CoreAudio read failed: {result}")
        return value.value

    device = read(1, Address(fourcc("dOut"), fourcc("glob"), 0))
    mute = Address(fourcc("mute"), fourcc("outp"), 0)
    original = read(device, mute)

    def restored():
        end = time.monotonic() + 5
        while time.monotonic() < end:
            if read(device, mute) == original: return
            time.sleep(0.05)
        raise AssertionError("The guardian did not restore the original mute state")

    helper = holder = None
    orphan_pid = None
    try:
        helper = subprocess.Popen([str(binary), "--local-audio-guardian"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        assert helper.stdout.readline().strip() == b"ok", "Output mute is unsupported or guardian failed"
        assert read(device, mute) == 1
        helper.stdin.close(); helper.wait(timeout=5); restored()
        print("PASS: TV-only temporary mute and normal restoration")
        code = """import json,subprocess,sys,time
p=subprocess.Popen([sys.argv[1],'--local-audio-guardian'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
print(json.dumps({'response':p.stdout.readline().decode().strip(),'pid':p.pid}),flush=True)
time.sleep(60)
"""
        holder = subprocess.Popen([sys.executable, "-c", code, str(binary)], stdout=subprocess.PIPE)
        result = json.loads(holder.stdout.readline()); orphan_pid = result["pid"]
        assert result["response"] == "ok"
        assert read(device, mute) == 1
        holder.kill(); holder.wait(timeout=5); restored()
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            try: os.kill(orphan_pid, 0)
            except ProcessLookupError: break
            time.sleep(0.05)
        else: raise AssertionError("The guardian did not exit after the parent died")
        print("PASS: original mute restored after unexpected parent exit")
        print(f"Original output mute preserved: {original}")
    finally:
        if helper:
            if helper.stdin and not helper.stdin.closed: helper.stdin.close()
            if helper.poll() is None: helper.wait(timeout=5)
        if holder and holder.poll() is None: holder.kill(); holder.wait(timeout=5)
        value = C.c_uint32(original)
        put(device, C.byref(mute), 0, None, 4, C.byref(value))
        if orphan_pid:
            try: os.kill(orphan_pid, signal.SIGTERM)
            except ProcessLookupError: pass


if __name__ == "__main__":
    main()
