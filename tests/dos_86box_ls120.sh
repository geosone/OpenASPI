#!/bin/bash
# Native ATAPI LS-120, not a USB device merely named SUPERDISK. Writes are
# restricted to this disposable image; validate it after shutting the VM down.
# LPT=1: the parallel port LS-120 instead (Shuttle EPAT bridge), through
# Imation's SD120PPD.SYS taken from LS120PACK (not shipped). Needs an 86Box
# with the EPAT fixes of geosone/86Box lpt-zip.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOX=${BOX:-$ROOT/../86Box/build-upc/src/86Box}
ROMDIR=${ROMDIR:-$HOME/.local/share/86Box/roms}
LEGACY86BOX=${LEGACY86BOX:-0}
LPT=${LPT:-0}
LS120PACK=${LS120PACK:-$HOME/Iso/Dos/LS-120_Parallel_Port_DriverPack.zip}
if [ "$LPT" = 1 ]; then
    OUT=${OUT:-$ROOT/build/86box-ls120-lpt}
    test -f "$LS120PACK"
else
    OUT=${OUT:-$ROOT/build/86box-ls120}
fi
test -x "$BOX"
test -d "$ROMDIR"
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
cp "$ROOT/tests/fixtures/86box-ls120.cfg" "$OUT/86box.cfg"
if [ "$LEGACY86BOX" = 1 ]; then
    # The 6.0 backport has fewer drive types and no automation interface.
    sed -i -e 's/rdisk_01_parameters = 7,/rdisk_01_parameters = 3,/' \
        -e 's/serial1_device = automation/serial1_device = stdio/' "$OUT/86box.cfg"
    cat >> "$OUT/86box.cfg" <<'EOF'

[Virtual Console (COM) #1]
mode = 0
EOF
fi
if [ "$LPT" = 1 ]; then
    sed -i -e 's/^lpt1_enabled = 0$/lpt1_enabled = 1/' \
        -e 's/^rdisk_01_parameters = 7, atapi$/rdisk_01_parameters = 7, lpt/' \
        -e 's/^rdisk_01_ide_channel = 1:0$/rdisk_01_lpt_port = 0/' "$OUT/86box.cfg"
    unzip -p "$LS120PACK" 'SuperDisk Parallel Port v5.46_DOS.exe' > "$OUT/sd120dos.zip"
    unzip -p "$OUT/sd120dos.zip" sd120ppd.sys > "$OUT/SD120PPD.SYS"
    mcopy -o -i "$OUT/boot.img" "$OUT/SD120PPD.SYS" ::/
    mcopy -o -i "$OUT/boot.img" "$ROOT/tests/fixtures/86box-ls120-lpt-config.sys" ::/CONFIG.SYS
else
    mcopy -o -i "$OUT/boot.img" "$ROOT/tests/fixtures/86box-ls120-config.sys" ::/CONFIG.SYS
fi
mcopy -o -i "$OUT/boot.img" "$ROOT/tests/fixtures/86box-ls120-autoexec.bat" ::/AUTOEXEC.BAT
mcopy -o -i "$OUT/boot.img" "$ROOT/build/dos/ASPIFDD.SYS" "$ROOT/build/dos/ASPISCAN.COM" ::/
truncate -s $((963*256*512)) "$OUT/ls120.img"
mkfs.fat -F16 -s4 -g8/32 -i 12012012 -n LS120 "$OUT/ls120.img" > "$OUT/mkfs.log"
mcopy -i "$OUT/ls120.img" "$ROOT/tests/fixtures/ls120-readme.txt" ::/LS120.TXT
head -c 100000 /dev/urandom > "$OUT/BIG.BIN"
mcopy -i "$OUT/ls120.img" "$OUT/BIG.BIN" ::/BIG.BIN
source "$ROOT/tests/86box_run.sh"
run_86box_dos --done 'OPENASPI 86BOX LS120 DONE' \
    --expect 'ASPIFDD LS120 read/write passed' --count 1 \
    --read-text 'ASPIFDD LS120 initial read passed'
mcopy -o -i "$OUT/ls120.img" ::/PLAIN.BIN "$OUT/PLAIN.BIN"
mcopy -o -i "$OUT/ls120.img" ::/VERIFY.BIN "$OUT/VERIFY.BIN"
cmp "$OUT/BIG.BIN" "$OUT/PLAIN.BIN"
cmp "$OUT/BIG.BIN" "$OUT/VERIFY.BIN"
fsck.fat -vn "$OUT/ls120.img" > "$OUT/fsck.log"
echo "86Box native LS-120 $([ "$LPT" = 1 ] && echo parallel port || echo ATAPI) read/write and host-image validation passed"
