#!/bin/bash
# EXFMT under MS-DOS 7.1 (the first disk of msdosinst) with EXFAT.SYS.
# BIOS (default): C: FAT16, an exFAT partition (BIOS 81h, D: of EXFAT.SYS)
#   and a blank 16 MB disk (BIOS 82h) with a read error at sector 20000
#   (QEMU blkdebug).  EXFMT /D:80 must refuse the FAT partition of C:
#   without /P:n.  EXFMT D: reformats D: (EXFAT.SYS mounts it again: VOL,
#   DIR, EXCHK), EXFMT /D:82 makes a superfloppy with one bad cluster.
# ASPI=1: EUSBASPI, ASPIDSK and a USB stick with FAT16 (D: of DOS): EXFMT
#   D: makes it exFAT through the exFAT service of ASPIDSK, EXFAT.SYS takes
#   D: over; then EXFMT D: once more, now on EXFAT.SYS's drive.  The FAT
#   stick goes in after the boot (QEMU monitor), in place of an exFAT stick:
#   SeaBIOS would show a FAT stick as a BIOS disk too, and DOS would give
#   it a letter of its own.
#   FDD=1: ASPIFDD instead of ASPIDSK, the stick named as a ZIP drive
# TEXFAT=1: all formats with /TEXFAT (fsck.exfat knows no TexFAT; only the
#   host check of build/host/test_exchk then)
# The results are checked on the host with fsck.exfat and test_exchk.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/dos-exfmt}
EUSBASPI_DIR=${EUSBASPI_DIR:-$ROOT/../eusbaspi}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
MSDOS_IMG=${MSDOS_IMG:-$ROOT/../msdosinst/out/DISK1.IMG}
ASPI=${ASPI:-}
BLK=ASPIDSK; PRODUCT=STICK
if test -n "${FDD:-}"; then BLK=ASPIFDD; PRODUCT='ZIP 100'; fi
X=; test -z "${TEXFAT:-}" || X=' /TEXFAT'

make -C "$ROOT" build/dos/EXFAT.SYS build/dos/EXCHK.EXE build/dos/EXFMT.EXE build/dos/$BLK.SYS \
    build/host/test_exchk build/host/test_exfmt >/dev/null
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
if test -n "$ASPI"; then
    nasm -f bin -w-reloc-abs-word -I"$EUSBASPI_DIR/src/" \
        -o "$OUT/EUSBASPI.SYS" "$EUSBASPI_DIR/src/eusbaspi.asm"
    printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' 'DEVICE=A:\EUSBASPI.SYS' \
        "DEVICE=A:\\$BLK.SYS" 'DEVICE=A:\EXFAT.SYS' > "$OUT/CONFIG.SYS"
    printf '%s > AUX\r\n' 'VOL D:' 'ECHO === INSERT' > "$OUT/AUTOEXEC.BAT"
    printf '%s\r\n' 'WAIT' >> "$OUT/AUTOEXEC.BAT"
    printf '%s > AUX\r\n' \
        'ECHO === FAT' 'DIR D:' 'DIR D:' 'EXFMT D:' \
        'ECHO === FORMAT1' "EXFMT D: /V:Stick$X /YES" 'IF ERRORLEVEL 1 ECHO EXFMT FAILED' \
        'ECHO === EXFAT1' 'VOL D:' 'DIR D:' 'EXCHK D:' 'IF ERRORLEVEL 1 ECHO EXCHK FAILED' \
        'ECHO === FORMAT2' "EXFMT D: /V:Zweimal$X /Q /YES" 'IF ERRORLEVEL 1 ECHO EXFMT FAILED' \
        'ECHO === EXFAT2' 'VOL D:' 'EXCHK D:' 'IF ERRORLEVEL 1 ECHO EXCHK FAILED' \
        'ECHO === END' >> "$OUT/AUTOEXEC.BAT"
    nasm -f bin -o "$OUT/WAIT.COM" "$ROOT/tests/wait_ticks.asm"
    mcopy -o -i "$OUT/boot.img" "$OUT/EUSBASPI.SYS" "$ROOT/build/dos/$BLK.SYS" "$OUT/WAIT.COM" ::/
else
    printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' 'DEVICE=A:\EXFAT.SYS' > "$OUT/CONFIG.SYS"
    printf '%s > AUX\r\n' \
        'ECHO === GUARD' 'EXFMT /D:80 /YES' \
        'ECHO === LAYOUT' 'EXFMT D:' 'EXFMT /D:82' \
        'ECHO === FORMAT1' "EXFMT D: /V:Formatiert$X /YES" 'IF ERRORLEVEL 1 ECHO EXFMT FAILED' \
        'ECHO === EXFAT1' 'VOL D:' 'DIR D:' 'EXCHK D:' 'IF ERRORLEVEL 1 ECHO EXCHK FAILED' \
        'ECHO === FORMAT2' "EXFMT /D:82 /V:LEER$X /YES" 'IF ERRORLEVEL 1 ECHO EXFMT FAILED' \
        'ECHO === END' > "$OUT/AUTOEXEC.BAT"
fi
printf '%s\r\n' 'QEXIT' >> "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" "$ROOT/build/dos/EXFAT.SYS" \
    "$ROOT/build/dos/EXCHK.EXE" "$ROOT/build/dos/EXFMT.EXE" "$OUT/QEXIT.COM" ::/

# C: FAT16
truncate -s 32M "$OUT/fat.img"
echo 'start=63, type=6' | sfdisk -q "$OUT/fat.img"
mkfs.fat -F16 -n FATDISK --offset 63 "$OUT/fat.img" $(( (32*2048 - 63) / 2 )) >/dev/null

