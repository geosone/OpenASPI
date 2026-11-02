#!/bin/bash
# Native parallel port ZIP 100 (PPA) through Iomega's ASPIPPM1.SYS. Writes are
# restricted to this disposable image; validate it after shutting the VM down.
# Needs an 86Box with lpt_zip.c and Iomega's DOS drivers in IOMEGA (not shipped).
# ZIP250=1: the ZIP 250 parallel port drive (IMM) through ASPIPPM2.SYS instead.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOX=${BOX:-$ROOT/../86Box/build-zip/src/86Box}
ROMDIR=${ROMDIR:-$HOME/.local/share/86Box/roms}
ZIP250=${ZIP250:-0}
if [ "$ZIP250" = 1 ]; then
    OUT=${OUT:-$ROOT/build/86box-zip250}
    ZIP_TYPE=2 ZIP_SECTORS=489532 ZIP_SPC=8 ZIP_ASPI=ASPIPPM2.SYS ZIP_ILM=NIBBLE2.ILM
else
    OUT=${OUT:-$ROOT/build/86box-zip}
    ZIP_TYPE=1 ZIP_SECTORS=196608 ZIP_SPC=4 ZIP_ASPI=ASPIPPM1.SYS ZIP_ILM=NIBBLE.ILM
fi
IOMEGA=${IOMEGA:-$HOME/mars/ahciaspi/ref/zip100}
test -x "$BOX"
test -d "$ROMDIR"
test -f "$IOMEGA/$ZIP_ASPI"
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
sed "s/^rdisk_01_parameters = 1, lpt$/rdisk_01_parameters = $ZIP_TYPE, lpt/" \
    "$ROOT/tests/fixtures/86box-zip.cfg" > "$OUT/86box.cfg"
sed -e "s/ASPIPPM1.SYS/$ZIP_ASPI/" -e "s/NIBBLE.ILM/$ZIP_ILM/" \
    "$ROOT/tests/fixtures/86box-zip-config.sys" > "$OUT/CONFIG.SYS"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" ::/CONFIG.SYS
mcopy -o -i "$OUT/boot.img" "$ROOT/tests/fixtures/86box-zip-autoexec.bat" ::/AUTOEXEC.BAT
mcopy -o -i "$OUT/boot.img" "$ROOT/build/dos/ASPIFDD.SYS" "$ROOT/build/dos/ASPISCAN.COM" ::/
mcopy -o -i "$OUT/boot.img" "$IOMEGA/$ZIP_ASPI" "$IOMEGA/$ZIP_ILM" ::/
truncate -s $((ZIP_SECTORS*512)) "$OUT/zip.img"
mkfs.fat -F16 -s$ZIP_SPC -g64/32 -i 12012012 -n ZIP "$OUT/zip.img" > "$OUT/mkfs.log"
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
echo "86Box native ZIP $([ "$ZIP250" = 1 ] && echo 250 || echo 100) parallel port read/write and host-image validation passed"
