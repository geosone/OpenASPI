#!/bin/bash
# Boot SvarDOS with EUSBASPI, ASPIDSK and ASPIFDD and three USB devices: a
# partitioned stick (ASPIDSK), a partitioned ZIP and an LS-120 superfloppy
# (ASPIFDD).  The drivers must not claim the same device, and every volume
# must be readable and writable through its driver (WRITE, and WRITE AND
# VERIFY with VERIFY ON).
#
# SeaBIOS presents the partitioned USB devices as BIOS disks as well, so DOS
# gives them C: and D:; ASPIDSK gets E:, ASPIFDD F: (ZIP) and G: (LS-120).

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/dos-disk"
EUSBASPI_DIR=${EUSBASPI_DIR:-$ROOT/../eusbaspi}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
DOS_DIR=${DOS_DIR:-$HOME/Iso/Dos}
SVARDOS_ZIP=${SVARDOS_ZIP:-$DOS_DIR/svardos-20250427-floppy-1.44M.zip}
DETECT_ONLY=${DETECT_ONLY:-0}
case "$DETECT_ONLY" in 0|1) ;; *) exit 1 ;; esac
if test "$DETECT_ONLY" = 1; then OUT="$OUT-detect"; fi

make -C "$ROOT" all >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX -Fo="$OUT/BLKFALL.COM" "$ROOT/tests/block_fallback.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX -Fo="$OUT/BLKIO.COM" "$ROOT/tests/block_ioctl.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX -DTEST_FDD -Fo="$OUT/FDDIO.COM" "$ROOT/tests/block_ioctl.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX -Fo="$OUT/DOSIO.COM" "$ROOT/tests/block_ioctl_dos.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX -Fo="$OUT/FDDGONE.COM" "$ROOT/tests/block_eject_dos.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX -Fo="$OUT/BLKACC.COM" "$ROOT/tests/block_access.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX -DTEST_FDD -Fo="$OUT/FDDACC.COM" "$ROOT/tests/block_access.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX -Fo="$OUT/MIDDSK.COM" "$ROOT/tests/media_id_write.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX -DTEST_FDD -Fo="$OUT/MIDFDD.COM" "$ROOT/tests/media_id_write.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX -Fo="$OUT/MIDLIVE.COM" "$ROOT/tests/media_id_dos.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX -Fo="$OUT/PARAMDSK.COM" "$ROOT/tests/block_params.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX -DTEST_FDD -Fo="$OUT/PARAMFDD.COM" "$ROOT/tests/block_params.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX -Fo="$OUT/TRACKDSK.COM" "$ROOT/tests/block_track.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX -DTEST_FDD -Fo="$OUT/TRACKFDD.COM" "$ROOT/tests/block_track.asm"

nasm -f bin -w-reloc-abs-word -I"$EUSBASPI_DIR/src/" \
    -o "$OUT/EUSBASPI.SYS" "$EUSBASPI_DIR/src/eusbaspi.asm"
nasm -f bin -o "$OUT/QEXIT.COM" "$AHCIASPI_DIR/tools/qexit.asm"

unzip -p "$SVARDOS_ZIP" svdos-1.44M-disk-1.img > "$OUT/boot.img"
while IFS= read -r file; do
    file=${file#::/}
    case "${file^^}" in
        KERNEL.SYS|COMMAND.COM) ;;
        *) mdel -i "$OUT/boot.img" "::/$file" ;;
    esac
done < <(mdir -b -i "$OUT/boot.img" ::/)

printf '%s\r\n' \
    'DEVICE=EUSBASPI.SYS' \
    'DEVICE=ASPIDSK.SYS' \
    'DEVICE=ASPIFDD.SYS' \
    'LASTDRIVE=Z' \
    'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
printf '%s\r\n' \
    '@ECHO OFF' \
    'BLKFALL > AUX' \
    'BLKIO > AUX' \
    'FDDIO > AUX' \
    'BLKACC > AUX' \
    'FDDACC > AUX' \
    'MIDDSK > AUX' \
    'MIDFDD > AUX' \
    'PARAMDSK > AUX' \
    'PARAMFDD > AUX' \
    'TRACKDSK > AUX' \
    'TRACKFDD > AUX' \
    'DOSIO > AUX' \
    'MIDLIVE E: > AUX' \
    'MIDLIVE F: > AUX' \
    'MIDLIVE G: > AUX' \
    'TYPE E:\DSKTEST.TXT > AUX' \
    'TYPE F:\ZIPTEST.TXT > AUX' \
    'TYPE G:\SFTEST.TXT > AUX' \
    'IF EXIST H:\NUL ECHO EXTRA DRIVE H > AUX' \
    'COPY E:\BIG.BIN BIG.BIN > NUL' \
    'COPY BIG.BIN E:\BIGW.BIN > NUL' \
    'VERIFY ON' \
    'COPY BIG.BIN F:\BIGW.BIN > NUL' \
    'COPY BIG.BIN G:\BIGW.BIN > NUL' \
    'VERIFY OFF' \
    'MD E:\NEWDIR' \
    'ECHO written by ASPIDSK > E:\NEWDIR\W.TXT' \
    'CALL CTLTEST.BAT' \
    'QEXIT' > "$OUT/AUTOEXEC.BAT"
