#!/bin/bash
# ASPIDSK /I13 (GitHub issue #2): MS-DOS 7.1, EUSBASPI on OHCI and two USB
# disks plugged in after the BIOS: a FAT16 stick (C:, INT 13h 80h) and a
# disk with only an NTFS partition (no letter, INT 13h 81h).  I13TEST
# checks the INT 13h functions on both and writes the last drive (sector
# contents restored).  With NTFSDOS_DIR (Sysinternals NTFSDOS.EXE) or
# NTFS4DOS (path of NTFS4DOS.EXE) given, those must mount the NTFS
# partition and TYPE a file of it; they are not part of OpenASPI.
#   NTFS_ONLY=1: only the NTFS disk (81h becomes 80h); ASPIDSK has no
#   unit then and must stay as a character device for its INT 13h drive
#   NTFSDOS_DIR=~/mars/scratch/ntfs/ntfsdos
#   NTFS4DOS=~/mars/scratch/ntfs/ntfs4dos/fw/ntfs4dos.us
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/dos-ntfs-i13}
EUSBASPI_DIR=${EUSBASPI_DIR:-$ROOT/../eusbaspi}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
MSDOS_IMG=${MSDOS_IMG:-$ROOT/../msdosinst/out/DISK1.IMG}
NTFSDOS_DIR=${NTFSDOS_DIR:-}
NTFS4DOS=${NTFS4DOS:-}
NTFS_ONLY=${NTFS_ONLY:-0}

make -C "$ROOT" build/dos/ASPIDSK.SYS >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"
nasm -f bin -o "$OUT/I13TEST.COM" "$ROOT/tests/i13test.asm"
nasm -f bin -o "$OUT/QEXIT.COM" "$AHCIASPI_DIR/tools/qexit.asm"
nasm -f bin -o "$OUT/DELAY.SYS" "$EUSBASPI_DIR/tools/delay.asm"
nasm -f bin -w-reloc-abs-word -I"$EUSBASPI_DIR/src/" \
    -o "$OUT/EUSBASPI.SYS" "$EUSBASPI_DIR/src/eusbaspi.asm"

cp "$MSDOS_IMG" "$OUT/boot.img"
while IFS= read -r file; do
    case "${file^^}" in
        *COMMAND.COM) ;;
        *) mdel -i "$OUT/boot.img" "$file" ;;
    esac
done < <(mdir -b -i "$OUT/boot.img" ::/)
printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' 'DEVICE=A:\DELAY.SYS' 'DEVICE=A:\DELAY.SYS' \
    'DEVICE=A:\EUSBASPI.SYS' 'DEVICE=A:\ASPIDSK.SYS /I13' > "$OUT/CONFIG.SYS"
printf '%s > AUX\r\n' 'ECHO === I13' 'TYPE C:\FATTEST.TXT' 'I13TEST W' > "$OUT/AUTOEXEC.BAT"
files=("$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" "$OUT/EUSBASPI.SYS" "$OUT/DELAY.SYS"
    "$ROOT/build/dos/ASPIDSK.SYS" "$OUT/I13TEST.COM" "$OUT/QEXIT.COM")
if test -n "$NTFSDOS_DIR"; then
    printf '%s > AUX\r\n' 'ECHO === NTFSDOS' 'NTFSDOS /L:N' 'TYPE N:\README.TXT' >> "$OUT/AUTOEXEC.BAT"
    files+=("$NTFSDOS_DIR/NTFSDOS.EXE")
fi
if test -n "$NTFS4DOS"; then
    cp "$NTFS4DOS" "$OUT/NTFS4DOS.EXE"
    printf '%s > AUX\r\n' 'ECHO === NTFS4DOS' 'NTFS4DOS' 'DIR N:' 'DIR O:' >> "$OUT/AUTOEXEC.BAT"
    files+=("$OUT/NTFS4DOS.EXE")
fi
printf '%s > AUX\r\n' 'ECHO === END' >> "$OUT/AUTOEXEC.BAT"
printf '%s\r\n' 'QEXIT' >> "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "${files[@]}" ::/

