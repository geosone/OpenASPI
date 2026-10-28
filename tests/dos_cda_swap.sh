#!/bin/bash
# Exchange the CD under AHCIASPI/ASPICDA/SHSUCDX in QEMU (BUS=ahci or ide):
# MEDIA CHANGED must report the exchange once even after another command
# consumed the drive's UNIT ATTENTION, and SHSUCDX must read the new disc.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUS=${BUS:-ahci}
OUT="$ROOT/build/dos-cda-swap-$BUS"
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
DOS_DIR=${DOS_DIR:-$HOME/Iso/Dos}
SVARDOS_ZIP=${SVARDOS_ZIP:-$DOS_DIR/svardos-20250427-floppy-1.44M.zip}

make -C "$ROOT" all >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT/a" "$OUT/b"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX \
    -Fo="$OUT/CDASWAP.COM" "$ROOT/tests/cda_swap.asm"
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

printf '%s\r\n' 'DEVICE=AHCIASPI.SYS /Q' 'DEVICE=ASPICDA.SYS /D:ASPICDA0' \
    'LASTDRIVE=Z' 'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
printf '%s\r\n' '@ECHO OFF' 'SHSUCDX /D:ASPICDA0,R > AUX' \
    'TYPE R:\DISCA.TXT > AUX' 'CDASWAP > AUX' 'TYPE R:\DISCB.TXT > AUX' \
    'IF EXIST R:\DISCA.TXT ECHO STALE DISC A > AUX' 'QEXIT' > "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" \
    "$OUT/AHCIASPI.SYS" "$ROOT/build/dos/ASPICDA.SYS" \
    "$ROOT/build/dos/SHSUCDX.COM" "$OUT/CDASWAP.COM" "$OUT/QEXIT.COM" ::/

printf 'CD SWAP DISC A\r\n' > "$OUT/a/DISCA.TXT"
printf 'CD SWAP DISC B\r\n' > "$OUT/b/DISCB.TXT"
# Different sizes, so a stale capacity cannot pass for the new disc.
xorriso -outdev "$OUT/a.iso" -volid DISCA -map "$OUT/a" / -padding 1m -end 2>/dev/null
xorriso -outdev "$OUT/b.iso" -volid DISCB -map "$OUT/b" / -padding 2m -end 2>/dev/null

timeout "${TIMEOUT:-150}" python3 "$ROOT/tests/cda_swap.py" "$OUT" "$BUS" > "$OUT/result.log"
log=$(tr -d '\r' < "$OUT/serial.log")
grep -q 'CD SWAP DISC A' <<<"$log"
grep -q 'ASPICDA media exchange through the ASPI manager passed' <<<"$log"
grep -q 'CD SWAP DISC B' <<<"$log"
! grep -q 'STALE DISC A\|FAILED' <<<"$log"
echo "OpenASPI ASPICDA media exchange ($BUS) passed"
