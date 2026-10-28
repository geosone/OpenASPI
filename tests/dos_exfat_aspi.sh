#!/bin/bash
# EXFAT.SYS with ASPIDSK: MS-DOS 7.1, EUSBASPI and a USB stick (removable
# SCSI disk) with an exFAT partition.  SeaBIOS shows the stick as a BIOS disk
# too; EXFAT.SYS must use it once, through ASPIDSK's letter (D:).
#   1. exFAT in: D: is EXFAT.SYS's (DIR, TYPE, COPY to C:)
#   2. the host changes the medium to a FAT16 stick: D: back to DOS/ASPIDSK
#   3. and back to the exFAT stick: D: again EXFAT.SYS's
# FDD=1: ASPIFDD instead of ASPIDSK, the stick named as a ZIP drive
# DAMAGE=hash: damage of tests/exchk_corrupt.py, repaired by EXCHK D: /F
#   through the WRITE function of the exFAT service

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/dos-exfat-aspi}
EUSBASPI_DIR=${EUSBASPI_DIR:-$ROOT/../eusbaspi}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
MSDOS_IMG=${MSDOS_IMG:-$ROOT/../msdosinst/out/DISK1.IMG}
BLK=ASPIDSK; PRODUCT=STICK
if test -n "${FDD:-}"; then BLK=ASPIFDD; PRODUCT='ZIP 100'; fi
DAMAGE=${DAMAGE:-}
FIX=; test -z "$DAMAGE" || FIX=' /F'

make -C "$ROOT" build/dos/EXFAT.SYS build/dos/EXCHK.EXE build/dos/$BLK.SYS >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"
nasm -f bin -o "$OUT/QEXIT.COM" "$AHCIASPI_DIR/tools/qexit.asm"
nasm -f bin -o "$OUT/WAIT.COM" "$ROOT/tests/wait_ticks.asm"
nasm -f bin -w-reloc-abs-word -I"$EUSBASPI_DIR/src/" \
    -o "$OUT/EUSBASPI.SYS" "$EUSBASPI_DIR/src/eusbaspi.asm"

cp "$MSDOS_IMG" "$OUT/boot.img"
while IFS= read -r file; do
    case "${file^^}" in
        *COMMAND.COM) ;;
        *) mdel -i "$OUT/boot.img" "$file" ;;
    esac
done < <(mdir -b -i "$OUT/boot.img" ::/)
printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' 'DEVICE=A:\EUSBASPI.SYS' \
    "DEVICE=A:\\$BLK.SYS" 'DEVICE=A:\EXFAT.SYS' > "$OUT/CONFIG.SYS"
printf '%s > AUX\r\n' \
    'ECHO === EXFAT1' 'DIR D:' 'TYPE D:\EINLA~11.TXT' 'MD C:\OUT' 'COPY D:\*.* C:\OUT' \
    "EXCHK D:$FIX" 'EXCHK D:' 'ECHO === SWAP1' > "$OUT/AUTOEXEC.BAT"
printf '%s\r\n' 'WAIT' >> "$OUT/AUTOEXEC.BAT"
printf '%s > AUX\r\n' \
    'ECHO === FAT' 'DIR D:' 'DIR D:' 'TYPE D:\FATTEST.TXT' \
    'ECHO === SWAP2' >> "$OUT/AUTOEXEC.BAT"
printf '%s\r\n' 'WAIT' >> "$OUT/AUTOEXEC.BAT"
printf '%s > AUX\r\n' \
    'ECHO === EXFAT2' 'DIR D:' 'DIR D:' 'TYPE D:\README.TXT' \
    'ECHO === END' >> "$OUT/AUTOEXEC.BAT"
printf '%s\r\n' 'QEXIT' >> "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" "$OUT/EUSBASPI.SYS" \
    "$ROOT/build/dos/$BLK.SYS" "$ROOT/build/dos/EXFAT.SYS" "$ROOT/build/dos/EXCHK.EXE" "$OUT/QEXIT.COM" "$OUT/WAIT.COM" ::/

# C: FAT16 for the copies
truncate -s 32M "$OUT/fat.img"
echo 'start=63, type=6' | sfdisk -q "$OUT/fat.img"
mkfs.fat -F16 -n FATDISK --offset 63 "$OUT/fat.img" $(( (32*2048 - 63) / 2 )) >/dev/null

