#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/dos-tape-ioctl"
DOS_DIR=${DOS_DIR:-$HOME/Iso/Dos}
SVARDOS_ZIP=${SVARDOS_ZIP:-$DOS_DIR/svardos-20250427-floppy-1.44M.zip}
JWASM=${JWASM:-$ROOT/build/tools/jwasm/jwasm}

make -C "$ROOT" all >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"

"$JWASM" -q -bin -0 -W4 -WX -I"$ROOT/" \
    -Fo="$OUT/MOCKASPI.SYS" "$ROOT/tests/mockaspi.asm"
"$JWASM" -q -bin -0 -W4 -WX \
    -Fo="$OUT/TAPETEST.COM" "$ROOT/tests/tape_ioctl.asm"
"$JWASM" -q -bin -0 -W4 -WX \
    -Fo="$OUT/QEXIT.COM" "$ROOT/tests/qexit.asm"

unzip -p "$SVARDOS_ZIP" svdos-1.44M-disk-1.img > "$OUT/boot.img"
while IFS= read -r file; do
    file=${file#::/}
    case "${file^^}" in
        KERNEL.SYS|COMMAND.COM) ;;
        *) mdel -i "$OUT/boot.img" "::/$file" ;;
    esac
done < <(mdir -b -i "$OUT/boot.img" ::/)

printf '%s\r\n' \
    'DEVICE=MOCKASPI.SYS' \
    'DEVICE=ASPITAP.SYS' \
    'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
printf '%s\r\n' \
    '@ECHO OFF' \
    'ASPISCAN > AUX' \
    'TAPECTL > AUX' \
    'TAPETEST > AUX' \
    'QEXIT' > "$OUT/AUTOEXEC.BAT"

mcopy -o -i "$OUT/boot.img" \
    "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" "$OUT/MOCKASPI.SYS" \
    "$ROOT/build/dos/ASPITAP.SYS" "$ROOT/build/dos/ASPISCAN.COM" \
    "$ROOT/build/dos/TAPECTL.COM" \
    "$OUT/TAPETEST.COM" \
    "$OUT/QEXIT.COM" ::/

set +e
timeout "${TIMEOUT:-60}" qemu-system-i386 \
    -machine pc -m 16 -display none -vga std \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    -serial file:"$OUT/serial.log" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04
rc=$?
set -e

if [ "$rc" -eq 124 ]; then
    echo 'QEMU timeout' >&2
    exit 1
fi

tr -d '\r' < "$OUT/serial.log"
grep -q 'OpenASPI TAPECTL status passed' "$OUT/serial.log"
grep -q 'OpenASPI tape IOCTL smoke test passed' "$OUT/serial.log"
! grep -q 'FAILED' "$OUT/serial.log"

echo 'OpenASPI emulated-tape smoke test passed'
