#!/bin/bash
# Real DOS INIT/enumeration with memory-only ASPI; no host block devices.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/block-ownership}
SVARDOS_ZIP=${SVARDOS_ZIP:-$HOME/Iso/Dos/svardos-20250427-floppy-1.44M.zip}
make -C "$ROOT" all >/dev/null
mkdir -p "$OUT"
unzip -p "$SVARDOS_ZIP" svdos-1.44M-disk-1.img > "$OUT/boot.img"
for driver in DSK FDD; do
    flags=()
    [ "$driver" != FDD ] || flags=(-DTEST_FDD)
    "$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX "${flags[@]}" \
        -Fo="$OUT/OWN$driver.COM" "$ROOT/tests/block_ownership.asm"
done
printf '\xba\xf4\x00\xb0\x00\xee\xeb\xfe' > "$OUT/QEXIT.COM"
printf '%s\r\n' 'LASTDRIVE=Z' 'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
printf '%s\r\n' '@ECHO OFF' 'OWNDSK > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'OWNFDD > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' 'ECHO OWNERSHIP PASSED > AUX' \
    'GOTO DONE' ':FAILED' 'ECHO OWNERSHIP FAILED > AUX' ':DONE' 'QEXIT' > "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" \
    "$OUT/OWNDSK.COM" "$OUT/OWNFDD.COM" "$OUT/QEXIT.COM" ::/
set +e
timeout "${TIMEOUT:-60}" qemu-system-i386 -machine pc -m 32 -display none \
    -drive "if=floppy,format=raw,file=$OUT/boot.img" -boot a \
    -serial "file:$OUT/serial.log" -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    > "$OUT/process.log" 2>&1
rc=$?
set -e
cat "$OUT/serial.log"
test "$rc" = 1
! grep -Fq 'FAILED' "$OUT/serial.log"
test "$(grep -Fc 'Block INIT BIOS ownership tests passed' "$OUT/serial.log")" = 2
grep -Fq 'OWNERSHIP PASSED' "$OUT/serial.log"
grep -Fq 'BIOS/DOS-owned device skipped: 12:31:0' "$OUT/serial.log"
test "$(grep -Fc 'GET DISK INFO unsupported' "$OUT/serial.log")" = 4
echo 'ASPIDSK/ASPIFDD INIT ownership, unsupported-manager and error tests passed'
