#!/bin/bash
# ASPIDSK options: SvarDOS, EUSBASPI and two USB devices plugged in after the
# BIOS, ASPIDSK.SYS /ID:1 /R:3 /PAUSE /NOSPINUP.
#   /ID:1   only target 1, the removable stick; the fixed disk (target 0)
#           gets no letter
#   /R:3    the stick (two volumes S1, S2) keeps three letters: C:, D: and
#           the reserved E:, "not ready" (DOS asks Abort/Retry/Fail) while
#           the medium has no third volume
#   /PAUSE  INIT waits for a key (sent through the monitor)
# Then the stick's medium changes to one with three volumes T1..T3: E: must
# show T3.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/dos-aspidsk-options"
EUSBASPI_DIR=${EUSBASPI_DIR:-$ROOT/../eusbaspi}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
DOS_DIR=${DOS_DIR:-$HOME/Iso/Dos}
SVARDOS_ZIP=${SVARDOS_ZIP:-$DOS_DIR/svardos-20250427-floppy-1.44M.zip}

make -C "$ROOT" all >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"
nasm -f bin -w-reloc-abs-word -I"$EUSBASPI_DIR/src/" \
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
    'DEVICE=EUSBASPI.SYS' 'DEVICE=ASPIDSK.SYS /ID:1 /r=3 /PAUSE /NOSPINUP' \
    'LASTDRIVE=Z' 'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
printf '%s\r\n' '@ECHO OFF' 'ECHO === BOOTED > AUX' \
    'TYPE C:\VOL.TXT > AUX' 'TYPE D:\VOL.TXT > AUX' \
    'IF EXIST F:\NUL ECHO EXTRA DRIVE F > AUX' \
    'ECHO === SWAP > AUX' 'WAIT' \
    'TYPE E:\VOL.TXT > AUX' 'TYPE C:\VOL.TXT > AUX' 'TYPE D:\VOL.TXT > AUX' \
    'ECHO OPENASPI OPTIONS DONE > AUX' 'QEXIT' > "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" \
    "$OUT/DELAY.SYS" "$OUT/EUSBASPI.SYS" "$ROOT/build/dos/ASPIDSK.SYS" \
    "$OUT/QEXIT.COM" "$OUT/WAIT.COM" ::/

fat() {
    mkfs.fat -F"$4" -n "$5" --offset "$2" "$1" $(( $3 / 2 )) >/dev/null 2>&1
    printf 'VOLUME %s\r\n' "$5" > "$OUT/VOL.TXT"
    mcopy -i "$1@@$(( $2 * 512 ))" "$OUT/VOL.TXT" ::/
}
truncate -s 32M "$OUT/disk.img"
printf 'label: dos\nstart=2048, size=32768, type=6\n' | sfdisk -q "$OUT/disk.img"
fat "$OUT/disk.img" 2048 32768 16 D1
truncate -s 64M "$OUT/stick.img"
printf 'label: dos\nstart=2048, size=32768, type=6\nstart=34816, size=32768, type=6\n' |
    sfdisk -q "$OUT/stick.img"
fat "$OUT/stick.img" 2048 32768 16 S1
fat "$OUT/stick.img" 34816 32768 16 S2
truncate -s 64M "$OUT/stick2.img"
printf 'label: dos\nstart=2048, size=32768, type=6\nstart=34816, size=32768, type=6\nstart=67584, size=32768, type=6\n' |
    sfdisk -q "$OUT/stick2.img"
fat "$OUT/stick2.img" 2048 32768 16 T1
fat "$OUT/stick2.img" 34816 32768 16 T2
fat "$OUT/stick2.img" 67584 32768 16 T3

monitor() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$OUT/mon.sock" >/dev/null; }
wait_for() {
    for _ in $(seq 1 600); do
        grep -qa "$1" "$OUT/serial.log" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}
set +e
timeout "${TIMEOUT:-120}" qemu-system-i386 \
    -machine pc -m 32 -display none -vga std \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    -device pci-ohci,id=usbhc \
    -serial file:"$OUT/serial.log" \
    -monitor unix:"$OUT/mon.sock",server,nowait \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 &
qemu=$!
sleep 2
monitor "drive_add 0 if=none,id=disk,format=raw,file=$OUT/disk.img"
monitor "device_add usb-storage,id=u1,bus=usbhc.0,port=1,drive=disk,removable=off"
monitor "drive_add 0 if=none,id=stick,format=raw,file=$OUT/stick.img"
monitor "device_add usb-storage,id=u2,bus=usbhc.0,port=2,drive=stick,removable=on"
# /PAUSE: AUTOEXEC does not start until a key is pressed
sleep 12
booted_early=0
grep -qa '=== BOOTED' "$OUT/serial.log" 2>/dev/null && booted_early=1
monitor "screendump $OUT/pause.ppm"
monitor "sendkey ret"
wait_for '=== SWAP' && monitor "change stick $OUT/stick2.img raw"
wait $qemu
set -e

tr -d '\r' < "$OUT/serial.log"
test "$booted_early" = 0 || { echo '/PAUSE did not wait' >&2; exit 1; }
grep -q 'OPENASPI OPTIONS DONE' "$OUT/serial.log"
got=$(tr -d '\r' < "$OUT/serial.log" | sed -n 's/^VOLUME //p' | tr '\n' ' ')
test "$got" = "S1 S2 T3 T1 T2 " || { echo "volumes: $got" >&2; exit 1; }
! grep -q 'EXTRA DRIVE' "$OUT/serial.log"
echo 'OpenASPI ASPIDSK options test passed'
