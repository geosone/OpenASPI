#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/format-partition}
BASE=${BASE:-$ROOT/build/dos-disk}
make -C "$ROOT" all >/dev/null
mkdir -p "$OUT"
cp "$BASE/zip.img" "$OUT/zip.img"
cp "$BASE/boot.img" "$OUT/boot.img"
dd if="$OUT/zip.img" of="$OUT/prefix-before.bin" bs=512 count=32 status=none
printf '%s\r\n' 'DEVICE=EUSBASPI.SYS' 'DEVICE=ASPIFDD.SYS /V' \
    'LASTDRIVE=Z' 'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
printf '%s\r\n' '@ECHO OFF' 'ASPIFMT D: /YES > AUX' \
    'IF ERRORLEVEL 1 GOTO FAILED' 'ECHO PARTITION FORMAT PASSED > AUX' 'GOTO DONE' \
    ':FAILED' 'ECHO PARTITION FORMAT FAILED > AUX' ':DONE' 'QEXIT' > "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" \
    "$ROOT/build/dos/ASPIFDD.SYS" "$ROOT/build/dos/ASPIFMT.EXE" ::/
set +e
timeout 180 qemu-system-i386 -machine pc -m 32 -display none \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    -device usb-ehci,id=usb -device usb-bot,id=bot,bus=usb.0 \
    -drive "id=zip,if=none,format=raw,file=$OUT/zip.img" \
    -device scsi-hd,bus=bot.0,drive=zip,removable=on,vendor=IOMEGA,product=ZIP-100 \
    -serial file:"$OUT/serial.log" -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    > "$OUT/process.log" 2>&1
rc=$?
set -e
cat "$OUT/serial.log"
test "$rc" = 1
grep -Fq 'PARTITION FORMAT PASSED' "$OUT/serial.log"
! grep -Fq 'FAILED' "$OUT/serial.log"
dd if="$OUT/zip.img" of="$OUT/prefix-after.bin" bs=512 count=32 status=none
cmp "$OUT/prefix-before.bin" "$OUT/prefix-after.bin"
dd if="$OUT/zip.img" of="$OUT/volume.img" bs=512 skip=32 status=none
fsck.fat -vn "$OUT/volume.img" > "$OUT/fsck.log"
if mdir -i "$OUT/zip.img@@16384" ::/BIGW.BIN >/dev/null 2>&1; then
    echo 'Format failed to clear old root directory' >&2; exit 1
fi
echo 'Partitioned ZIP format preserves MBR and prefix sectors'