printf '%s\r\n' '@ECHO OFF' \
    'ASPICTL LOCK F: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'ASPICTL LOCK F: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'ASPICTL STATUS F: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'EJECT F: > AUX' 'IF NOT ERRORLEVEL 1 GOTO FAILED' \
    'ASPICTL UNLOCK F: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'EJECT F: > AUX' 'IF NOT ERRORLEVEL 1 GOTO FAILED' \
    'CLOSE F: > AUX' 'IF NOT ERRORLEVEL 2 GOTO FAILED' \
    'EJECT F: /FORCE > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'ASPICTL STATUS F: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'FDDGONE > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'ECHO FDD ASPICTL locks/force/eject passed > AUX' 'GOTO DONE' \
    ':FAILED' 'ECHO FDD ASPICTL FAILED > AUX' ':DONE' > "$OUT/CTLTEST.BAT"
if test "$DETECT_ONLY" = 1; then
    printf '%s\r\n' '@ECHO OFF' 'BLKFALL > AUX' 'BLKIO > AUX' 'FDDIO > AUX' \
        'ASPISCAN /Q /DISK' 'IF ERRORLEVEL 1 GOTO failed' \
        'ASPISCAN /Q /FDD' 'IF ERRORLEVEL 2 GOTO failed' \
        'IF NOT ERRORLEVEL 1 GOTO failed' \
        'ECHO Removable stick detection passed > AUX' 'QEXIT' \
        ':failed' 'ECHO Removable stick detection FAILED > AUX' 'QEXIT' > "$OUT/AUTOEXEC.BAT"
fi
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" \
    "$OUT/EUSBASPI.SYS" "$ROOT/build/dos/ASPIDSK.SYS" \
    "$ROOT/build/dos/ASPIFDD.SYS" "$ROOT/build/dos/ASPISCAN.COM" "$OUT/BLKFALL.COM" \
    "$OUT/BLKIO.COM" "$OUT/FDDIO.COM" "$OUT/DOSIO.COM" "$OUT/QEXIT.COM" ::/
mcopy -o -i "$OUT/boot.img" "$OUT/CTLTEST.BAT" "$OUT/FDDGONE.COM" \
    "$ROOT/build/dos/ASPICTL.EXE" "$ROOT/build/dos/EJECT.EXE" "$ROOT/build/dos/CLOSE.EXE" ::/
mcopy -o -i "$OUT/boot.img" "$OUT/BLKACC.COM" "$OUT/FDDACC.COM" ::/
mcopy -o -i "$OUT/boot.img" "$OUT/MIDDSK.COM" "$OUT/MIDFDD.COM" "$OUT/MIDLIVE.COM" ::/
mcopy -o -i "$OUT/boot.img" "$OUT/PARAMDSK.COM" "$OUT/PARAMFDD.COM" ::/
mcopy -o -i "$OUT/boot.img" "$OUT/TRACKDSK.COM" "$OUT/TRACKFDD.COM" ::/

# partitioned stick (FAT16, partition at 63) with a file larger than one
# 64-sector READ(10)
truncate -s 64M "$OUT/stick.img"
echo 'start=63, type=6' | sfdisk -q "$OUT/stick.img"
mkfs.fat -F16 -i 11112222 -n STICK --offset 63 "$OUT/stick.img" $(( (64*2048 - 63) / 2 )) >/dev/null
printf 'ASPIDSK STICK PASSED\r\n' > "$OUT/DSKTEST.TXT"
head -c 100000 /dev/urandom > "$OUT/BIG.BIN"
mcopy -i "$OUT/stick.img@@32256" "$OUT/DSKTEST.TXT" "$OUT/BIG.BIN" ::/
# ZIP: partitioned (partition at 32, as Iomega formats it)
truncate -s 96M "$OUT/zip.img"
echo 'start=32, type=6' | sfdisk -q "$OUT/zip.img"
mkfs.fat -F16 -i 33334444 -n ZIPDISK --offset 32 "$OUT/zip.img" $(( (96*2048 - 32) / 2 )) >/dev/null
printf 'ASPIFDD ZIP PASSED\r\n' > "$OUT/ZIPTEST.TXT"
mcopy -i "$OUT/zip.img@@16384" "$OUT/ZIPTEST.TXT" ::/
# LS-120: superfloppy (no partition table)
truncate -s 120M "$OUT/ls120.img"
mkfs.fat -F16 -i 55556666 -n SUPERDISK "$OUT/ls120.img" >/dev/null
printf 'ASPIFDD LS-120 PASSED\r\n' > "$OUT/SFTEST.TXT"
mcopy -i "$OUT/ls120.img" "$OUT/SFTEST.TXT" ::/

