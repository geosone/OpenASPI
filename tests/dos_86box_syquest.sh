#!/bin/bash
# SyQuest EZFlyer 230 (EZ135=1: EZ135) as a native ATA cartridge drive on the
# secondary IDE master, read and written through the BIOS. SQATDRVR=<path>
# also loads SyQuest's SQATDRVR.SYS (not shipped; the Windows 98 driver
# library has 1.75) with SQOPT options. Writes are restricted to this
# disposable image; it is checked after the VM shuts down. Needs an 86Box with
# the SyQuest ATA drives of geosone/86Box lpt-zip.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOX=${BOX:-$ROOT/../86Box/build-upc/src/86Box}
ROMDIR=${ROMDIR:-$HOME/.local/share/86Box/roms}
EZ135=${EZ135:-0}
EZ135CART=${EZ135CART:-$EZ135}
SQATDRVR=${SQATDRVR:-}
SQOPT=${SQOPT:-}
OUT=${OUT:-$ROOT/build/86box-syquest}
if [ "$EZ135" = 1 ]; then TYPE=9; else TYPE=10; fi
if [ "$EZ135CART" = 1 ]; then SECTORS=262144; else SECTORS=450560; fi
test -x "$BOX"
test -d "$ROMDIR"
[ -z "$SQATDRVR" ] || test -f "$SQATDRVR"
mkdir -p "$OUT"
if [ -e "$OUT/control.sock" ]; then
    echo "Refusing to reuse an existing control socket: $OUT/control.sock" >&2
    exit 1
fi
if [ ! -f "$ROOT/build/dos-cda/boot.img" ]; then
    bash "$ROOT/tests/dos_cda.sh" >/dev/null
fi
cp "$ROOT/build/dos-cda/boot.img" "$OUT/"
sed -e "s/^rdisk_01_parameters = 7, atapi$/rdisk_01_parameters = $TYPE, ide/" \
    -e 's/^rdisk_01_image_path = ls120.img$/rdisk_01_image_path = cart.img/' \
    "$ROOT/tests/fixtures/86box-ls120.cfg" > "$OUT/86box.cfg"
grep -q "^rdisk_01_parameters = $TYPE, ide$" "$OUT/86box.cfg"
rm -f "$OUT/cart.img"
python3 -I "$ROOT/tests/86box_syquest_cart.py" "$OUT/cart.img" "$SECTORS"
printf '%s\r\n' 'Hello from the SyQuest cartridge' > "$OUT/HELLO.TXT"
mcopy -i "$OUT/cart.img@@16384" "$OUT/HELLO.TXT" ::/
{
    if [ -n "$SQATDRVR" ]; then
        cp "$SQATDRVR" "$OUT/SQATDRVR.SYS"
        mcopy -o -i "$OUT/boot.img" "$OUT/SQATDRVR.SYS" ::/
        printf 'DEVICE=SQATDRVR.SYS %s\r\n' "$SQOPT"
    fi
    printf '%s\r\n' 'LASTDRIVE=Z' 'SHELL=COMMAND.COM /P'
} > "$OUT/CONFIG.SYS"
printf '%s\r\n' '@ECHO OFF' 'TYPE C:\HELLO.TXT > AUX' \
    'COPY C:\HELLO.TXT C:\COPY.TXT > NUL' 'TYPE C:\COPY.TXT > AUX' \
    'ECHO OPENASPI 86BOX SYQUEST DONE > AUX' > "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" ::/
source "$ROOT/tests/86box_run.sh"
run_86box_dos --done 'OPENASPI 86BOX SYQUEST DONE' \
    --expect 'Hello from the SyQuest cartridge' --count 2 \
    --read-text 'Hello from the SyQuest cartridge'
if [ -n "$SQATDRVR" ]; then
    grep -q 'has been taken over' "$OUT/screen.txt"
fi
dd if="$OUT/cart.img" of="$OUT/part.img" bs=512 skip=32 status=none
fsck.fat -n "$OUT/part.img" >/dev/null
rm -f "$OUT/part.img"
cmp <(mcopy -i "$OUT/cart.img@@16384" ::/COPY.TXT -) "$OUT/HELLO.TXT"
echo "SyQuest ATA cartridge test passed"
