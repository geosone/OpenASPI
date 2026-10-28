#!/bin/bash
# ASPIDSK on a write-protected medium: MS-DOS 7.1, EUSBASPI and a read-only
# QEMU USB disk, whose target answers WRITE with DATA PROTECT. Absolute and
# DOS writes to D: must fail with DOS error 00h (write protect), and D: stays
# readable. FDD=1: ASPIFDD with the disk named as a ZIP drive.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/dos-disk-protect}
EUSBASPI_DIR=${EUSBASPI_DIR:-$ROOT/../eusbaspi}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
MSDOS_IMG=${MSDOS_IMG:-$ROOT/../msdosinst/out/DISK1.IMG}
BLK=ASPIDSK; PRODUCT=STICK
if test -n "${FDD:-}"; then BLK=ASPIFDD; PRODUCT='ZIP 100'; fi

make -C "$ROOT" build/dos/$BLK.SYS >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"
nasm -f bin -o "$OUT/QEXIT.COM" "$AHCIASPI_DIR/tools/qexit.asm"
nasm -f bin -w-reloc-abs-word -I"$EUSBASPI_DIR/src/" \
    -o "$OUT/EUSBASPI.SYS" "$EUSBASPI_DIR/src/eusbaspi.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX \
    -Fo="$OUT/PROTECT.COM" "$ROOT/tests/disk_protect.asm"

cp "$MSDOS_IMG" "$OUT/boot.img"
while IFS= read -r file; do
    case "${file^^}" in
        *COMMAND.COM) ;;
        *) mdel -i "$OUT/boot.img" "$file" ;;
    esac
done < <(mdir -b -i "$OUT/boot.img" ::/)
printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' 'DEVICE=A:\EUSBASPI.SYS' \
    "DEVICE=A:\\$BLK.SYS" > "$OUT/CONFIG.SYS"
printf '%s > AUX\r\n' 'ECHO === START' 'PROTECT' 'TYPE D:\README.TXT' \
    'ECHO === END' > "$OUT/AUTOEXEC.BAT"
printf '%s\r\n' 'QEXIT' >> "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" "$OUT/EUSBASPI.SYS" \
    "$ROOT/build/dos/$BLK.SYS" "$OUT/PROTECT.COM" "$OUT/QEXIT.COM" ::/

truncate -s 32M "$OUT/stick.img"
echo 'start=63, type=6' | sfdisk -q "$OUT/stick.img"
mkfs.fat -F16 -n PROTECTED --offset 63 "$OUT/stick.img" $(( (32*2048 - 63) / 2 )) >/dev/null
printf 'Protected stick read by %s\r\n' "$BLK" > "$OUT/README.TXT"
mcopy -i "$OUT/stick.img@@32256" "$OUT/README.TXT" ::/
sum_before=$(sha256sum < "$OUT/stick.img")

set +e
timeout "${TIMEOUT:-120}" qemu-system-i386 \
    -machine pc -m 32 -display none -vga std \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    -device pci-ohci,id=usbhc \
    -device usb-bot,id=bot1,bus=usbhc.0,port=1 \
    -drive id=stick,if=none,format=raw,readonly=on,file="$OUT/stick.img" \
    -device scsi-hd,bus=bot1.0,drive=stick,removable=on,vendor=OPENASPI,product="$PRODUCT" \
    -serial file:"$OUT/serial.log" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04
rc=$?
set -e
tr -d '\0' < "$OUT/serial.log" > "$OUT/serial.txt"

fail=0
grep -q "Live block write protection passed" "$OUT/serial.txt" || fail=1
grep -q "Protected stick read by $BLK" "$OUT/serial.txt" || fail=1
grep -q '=== END' "$OUT/serial.txt" || fail=1
test "$(sha256sum < "$OUT/stick.img")" = "$sum_before" || fail=1
if test "$fail" = 0; then
    echo "$BLK live write protection test passed (qemu rc=$rc)"
else
    cat "$OUT/serial.txt"
    exit 1
fi
