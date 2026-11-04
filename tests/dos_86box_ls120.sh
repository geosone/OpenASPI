#!/bin/bash
# Native ATAPI LS-120, not a USB device merely named SUPERDISK. Writes are
# restricted to this disposable image; validate it after shutting the VM down.
# LPT=1: the parallel port LS-120 instead (Shuttle EPAT bridge), through
# Imation's SD120PPD.SYS taken from LS120PACK (not shipped). Needs 86Box
# master from 2026-11-04 on (PR #8697: EPAT fixes, rdisk_t layout fix).
# LPT=1 MGR=path: that ASPI manager (for example PORTASPI.SYS) instead of
# SD120PPD.SYS, loaded with /V and MGROPT.
# LPT=1 BRIDGE=name: the drive behind another bridge of 86Box's bus LPT
# (on26, epia, bpck, frpw, friq: an ATAPI drive on the bridge's IDE board;
# needs the lpt-epat-hdd branch of github.com/geosone/86Box).
# LPT=1 BLKDRV=path: that block driver for the drive instead of an ASPI
# manager and ASPIFDD (for example Freecom's FCLSPAR.SYS, not shipped),
# loaded with BLKOPT.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOX=${BOX:-$ROOT/../86Box/build-upc/src/86Box}
ROMDIR=${ROMDIR:-$HOME/.local/share/86Box/roms}
LEGACY86BOX=${LEGACY86BOX:-0}
LPT=${LPT:-0}
LS120PACK=${LS120PACK:-$HOME/Iso/Dos/LS-120_Parallel_Port_DriverPack.zip}
MGR=${MGR:-}
MGROPT=${MGROPT:-}
BRIDGE=${BRIDGE:-epat}
BLKDRV=${BLKDRV:-}
BLKOPT=${BLKOPT:-}
if [ "$LPT" = 1 ]; then
    OUT=${OUT:-$ROOT/build/86box-ls120-lpt}
    if [ -n "$BLKDRV" ]; then test -f "$BLKDRV"
    elif [ -n "$MGR" ]; then test -f "$MGR"; else test -f "$LS120PACK"; fi
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
    if [ "$BRIDGE" != epat ]; then
        sed -i "s/^rdisk_01_lpt_port = 0$/&\nrdisk_01_lpt_bridge = $BRIDGE/" "$OUT/86box.cfg"
        grep -q "^rdisk_01_lpt_bridge = $BRIDGE$" "$OUT/86box.cfg"
    fi
    if [ -n "$BLKDRV" ]; then
        name=$(basename "$BLKDRV" | tr a-z A-Z)
        mcopy -o -i "$OUT/boot.img" "$BLKDRV" ::/"$name"
        printf 'DEVICE=%s %s\r\nLASTDRIVE=Z\r\nSHELL=COMMAND.COM /P\r\n' "$name" "$BLKOPT" > "$OUT/CONFIG.SYS"
        mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" ::/CONFIG.SYS
    elif [ -n "$MGR" ]; then
        name=$(basename "$MGR" | tr a-z A-Z)
        mcopy -o -i "$OUT/boot.img" "$MGR" ::/"$name"
        sed "1s|.*|DEVICE=$name /V $MGROPT|" \
            "$ROOT/tests/fixtures/86box-ls120-lpt-config.sys" > "$OUT/CONFIG.SYS"
        mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" ::/CONFIG.SYS
    else
        unzip -p "$LS120PACK" 'SuperDisk Parallel Port v5.46_DOS.exe' > "$OUT/sd120dos.zip"
        unzip -p "$OUT/sd120dos.zip" sd120ppd.sys > "$OUT/SD120PPD.SYS"
        mcopy -o -i "$OUT/boot.img" "$OUT/SD120PPD.SYS" ::/
        mcopy -o -i "$OUT/boot.img" "$ROOT/tests/fixtures/86box-ls120-lpt-config.sys" ::/CONFIG.SYS
    fi
else
    mcopy -o -i "$OUT/boot.img" "$ROOT/tests/fixtures/86box-ls120-config.sys" ::/CONFIG.SYS
fi
if [ -n "$BLKDRV" ]; then
    # No ASPI manager to scan: the block driver's letter is the first free one.
    sed -e '/^ASPISCAN /d' -e '/LS120 detection FAILED/d' \
        "$ROOT/tests/fixtures/86box-ls120-autoexec.bat" > "$OUT/AUTOEXEC.BAT"
    mcopy -o -i "$OUT/boot.img" "$OUT/AUTOEXEC.BAT" ::/AUTOEXEC.BAT
else
    mcopy -o -i "$OUT/boot.img" "$ROOT/tests/fixtures/86box-ls120-autoexec.bat" ::/AUTOEXEC.BAT
fi
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
