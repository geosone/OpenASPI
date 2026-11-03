#!/bin/bash
# ASPIDSK with every volume of a disk: SvarDOS, EUSBASPI and two USB devices
# plugged in after the BIOS (so DOS itself sees none of them), each volume
# with a VOL.TXT naming it.
#   disk (fixed): P1 FAT16, P2 Linux, P3 extended with L1 FAT16, L2 FAT12,
#                 L3 exFAT, L4 type 07h without exFAT, L5 FAT16 LBA;
#                 P4 FAT16 LBA
#   stick (removable): S1 FAT16, S2 FAT16
# ASPIDSK's volumes come FAT first (primaries, then the logical drives),
# then exFAT: C: P1, D: P4, E: L1, F: L2, G: L5, H: L3 (EXFAT.SYS), then the
# stick I: S1, J: S2. P2 and L4 get no letter. Every FAT volume is written
# to and checked on the host. On the stick, a lock taken through I: must
# keep J: from ejecting the cartridge. Then the stick's medium changes to
# one with volumes T1, T2: J: is read first and sees the change, and I:
# must see it too (its own TEST UNIT READY no longer reports it).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/dos-partitions"
EUSBASPI_DIR=${EUSBASPI_DIR:-$ROOT/../eusbaspi}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
DOS_DIR=${DOS_DIR:-$HOME/Iso/Dos}
SVARDOS_ZIP=${SVARDOS_ZIP:-$DOS_DIR/svardos-20250427-floppy-1.44M.zip}

make -C "$ROOT" all >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"
nasm -f bin -w-reloc-abs-word ${E9LOG:+-DE9LOG} -I"$EUSBASPI_DIR/src/" \
    -o "$OUT/EUSBASPI.SYS" "$EUSBASPI_DIR/src/eusbaspi.asm"
nasm -f bin -o "$OUT/DELAY.SYS" "$EUSBASPI_DIR/tools/delay.asm"
nasm -f bin -o "$OUT/QEXIT.COM" "$AHCIASPI_DIR/tools/qexit.asm"
nasm -f bin -o "$OUT/WAIT.COM" "$ROOT/tests/wait_ticks.asm"

unzip -p "$SVARDOS_ZIP" svdos-1.44M-disk-1.img > "$OUT/boot.img"
while IFS= read -r file; do
    file=${file#::/}
    case "${file^^}" in
        KERNEL.SYS|COMMAND.COM) ;;
        *) mdel -i "$OUT/boot.img" "::/$file" ;;
    esac
done < <(mdir -b -i "$OUT/boot.img" ::/)

printf '%s\r\n' 'DEVICE=DELAY.SYS' 'DEVICE=DELAY.SYS' 'DEVICE=DELAY.SYS' \
    'DEVICE=EUSBASPI.SYS' 'DEVICE=ASPIDSK.SYS' 'DEVICE=EXFAT.SYS' \
    'LASTDRIVE=Z' 'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
{
    printf '%s\r\n' '@ECHO OFF'
    for d in C D E F G H I J; do printf 'TYPE %s:\\VOL.TXT > AUX\r\n' "$d"; done
    printf '%s\r\n' 'IF EXIST K:\NUL ECHO EXTRA DRIVE K > AUX'
    for d in C D E F G I J; do
        printf 'COPY BIG.BIN %s:\\BIGW.BIN > NUL\r\n' "$d"
    done
    printf '%s\r\n' 'VERIFY ON' 'COPY BIG.BIN E:\BIGV.BIN > NUL' 'VERIFY OFF' \
        'ASPICTL LOCK I: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
        'EJECT J: > AUX' 'IF NOT ERRORLEVEL 1 GOTO FAILED' \
        'ASPICTL UNLOCK I: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
        'ECHO Sibling lock passed > AUX' 'GOTO DONE' \
        ':FAILED' 'ECHO Sibling lock FAILED > AUX' ':DONE' \
        'ECHO === SWAP > AUX' 'WAIT' \
        'TYPE J:\VOL.TXT > AUX' 'TYPE I:\VOL.TXT > AUX' \
        'ECHO OPENASPI PARTITIONS DONE > AUX' 'QEXIT'
} > "$OUT/AUTOEXEC.BAT"
head -c 100000 /dev/urandom > "$OUT/BIG.BIN"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" \
    "$OUT/DELAY.SYS" "$OUT/EUSBASPI.SYS" "$ROOT/build/dos/ASPIDSK.SYS" \
    "$ROOT/build/dos/EXFAT.SYS" "$ROOT/build/dos/ASPICTL.EXE" \
    "$ROOT/build/dos/EJECT.EXE" "$OUT/QEXIT.COM" "$OUT/WAIT.COM" "$OUT/BIG.BIN" ::/

