#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/diskcopy-swap}
BASE=${BASE:-$ROOT/build/removable-tools}
make -C "$ROOT" all >/dev/null
mkdir -p "$OUT"
test ! -e "$OUT/qmp.sock"
cp "$BASE/expected.img" "$OUT/source.img"
cp --sparse=always "$BASE/storage.img" "$OUT/storage.img"
cp "$BASE/boot.img" "$OUT/boot.img"
mcopy -o -i "$OUT/boot.img" "$ROOT/build/dos/ASPIFDD.SYS" "$ROOT/build/dos/ASPIDD.EXE" ::/
truncate -s $(stat -c %s "$OUT/source.img") "$OUT/swapped.img"
truncate -s 1474560 "$OUT/wrong.img"
sha256sum "$OUT/wrong.img" > "$OUT/wrong.sha256"
# One ASPI unit plus C: fixed storage: removable medium is D:.
for mode in success mismatch cancel; do
    test_condition='IF ERRORLEVEL 1 GOTO FAILED'
    [ "$mode" = success ] || test_condition='IF NOT ERRORLEVEL 1 GOTO FAILED'
    printf '%s\r\n' '@ECHO OFF' "ASPIDD D: /YES /TEMP:C:\\$mode.IMG > AUX" \
        "$test_condition" 'ECHO SWAP TEST PASSED > AUX' 'GOTO DONE' \
        ':FAILED' 'ECHO SWAP TEST FAILED > AUX' ':DONE' 'QEXIT' > "$OUT/AUTOEXEC.BAT"
    mcopy -o -i "$OUT/boot.img" "$OUT/AUTOEXEC.BAT" ::/
    python3 "$ROOT/tests/diskcopy_swap.py" "$OUT" "$ROOT" "$mode"
    if [ "$mode" = success ]; then
        cmp "$OUT/swapped.img" "$BASE/expected.img"
        if mdir -i "$OUT/storage.img@@32256" ::/SUCCESS.IMG >/dev/null 2>&1; then
            echo 'Successful copy leaked temporary image' >&2; exit 1
        fi
    else
        mcopy -o -i "$OUT/storage.img@@32256" "::/$mode.IMG" "$OUT/$mode-retained.img"
        cmp "$OUT/$mode-retained.img" "$BASE/expected.img"
    fi
done
sha256sum -c "$OUT/wrong.sha256"
cmp "$OUT/source.img" "$BASE/expected.img"
echo 'ASPIDD one-drive exchange, size refusal and cancellation passed'
