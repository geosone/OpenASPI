#!/bin/bash
# DEFRAG under MS-DOS 7.1 (the first disk of msdosinst), on fragmented
# images of tests/defrag_image.sh.
# BIOS (default): C: FAT16 and D: FAT32 (INT 21h 7305h): DEFRAG /A, DEFRAG
#   (full), DEFRAG /A again (nothing fragmented), ASPICHK; D: with /U.
#   The screen is used for C: (keys sent through the QEMU monitor).
# ASPI=1: EUSBASPI, ASPIDSK and a FAT12 USB stick (in place of an exFAT
#   stick after the boot, see tests/dos_aspichk.sh), through the exFAT
#   service of ASPIDSK.
# CUT=SECONDS: QEMU is stopped that long after DEFRAG C: has started (power
#   loss, fractions allowed: DEFRAG takes about a second there); then
#   test_fatchk F on the host must make C: clean and no file may differ.
# Afterwards on the host: fsck.fat and test_fatchk find no error, every
# file is as before (mtools), test_defrag finds nothing fragmented.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/dos-defrag}
EUSBASPI_DIR=${EUSBASPI_DIR:-$ROOT/../eusbaspi}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
MSDOS_IMG=${MSDOS_IMG:-$ROOT/../msdosinst/out/DISK1.IMG}
ASPI=${ASPI:-}
CUT=${CUT:-}

make -C "$ROOT" build/dos/DEFRAG.EXE build/dos/ASPICHK.EXE build/dos/ASPIDSK.SYS build/host/test_exfmt \
    build/host/test_defrag build/host/test_fatchk >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"
nasm -f bin -o "$OUT/QEXIT.COM" "$AHCIASPI_DIR/tools/qexit.asm"

cp "$MSDOS_IMG" "$OUT/boot.img"
while IFS= read -r file; do
    case "${file^^}" in
        *COMMAND.COM) ;;
        *) mdel -i "$OUT/boot.img" "$file" ;;
    esac
done < <(mdir -b -i "$OUT/boot.img" ::/)

steps() {   # DRIVE NAME OPTIONS
    printf '%s > AUX\r\n' "ECHO === $2" "DEFRAG $1 /A /B" "ECHO === RUN$2"
    if test "$3" = SCREEN; then printf '%s\r\n' "DEFRAG $1"; else printf '%s > AUX\r\n' "DEFRAG $1 $3"; fi
    printf '%s > AUX\r\n' 'IF ERRORLEVEL 1 ECHO DEFRAG FAILED' "ECHO === AFTER$2" "DEFRAG $1 /A /B" \
        "ASPICHK $1" 'IF ERRORLEVEL 1 ECHO ASPICHK FAILED'
}
# an image of defrag_image.sh as partition 1 (sector 63) of a disk
disk() {   # NAME SIZE_MB BITS SPC TYPE
    sh "$ROOT/tests/defrag_image.sh" "$OUT/$1" "$2" "$3" "$4" >/dev/null
    python3 - "$OUT/$1/fat.img" "$3" <<'PY'
import struct, sys
f = open(sys.argv[1], 'r+b')
for s in ((0, 6) if sys.argv[2] == '32' else (0,)):   # hidden sectors 63
    f.seek(s * 512 + 28); f.write(struct.pack('<I', 63))
PY
    truncate -s $(( $2 + 1 ))M "$OUT/$1.img"
    echo "start=63, size=$(( $2 * 2048 )), type=$5" | sfdisk -q "$OUT/$1.img"
    dd if="$OUT/$1/fat.img" of="$OUT/$1.img" bs=512 seek=63 conv=notrunc status=none
}
if test -n "$ASPI"; then
    nasm -f bin -w-reloc-abs-word -I"$EUSBASPI_DIR/src/" \
        -o "$OUT/EUSBASPI.SYS" "$EUSBASPI_DIR/src/eusbaspi.asm"
    nasm -f bin -o "$OUT/WAIT.COM" "$ROOT/tests/wait_ticks.asm"
    printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' 'DEVICE=A:\EUSBASPI.SYS' 'DEVICE=A:\ASPIDSK.SYS' > "$OUT/CONFIG.SYS"
    { printf '%s > AUX\r\n' 'ECHO === INSERT'; printf 'WAIT\r\n'; steps D: STICK /B; } > "$OUT/AUTOEXEC.BAT"
    mcopy -o -i "$OUT/boot.img" "$OUT/EUSBASPI.SYS" "$ROOT/build/dos/ASPIDSK.SYS" "$OUT/WAIT.COM" ::/
    truncate -s 32M "$OUT/c.img"
    echo 'start=63, type=6' | sfdisk -q "$OUT/c.img"
    mkfs.fat -F16 -n FATDISK --offset 63 "$OUT/c.img" $(( (32*2048 - 63) / 2 )) >/dev/null
    disk stick 4 12 4 1
    truncate -s 32M "$OUT/exstick.img"
    echo 'start=2048, type=7' | sfdisk -q "$OUT/exstick.img"
    truncate -s 31M "$OUT/exvol.img"
    "$ROOT/build/host/test_exfmt" "$OUT/exvol.img" 0 1 BOOTSTICK >/dev/null
    dd if="$OUT/exvol.img" of="$OUT/exstick.img" bs=512 seek=2048 conv=notrunc status=none
    disks=(-drive if=ide,index=0,format=raw,file="$OUT/c.img"
           -device pci-ohci,id=usbhc -device usb-bot,id=bot1,bus=usbhc.0,port=1
           -drive id=stick,if=none,format=raw,file="$OUT/exstick.img"
           -device scsi-hd,bus=bot1.0,drive=stick,removable=on,vendor=OPENASPI,product=STICK)
    checked=(stick)
