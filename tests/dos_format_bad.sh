#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/format-bad}
make -C "$ROOT" all build/host/test_fat_format >/dev/null
mkdir -p "$OUT"
cp "$ROOT/build/removable-tools/boot.img" "$OUT/boot.img"
cp --sparse=always "$ROOT/build/removable-tools/storage.img" "$OUT/storage.img"
mcopy -o -i "$OUT/boot.img" "$ROOT/build/dos/ASPIFDD.SYS" "$ROOT/build/dos/ASPIFMT.EXE" ::/
for mode in fat12 fat16 metadata; do
    sectors=19200; bad=1000; option=
    [ "$mode" != fat12 ] || { sectors=1440; bad=357; }
    [ "$mode" != metadata ] || bad=1
    "$ROOT/build/host/test_fat_format" "$sectors" "$OUT/disk.img" >/dev/null
    cat > "$OUT/bad.conf" <<EOF
[inject-error]
event = "read_aio"
errno = "5"
sector = "$bad"
once = "off"
immediately = "on"
EOF
    check='IF ERRORLEVEL 1 GOTO FAILED'
    [ "$mode" != metadata ] || check='IF NOT ERRORLEVEL 1 GOTO FAILED'
    printf '%s\r\n' '@ECHO OFF' "ASPIFMT D: /YES $option > AUX" \
        "$check" 'ECHO BAD FORMAT TEST PASSED > AUX' 'GOTO DONE' ':FAILED' \
        'ECHO BAD FORMAT TEST FAILED > AUX' ':DONE' 'QEXIT' > "$OUT/AUTOEXEC.BAT"
    mcopy -o -i "$OUT/boot.img" "$OUT/AUTOEXEC.BAT" ::/
    set +e
    timeout 180 qemu-system-i386 -machine pc -m 32 -display none \
        -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
        -drive if=ide,format=raw,file="$OUT/storage.img" \
        -device usb-ehci,id=usb -device usb-bot,id=bot,bus=usb.0 \
        -drive "id=src,if=none,format=raw,file=blkdebug:$OUT/bad.conf:$OUT/disk.img" \
        -device scsi-hd,bus=bot.0,drive=src,removable=on,vendor=IOMEGA,product=ZIP-100 \
        -serial file:"$OUT/serial-$mode.log" -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        > "$OUT/process-$mode.log" 2>&1
    rc=$?
    set -e
    cat "$OUT/serial-$mode.log"
    test "$rc" = 1
    grep -Fq 'BAD FORMAT TEST PASSED' "$OUT/serial-$mode.log"
    ! grep -Fq 'TEST FAILED' "$OUT/serial-$mode.log"
    [ "$mode" = metadata ] && continue
    fsck.fat -vn "$OUT/disk.img" > "$OUT/fsck-$mode.log"
    python3 - "$OUT/disk.img" "$bad" "$mode" <<'PY'
import struct,sys
from pathlib import Path
p=Path(sys.argv[1]); bad=int(sys.argv[2]); mode=sys.argv[3]
b=p.read_bytes(); spc=b[13]; reserved=struct.unpack_from('<H',b,14)[0]
fat=struct.unpack_from('<H',b,22)[0]; root=struct.unpack_from('<H',b,17)[0]
data=reserved+2*fat+(root*32+511)//512
cluster=2+(bad-data)//spc; bits=12 if mode=='fat12' else 16
entry=cluster+cluster//2 if bits==12 else 2*cluster
for copy in range(2):
    v=struct.unpack_from('<H',b,(reserved+copy*fat)*512+entry)[0]
    if bits==12: v=(v>>4 if cluster&1 else v&0xFFF)
    assert v==(0xFF7 if bits==12 else 0xFFF7),(mode,copy,cluster,hex(v))
PY
done
echo 'FAT12/16 bad-cluster marking, boundary packing and metadata failure passed'
