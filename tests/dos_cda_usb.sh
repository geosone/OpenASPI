#!/bin/bash
# ASPICDA on a USB CD (EUSBASPI, QEMU usb-bot + scsi-cd) under SvarDOS and
# SHSUCDX: DIR, VOL and TYPE must not send READ SUB-CHANNEL (42h), and must
# still work when the drive knows only the commands of a minimal USB CD
# firmware (EUSBASPI test build with REJECT_OPS: everything else beyond
# TEST UNIT READY, REQUEST SENSE, INQUIRY, READ CAPACITY, READ(10) and
# READ TOC ends in ILLEGAL REQUEST).

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/dos-cda-usb}
EUSBASPI_DIR=${EUSBASPI_DIR:-$ROOT/../eusbaspi}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
DOS_DIR=${DOS_DIR:-$HOME/Iso/Dos}
SVARDOS_ZIP=${SVARDOS_ZIP:-$DOS_DIR/svardos-20250427-floppy-1.44M.zip}
REJECT=0x42,0x2B,0x5A,0x1A,0x4A,0x46,0xBE,0x1E,0x1B,0x45,0x47,0x4B,0x4E,0x55,0x15,0x2F,0xBD,0x51,0x52,0x44

make -C "$ROOT" all >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT/cdroot"
nasm -f bin -o "$OUT/QEXIT.COM" "$AHCIASPI_DIR/tools/qexit.asm"

unzip -p "$SVARDOS_ZIP" svdos-1.44M-disk-1.img > "$OUT/boot.img"
while IFS= read -r file; do
    file=${file#::/}
    case "${file^^}" in
        KERNEL.SYS|COMMAND.COM) ;;
        *) mdel -i "$OUT/boot.img" "::/$file" ;;
    esac
done < <(mdir -b -i "$OUT/boot.img" ::/)
printf '%s\r\n' 'DEVICE=EUSBASPI.SYS' 'DEVICE=ASPICDA.SYS /D:ASPICDA0' \
    'LASTDRIVE=Z' 'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
printf '%s\r\n' '@ECHO OFF' 'SHSUCDX /D:ASPICDA0,R > AUX' \
    'DIR R:\ > AUX' 'VOL R: > AUX' 'TYPE R:\README.TXT > AUX' \
    'DIR R:\ > AUX' 'QEXIT' > "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" \
    "$ROOT/build/dos/ASPICDA.SYS" "$ROOT/build/dos/SHSUCDX.COM" \
    "$OUT/QEXIT.COM" ::/

printf 'USB CD read by ASPICDA\r\n' > "$OUT/cdroot/README.TXT"
xorriso -outdev "$OUT/cd.iso" -volid USBCDTEST -map "$OUT/cdroot" / \
    -padding 1m -end 2>/dev/null

run() { # name nasm-options...
    local name=$1; shift
    nasm -f bin -w-reloc-abs-word "$@" -I"$EUSBASPI_DIR/src/" \
        -o "$OUT/EUSBASPI.SYS" "$EUSBASPI_DIR/src/eusbaspi.asm"
    mcopy -o -i "$OUT/boot.img" "$OUT/EUSBASPI.SYS" ::/
    set +e
    timeout "${TIMEOUT:-90}" qemu-system-i386 \
        -machine pc -m 32 -display none -vga std \
        -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
        -device usb-ehci,id=usb -device usb-bot,id=bot,bus=usb.0 \
        -drive "id=cd,if=none,format=raw,media=cdrom,file=$OUT/cd.iso" \
        -device scsi-cd,bus=bot.0,drive=cd \
        -trace scsi_req_parsed \
        -serial file:"$OUT/serial-$name.log" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/qemu-$name.log" 2>&1
    local rc=$?
    set -e
    tr -d '\r\0' < "$OUT/serial-$name.log" > "$OUT/serial-$name.txt"
    cat "$OUT/serial-$name.txt"
    test "$rc" = 1
    test "$(grep -c 'Volume in drive R is USBCDTEST' "$OUT/serial-$name.txt")" = 3
    test "$(grep -c 'README   TXT' "$OUT/serial-$name.txt")" = 2
    grep -q 'USB CD read by ASPICDA' "$OUT/serial-$name.txt"
}
run full
if awk '/scsi_req_parsed/ { for (i = 1; i < NF; i++)
        if ($i == "command" && $(i + 1) == 66) found = 1 }
        END { exit !found }' "$OUT/qemu-full.log"; then
    echo 'READ SUB-CHANNEL sent to the USB CD' >&2
    exit 1
fi
run minimal "-DREJECT_OPS=$REJECT"
echo 'ASPICDA on a USB CD: DIR/VOL/TYPE without READ SUB-CHANNEL, also on a minimal drive'