if test -n "$ASPI"; then
    truncate -s 32M "$OUT/stick.img"
    echo 'start=63, type=6' | sfdisk -q "$OUT/stick.img"
    mkfs.fat -F16 -n FATSTICK --offset 63 "$OUT/stick.img" $(( (32*2048 - 63) / 2 )) >/dev/null
    truncate -s 32M "$OUT/exstick.img"
    echo 'start=2048, type=7' | sfdisk -q "$OUT/exstick.img"
    truncate -s 31M "$OUT/exvol.img"
    "$ROOT/build/host/test_exfmt" "$OUT/exvol.img" 0 1 BOOTSTICK >/dev/null
    dd if="$OUT/exvol.img" of="$OUT/exstick.img" bs=512 seek=2048 conv=notrunc status=none
    disks=(-device pci-ohci,id=usbhc -device usb-bot,id=bot1,bus=usbhc.0,port=1
           -drive id=stick,if=none,format=raw,file="$OUT/exstick.img"
           -device scsi-hd,bus=bot1.0,drive=stick,removable=on,vendor=OPENASPI,product="$PRODUCT")
else
    sh "$ROOT/tests/exfat_image.sh" "$OUT/x" 64 >/dev/null
    truncate -s 65M "$OUT/exfat-disk.img"
    echo 'start=2048, type=7' | sfdisk -q "$OUT/exfat-disk.img"
    dd if="$OUT/x/exfat.img" of="$OUT/exfat-disk.img" bs=512 seek=2048 conv=notrunc status=none
    truncate -s 16M "$OUT/blank.img"
    printf '[inject-error]\nevent = "read_aio"\nerrno = "5"\nsector = "20000"\nonce = "off"\n' > "$OUT/bad.conf"
    disks=(-drive if=ide,index=1,format=raw,file="$OUT/exfat-disk.img"
           -drive if=ide,index=2,format=raw,file="blkdebug:$OUT/bad.conf:$OUT/blank.img")
fi

monitor() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$OUT/mon.sock" >/dev/null; }
wait_for() {
    for _ in $(seq 1 600); do
        grep -qa "$1" "$OUT/serial.log" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}

set +e
timeout "${TIMEOUT:-180}" qemu-system-i386 \
    -machine pc -m 32 -display none -vga std \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    -drive if=ide,index=0,format=raw,file="$OUT/fat.img" \
    "${disks[@]}" \
    -serial file:"$OUT/serial.log" \
    -monitor unix:"$OUT/mon.sock",server,nowait \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 &
qemu=$!
if test -n "$ASPI"; then wait_for '=== INSERT' && monitor "change stick $OUT/stick.img raw"; fi
wait $qemu
rc=$?
set -e
tr -d '\0' < "$OUT/serial.log" > "$OUT/serial.txt"

fail=0
section() { sed -n "/=== $1/,/=== $2/p" "$OUT/serial.txt"; }
need() { section "$1" "$2" | grep -q "$3" || { echo "missing in $1: $3"; fail=1; }; }
# the host check of a volume image: fsck.exfat (not for TexFAT), test_exchk
host_check() {   # IMAGE LABEL [BAD]
    if test -z "$X"; then
        fsck.exfat -n "$1" > "$1.fsck" 2>&1 || { echo "fsck.exfat: errors in $1"; cat "$1.fsck"; fail=1; }
    fi
    "$ROOT/build/host/test_exchk" "$1" > "$1.chk" || { echo "test_exchk: errors in $1"; cat "$1.chk"; fail=1; }
    grep -q "bad ${3:-0}\$" "$1.chk" || { echo "not ${3:-0} bad clusters in $1"; cat "$1.chk"; fail=1; }
    test "$(dd if="$1" bs=1 skip=110 count=1 status=none | od -An -tu1 | tr -d ' ')" = "$(test -z "$X" && echo 1 || echo 2)" ||
        { echo "wrong number of FATs in $1"; fail=1; }
}
grep -q 'EXFMT FAILED' "$OUT/serial.txt" && { echo "EXFMT failed"; fail=1; }
grep -q 'EXCHK FAILED' "$OUT/serial.txt" && { echo "EXCHK failed"; fail=1; }
if test -n "$ASPI"; then
    need FAT FORMAT1 'FATSTICK'
    need FAT FORMAT1 'Layout only'
    need FORMAT1 EXFAT1 'Format complete'
    need EXFAT1 FORMAT2 'STICK'
    need EXFAT1 FORMAT2 'No errors found'
    need FORMAT2 EXFAT2 'Format complete'
    need EXFAT2 END 'ZWEIMAL'
    need EXFAT2 END 'No errors found'
    sfdisk -d "$OUT/stick.img" | grep -q 'type=7' || { echo "partition type not 07h"; fail=1; }
    dd if="$OUT/stick.img" of="$OUT/vol.img" bs=512 skip=63 status=none
    host_check "$OUT/vol.img"
else
    need GUARD LAYOUT 'name it with /P:n'
    need LAYOUT FORMAT1 'Layout only'
    need LAYOUT FORMAT1 'whole medium'
    need FORMAT1 EXFAT1 'partition 1 (type 07h)'
    need FORMAT1 EXFAT1 'Format complete'
    need EXFAT1 FORMAT2 'FORMATIERT'
    need EXFAT1 FORMAT2 'No errors found'
    need FORMAT2 END '1 bad clusters'
    need FORMAT2 END 'Format complete'
    dd if="$OUT/exfat-disk.img" of="$OUT/vol.img" bs=512 skip=2048 status=none
    host_check "$OUT/vol.img"
    host_check "$OUT/blank.img" LEER 1
fi
if test "$fail" = 0; then echo "EXFMT ${ASPI:+$BLK }test passed (qemu rc=$rc)"; else cat "$OUT/serial.txt"; exit 1; fi
