#!/bin/bash
# ASPIFDD with a BIOS that maps ATAPI removable drives itself, as ReBIOS's
# SeaBIOS does (github.com/ReBIOS-Project/seabios, floppy_a, floppy_b,
# zip_mode). AHCIASPI finds the mapping through EDD and reports it in GET
# DISK INFO; ASPIFDD must take the letter DOS has over: one letter, reached
# through ASPI (ASPIFMT on it), and no second one.
#   MODE=ls120  an LS-120 as BIOS A:, booted
#   MODE=zip    a ZIP 100 with a partition as BIOS 80h (C:), booted
#   MODE=ab     an LS-120 as BIOS A:, booted, and a ZIP 100 superfloppy as B:
# Local inputs, not shipped:
#   ROMDIR   86Box ROM set whose 686nx BIOS (machines/686nx/6nx.140) is such
#            a SeaBIOS 86Box test build: etc/floppy-a "LS-120", zip_mode
#            auto, CMOS 10h cleared (no real floppy)
#   LS120IMG a bootable MS-DOS 7.1 LS-120 image with LS120.TXT and BIG.BIN
#   ZIPIMG   a bootable MS-DOS 7.1 ZIP 100 image, FAT16 at LBA 32, with
#            ZIP.TXT and BIG.BIN
# The images are copied; writes go to the copies only. Without ROMDIR the
# test is skipped.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BT=${BOOTIT:-$ROOT/../bootit/tests}
BOX=${BOX:-$BT/86box-build/86Box}
if [ -z "${ROMDIR:-}" ]; then
    echo "ReBIOS takeover test skipped: set ROMDIR (see the header)"
    exit 0
fi
LS120IMG=${LS120IMG:-$BT/msdos71-ls120/ls120-native.img}
ZIPIMG=${ZIPIMG:-$BT/zip100/zip.img}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
MODE=${MODE:-ls120}
OUT=${OUT:-$ROOT/build/86box-rebios-$MODE}
ext=
case "$MODE" in ls120|zip|ab) ;; *) echo "MODE: ls120, zip or ab" >&2; exit 2;; esac
test -x "$BOX"
test -f "$ROMDIR/machines/686nx/6nx.140"
mkdir -p "$OUT"
make -C "$ROOT" build/dos/ASPIFDD.SYS build/dos/ASPIFMT.EXE >/dev/null
make -C "$AHCIASPI_DIR" >/dev/null
cp "$AHCIASPI_DIR/build/AHCIASPI.SYS" "$OUT/AHCIASPI.SYS"

cat > "$OUT/86box.cfg" <<'EOF'
[General]
confirm_exit = 0
vid_renderer = qt_software

[Machine]
cpu_family = pentiumpro
cpu_multi = 3
cpu_speed = 200000000
cpu_use_dynarec = 1
fpu_type = internal
machine = 686nx
mem_size = 32768
time_sync = disabled

[Video]
gfxcard = et4000ax

[Input devices]
keyboard_type = keyboard_ps2
mouse_type = none
tablet_type = none

[Ports (COM & LPT)]
lpt1_enabled = 0
serial1_device = automation
serial2_enabled = 0

[Floppy and CD-ROM drives]
fdd_01_type = none
fdd_02_type = none

[Other removable devices]
EOF
if [ "$MODE" = zip ]; then
    boot=C; read_text='ZIP.TXT'
    cp "$ZIPIMG" "$OUT/zip.img"
    I="$OUT/zip.img@@16384"
    mdel -i "$I" ::/PLAIN.BIN ::/VERIFY.BIN ::/BOOTCHK.BIN 2>/dev/null || true
    printf '%s\n' 'rdisk_01_parameters = 1, atapi' 'rdisk_01_ide_channel = 1:0' \
        'rdisk_01_image_path = zip.img' >> "$OUT/86box.cfg"
else
    boot=A; read_text='LS120.TXT'
    cp "$LS120IMG" "$OUT/ls120.img"
    I="$OUT/ls120.img"
    mdel -i "$I" ::/PLAIN.BIN ::/VERIFY.BIN ::/BOOTCHK.BIN 2>/dev/null || true
    printf '%s\n' 'rdisk_01_parameters = 7, atapi' 'rdisk_01_ide_channel = 1:0' \
        'rdisk_01_image_path = ls120.img' >> "$OUT/86box.cfg"
fi
if [ "$MODE" = ab ]; then
    ext=B
    truncate -s $((196608*512)) "$OUT/zipb.img"
    mkfs.fat -F16 -n ZIPSUPER -i 12345678 -h 0 -S 512 -s 4 -g 64/32 \
        "$OUT/zipb.img" > "$OUT/mkfs.log"
    printf 'ZIP superfloppy B: read passed\r\n' > "$OUT/ZIPB.TXT"
    mcopy -i "$OUT/zipb.img" "$OUT/ZIPB.TXT" ::/
    printf '%s\n' 'rdisk_02_parameters = 1, atapi' 'rdisk_02_ide_channel = 1:1' \
        'rdisk_02_image_path = zipb.img' >> "$OUT/86box.cfg"
