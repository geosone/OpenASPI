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
# the ZIP is plugged in after the BIOS (DELAY.SYS from dos_disk waits for it),
# else EUSBASPI serves it as the BIOS disk C: and ASPIFDD leaves it alone
printf '%s\r\n' 'DEVICE=DELAY.SYS' 'DEVICE=DELAY.SYS' \
    'DEVICE=EUSBASPI.SYS' 'DEVICE=ASPIFDD.SYS /V' \
    'LASTDRIVE=Z' 'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
printf '%s\r\n' '@ECHO OFF' 'ASPIFMT C: /YES > AUX' \
    'IF ERRORLEVEL 1 GOTO FAILED' 'ECHO PARTITION FORMAT PASSED > AUX' 'GOTO DONE' \
    ':FAILED' 'ECHO PARTITION FORMAT FAILED > AUX' ':DONE' 'QEXIT' > "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" \
    "$ROOT/build/dos/ASPIFDD.SYS" "$ROOT/build/dos/ASPIFMT.EXE" ::/
set +e
{ sleep 2; printf '%s\n' \
    "drive_add 0 if=none,id=zip,format=raw,file=$OUT/zip.img" \
    "device_add usb-bot,id=bot,bus=usb.0" \
    "device_add scsi-hd,bus=bot.0,drive=zip,removable=on,vendor=IOMEGA,product=ZIP-100" \
    "qom-set /machine/peripheral/bot attached true"; sleep 180; } |
timeout 180 qemu-system-i386 -machine pc -m 32 -display none -monitor stdio \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    -device usb-ehci,id=usb \
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
