#!/usr/bin/env python3
"""Drive a dedicated held 86Box DOS test VM through its local UNIX socket."""
import argparse
import json
from pathlib import Path
import socket
import os
import subprocess
import time
import ctypes


def close_x11_window(window):
    """Request Qt's normal close path without a window manager or guest keys."""
    class Message(ctypes.Structure):
        _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong),
                    ("send_event", ctypes.c_int), ("display", ctypes.c_void_p),
                    ("window", ctypes.c_ulong), ("message_type", ctypes.c_ulong),
                    ("format", ctypes.c_int), ("data", ctypes.c_long * 5)]

    class Event(ctypes.Union):
        _fields_ = [("message", Message), ("padding", ctypes.c_long * 24)]

    x11 = ctypes.CDLL("libX11.so.6")
    x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x11.XOpenDisplay.restype = ctypes.c_void_p
    x11.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    x11.XInternAtom.restype = ctypes.c_ulong
    x11.XSendEvent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int,
                              ctypes.c_long, ctypes.POINTER(Event)]
    x11.XCloseDisplay.argtypes = [ctypes.c_void_p]
    display = x11.XOpenDisplay(None)
    if not display:
        raise RuntimeError("Cannot open the private X display")
    try:
        event = Event()
        event.message = Message(33, 0, 1, display, int(window),
                                x11.XInternAtom(display, b"WM_PROTOCOLS", 0), 32,
                                (ctypes.c_long * 5)(
                                    x11.XInternAtom(display, b"WM_DELETE_WINDOW", 0)))
        if not x11.XSendEvent(display, int(window), 0, 0, ctypes.byref(event)):
            raise RuntimeError("Could not request normal VM shutdown")
    finally:
        x11.XCloseDisplay(display)


def legacy_output(vm, pid, done):
    """86Box 6.0: private X display, COM1 stdio, normal GUI shutdown."""
    window = None
    try:
        for _ in range(120):
            os.kill(pid, 0)
            found = subprocess.run(
                ["xdotool", "search", "--onlyvisible", "--pid", str(pid)],
                capture_output=True, text=True)
            if found.returncode == 0:
                window = found.stdout.splitlines()[0]
                subprocess.run(["xdotool", "windowfocus", window], check=True)
                subprocess.run(["xdotool", "key", "F1"], check=True)
            output = (vm / "serial.log").read_bytes().decode("cp437")
            if done in output:
                return output
            time.sleep(1)
        raise RuntimeError("Legacy VM did not complete; see serial.log")
    finally:
        if window:
            close_x11_window(window)


def validate(output, args):
    if "FAILED" in output or output.count(args.expect) != args.count:
        raise RuntimeError("DOS guest check failed; see serial.log")
    if args.read_text not in output:
        raise RuntimeError("Expected file content was not read; see serial.log")
    if args.high and output.count("ASPI manager and ASPICDA verified in upper memory") != 2:
        raise RuntimeError("Resident addresses were not verified in UMBs")
    print(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vm", type=Path)
    parser.add_argument("--high", action="store_true")
    parser.add_argument("--legacy-pid", type=int)
    parser.add_argument("--aspi-ui", action="store_true")
    parser.add_argument("--ui-no-aspi", action="store_true")
    parser.add_argument("--done", default="OPENASPI 86BOX UPC DONE")
    parser.add_argument("--expect", default="ASPICDA image UPC 0123456789012 passed")
    parser.add_argument("--count", type=int, default=2)
    parser.add_argument("--read-text", default="OpenASPI ASPICDA read test")
    args = parser.parse_args()
    vm = args.vm.resolve()
    if args.legacy_pid:
        validate(legacy_output(vm, args.legacy_pid, args.done), args)
        return
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(60)
        connection.connect(str(vm / "control.sock"))
        channel = connection.makefile("rwb", buffering=0)

        def command(text):
            channel.write((text + "\n").encode("ascii"))
            result = json.loads(channel.readline())
            if not result.get("ok"):
                raise RuntimeError(f"{text}: {result}")
            return result

        try:
            ui_phase = 0
            for _ in range(90):
                serial = command("serial read 1")
                output = bytes.fromhex(serial["data"]).decode("cp437")
                (vm / "serial.log").write_text(output, encoding="utf-8")
                if args.done in output:
                    break
                screen = command("text")
                text = "\n".join(bytes.fromhex(row).decode("cp437")
                                 for row in screen.get("chars", []))
                (vm / "screen.txt").write_text(text, encoding="utf-8")
                if "Press F1 to continue" in text:
                    command("key down 0x3b")
                    command("key up 0x3b")
                if args.aspi_ui and "OpenASPI - ASPI Manager" in text:
                    if args.ui_no_aspi and ("No ASPI manager" in text or "Kein ASPI-Manager" in text):
                        (vm / "ui-no-aspi.txt").write_text(text, encoding="utf-8")
                        command("key down 0x01")
                        command("key up 0x01")
                        ui_phase = 3
                    elif ui_phase == 0 and "LS-120 COSM" in text:
                        # Select the device and verify its INQUIRY identity.
                        command("key down 0x150")
                        command("key up 0x150")
                        ui_phase = 1
                    elif ui_phase == 1 and "MATSHITA" in text and "0270" in text:
                        (vm / "ui-device.txt").write_text(text, encoding="utf-8")
                        (vm / "ui-device.json").write_text(json.dumps(screen), encoding="utf-8")
                        command("key down 0x13")  # R
                        command("key up 0x13")
                        ui_phase = 2
                    elif ui_phase == 2 and "AHCIASPI" in text:
                        command("key down 0x01")  # Esc
                        command("key up 0x01")
                        ui_phase = 3
                command("step 2000")
            else:
                raise RuntimeError("VM did not complete; see screen.txt and serial.log")
            validate(output, args)
            if args.aspi_ui and ui_phase != 3:
                raise RuntimeError("ASPI GUI selection/rescan/exit did not complete")
        finally:
            connection.settimeout(3)
            try:
                command("quit")
            except (OSError, ValueError, RuntimeError):
                pass  # The shell harness also cleans up a failed emulator.


if __name__ == "__main__":
    main()