fi
printf '%s\n' '' '[Virtual Console (COM) #1]' 'mode = 0' >> "$OUT/86box.cfg"

mcopy -o -i "$I" "$OUT/AHCIASPI.SYS" "$ROOT/build/dos/ASPIFDD.SYS" \
    "$ROOT/build/dos/ASPIFMT.EXE" ::/
printf '%s\r\n' 'FILES=30' 'BUFFERS=20' "DEVICE=$boot:\\AHCIASPI.SYS /V" \
    "DEVICE=$boot:\\ASPIFDD.SYS /V" 'LASTDRIVE=Z' \
    "SHELL=$boot:\\COMMAND.COM $boot:\\ /P" > "$OUT/CONFIG.SYS"
# ASPIFMT reaches a drive only through ASPIFDD's raw-media service: its
# preview on the BIOS letter shows the takeover. The next letter must not
# exist (a second letter for the same drive).
next=$([ "$MODE" = zip ] && echo D || echo C)
{
    printf '%s\n' '@ECHO OFF' "TYPE $boot:\\$read_text > AUX"
    for d in $boot $ext; do
        printf '%s\n' "ASPIFMT $d: > AUX" \
            "IF NOT ERRORLEVEL 1 ECHO ASPIFMT $d: preview passed > AUX"
    done
    printf '%s\n' "COPY $boot:\\BIG.BIN $boot:\\PLAIN.BIN > NUL" 'VERIFY ON' \
        "COPY $boot:\\BIG.BIN $boot:\\VERIFY.BIN > NUL" 'VERIFY OFF'
    if [ -n "$ext" ]; then
        printf '%s\n' "TYPE $ext:\\ZIPB.TXT > AUX" \
            "COPY $boot:\\BIG.BIN $ext:\\BIG.BIN > NUL" 'VERIFY ON' \
            "COPY $ext:\\BIG.BIN $ext:\\VERIFY.BIN > NUL" 'VERIFY OFF' \
            "COPY $ext:\\BIG.BIN $boot:\\BACK.BIN > NUL"
    fi
    printf '%s\n' "IF EXIST $next:\\NUL ECHO SECOND LETTER $next: > AUX" \
        'ECHO ReBIOS read/write passed > AUX' 'ECHO OPENASPI 86BOX REBIOS DONE > AUX'
} | sed 's/$/\r/' > "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$I" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" ::/

expect=(--expect 'ReBIOS read/write passed' --expect "ASPIFMT $boot: preview passed")
[ -z "$ext" ] || expect+=(--expect "ASPIFMT $ext: preview passed" --expect 'ZIP superfloppy B: read passed')
source "$ROOT/tests/86box_run.sh"
run_86box_dos --done 'OPENASPI 86BOX REBIOS DONE' "${expect[@]}" --count 1 \
    --read-text "$(mtype -i "$I" "::/$read_text" | tr -d '\r' | head -1)"
if tr -d '\r' < "$OUT/serial.log" | grep -q 'SECOND LETTER'; then
    echo "a second letter $next: for the drive" >&2
    exit 1
fi

mcopy -o -i "$I" ::/BIG.BIN "$OUT/BIG.BIN"
for f in PLAIN VERIFY; do
    mcopy -o -i "$I" "::/$f.BIN" "$OUT/$f.BIN"
    cmp "$OUT/BIG.BIN" "$OUT/$f.BIN"
done
if [ "$MODE" = zip ]; then
    dd if="$OUT/zip.img" of="$OUT/part.img" bs=512 skip=32 status=none
    fsck.fat -vn "$OUT/part.img" > "$OUT/fsck.log"
else
    fsck.fat -vn "$OUT/ls120.img" > "$OUT/fsck.log"
fi
if [ -n "$ext" ]; then
    mcopy -o -i "$I" ::/BACK.BIN "$OUT/BACK.BIN"
    mcopy -o -i "$OUT/zipb.img" ::/BIG.BIN "$OUT/ZBIG.BIN"
    mcopy -o -i "$OUT/zipb.img" ::/VERIFY.BIN "$OUT/ZVERIFY.BIN"
    for f in BACK ZBIG ZVERIFY; do cmp "$OUT/BIG.BIN" "$OUT/$f.BIN"; done
    fsck.fat -vn "$OUT/zipb.img" > "$OUT/fsck-b.log"
fi
echo "ASPIFDD takeover of the BIOS letters passed (MODE=$MODE)"
