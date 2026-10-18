#!/bin/bash
# Boot SvarDOS with AHCIASPI, ASPITAP and an ATAPI CD-ROM.  This deliberately
# has no tape: ASPITAP must reject installation cleanly, while ASPISCAN must
# enumerate the CD-ROM through the same SCSIMGR$ and report zero tape devices.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/dos-scan"
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
DOS_DIR=${DOS_DIR:-$HOME/Iso/Dos}
SVARDOS_ZIP=${SVARDOS_ZIP:-$DOS_DIR/svardos-20250427-floppy-1.44M.zip}

make -C "$ROOT" all >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT/cdroot"

nasm -f bin -w-reloc-abs-word -DE9LOG -I"$AHCIASPI_DIR/src/" \
    -o "$OUT/AHCIASPI.SYS" "$AHCIASPI_DIR/src/ahciaspi.asm"
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
    'DEVICE=AHCIASPI.SYS /Q' \
    'DEVICE=ASPITAP.SYS' \
    'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
printf '%s\r\n' \
    '@ECHO OFF' \
    'ASPISCAN > AUX' \
    'QEXIT' > "$OUT/AUTOEXEC.BAT"

mcopy -o -i "$OUT/boot.img" \
    "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" "$OUT/AHCIASPI.SYS" \
    "$ROOT/build/dos/ASPITAP.SYS" "$ROOT/build/dos/ASPISCAN.COM" \
    "$OUT/QEXIT.COM" ::/

printf 'OpenASPI read-only scan test\r\n' > "$OUT/cdroot/README.TXT"
xorriso -as mkisofs -quiet -V OPENASPI -o "$OUT/cd.iso" \
    "$OUT/cdroot" 2>/dev/null

set +e
timeout "${TIMEOUT:-60}" qemu-system-i386 \
    -machine pc -m 32 -display none -vga std \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    -device ich9-ahci,id=ahci \
    -drive id=cd,if=none,format=raw,media=cdrom,file="$OUT/cd.iso" \
    -device ide-cd,drive=cd,bus=ahci.0,model='OPENASPI CD-ROM' \
    -debugcon file:"$OUT/debug.log" -serial file:"$OUT/serial.log" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04
rc=$?
set -e

if [ "$rc" -eq 124 ]; then
    echo 'QEMU timeout' >&2
    exit 1
fi

tr -d '\r' < "$OUT/serial.log"
grep -q 'type=05' "$OUT/serial.log"
grep -q 'tapes: 00' "$OUT/serial.log"
grep -q 'ASPITAP RMT0 absent' "$OUT/serial.log"

echo 'OpenASPI DOS scan smoke test passed'
