#!/bin/bash
# Boots MS-DOS 7.1 (the first disk of msdosinst) with EXFAT.SYS and two IDE
# disks: a FAT16 disk (BIOS 80h, C:) and an exFAT disk (BIOS 81h) with an
# MBR partition of type 07h, which gets D:.  DIR, CD, TYPE and COPY *.* to
# C: go through the redirector; the copies are compared on the host with
# the files written by the Linux exFAT driver.
#   SUPER=1: the exFAT disk without a partition table (superfloppy)
#   SVARDOS=1: SvarDOS (EDR-DOS kernel) instead of MS-DOS 7.1
#   HIGH=DIR: MS-DOS with HIMEM.SYS, EMM386.EXE and MEM.EXE from DIR and
#             DEVICEHIGH=EXFAT.SYS; MEM /C must show it in upper memory
#   OPTS=/C: options for EXFAT.SYS (/C: CHS reads without INT 13h extensions)
#   DAMAGE=bitmap-set: damage of tests/exchk_corrupt.py EXCHK must find and
#             EXCHK /F repair (fsck.exfat checks the result); only damage
#             that keeps the file data: bitmap-set, bitmap-clear, hash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/dos-exfat}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
MSDOS_IMG=${MSDOS_IMG:-$ROOT/../msdosinst/out/DISK1.IMG}
SUPER=${SUPER:-0}
SVARDOS=${SVARDOS:-0}
HIGH=${HIGH:-}
OPTS=${OPTS:-}
DAMAGE=${DAMAGE:-}
SVARDOS_ZIP=${SVARDOS_ZIP:-$HOME/Iso/Dos/svardos-20250427-floppy-1.44M.zip}

make -C "$ROOT" build/dos/EXFAT.SYS build/dos/EXCHK.EXE >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"
nasm -f bin -o "$OUT/QEXIT.COM" "$AHCIASPI_DIR/tools/qexit.asm"

# boot floppy: the system files and COMMAND.COM only
if test "$SVARDOS" = 1; then
    unzip -p "$SVARDOS_ZIP" svdos-1.44M-disk-1.img > "$OUT/boot.img"
else
    cp "$MSDOS_IMG" "$OUT/boot.img"
fi
while IFS= read -r file; do
    case "${file^^}" in
        *COMMAND.COM|*KERNEL.SYS) ;;
        *) mdel -i "$OUT/boot.img" "$file" ;;
    esac
done < <(mdir -b -i "$OUT/boot.img" ::/)
if test -n "$HIGH"; then
    printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' 'DEVICE=A:\HIMEM.SYS' \
        'DEVICE=A:\EMM386.EXE NOEMS' 'DOS=HIGH,UMB' "DEVICEHIGH=A:\\EXFAT.SYS $OPTS" > "$OUT/CONFIG.SYS"
    mcopy -o -i "$OUT/boot.img" "$HIGH/HIMEM.SYS" "$HIGH/EMM386.EXE" "$HIGH/MEM.EXE" ::/
else
    printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' "DEVICE=A:\\EXFAT.SYS $OPTS" > "$OUT/CONFIG.SYS"
fi
# every command with "> AUX": SvarCOM has no CTTY
printf '%s > AUX\r\n' \
    'ECHO === DIR' 'DIR D:' \
    'ECHO === DIR /S' 'DIR D:\UNTERO~1 /S' \
    'ECHO === LABEL' 'VOL D:' \
    'ECHO === TYPE' 'TYPE D:\README.TXT' 'TYPE D:\EINLA~11.TXT' \
    'ECHO === CD' 'D:' 'CD \UNTERO~1\TIEFER' 'CD' 'TYPE DATEI.DAT' 'CD ..' 'CD' 'CD \NIX' 'A:' \
    'ECHO === WRITE' 'COPY A:\QEXIT.COM D:\NEU.COM' 'MD D:\NEU' 'DEL D:\README.TXT' \
    'ECHO === COPY' 'MD C:\OUT' 'COPY D:\*.* C:\OUT' 'COPY D:\SUB\*.* C:\OUT' \
    'ECHO === EXCHK' 'EXCHK D:' 'IF ERRORLEVEL 1 ECHO EXCHK FAILED' \
    'ECHO === EXCHK /F' 'EXCHK D: /F' 'EXCHK D:' 'IF ERRORLEVEL 1 ECHO AFTER FIX FAILED' 'DIR D:\SUB' \
    'ECHO === END' > "$OUT/AUTOEXEC.BAT"
