#!/bin/bash
# Isolated positive image-backed UPC test; never uses existing registered VMs.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOX=${BOX:-$ROOT/../86Box/build-upc/src/86Box}
ROMDIR=${ROMDIR:-$HOME/.local/share/86Box/roms}
HIGH=${HIGH:-0}
JEMMEX=${JEMMEX:-$HOME/Iso/Dos/JEMM/JEMM/JEMMEX.EXE}
test_suffix=
test_asm_flags=()
if [ "$HIGH" = 1 ]; then
    test_suffix=-high
    test_asm_flags=(-DEXPECT_HIGH)
    test -f "$JEMMEX" || { echo 'Set JEMMEX to a local JEMMEX.EXE' >&2; exit 1; }
fi
OUT=${OUT:-$ROOT/build/86box-upc$test_suffix}
test -x "$BOX" || { echo 'Set BOX to the local patched AUTOMATION=ON build' >&2; exit 1; }
test -d "$ROMDIR" || { echo 'Set ROMDIR to your existing 86Box ROM set' >&2; exit 1; }
mkdir -p "$OUT"
if [ -e "$OUT/control.sock" ]; then
    echo "Refusing to reuse an existing control socket: $OUT/control.sock" >&2
    exit 1
fi
make -C "$ROOT" all >/dev/null
if [ ! -f "$ROOT/build/dos-cda/cd.iso" ]; then
    bash "$ROOT/tests/dos_cda.sh" >/dev/null
fi
cp "$ROOT/build/dos-cda/boot.img" "$ROOT/build/dos-cda/cd.iso" "$OUT/"
cp "$ROOT/tests/fixtures/cd-catalog.cue" "$OUT/cd.cue"
cp "$ROOT/tests/fixtures/86box-upc.cfg" "$OUT/86box.cfg"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX "${test_asm_flags[@]}" \
    -Fo="$OUT/UPCIMAGE.COM" "$ROOT/tests/cda_upc_image.asm"
mcopy -o -i "$OUT/boot.img" "$OUT/UPCIMAGE.COM" ::/
mcopy -o -i "$OUT/boot.img" "$ROOT/tests/fixtures/86box-upc-autoexec.bat" ::/AUTOEXEC.BAT
if [ "$HIGH" = 1 ]; then
    mcopy -o -i "$OUT/boot.img" "$JEMMEX" ::/JEMMEX.EXE
    mcopy -o -i "$OUT/boot.img" "$ROOT/tests/fixtures/86box-upc-high-config.sys" ::/CONFIG.SYS
fi

test_probe_flags=()
[ "$HIGH" = 1 ] && test_probe_flags=(--high)
source "$ROOT/tests/86box_run.sh"
run_86box_dos "${test_probe_flags[@]}"
echo "86Box image-backed UPC test passed (HIGH=$HIGH): $OUT"