# the exFAT stick (MBR, type 07h) and a FAT16 stick
sh "$ROOT/tests/exfat_image.sh" "$OUT/x" 64 >/dev/null
if test -n "$DAMAGE"; then python3 "$ROOT/tests/exchk_corrupt.py" "$OUT/x/exfat.img" "$DAMAGE"; fi
truncate -s 65M "$OUT/exstick.img"
echo 'start=2048, type=7' | sfdisk -q "$OUT/exstick.img"
dd if="$OUT/x/exfat.img" of="$OUT/exstick.img" bs=512 seek=2048 conv=notrunc status=none
truncate -s 32M "$OUT/fatstick.img"
echo 'start=63, type=6' | sfdisk -q "$OUT/fatstick.img"
mkfs.fat -F16 -n FATSTICK --offset 63 "$OUT/fatstick.img" $(( (32*2048 - 63) / 2 )) >/dev/null
printf 'FAT stick read by ASPIDSK\r\n' > "$OUT/FATTEST.TXT"
mcopy -i "$OUT/fatstick.img@@32256" "$OUT/FATTEST.TXT" ::/

monitor() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$OUT/mon.sock" >/dev/null; }
wait_for() {
    for _ in $(seq 1 600); do
        grep -qa "$1" "$OUT/serial.log" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}

set +e
timeout "${TIMEOUT:-180}" qemu-system-i386 \
    -machine pc -m 32 -display none -vga std \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    -drive if=ide,index=0,format=raw,file="$OUT/fat.img" \
    -device pci-ohci,id=usbhc \
    -device usb-bot,id=bot1,bus=usbhc.0,port=1 \
    -drive id=stick,if=none,format=raw,file="$OUT/exstick.img" \
    -device scsi-hd,bus=bot1.0,drive=stick,removable=on,vendor=OPENASPI,product="$PRODUCT" \
    -serial file:"$OUT/serial.log" \
    -monitor unix:"$OUT/mon.sock",server,nowait \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 &
qemu=$!
wait_for '=== SWAP1' && monitor "change stick $OUT/fatstick.img raw"
wait_for '=== SWAP2' && monitor "change stick $OUT/exstick.img raw"
wait $qemu
rc=$?
set -e
tr -d '\0' < "$OUT/serial.log" > "$OUT/serial.txt"

fail=0
section() { sed -n "/=== $1/,/=== $2/p" "$OUT/serial.txt"; }
need() { section "$1" "$2" | grep -q "$3" || { echo "missing in $1: $3"; fail=1; }; }
need EXFAT1 SWAP1 'EINLA~11'
need EXFAT1 SWAP1 'Datei 11'
need EXFAT1 SWAP1 'No errors found'
if test -n "$DAMAGE"; then
    need EXFAT1 SWAP1 'Corrected: '
    dd if="$OUT/exstick.img" of="$OUT/fixed.img" bs=512 skip=2048 status=none
    fsck.exfat -n "$OUT/fixed.img" >/dev/null 2>&1 || { echo "fsck.exfat finds errors after EXCHK /F"; fail=1; }
fi
need EXFAT1 SWAP1 'ASPI unit 0'
need FAT SWAP2 'FAT stick read by'
need FAT SWAP2 'FATSTICK'
need EXFAT2 END 'OPENASPI'
need EXFAT2 END 'hallo'
test "$(grep -c 'EINLA~11' "$OUT/serial.txt")" -ge 2 || { echo "exFAT not back"; fail=1; }
mkdir -p "$OUT/copies"
mcopy -n -i "$OUT/fat.img@@32256" '::/OUT/*' "$OUT/copies/" 2>/dev/null || fail=1
cmp -s "$OUT/copies/FRAG.BIN" "$OUT/x/files/frag.bin" || { echo "differs: FRAG.BIN"; fail=1; }
cmp -s "$OUT/copies/ZUFALL.BIN" "$OUT/x/files/zufall.bin" || { echo "differs: ZUFALL.BIN"; fail=1; }
if test "$fail" = 0; then echo "EXFAT.SYS with $BLK test passed (qemu rc=$rc)"; else cat "$OUT/serial.txt"; exit 1; fi