if test -n "$HIGH"; then printf '%s > AUX\r\n' 'MEM /C' >> "$OUT/AUTOEXEC.BAT"; fi
printf '%s\r\n' \
    'QEXIT' >> "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" \
    "$ROOT/build/dos/EXFAT.SYS" "$ROOT/build/dos/EXCHK.EXE" "$OUT/QEXIT.COM" ::/

# C: FAT16 for the copies
truncate -s 32M "$OUT/fat.img"
echo 'start=63, type=6' | sfdisk -q "$OUT/fat.img"
mkfs.fat -F16 -n FATDISK --offset 63 "$OUT/fat.img" $(( (32*2048 - 63) / 2 )) >/dev/null

# the exFAT disk
sh "$ROOT/tests/exfat_image.sh" "$OUT/x" 64 >/dev/null
if test -n "$DAMAGE"; then python3 "$ROOT/tests/exchk_corrupt.py" "$OUT/x/exfat.img" "$DAMAGE"; fi
if test "$SUPER" = 1; then
    cp "$OUT/x/exfat.img" "$OUT/exfat-disk.img"
else
    truncate -s 65M "$OUT/exfat-disk.img"
    echo 'start=2048, type=7' | sfdisk -q "$OUT/exfat-disk.img"
    dd if="$OUT/x/exfat.img" of="$OUT/exfat-disk.img" bs=512 seek=2048 conv=notrunc status=none
fi

set +e
timeout "${TIMEOUT:-120}" qemu-system-i386 \
    -machine pc -m 32 -display none -vga std \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    -drive if=ide,index=0,format=raw,file="$OUT/fat.img" \
    -drive if=ide,index=1,format=raw,file="$OUT/exfat-disk.img" \
    -serial file:"$OUT/serial.log" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04
rc=$?
set -e
tr -d '\0' < "$OUT/serial.log" > "$OUT/serial.txt"

fail=0
check() { grep -q "$1" "$OUT/serial.txt" || { echo "missing: $1"; fail=1; }; }
check '=== END'
check '        21 files'
if test -n "$DAMAGE"; then
    check 'EXCHK FAILED'
    check 'Corrected: '
    check 'A        B'
    grep -q 'AFTER FIX FAILED' "$OUT/serial.txt" && { echo "EXCHK /F did not repair"; fail=1; }
    if test "$SUPER" = 1; then cp "$OUT/exfat-disk.img" "$OUT/fixed.img"
    else dd if="$OUT/exfat-disk.img" of="$OUT/fixed.img" bs=512 skip=2048 status=none; fi
    fsck.exfat -n "$OUT/fixed.img" >/dev/null 2>&1 || { echo "fsck.exfat finds errors after EXCHK /F"; fail=1; }
else
    check 'No errors found'
    grep -q 'EXCHK FAILED' "$OUT/serial.txt" && { echo "EXCHK failed"; fail=1; }
fi
check 'EINLA~11'
check 'UNTERO~1'
check 'Datei 11'
check 'tief'
if test -n "$HIGH"; then
    grep -qE '^  EXFAT +[0-9.,]+ +\([0-9]+K\) +0 +\(0K\)' "$OUT/serial.txt" ||
        { echo "EXFAT.SYS not in upper memory"; fail=1; }
fi
mkdir -p "$OUT/copies"
mcopy -n -i "$OUT/fat.img@@32256" '::/OUT/*' "$OUT/copies/" 2>/dev/null || fail=1
F=$OUT/x/files
cmp_file() { cmp -s "$OUT/copies/$1" "$2" || { echo "differs: $1"; fail=1; }; }
cmp_file ZUFALL.BIN "$F/zufall.bin"
cmp_file FRAG.BIN "$F/frag.bin"
cmp_file SPARSE.DAT "$F/sparse.dat"
cmp_file README.TXT "$F/README.TXT"
cmp_file EINLA~12.TXT "$F/Ein langer Name 12.txt"
cmp_file A.B "$F/SUB/A.B"
if test "$fail" = 0; then echo "EXFAT.SYS test passed (qemu rc=$rc)"; else cat "$OUT/serial.txt"; exit 1; fi
