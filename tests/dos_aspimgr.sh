#!/bin/bash
# Exercise the actual QUILIB GUI and ASPI C/assembly bridge on native ATAPI.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOX=${BOX:-$ROOT/../86Box/build-upc/src/86Box}
ROMDIR=${ROMDIR:-$HOME/.local/share/86Box/roms}
MAXLANG=${MAXLANG:-US}
NOASPI=${NOASPI:-0}
OUT=${OUT:-$ROOT/build/aspimgr-test-$MAXLANG-$NOASPI}
make -C "$ROOT" MAXLANG="$MAXLANG" all >/dev/null
test -x "$BOX"
test -d "$ROMDIR"
mkdir -p "$OUT"
test ! -e "$OUT/control.sock"
if [ ! -f "$ROOT/build/dos-cda/boot.img" ]; then
    bash "$ROOT/tests/dos_cda.sh" >/dev/null
fi
cp "$ROOT/build/dos-cda/boot.img" "$OUT/boot.img"
cp "$ROOT/tests/fixtures/86box-ls120.cfg" "$OUT/86box.cfg"
truncate -s $((963*256*512)) "$OUT/ls120.img"
# Inventory uses only INQUIRY, so this image intentionally has no filesystem.
printf '%s\r\n' 'DEVICE=AHCIASPI.SYS /Q' 'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
printf '%s\r\n' '@ECHO OFF' 'ASPIMGR /TEXT > AUX' \
    'IF ERRORLEVEL 1 ECHO ASPIMGR text FAILED > AUX' 'ASPIMGR' \
    'IF ERRORLEVEL 1 ECHO ASPIMGR GUI FAILED > AUX' \
    'ECHO ASPIMGR DOS checks passed > AUX' \
    'ECHO OPENASPI ASPIMGR DONE > AUX' > "$OUT/AUTOEXEC.BAT"
test_probe_flags=()
test_read_text=MATSHITA
if [ "$NOASPI" = 1 ]; then
    printf '%s\r\n' 'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
    printf '%s\r\n' '@ECHO OFF' 'ASPIMGR /TEXT > AUX' \
        'IF NOT ERRORLEVEL 2 ECHO ASPIMGR no-manager text FAILED > AUX' \
        'ASPIMGR' 'IF NOT ERRORLEVEL 2 ECHO ASPIMGR no-manager GUI FAILED > AUX' \
        'ECHO ASPIMGR DOS checks passed > AUX' \
        'ECHO OPENASPI ASPIMGR DONE > AUX' > "$OUT/AUTOEXEC.BAT"
    test_probe_flags=(--ui-no-aspi)
    test_read_text='Error: 1'
fi
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" \
    "$ROOT/build/$MAXLANG/dos/ASPIMGR.EXE" ::/
source "$ROOT/tests/86box_run.sh"
run_86box_dos --aspi-ui --done 'OPENASPI ASPIMGR DONE' \
    --expect 'ASPIMGR DOS checks passed' --count 1 --read-text "$test_read_text" \
    "${test_probe_flags[@]}"
echo "ASPIMGR DOS checks passed ($MAXLANG, NOASPI=$NOASPI)"
