#!/bin/bash
# ASPICHK under MS-DOS 7.1 (the first disk of msdosinst).
# BIOS (default): C: FAT16 with a cross-linked file, D: FAT32 with a broken
#   cluster chain, both partitions of tests/fat_image.sh images (INT 21h
#   7305h).  ASPICHK must find the error (errorlevel 1), repair it with /F,
#   then find nothing; DIR still works and fsck.fat finds no error.
# ASPI=1: EUSBASPI, ASPIDSK and a USB stick with FAT16 and a lost cluster,
#   read through the exFAT service of ASPIDSK.  The FAT stick goes in after
#   the boot (QEMU monitor), in place of an exFAT stick (SeaBIOS would show
#   a FAT stick as a BIOS disk too).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/dos-aspichk}
EUSBASPI_DIR=${EUSBASPI_DIR:-$ROOT/../eusbaspi}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
MSDOS_IMG=${MSDOS_IMG:-$ROOT/../msdosinst/out/DISK1.IMG}
ASPI=${ASPI:-}

make -C "$ROOT" build/dos/ASPICHK.EXE build/dos/ASPIDSK.SYS build/host/test_exfmt >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"
nasm -f bin -o "$OUT/QEXIT.COM" "$AHCIASPI_DIR/tools/qexit.asm"

cp "$MSDOS_IMG" "$OUT/boot.img"
while IFS= read -r file; do
    case "${file^^}" in
        *COMMAND.COM) ;;
        *) mdel -i "$OUT/boot.img" "$file" ;;
    esac
done < <(mdir -b -i "$OUT/boot.img" ::/)

# check, repair, check again; DIR shows the files still
steps() {   # DRIVE NAME
    printf '%s > AUX\r\n' "ECHO === $2" "ASPICHK $1" 'IF ERRORLEVEL 1 ECHO RC1' \
        "ECHO === FIX$2" "ASPICHK $1 /F" "ECHO === AFTER$2" "ASPICHK $1" 'IF ERRORLEVEL 1 ECHO STILL BAD' \
        "DIR $1"
}
# a FAT image of fat_image.sh with DAMAGE as partition 1 (sector 63) of a disk
disk() {   # NAME SIZE_MB BITS DAMAGE TYPE
    sh "$ROOT/tests/fat_image.sh" "$OUT/$1" "$2" "$3" >/dev/null
    python3 "$ROOT/tests/fatchk_corrupt.py" "$OUT/$1/fat.img" "$4"
    python3 - "$OUT/$1/fat.img" "$3" <<'EOF'
import struct, sys
f = open(sys.argv[1], 'r+b')
for s in ((0, 6) if sys.argv[2] == '32' else (0,)):   # hidden sectors 63
    f.seek(s * 512 + 28); f.write(struct.pack('<I', 63))
EOF
    truncate -s $(( $2 + 1 ))M "$OUT/$1.img"
    echo "start=63, size=$(( $2 * 2048 )), type=$5" | sfdisk -q "$OUT/$1.img"
    dd if="$OUT/$1/fat.img" of="$OUT/$1.img" bs=512 seek=63 conv=notrunc status=none
}
if test -n "$ASPI"; then
    nasm -f bin -w-reloc-abs-word -I"$EUSBASPI_DIR/src/" \
        -o "$OUT/EUSBASPI.SYS" "$EUSBASPI_DIR/src/eusbaspi.asm"
    nasm -f bin -o "$OUT/WAIT.COM" "$ROOT/tests/wait_ticks.asm"
    printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' 'DEVICE=A:\EUSBASPI.SYS' 'DEVICE=A:\ASPIDSK.SYS' > "$OUT/CONFIG.SYS"
    { printf '%s > AUX\r\n' 'ECHO === INSERT'; printf 'WAIT\r\n'; steps D: STICK; } > "$OUT/AUTOEXEC.BAT"
    mcopy -o -i "$OUT/boot.img" "$OUT/EUSBASPI.SYS" "$ROOT/build/dos/ASPIDSK.SYS" "$OUT/WAIT.COM" ::/
    truncate -s 32M "$OUT/c.img"
    echo 'start=63, type=6' | sfdisk -q "$OUT/c.img"
    mkfs.fat -F16 -n FATDISK --offset 63 "$OUT/c.img" $(( (32*2048 - 63) / 2 )) >/dev/null
    disk stick 32 16 lost 6
    truncate -s 32M "$OUT/exstick.img"
    echo 'start=2048, type=7' | sfdisk -q "$OUT/exstick.img"
    truncate -s 31M "$OUT/exvol.img"
    "$ROOT/build/host/test_exfmt" "$OUT/exvol.img" 0 1 BOOTSTICK >/dev/null
    dd if="$OUT/exvol.img" of="$OUT/exstick.img" bs=512 seek=2048 conv=notrunc status=none
    disks=(-drive if=ide,index=0,format=raw,file="$OUT/c.img"
           -device pci-ohci,id=usbhc -device usb-bot,id=bot1,bus=usbhc.0,port=1
           -drive id=stick,if=none,format=raw,file="$OUT/exstick.img"
           -device scsi-hd,bus=bot1.0,drive=stick,removable=on,vendor=OPENASPI,product=STICK)
    checked=(stick)
