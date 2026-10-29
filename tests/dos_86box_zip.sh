#!/bin/bash
# Native parallel port ZIP 100 (PPA) through Iomega's ASPIPPM1.SYS. Writes are
# restricted to this disposable image; validate it after shutting the VM down.
# Needs an 86Box with lpt_zip.c and Iomega's DOS drivers in IOMEGA (not shipped).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOX=${BOX:-$ROOT/../86Box/build-zip/src/86Box}
ROMDIR=${ROMDIR:-$HOME/.local/share/86Box/roms}
OUT=${OUT:-$ROOT/build/86box-zip}
IOMEGA=${IOMEGA:-$HOME/mars/ahciaspi/ref/zip100}
test -x "$BOX"
test -d "$ROMDIR"
test -f "$IOMEGA/ASPIPPM1.SYS"
mkdir -p "$OUT"
if [ -e "$OUT/control.sock" ]; then
    echo "Refusing to reuse an existing control socket: $OUT/control.sock" >&2
    exit 1
fi
make -C "$ROOT" all >/dev/null
if [ ! -f "$ROOT/build/dos-cda/boot.img" ]; then
    bash "$ROOT/tests/dos_cda.sh" >/dev/null
fi
cp "$ROOT/build/dos-cda/boot.img" "$OUT/"
cp "$ROOT/tests/fixtures/86box-zip.cfg" "$OUT/86box.cfg"
mcopy -o -i "$OUT/boot.img" "$ROOT/tests/fixtures/86box-zip-config.sys" ::/CONFIG.SYS
mcopy -o -i "$OUT/boot.img" "$ROOT/tests/fixtures/86box-zip-autoexec.bat" ::/AUTOEXEC.BAT
mcopy -o -i "$OUT/boot.img" "$ROOT/build/dos/ASPIFDD.SYS" "$ROOT/build/dos/ASPISCAN.COM" ::/
mcopy -o -i "$OUT/boot.img" "$IOMEGA/ASPIPPM1.SYS" "$IOMEGA/NIBBLE.ILM" ::/
truncate -s $((196608*512)) "$OUT/zip.img"
mkfs.fat -F16 -s4 -g64/32 -i 12012012 -n ZIP "$OUT/zip.img" > "$OUT/mkfs.log"
mcopy -i "$OUT/zip.img" "$ROOT/tests/fixtures/zip-readme.txt" ::/ZIP.TXT
head -c 100000 /dev/urandom > "$OUT/BIG.BIN"
mcopy -i "$OUT/zip.img" "$OUT/BIG.BIN" ::/BIG.BIN
source "$ROOT/tests/86box_run.sh"
run_86box_dos --done 'OPENASPI 86BOX ZIP DONE' \
    --expect 'ASPIFDD ZIP read/write passed' --count 1 \
    --read-text 'ASPIFDD ZIP initial read passed'
mcopy -o -i "$OUT/zip.img" ::/PLAIN.BIN "$OUT/PLAIN.BIN"
mcopy -o -i "$OUT/zip.img" ::/VERIFY.BIN "$OUT/VERIFY.BIN"
cmp "$OUT/BIG.BIN" "$OUT/PLAIN.BIN"
cmp "$OUT/BIG.BIN" "$OUT/VERIFY.BIN"
fsck.fat -vn "$OUT/zip.img" > "$OUT/fsck.log"
echo '86Box native ZIP 100 parallel port read/write and host-image validation passed'
