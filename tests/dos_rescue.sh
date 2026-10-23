#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/rescue}
make -C "$ROOT" all build/host/test_fat_format >/dev/null
mkdir -p "$OUT"
test ! -e "$OUT/qmp.sock"
cp "$ROOT/build/removable-tools/boot.img" "$OUT/boot.img"
cp --sparse=always "$ROOT/build/removable-tools/storage.img" "$OUT/storage.img"
"$ROOT/build/host/test_fat_format" 19200 "$OUT/source.img" >/dev/null
truncate -s $((19200*512)) "$OUT/target.img"
python3 - "$OUT" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
with (p/'source.img').open('r+b') as f: f.seek(1000*512); f.write(b'Z'*512)
(p/'expected.img').write_bytes((p/'source.img').read_bytes())
with (p/'expected.img').open('r+b') as f: f.seek(1000*512); f.write(bytes(512))
PY
cat > "$OUT/bad.conf" <<'EOF'
[inject-error]
event = "read_aio"
errno = "5"
sector = "1000"
once = "off"
immediately = "on"
EOF
mcopy -o -i "$OUT/boot.img" "$ROOT/build/dos/ASPIFDD.SYS" "$ROOT/build/dos/ASPIDD.EXE" \
    "$ROOT/build/dos/ASPICTL.EXE" "$ROOT/build/US/dos/ASPIDDG.EXE" ::/
for mode in cli gui; do
    if [ "$mode" = cli ]; then
        printf '%s\r\n' '@ECHO OFF' \
            'ASPIDD READ D: C:\ERROR.IMG > AUX' 'IF NOT ERRORLEVEL 1 GOTO FAILED' \
            'ASPIDD READ D: C:\RESCUE.IMG /RESCUE /MAP:C:\CLI.MAP > AUX' > "$OUT/AUTOEXEC.BAT"
    else
        printf '%s\r\n' '@ECHO OFF' \
            'ASPIDDG D: E: /YES /RESCUE /MAP:C:\GUI.MAP > AUX' > "$OUT/AUTOEXEC.BAT"
    fi
    printf '%s\r\n' 'IF ERRORLEVEL 4 GOTO FAILED' 'IF NOT ERRORLEVEL 3 GOTO FAILED' \
        'ASPICTL STATUS D: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
        'ECHO RESCUE TEST PASSED > AUX' 'GOTO DONE' ':FAILED' \
        'ECHO RESCUE TEST FAILED > AUX' ':DONE' 'QEXIT' >> "$OUT/AUTOEXEC.BAT"
    mcopy -o -i "$OUT/boot.img" "$OUT/AUTOEXEC.BAT" ::/
    python3 "$ROOT/tests/rescue_vm.py" "$OUT" "$mode"
    mcopy -o -i "$OUT/storage.img@@32256" "::/$mode.MAP" "$OUT/$mode.MAP"
    grep -Eq '^1000,(30|31),' "$OUT/$mode.MAP"
    test "$(wc -l < "$OUT/$mode.MAP")" = 2
done
mcopy -o -i "$OUT/storage.img@@32256" ::/RESCUE.IMG "$OUT/captured.img"
cmp "$OUT/captured.img" "$OUT/expected.img"
cmp "$OUT/target.img" "$OUT/expected.img"
echo 'ASPIDD rescue image/copy, sector map and QUILIB GUI tests passed'