else
    printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' > "$OUT/CONFIG.SYS"
    { steps C: C; steps D: D; } > "$OUT/AUTOEXEC.BAT"
    disk c 32 16 cross 6
    disk d 64 32 chain c
    disks=(-drive if=ide,index=0,format=raw,file="$OUT/c.img"
           -drive if=ide,index=1,format=raw,file="$OUT/d.img")
    checked=(c d)
fi
printf '%s > AUX\r\n' 'ECHO === END' >> "$OUT/AUTOEXEC.BAT"
printf '%s\r\n' 'QEXIT' >> "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" \
    "$ROOT/build/dos/ASPICHK.EXE" "$OUT/QEXIT.COM" ::/

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
    "${disks[@]}" \
    -serial file:"$OUT/serial.log" \
    -monitor unix:"$OUT/mon.sock",server,nowait \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 &
qemu=$!
if test -n "$ASPI"; then wait_for '=== INSERT' && monitor "change stick $OUT/stick.img raw"; fi
wait $qemu
rc=$?
set -e
tr -d '\0' < "$OUT/serial.log" > "$OUT/serial.txt"

fail=0
section() { sed -n "/=== $1 /,/=== $2 /p" "$OUT/serial.txt" | tr -d '\r'; }
need() { section "$1" "$2" | grep -q "$3" || { echo "missing in $1: $3"; fail=1; }; }
lack() { ! section "$1" "$2" | grep -q "$3" || { echo "unexpected in $1: $3"; fail=1; }; }
grep -q 'STILL BAD' "$OUT/serial.txt" && { echo "errors left after /F"; fail=1; }
if test -n "$ASPI"; then
    need STICK FIXSTICK 'ASPI unit'
    need STICK FIXSTICK 'is allocated, but not used (lost)'
    need STICK FIXSTICK 'RC1'
    need FIXSTICK AFTERSTICK 'Corrected'
    need AFTERSTICK END 'No errors found'
    need AFTERSTICK END 'FRAG     BIN'
else
    need C FIXC 'klein.txt: cluster [0-9]* is used twice (cross-linked)'
    need C FIXC 'RC1'
    need C FIXC 'FAT16'
    need FIXC AFTERC 'Corrected'
    need AFTERC D 'No errors found'
    need AFTERC D 'FRAG     BIN'
    need D FIXD 'FAT32 interface'
    need D FIXD 'frag.bin: cluster chain has'
    need D FIXD 'RC1'
    need D FIXD 'FAT32'
    need FIXD AFTERD 'Corrected'
    need AFTERD END 'No errors found'
    need AFTERD END 'FRAG     BIN'
fi
for n in "${checked[@]}"; do
    dd if="$OUT/$n.img" of="$OUT/$n.vol" bs=512 skip=63 status=none
    fsck.fat -n "$OUT/$n.vol" > "$OUT/$n.fsck" 2>&1 || { echo "fsck.fat: errors on $n"; cat "$OUT/$n.fsck"; fail=1; }
done
if test "$fail" = 0; then echo "ASPICHK ${ASPI:+ASPIDSK }test passed (qemu rc=$rc)"; else cat "$OUT/serial.txt"; exit 1; fi
