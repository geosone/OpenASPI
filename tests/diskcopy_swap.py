"""Exchange disposable QEMU media at ASPIDD's real one-drive prompt."""
import json
from pathlib import Path
import socket
import subprocess
import sys
import time

out, root, mode = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), sys.argv[3]
serial = out / f"serial-{mode}.log"
sock = out / "qmp.sock"
target = out / ("wrong.img" if mode == "mismatch" else "swapped.img")
assert not sock.exists()
args = ["qemu-system-i386", "-machine", "pc", "-m", "32", "-display", "none",
        "-drive", f"if=floppy,format=raw,file={out / 'boot.img'}", "-boot", "a",
        "-drive", f"if=ide,format=raw,file={out / 'storage.img'}",
        "-device", "usb-ehci,id=usb", "-device", "usb-bot,id=bot,bus=usb.0,port=1",
        "-drive", f"id=src,if=none,format=raw,file={out / 'source.img'}",
        "-device", "scsi-hd,bus=bot.0,drive=src,removable=on,vendor=IOMEGA,product=ZIP-100",
        "-serial", f"file:{serial}", "-debugcon", f"file:{out / ('trace-'+mode+'.log')}",
        "-qmp", f"unix:{sock},server=on,wait=off",
        "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"]
with (out / f"process-{mode}.log").open("wb") as log:
    proc = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
    try:
        for _ in range(150):
            if sock.exists():
                break
            if proc.poll() is not None:
                raise RuntimeError("QEMU exited before QMP became ready")
            time.sleep(.1)
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(10)
            connection.connect(str(sock))
            channel = connection.makefile("rwb", buffering=0)
            json.loads(channel.readline())

            def command(name, arguments=None):
                payload = {"execute": name}
                if arguments is not None:
                    payload["arguments"] = arguments
                channel.write((json.dumps(payload) + "\n").encode())
                while True:
                    reply = json.loads(channel.readline())
                    if "event" in reply:
                        continue
                    if "error" in reply:
                        raise RuntimeError(reply)
                    return reply.get("return")

            command("qmp_capabilities")
            exchanged = False
            deadline = time.monotonic() + 600
            while proc.poll() is None and time.monotonic() < deadline:
                text = serial.read_bytes().decode("cp437") if serial.exists() else ""
                if not exchanged and "Insert TARGET medium" in text:
                    if mode != "cancel":
                        command("blockdev-change-medium", {"device": "src", "filename": str(target), "format": "raw"})
                        command("blockdev-close-tray", {"device": "src"})
                        (out / f"block-{mode}.json").write_text(json.dumps(command("query-block")))
                    command("human-monitor-command", {"command-line": "sendkey esc" if mode == "cancel" else "sendkey ret"})
                    exchanged = True
                time.sleep(.2)
            if proc.poll() is None:
                raise RuntimeError("one-drive copy timed out")
            text = serial.read_bytes().decode("cp437")
            print(text)
            if proc.returncode != 1 or not exchanged or "SWAP TEST PASSED" not in text or "SWAP TEST FAILED" in text:
                raise RuntimeError(f"one-drive {mode} failed")
    finally:
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=10)
        if sock.exists():
            sock.unlink()
