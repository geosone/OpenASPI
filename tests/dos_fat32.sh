#!/bin/bash
# FreeDOS with FAT32 support; all disks are disposable copies or new images.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/fat32-dos}
BOOT=${FREEDOS_IMG:-$HOME/Iso/Dos/freedos/FD14LITE.img}
make -C "$ROOT" all >/dev/null
mkdir -p "$OUT"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX -DUSE_FAT32 \
    -Fo="$OUT/MID32.COM" "$ROOT/tests/media_id_dos.asm"
cp "$BOOT" "$OUT/boot.img"
truncate -s $((196608*512)) "$OUT/zip.img"
image="$OUT/zip.img"
if [ -n "${BAD_LBA:-}" ]; then
    cat > "$OUT/bad.conf" <<EOF
[inject-error]
event = "read_aio"
errno = "5"
sector = "$BAD_LBA"
once = "off"
immediately = "on"
EOF
    image="blkdebug:$OUT/bad.conf:$OUT/zip.img"
fi
nasm -f bin -w-reloc-abs-word -I"$ROOT/../eusbaspi/src/" \
    -o "$OUT/EUSBASPI.SYS" "$ROOT/../eusbaspi/src/eusbaspi.asm"
printf '%s\r\n' 'DEVICE=C:\EUSBASPI.SYS' 'DEVICE=C:\ASPIFDD.SYS /V' \
    'LASTDRIVE=Z' 'SHELL=C:\COMMAND.COM C:\ /P=C:\FDAUTO.BAT' > "$OUT/FDCONFIG.SYS"
printf '%s\r\n' '@ECHO OFF' 'ASPIFMT D: /YES /FAT:32 > AUX' \
    'IF ERRORLEVEL 1 GOTO FAILED' 'MID32 D: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'ECHO FAT32 DOS file access passed>D:\FAT32.TXT' \
    'TYPE D:\FAT32.TXT > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'ECHO FAT32 TEST PASSED > AUX' 'GOTO DONE' ':FAILED' \
    'ECHO FAT32 TEST FAILED > AUX' ':DONE' 'QEXIT' > "$OUT/FDAUTO.BAT"
mcopy -o -i "$OUT/boot.img@@32256" "$OUT/FDCONFIG.SYS" "$OUT/FDAUTO.BAT" \
    "$OUT/EUSBASPI.SYS" "$ROOT/build/dos/ASPIFDD.SYS" \
    "$ROOT/build/dos/ASPIFMT.EXE" "$ROOT/build/dos-cda/QEXIT.COM" "$OUT/MID32.COM" ::/
printf '\xf8\x02' > "$OUT/sercon-port"
set +e
timeout "${TIMEOUT:-180}" qemu-system-i386 -machine pc -m 32 -display none \
    -drive if=ide,format=raw,file="$OUT/boot.img" -boot c \
    -device usb-ehci,id=usb -device usb-bot,id=bot,bus=usb.0 \
    -drive "id=zip,if=none,format=raw,file=$image" \
    -device scsi-hd,bus=bot.0,drive=zip,removable=on,vendor=IOMEGA,product=ZIP-100 \
    -serial file:"$OUT/serial.log" -serial file:"$OUT/console.log" \
    -fw_cfg name=etc/sercon-port,file="$OUT/sercon-port" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/process.log" 2>&1
rc=$?
set -e
cat "$OUT/serial.log"
test "$rc" = 1
grep -Fq 'FAT32 TEST PASSED' "$OUT/serial.log"
! grep -Fq 'FAILED' "$OUT/serial.log"
fsck.fat -vn "$OUT/zip.img" > "$OUT/fsck.log"
mtype -i "$OUT/zip.img" ::/FAT32.TXT | grep -Fq 'FAT32 DOS file access passed'
echo 'FAT32 format, mount and DOS file read/write passed'

# Mount the same FAT32 media through the generic ASPIDSK owner as well.
printf '%s\r\n' 'DEVICE=C:\EUSBASPI.SYS' 'DEVICE=C:\ASPIDSK.SYS' \
    'LASTDRIVE=Z' 'SHELL=C:\COMMAND.COM C:\ /P=C:\FDAUTO.BAT' > "$OUT/FDCONFIG.SYS"
printf '%s\r\n' '@ECHO OFF' 'MID32 D: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'TYPE D:\FAT32.TXT > AUX' \
    'IF ERRORLEVEL 1 GOTO FAILED' 'ECHO ASPIDSK FAT32 write passed>D:\DSK32.TXT' \
    'TYPE D:\DSK32.TXT > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'ECHO ASPIDSK FAT32 TEST PASSED > AUX' 'GOTO DONE' ':FAILED' \
    'ECHO ASPIDSK FAT32 TEST FAILED > AUX' ':DONE' 'QEXIT' > "$OUT/FDAUTO.BAT"
mcopy -o -i "$OUT/boot.img@@32256" "$OUT/FDCONFIG.SYS" "$OUT/FDAUTO.BAT" \
    "$ROOT/build/dos/ASPIDSK.SYS" ::/
set +e
timeout 180 qemu-system-i386 -machine pc -m 32 -display none \
    -drive if=ide,format=raw,file="$OUT/boot.img" -boot c \
    -device usb-ehci,id=usb -device usb-bot,id=bot,bus=usb.0 \
    -drive "id=zip,if=none,format=raw,file=$image" \
    -device scsi-hd,bus=bot.0,drive=zip,removable=on,vendor=OPENASPI,product=STICK \
    -serial file:"$OUT/serial-dsk.log" -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    > "$OUT/process-dsk.log" 2>&1
rc=$?
set -e
cat "$OUT/serial-dsk.log"
test "$rc" = 1
grep -Fq 'ASPIDSK FAT32 TEST PASSED' "$OUT/serial-dsk.log"
! grep -Fq 'FAILED' "$OUT/serial-dsk.log"
fsck.fat -vn "$OUT/zip.img" > "$OUT/fsck-dsk.log"