else
    printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' > "$OUT/CONFIG.SYS"
    if test -n "$CUT"; then
        printf '%s > AUX\r\n' 'ECHO === RUNC' 'DEFRAG C: /B' > "$OUT/AUTOEXEC.BAT"
    else
        { steps C: C SCREEN; steps D: D "/U /B"; } > "$OUT/AUTOEXEC.BAT"
    fi
    disk c 32 16 1 6
    disk d 64 32 1 c
    disks=(-drive if=ide,index=0,format=raw,file="$OUT/c.img"
           -drive if=ide,index=1,format=raw,file="$OUT/d.img")
    checked=(c d)
fi
printf '%s > AUX\r\n' 'ECHO === END' >> "$OUT/AUTOEXEC.BAT"
printf '%s\r\n' 'QEXIT' >> "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" \
    "$ROOT/build/dos/DEFRAG.EXE" "$ROOT/build/dos/ASPICHK.EXE" "$OUT/QEXIT.COM" ::/

monitor() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$OUT/mon.sock" >/dev/null; }
wait_for() {
    for _ in $(seq 1 900); do
        grep -qa "$1" "$OUT/serial.log" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}

set +e
timeout "${TIMEOUT:-300}" qemu-system-i386 \
    -machine pc -m 32 -display none -vga std \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    "${disks[@]}" \
    -serial file:"$OUT/serial.log" \
    -monitor unix:"$OUT/mon.sock",server,nowait \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 &
qemu=$!
if test -n "$ASPI"; then wait_for '=== INSERT' && monitor "change stick $OUT/stick.img raw"; fi
if test -n "$CUT"; then
    wait_for '=== RUNC' && sleep "$CUT" && monitor quit
elif test -z "$ASPI"; then
    # the screen of DEFRAG C: waits for a key at the end
    wait_for '=== RUNC' && sleep 3 && monitor "screendump $OUT/screen.ppm"
    until grep -qa '=== AFTERC' "$OUT/serial.log" || ! kill -0 $qemu 2>/dev/null; do
        monitor "sendkey ret"; sleep 1
    done
fi
wait $qemu
rc=$?
set -e
tr -d '\0' < "$OUT/serial.log" > "$OUT/serial.txt"

