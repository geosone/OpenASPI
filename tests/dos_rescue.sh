#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAXLANG=${MAXLANG:-US}
OUT=${OUT:-$ROOT/build/rescue}
make -C "$ROOT" all build/host/test_fat_format >/dev/null
mkdir -p "$OUT"
test ! -e "$OUT/qmp.sock"
cp "$ROOT/build/removable-tools/boot.img" "$OUT/boot.img"
printf '%s\r\n' 'DEVICE=EUSBASPI.SYS' 'DEVICE=ASPIFDD.SYS /V' \
    'LASTDRIVE=Z' 'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
nasm -f bin -w-reloc-abs-word -I"$ROOT/../eusbaspi/src/" \
    -o "$OUT/EUSBASPI.SYS" "$ROOT/../eusbaspi/src/eusbaspi.asm"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/EUSBASPI.SYS" ::/
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
    "$ROOT/build/dos/ASPICTL.EXE" "$ROOT/build/$MAXLANG/dos/ASPIDDG.EXE" ::/
for mode in cli gui select cancel; do
    if [ "$mode" = cli ]; then
        printf '%s\r\n' '@ECHO OFF' \
            'ASPIDD READ D: C:\ERROR.IMG > AUX' 'IF NOT ERRORLEVEL 1 GOTO FAILED' \
            'ASPIDD READ D: C:\RESCUE.IMG /RESCUE /MAP:C:\CLI.MAP > AUX' > "$OUT/AUTOEXEC.BAT"
    elif [ "$mode" = gui ]; then
        printf '%s\r\n' '@ECHO OFF' \
            'ASPIDDG D: E: /YES /RESCUE /MAP:C:\GUI.MAP > AUX' > "$OUT/AUTOEXEC.BAT"
    elif [ "$mode" = select ]; then
        printf '%s\r\n' '@ECHO OFF' 'SET TEMP=C:\' 'ASPIDDG > AUX' > "$OUT/AUTOEXEC.BAT"
    else
        printf '%s\r\n' '@ECHO OFF' 'ASPIDDG D: E: /YES /RESCUE /MAP:C:\CANCEL.MAP > AUX' > "$OUT/AUTOEXEC.BAT"
    fi
    if [ "$mode" = cancel ]; then
        printf '%s\r\n' 'IF ERRORLEVEL 2 GOTO FAILED' 'IF NOT ERRORLEVEL 1 GOTO FAILED' >> "$OUT/AUTOEXEC.BAT"
    else
        printf '%s\r\n' 'IF ERRORLEVEL 4 GOTO FAILED' 'IF NOT ERRORLEVEL 3 GOTO FAILED' >> "$OUT/AUTOEXEC.BAT"
    fi
    printf '%s\r\n' \
        'ASPICTL STATUS D: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
        'ASPICTL STATUS E: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
        'ECHO RESCUE TEST PASSED > AUX' 'GOTO DONE' ':FAILED' \
        'ECHO RESCUE TEST FAILED > AUX' ':DONE' 'QEXIT' >> "$OUT/AUTOEXEC.BAT"
    mcopy -o -i "$OUT/boot.img" "$OUT/AUTOEXEC.BAT" ::/
    python3 "$ROOT/tests/rescue_vm.py" "$OUT" "$mode"
    if [ "$mode" = cancel ]; then
        test "$(grep -Fc 'locks=0' "$OUT/serial-$mode.log")" = 2
        continue
    fi
    name="$mode.MAP"
    [ "$mode" != select ] || name=OA000.MAP
    mcopy -o -i "$OUT/storage.img@@32256" "::/$name" "$OUT/$mode.MAP"
    grep -Eq '^1000,(30|31),' "$OUT/$mode.MAP"
    test "$(wc -l < "$OUT/$mode.MAP")" = 2
done
mcopy -o -i "$OUT/storage.img@@32256" ::/RESCUE.IMG "$OUT/captured.img"
cmp "$OUT/captured.img" "$OUT/expected.img"
cmp "$OUT/target.img" "$OUT/expected.img"
echo 'ASPIDD rescue image/copy, sector map and QUILIB GUI tests passed'
