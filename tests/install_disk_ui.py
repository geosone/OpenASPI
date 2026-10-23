"""Check the real installer's selected language at its first DOS page."""
import json
from pathlib import Path
import socket
import subprocess
import sys
import time

work, language, release = Path(sys.argv[1]).resolve(), sys.argv[2], Path(sys.argv[3]).resolve()
autoexec = work / "UIAUTO.BAT"
autoexec.write_bytes(b"@ECHO OFF\r\nB:\\INSTALL /B:C: B:\\INSTALL.INI\r\nQEXIT\r\n")
subprocess.run(["mcopy", "-o", "-i", str(work / "boot.img"), str(autoexec), "::/AUTOEXEC.BAT"], check=True)
sock = work / "ui-qmp.sock"
assert not sock.exists()
args = ["qemu-system-i386", "-machine", "pc", "-m", "32", "-display", "none",
        "-drive", f"if=floppy,index=0,format=raw,file={work/'boot.img'}", "-boot", "a",
        "-drive", f"if=floppy,index=1,format=raw,readonly=on,file={release/language/('openaspi-'+language.lower()+'-disk1.img')}",
        "-drive", f"if=ide,format=raw,file={work/'storage.img'}",
        "-qmp", f"unix:{sock},server=on,wait=off"]
with (work / "ui-process.log").open("wb") as log:
    proc = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
    try:
        deadline = time.monotonic() + 60
        while not sock.exists():
            if proc.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError("installer UI VM did not start")
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
            expected = ("Willkommen", "Weiter", "OpenASPI Installation", "Geraetetreiber") if language == "GR" else (
                "Welcome", "Continue", "OpenASPI Setup", "device drivers")
            snapshot = work / "ui-vram.bin"
            while time.monotonic() < deadline:
                if proc.poll() is not None:
                    raise RuntimeError("installer exited before its welcome page")
                command("pmemsave", {"val": 0xB8000, "size": 4000, "filename": str(snapshot)})
                text = snapshot.read_bytes()[::2].decode("cp437")
                if all(value in text for value in expected):
                    (work / "ui-welcome.txt").write_text("\n".join(text[i:i+80] for i in range(0, 2000, 80)))
                    command("screendump", {"filename": str(work / "ui-welcome.ppm")})
                    command("quit")
                    proc.wait(timeout=10)
                    break
                time.sleep(.1)
            else:
                raise RuntimeError(f"{language}: installer language did not match {expected}")
    finally:
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=10)
        if sock.exists():
            sock.unlink()
print(f"{language}: actual DOS installer welcome page and controls use the package language")