fail=0
section() { sed -n "/=== $1 /,/=== $2 /p" "$OUT/serial.txt" | tr -d '\r'; }
need() { section "$1" "$2" | grep -q "$3" || { echo "missing in $1: $3"; fail=1; }; }
host() {   # NAME: the volume of a disk image on the host
    dd if="$OUT/$1.img" of="$OUT/$1.vol" bs=512 skip=63 status=none
    python3 - "$OUT/$1.vol" <<'PY'
import struct, sys
f = open(sys.argv[1], 'r+b')
b = f.read(512)
for s in ((0, 6) if not struct.unpack_from('<H', b, 22)[0] else (0,)):   # hidden sectors 0 again
    f.seek(s * 512 + 28); f.write(struct.pack('<I', 0))
PY
}
same() {   # NAME
    rm -rf "$OUT/out"; mkdir "$OUT/out"
    mcopy -s -n -i "$OUT/$1.vol" '::*' "$OUT/out/" 2>/dev/null
    diff -r "$OUT/out" "$OUT/$1/files" > "$OUT/$1.diff" 2>&1 || { echo "files of $1 differ"; head "$OUT/$1.diff"; fail=1; }
}
if test -n "$CUT"; then
    host c
    "$ROOT/build/host/test_fatchk" "$OUT/c.vol" > "$OUT/c.before" || true
    "$ROOT/build/host/test_fatchk" "$OUT/c.vol" 0 0 F > "$OUT/c.fix" || true
    "$ROOT/build/host/test_fatchk" "$OUT/c.vol" > "$OUT/c.chk" || { echo "errors after the repair"; cat "$OUT/c.fix" "$OUT/c.chk"; fail=1; }
    fsck.fat -n "$OUT/c.vol" > "$OUT/c.fsck" 2>&1 || { echo "fsck.fat: errors"; cat "$OUT/c.fsck"; fail=1; }
    same c
    state=interrupted; grep -q 'Defragmentation done' "$OUT/serial.txt" && state=finished
    if test "$fail" = 0; then echo "DEFRAG power loss after ${CUT}s passed ($state, $(grep -c 'ERROR\|WARNING' "$OUT/c.before") findings repaired)"; else cat "$OUT/serial.txt"; exit 1; fi
    exit 0
fi
grep -q 'DEFRAG FAILED' "$OUT/serial.txt" && { echo "DEFRAG failed"; fail=1; }
grep -q 'ASPICHK FAILED' "$OUT/serial.txt" && { echo "ASPICHK failed"; fail=1; }
if test -n "$ASPI"; then names=(STICK); else names=(C D); fi
for n in "${names[@]}"; do
    nx=END; test "$n" = C && nx=D
    need "$n" "RUN$n" 'fragmented: [1-9][0-9]* before'
    need "AFTER$n" "$nx" 'fragmented: 0 before'
    need "AFTER$n" "$nx" 'No errors found'
done
test -z "$ASPI" && { need RUND AFTERD 'Joining'; need AFTERC D 'FAT16'; need AFTERD END 'FAT32'; }
test -n "$ASPI" && need AFTERSTICK END 'FAT12'
for n in "${checked[@]}"; do
    host "$n"
    fsck.fat -n "$OUT/$n.vol" > "$OUT/$n.fsck" 2>&1 || { echo "fsck.fat: errors on $n"; cat "$OUT/$n.fsck"; fail=1; }
    "$ROOT/build/host/test_fatchk" "$OUT/$n.vol" > "$OUT/$n.chk" || { echo "test_fatchk: errors on $n"; cat "$OUT/$n.chk"; fail=1; }
    "$ROOT/build/host/test_defrag" "$OUT/$n.vol" > "$OUT/$n.dfg"
    grep -q 'fragmented 0' "$OUT/$n.dfg" || { echo "$n still fragmented"; cat "$OUT/$n.dfg"; fail=1; }
    same "$n"
done
if test "$fail" = 0; then echo "DEFRAG ${ASPI:+ASPIDSK }test passed (qemu rc=$rc)"; else cat "$OUT/serial.txt"; exit 1; fi