# FAT16 stick
truncate -s 32M "$OUT/fat.img"
echo 'start=63, type=6' | sfdisk -q "$OUT/fat.img"
mkfs.fat -F16 -n FATSTICK --offset 63 "$OUT/fat.img" $(( (32*2048 - 63) / 2 )) >/dev/null
printf 'FAT stick read by ASPIDSK\r\n' > "$OUT/FATTEST.TXT"
mcopy -i "$OUT/fat.img@@32256" "$OUT/FATTEST.TXT" ::/
# NTFS disk: one type 07h partition at 1 MB
SECTORS=$((128 * 2048))
truncate -s $((SECTORS * 512)) "$OUT/ntfs.img"
echo 'start=2048, type=7' | sfdisk -q "$OUT/ntfs.img"
truncate -s $(((SECTORS - 2048) * 512)) "$OUT/part.img"
mkntfs -q -F -Q -s 512 -p 2048 -H 255 -S 63 -L NTFSDISK "$OUT/part.img" >/dev/null
printf 'NTFS volume read through INT 13h\r\n' > "$OUT/README.TXT"
ntfscp -q "$OUT/part.img" "$OUT/README.TXT" README.TXT
dd if="$OUT/part.img" of="$OUT/ntfs.img" bs=512 seek=2048 conv=notrunc status=none
rm -f "$OUT/part.img"
cp "$OUT/ntfs.img" "$OUT/ntfs-before.img"

plug=()
if test "$NTFS_ONLY" = 0; then plug+=(
    "drive_add 0 if=none,id=fat,format=raw,file=$OUT/fat.img"
    "device_add usb-bot,id=bot1,bus=usbhc.0,port=1"
    "device_add scsi-hd,bus=bot1.0,drive=fat,removable=on,vendor=OPENASPI,product=STICK"
    "qom-set /machine/peripheral/bot1 attached true"); fi
plug+=(
    "drive_add 0 if=none,id=ntfs,format=raw,file=$OUT/ntfs.img"
    "device_add usb-bot,id=bot2,bus=usbhc.0,port=2"
    "device_add scsi-hd,bus=bot2.0,drive=ntfs,vendor=OPENASPI,product=NTFS"
    "qom-set /machine/peripheral/bot2 attached true")
set +e
{ sleep 2; printf '%s\n' "${plug[@]}"; sleep "${TIMEOUT:-120}"; } |
timeout "${TIMEOUT:-120}" qemu-system-i386 \
    -machine pc -m 32 -display none -vga std -monitor stdio \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    -device pci-ohci,id=usbhc \
    -serial file:"$OUT/serial.log" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/monitor.log" 2>&1
rc=$?
set -e
tr -d '\0' < "$OUT/serial.log" > "$OUT/serial.txt"

fail=0
need() { grep -q "$1" "$OUT/serial.txt" || { echo "missing: $1"; fail=1; }; }
need '=== END'
NTFS_DRIVE=81
if test "$NTFS_ONLY" = 0; then
    need 'FAT stick read by ASPIDSK'
    need 'I13 80 ext 21 sectors 00010000 chs .* type 06AA55'
else
    NTFS_DRIVE=80
fi
need "I13 $NTFS_DRIVE ext 21 sectors $(printf '%08X' $SECTORS) chs .* type 07AA55"
need 'I13 write ok'
need 'I13TEST PASSED'
grep -q 'FAIL' "$OUT/serial.txt" && { echo 'a check failed'; fail=1; }
cmp -s "$OUT/ntfs.img" "$OUT/ntfs-before.img" || { echo 'the NTFS disk changed'; fail=1; }
if test -n "$NTFSDOS_DIR"; then
    need 'NTFS volume read through INT 13h'
fi
if test -n "$NTFS4DOS"; then
    sed -n '/=== NTFS4DOS/,/=== END/p' "$OUT/serial.txt" | grep -q 'README' ||
        { echo 'NTFS4DOS: no README.TXT'; fail=1; }
    sed -n '/=== NTFS4DOS/,/=== END/p' "$OUT/serial.txt" | grep -q 'CauseWay error' &&
        { echo 'NTFS4DOS crashed'; fail=1; }
fi
if test "$fail" = 0; then echo "ASPIDSK /I13 test passed (qemu rc=$rc)"; else cat "$OUT/serial.txt"; exit 1; fi