fdd_devices=()
if test "$DETECT_ONLY" = 0; then
    fdd_devices=(-device usb-bot,id=bot2,bus=usbhc.0,port=2
        -drive "id=zip,if=none,format=raw,file=$OUT/zip.img"
        -device scsi-hd,bus=bot2.0,drive=zip,removable=on,vendor=IOMEGA,product=ZIP-100
        -device usb-bot,id=bot3,bus=usbhc.0,port=3
        -drive "id=ls120,if=none,format=raw,file=$OUT/ls120.img"
        -device scsi-hd,bus=bot3.0,drive=ls120,removable=on,vendor=MATSHITA,product=LS-120)
fi
set +e
timeout "${TIMEOUT:-90}" qemu-system-i386 \
    -machine pc -m 32 -display none -vga std \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    -device pci-ohci,id=usbhc \
    -device usb-bot,id=bot1,bus=usbhc.0,port=1 \
    -drive id=stick,if=none,format=raw,file="$OUT/stick.img" \
    -device scsi-hd,bus=bot1.0,drive=stick,removable=on,vendor=OPENASPI,product=STICK \
    "${fdd_devices[@]}" \
    -serial file:"$OUT/serial.log" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04
rc=$?
set -e

if [ "$rc" -eq 124 ]; then
    echo 'QEMU timeout' >&2
    exit 1
fi
test "$rc" -eq 1 || { echo "Unexpected QEMU exit: $rc" >&2; exit 1; }
grep -q 'Block fallback LBA/buffer/count and hard-error tests passed' "$OUT/serial.log"
test "$(grep -c 'Block IOCTL parameters/query tests passed' "$OUT/serial.log")" -eq 2
! grep -q 'Block IOCTL regression FAILED' "$OUT/serial.log"
if test "$DETECT_ONLY" = 1; then
    grep -q 'Removable stick detection passed' "$OUT/serial.log"
    ! grep -q 'FAILED' "$OUT/serial.log"
    echo 'OpenASPI removable USB stick detector regression passed'
    exit 0
fi

grep -q 'DOS block IOCTL end-to-end tests passed' "$OUT/serial.log"
test "$(grep -Fc 'Block access policy/logical mapping tests passed' "$OUT/serial.log")" = 2
test "$(grep -Fc 'Media-ID write, backup, extent and failure tests passed' "$OUT/serial.log")" = 2
test "$(grep -Fc 'Block SET parameters, capacity, override and media-change tests passed' "$OUT/serial.log")" = 2
test "$(grep -Fc 'Block track CHS/buffer/chunk/verify/error tests passed' "$OUT/serial.log")" = 2
test "$(grep -Fc 'DOS Media-ID set/get/restore passed' "$OUT/serial.log")" = 3
test "$(grep -Fc 'DOS physical track read/write/verify passed' "$OUT/serial.log")" = 3
grep -q 'FDD ASPICTL locks/force/eject passed' "$OUT/serial.log"
grep -q 'locks=2' "$OUT/serial.log"
grep -q 'locks=0' "$OUT/serial.log"
! grep -q 'FAILED' "$OUT/serial.log"
! grep -q 'DOS block IOCTL end-to-end FAILED' "$OUT/serial.log"
mcopy -o -i "$OUT/boot.img" ::/BIG.BIN "$OUT/BIG.OUT"
cmp "$OUT/BIG.OUT" "$OUT/BIG.BIN"
# the files written through the drivers, read back from the images
mcopy -o -i "$OUT/stick.img@@32256" ::/BIGW.BIN "$OUT/W1.BIN"
mcopy -o -i "$OUT/zip.img@@16384" ::/BIGW.BIN "$OUT/W2.BIN"
mcopy -o -i "$OUT/ls120.img" ::/BIGW.BIN "$OUT/W3.BIN"
for f in W1 W2 W3; do cmp "$OUT/$f.BIN" "$OUT/BIG.BIN"; done
mtype -i "$OUT/stick.img@@32256" ::/NEWDIR/W.TXT | grep -q 'written by ASPIDSK'
# the file systems are still consistent
dd if="$OUT/stick.img" of="$OUT/part.img" bs=512 skip=63 status=none
fsck.fat -n "$OUT/part.img" >/dev/null
dd if="$OUT/zip.img" of="$OUT/part.img" bs=512 skip=32 status=none
fsck.fat -n "$OUT/part.img" >/dev/null
fsck.fat -n "$OUT/ls120.img" >/dev/null

tr -d '\r' < "$OUT/serial.log"
grep -q 'ASPIDSK STICK PASSED' "$OUT/serial.log"
grep -q 'ASPIFDD ZIP PASSED' "$OUT/serial.log"
grep -q 'ASPIFDD LS-120 PASSED' "$OUT/serial.log"
! grep -q 'EXTRA DRIVE' "$OUT/serial.log"

echo 'OpenASPI ASPIDSK/ASPIFDD read/write test passed'
