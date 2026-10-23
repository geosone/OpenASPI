"""QEMU block-error injection and QUILIB GUI progress/finish exercise."""
import json
from pathlib import Path
import socket
import subprocess
import sys
import time
out, mode = Path(sys.argv[1]).resolve(), sys.argv[2]
sock = out / "qmp.sock"
assert not sock.exists()
args = ["qemu-system-i386", "-machine", "pc", "-m", "32", "-display", "none",
        "-drive", f"if=floppy,format=raw,file={out/'boot.img'}", "-boot", "a",
        "-drive", f"if=ide,format=raw,file={out/'storage.img'}",
        "-device", "usb-ehci,id=usb", "-device", "usb-bot,id=bot1,bus=usb.0,port=1",
        "-drive", f"id=src,if=none,format=raw,file=blkdebug:{out/'bad.conf'}:{out/'source.img'}",
        "-device", "scsi-hd,bus=bot1.0,drive=src,removable=on,vendor=IOMEGA,product=ZIP-100",
        "-device", "usb-bot,id=bot2,bus=usb.0,port=2",
        "-drive", f"id=dst,if=none,format=raw,file={out/'target.img'}",
        "-device", "scsi-hd,bus=bot2.0,drive=dst,removable=on,vendor=IOMEGA,product=ZIP-100",
        "-serial", f"file:{out/('serial-'+mode+'.log')}",
        "-qmp", f"unix:{sock},server=on,wait=off",
        "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"]
with (out/f"process-{mode}.log").open("wb") as log:
    proc = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
    try:
        for _ in range(150):
            if sock.exists(): break
            if proc.poll() is not None: raise RuntimeError("QEMU startup failed")
            time.sleep(.1)
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(10); connection.connect(str(sock))
            channel=connection.makefile("rwb",buffering=0); json.loads(channel.readline())

            def command(name, arguments=None):
                payload={"execute":name}
                if arguments is not None: payload["arguments"]=arguments
                channel.write((json.dumps(payload)+"\n").encode())
                while True:
                    reply=json.loads(channel.readline())
                    if "event" in reply: continue
                    if "error" in reply: raise RuntimeError(reply)
                    return reply.get("return")

            command("qmp_capabilities")
            finished=False; saw_gui=False; selected=False; confirmed=False; aborted=False
            deadline=time.monotonic()+300
            serial=out/f"serial-{mode}.log"
            while proc.poll() is None and time.monotonic()<deadline:
                text=serial.read_bytes().decode("cp437") if serial.exists() else ""
                if mode!="cli" and not finished:
                    snapshot=out/"vram.bin"
                    command("pmemsave",{"val":0xB8000,"size":4000,"filename":str(snapshot)})
                    chars=snapshot.read_bytes()[::2].decode("cp437")
                    if "OpenASPI - ASPIDD" in chars:
                        saw_gui=True
                        (out/"gui-progress.txt").write_text("\n".join(chars[i:i+80] for i in range(0,2000,80)))
                    if mode=="select" and not selected and ("Choose source and target" in chars or "Quelle und Ziel waehlen" in chars):
                        for key in ("d","tab","e","f2","ret"):
                            command("human-monitor-command",{"command-line":f"sendkey {key}"})
                            time.sleep(.15)
                        selected=True
                    if mode=="select" and not confirmed and ("overwrite target?" in chars or "Ziel loeschen?" in chars):
                        key="j" if "Ziel loeschen?" in chars else "y"
                        command("human-monitor-command",{"command-line":f"sendkey {key}"}); confirmed=True
                    if mode=="cancel" and not aborted and ("Copy/verify" in chars or "Kopieren/pruefen" in chars):
                        command("human-monitor-command",{"command-line":"sendkey esc"}); aborted=True
                    result_ready="ASPIDD failed/incomplete." in text if mode=="cancel" else "ASPIDD rescue completed" in text
                    if not finished and result_ready:
                        # Finish stays visible until the user acknowledges it.
                        command("human-monitor-command",{"command-line":f"screendump {out/('gui-'+mode+'.ppm')}"})
                        command("human-monitor-command",{"command-line":"sendkey ret"})
                        finished=True
                time.sleep(.1)
            if proc.poll() is None: raise RuntimeError("rescue VM timed out")
            text=serial.read_bytes().decode("cp437"); print(text)
            if proc.returncode!=1 or "RESCUE TEST PASSED" not in text or "TEST FAILED" in text:
                raise RuntimeError(f"{mode} rescue integration failed")
            if mode!="cli" and not (finished and saw_gui): raise RuntimeError("GUI not exercised")
            if mode=="select" and not (selected and confirmed): raise RuntimeError("GUI selection not exercised")
            if mode=="cancel" and not aborted: raise RuntimeError("GUI cancellation not exercised")
    finally:
        if proc.poll() is None: proc.terminate(); proc.wait(timeout=10)
        if sock.exists(): sock.unlink()