# fat IMG START SIZE FATBITS NAME: a FAT volume with VOL.TXT
fat() {
    mkfs.fat -F"$4" -n "$5" --offset "$2" "$1" $(( $3 / 2 )) >/dev/null 2>&1
    printf 'VOLUME %s\r\n' "$5" > "$OUT/VOL.TXT"
    mcopy -i "$1@@$(( $2 * 512 ))" "$OUT/VOL.TXT" ::/
}
truncate -s 128M "$OUT/disk.img"
sfdisk -q "$OUT/disk.img" <<'EOF'
label: dos
start=2048, size=32768, type=6
start=34816, size=16384, type=83
start=51200, size=163840, type=5
start=215040, size=47104, type=e
start=53248, size=32768, type=6
start=88064, size=8192, type=1
start=98304, size=32768, type=7
start=133120, size=16384, type=7
start=151552, size=32768, type=e
EOF
sfdisk -d "$OUT/disk.img" > "$OUT/disk.layout"
fat "$OUT/disk.img" 2048 32768 16 P1
fat "$OUT/disk.img" 215040 47104 16 P4
fat "$OUT/disk.img" 53248 32768 16 L1
fat "$OUT/disk.img" 88064 8192 12 L2
fat "$OUT/disk.img" 151552 32768 16 L5
sh "$ROOT/tests/exfat_image.sh" "$OUT/x" 16 >/dev/null
dd if="$OUT/x/exfat.img" of="$OUT/disk.img" bs=512 seek=98304 conv=notrunc status=none
truncate -s 64M "$OUT/stick.img"
sfdisk -q "$OUT/stick.img" <<'EOF'
label: dos
start=2048, size=32768, type=6
start=34816, size=96256, type=6
EOF
fat "$OUT/stick.img" 2048 32768 16 S1
fat "$OUT/stick.img" 34816 96256 16 S2
cp "$OUT/stick.img" "$OUT/stick2.img"
fat "$OUT/stick2.img" 2048 32768 16 T1
fat "$OUT/stick2.img" 34816 96256 16 T2

# the exFAT volume's VOL.TXT
printf 'VOLUME L3\r\n' > "$OUT/VOL.TXT"
loop=$(udisksctl loop-setup --no-user-interaction -o $((98304 * 512)) \
    -s $((32768 * 512)) -f "$OUT/disk.img" | sed -n 's/.* as \(\/dev\/[a-z0-9]*\)\.$/\1/p')
mnt=$(udisksctl mount --no-user-interaction -b "$loop" | sed -n 's/.* at \(.*\)$/\1/p')
cp "$OUT/VOL.TXT" "$mnt/VOL.TXT"
udisksctl unmount --no-user-interaction -b "$loop" >/dev/null
udisksctl loop-delete --no-user-interaction -b "$loop" >/dev/null

monitor() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$OUT/mon.sock" >/dev/null; }
wait_for() {
    for _ in $(seq 1 600); do
        grep -qa "$1" "$OUT/serial.log" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}
set +e
timeout "${TIMEOUT:-150}" qemu-system-i386 \
    -machine pc -m 32 -display none -vga std \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    -device pci-ohci,id=usbhc \
    -serial file:"$OUT/serial.log" -debugcon file:"$OUT/debug.log" \
    -monitor unix:"$OUT/mon.sock",server,nowait \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 &
qemu=$!
# after the BIOS, before EUSBASPI (DELAY.SYS)
sleep 2
monitor "drive_add 0 if=none,id=disk,format=raw,file=$OUT/disk.img"
monitor "device_add usb-storage,id=u1,bus=usbhc.0,port=1,drive=disk,removable=off"
monitor "drive_add 0 if=none,id=stick,format=raw,file=$OUT/stick.img"
monitor "device_add usb-storage,id=u2,bus=usbhc.0,port=2,drive=stick,removable=on"
wait_for '=== SWAP' && monitor "change stick $OUT/stick2.img raw"
wait $qemu
set -e

tr -d '\r' < "$OUT/serial.log"
grep -q 'OPENASPI PARTITIONS DONE' "$OUT/serial.log"
# the volumes in their order, each once
got=$(tr -d '\r' < "$OUT/serial.log" | sed -n 's/^VOLUME //p' | tr '\n' ' ')
test "$got" = "P1 P4 L1 L2 L5 L3 S1 S2 T2 T1 " || { echo "volumes: $got" >&2; exit 1; }
grep -q 'Sibling lock passed' "$OUT/serial.log"
! grep -q 'EXTRA DRIVE\|FAILED' "$OUT/serial.log"
# the writes, read back from the images; the file systems still consistent
check() {
    dd if="$1" of="$OUT/part.img" bs=512 skip="$2" count="$3" status=none
    fsck.fat -n "$OUT/part.img" >/dev/null
    for f in $4; do cmp <(mcopy -i "$OUT/part.img" "::/$f" -) "$OUT/BIG.BIN"; done
}
check "$OUT/disk.img" 2048 32768 BIGW.BIN
check "$OUT/disk.img" 215040 47104 BIGW.BIN
check "$OUT/disk.img" 53248 32768 'BIGW.BIN BIGV.BIN'
check "$OUT/disk.img" 88064 8192 BIGW.BIN
check "$OUT/disk.img" 151552 32768 BIGW.BIN
check "$OUT/stick.img" 2048 32768 BIGW.BIN
check "$OUT/stick.img" 34816 96256 BIGW.BIN
# the Linux partition and the non-exFAT type 07h stay untouched
test "$(sfdisk -d "$OUT/disk.img")" = "$(cat "$OUT/disk.layout")"
rm -f "$OUT/part.img"
echo 'OpenASPI ASPIDSK all partitions test passed'
