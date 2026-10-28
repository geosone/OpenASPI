"""Exchange the QEMU CD while CDASWAP waits at its prompt (dos_cda_swap.sh)."""
import json
from pathlib import Path
import socket
import subprocess
import sys
import time

out, bus = Path(sys.argv[1]).resolve(), sys.argv[2]
serial = out / "serial.log"
sock = out / "qmp.sock"
assert not sock.exists()
if bus == "ide":
    cd_args = ["-device", "ide-cd,drive=cd,bus=ide.1,model=OPENASPI CD-ROM"]
else:
    cd_args = ["-device", "ich9-ahci,id=ahci",
               "-device", "ide-cd,drive=cd,bus=ahci.0,model=OPENASPI CD-ROM"]
args = ["qemu-system-i386", "-machine", "pc", "-m", "32", "-display", "none",
        "-drive", f"if=floppy,format=raw,file={out / 'boot.img'}", "-boot", "a",
        "-drive", f"id=cd,if=none,format=raw,media=cdrom,file={out / 'a.iso'}",
        *cd_args,
        "-serial", f"file:{serial}", "-debugcon", f"file:{out / 'debug.log'}",
        "-qmp", f"unix:{sock},server=on,wait=off",
        "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"]
with (out / "process.log").open("wb") as log:
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
            deadline = time.monotonic() + 120
            while proc.poll() is None and time.monotonic() < deadline:
                text = serial.read_bytes().decode("cp437") if serial.exists() else ""
                if not exchanged and "SWAP CD NOW" in text:
                    command("blockdev-change-medium", {"device": "cd", "filename": str(out / "b.iso"),
                                                       "format": "raw"})
                    command("human-monitor-command", {"command-line": "sendkey ret"})
                    exchanged = True
                time.sleep(.2)
            if proc.poll() is None:
                raise RuntimeError("CD exchange timed out")
            text = serial.read_bytes().decode("cp437")
            print(text.replace("\r", ""))
            if proc.returncode != 1 or not exchanged:
                raise RuntimeError("CD exchange failed")
    finally:
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=10)
        if sock.exists():
            sock.unlink()
