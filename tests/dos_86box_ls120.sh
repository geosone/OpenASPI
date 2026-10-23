#!/bin/bash
# Native ATAPI LS-120, not a USB device merely named SUPERDISK. Writes are
# restricted to this disposable image; validate it after shutting the VM down.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOX=${BOX:-$ROOT/../86Box/build-upc/src/86Box}
ROMDIR=${ROMDIR:-$HOME/.local/share/86Box/roms}
LEGACY86BOX=${LEGACY86BOX:-0}
OUT=${OUT:-$ROOT/build/86box-ls120}
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
mcopy -o -i "$OUT/boot.img" "$ROOT/tests/fixtures/86box-ls120-config.sys" ::/CONFIG.SYS
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
echo '86Box native LS-120 ATAPI read/write and host-image validation passed'
