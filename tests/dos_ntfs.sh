#!/bin/bash
# NTFS.SYS: MS-DOS 7.1 with a FAT16 IDE disk (C:) and an IDE disk with an
# NTFS partition made by openfat's tests/ntfs_image.sh (long and German
# names, 150 files in a directory, fragmented, sparse, resident and
# compressed files, a file with an attribute list, a DOS name of its own);
# EUSBASPI and ASPIDSK /I13 add a USB disk with a second NTFS volume.
# NTFS.SYS /L:N gives them N: and O:, /Z:2 the time UTC + 2 hours.  DIR, TYPE and COPY to C:; the copies
# must equal the originals.  Writing, the compressed file and an open for
# writing are refused; the NTFS disks are not changed.
#   SVARDOS=1: SvarDOS (EDR-DOS kernel, SvarCOM) instead of MS-DOS 7.1
#   OPTS=/C: more options for NTFS.SYS (/C: CHS reads without INT 13h
#            extensions)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/dos-ntfs}
EUSBASPI_DIR=${EUSBASPI_DIR:-$ROOT/../eusbaspi}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
MSDOS_IMG=${MSDOS_IMG:-$ROOT/../msdosinst/out/DISK1.IMG}
OPENFAT=$ROOT/deps/openfat
SVARDOS=${SVARDOS:-0}
OPTS=${OPTS:-}
SVARDOS_ZIP=${SVARDOS_ZIP:-$HOME/Iso/Dos/svardos-20250427-floppy-1.44M.zip}

make -C "$ROOT" build/dos/ASPIDSK.SYS build/dos/NTFS.SYS >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"
nasm -f bin -o "$OUT/QEXIT.COM" "$AHCIASPI_DIR/tools/qexit.asm"
nasm -f bin -o "$OUT/DELAY.SYS" "$EUSBASPI_DIR/tools/delay.asm"
nasm -f bin -w-reloc-abs-word -I"$EUSBASPI_DIR/src/" \
    -o "$OUT/EUSBASPI.SYS" "$EUSBASPI_DIR/src/eusbaspi.asm"

if test "$SVARDOS" = 1; then
    unzip -p "$SVARDOS_ZIP" svdos-1.44M-disk-1.img > "$OUT/boot.img"
else
    cp "$MSDOS_IMG" "$OUT/boot.img"
fi
while IFS= read -r file; do
    case "${file^^}" in
        *COMMAND.COM|*KERNEL.SYS) ;;
        *) mdel -i "$OUT/boot.img" "$file" ;;
    esac
done < <(mdir -b -i "$OUT/boot.img" ::/)
printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' 'DEVICE=A:\DELAY.SYS' 'DEVICE=A:\DELAY.SYS' \
    'DEVICE=A:\EUSBASPI.SYS' 'DEVICE=A:\ASPIDSK.SYS /I13' "DEVICE=A:\\NTFS.SYS /L:N /Z:2 $OPTS" > "$OUT/CONFIG.SYS"
{
    printf '%s > AUX\r\n' 'ECHO === DIR' 'DIR N:' 'DIR N:\VIELE' 'DIR O:'
    printf '%s > AUX\r\n' 'ECHO === TYPE' 'TYPE N:\README.TXT' 'TYPE N:\UNTERO~1\TIEFER\DATEI.DAT' \
        'TYPE O:\README.TXT' 'CD N:\SUB' 'TYPE N:A.B' 'VOL N:'
    printf '%s > AUX\r\n' 'ECHO === COPY'
    for f in GROSS.BIN VIELE.BIN FRAG.BIN SPARSE.DAT ZUFALL.BIN LANGDOS.TXT EINLA~12.TXT 'VIELE\DATEI150.TXT'; do
        printf 'COPY N:\\%s C:\\ > AUX\r\n' "$f"
    done
    printf '%s > AUX\r\n' 'ECHO === DENIED' 'COPY N:\KOMPR\ZAHLEN.TXT C:\' 'COPY A:\QEXIT.COM N:\' \
        'MD N:\NEU' 'DEL N:\README.TXT' 'REN N:\README.TXT X.TXT' 'DIR N:\README.TXT'
    printf '%s > AUX\r\n' 'ECHO === END'
    printf '%s\r\n' 'QEXIT'
} > "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" "$OUT/EUSBASPI.SYS" "$OUT/DELAY.SYS" \
    "$ROOT/build/dos/ASPIDSK.SYS" "$ROOT/build/dos/NTFS.SYS" "$OUT/QEXIT.COM" ::/

# C: FAT16
truncate -s 64M "$OUT/c.img"
echo 'start=63, type=6' | sfdisk -q "$OUT/c.img"
mkfs.fat -F16 -n DOSDISK --offset 63 "$OUT/c.img" $(( (64*2048 - 63) / 2 )) >/dev/null
# IDE NTFS disk: the image of ntfs_image.sh in a type 07h partition at 1 MB
sh "$OPENFAT/tests/ntfs_image.sh" "$OUT/n" 64 4096 >/dev/null
SECTORS=$(( (64 + 1) * 2048 ))
truncate -s $((SECTORS * 512)) "$OUT/ntfs.img"
echo 'start=2048, type=7' | sfdisk -q "$OUT/ntfs.img"
dd if="$OUT/n/ntfs.img" of="$OUT/ntfs.img" bs=1M seek=1 conv=notrunc status=none
# USB NTFS disk (ASPIDSK /I13), 512-byte clusters
truncate -s 64M "$OUT/usb.img"
echo 'start=2048, type=7' | sfdisk -q "$OUT/usb.img"
truncate -s $((64 * 1048576 - 1048576)) "$OUT/part.img"
mkntfs -q -F -Q -c 512 -L USBNTFS "$OUT/part.img" >/dev/null
printf 'NTFS on USB through ASPIDSK /I13\r\n' > "$OUT/README.TXT"
ntfscp -q "$OUT/part.img" "$OUT/README.TXT" README.TXT
utc=$(date -u +%-H)
dd if="$OUT/part.img" of="$OUT/usb.img" bs=1M seek=1 conv=notrunc status=none
rm -f "$OUT/part.img"
cp "$OUT/ntfs.img" "$OUT/ntfs-before.img"
cp "$OUT/usb.img" "$OUT/usb-before.img"

plug=(
    "drive_add 0 if=none,id=usb,format=raw,file=$OUT/usb.img"
    "device_add usb-bot,id=bot1,bus=usbhc.0,port=1"
    "device_add scsi-hd,bus=bot1.0,drive=usb,vendor=OPENASPI,product=NTFS"
    "qom-set /machine/peripheral/bot1 attached true")
set +e
{ sleep 2; printf '%s\n' "${plug[@]}"; sleep "${TIMEOUT:-180}"; } |
timeout "${TIMEOUT:-180}" qemu-system-i386 \
    -machine pc -m 32 -display none -vga std -monitor stdio \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    -drive if=ide,index=0,format=raw,file="$OUT/c.img" \
    -drive if=ide,index=1,format=raw,file="$OUT/ntfs.img" \
    -device pci-ohci,id=usbhc \
    -serial file:"$OUT/serial.log" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/monitor.log" 2>&1
rc=$?
set -e
tr -d '\0' < "$OUT/serial.log" > "$OUT/serial.txt"

fail=0
need() { grep -q -- "$1" "$OUT/serial.txt" || { echo "missing: $1"; fail=1; }; }
section() { sed -n "/=== $1/,/=== /p" "$OUT/serial.txt"; }
need '=== END'
need 'hallo'
need 'tief'
need 'NTFS on USB through ASPIDSK /I13'
need 'sub'
need 'OPENASPI'
# /Z:2: O:\README.TXT's time is UTC + 2 hours (the format: 9:28p)
h=$(( (utc + 2) % 24 )); hh=$(( h % 12 )); test "$hh" = 0 && hh=12
ap=a; test "$h" -ge 12 && ap=p
section DIR | grep -q "README   TXT  *34 .* $hh:..$ap" || { echo "O:\README.TXT: not $hh:xx$ap (/Z:2)"; fail=1; }
# the free space as the library counts it on the host (EDR-DOS: one
# sector per cluster, see disk_space in ntfssys.c)
make -C "$OPENFAT" build/host/test_ntfs >/dev/null
free=$("$OPENFAT/build/host/test_ntfs" "$OUT/n/ntfs.img" 2>/dev/null | sed -n 's/.*, \([0-9]*\) of [0-9]* clusters of \([0-9]*\) bytes free/\1 \2/p')
free=$(printf "%'d" $(( ${free% *} * ${free#* } )) | tr . ,)
section DIR | grep -q " $free [Bb]ytes fre" || { echo "DIR N: not $free bytes free"; fail=1; }
section DIR | grep -q 'EINLA~12 TXT' || { echo 'DIR N: lacks EINLA~12.TXT'; fail=1; }
section DIR | grep -q 'LANGDOS  TXT' || { echo 'DIR N: lacks LANGDOS.TXT'; fail=1; }
test "$(section DIR | grep -c '^DATEI[0-9]* *TXT')" = 150 || { echo 'DIR N:\VIELE: not 150 files'; fail=1; }
mkdir -p "$OUT/c"
for f in GROSS.BIN VIELE.BIN FRAG.BIN SPARSE.DAT ZUFALL.BIN LANGDOS.TXT EINLA~12.TXT DATEI150.TXT; do
    mcopy -o -i "$OUT/c.img@@32256" "::/$f" "$OUT/c/$f" 2>/dev/null || { echo "C:\\$f missing"; fail=1; }
done
cmpf() { cmp -s "$OUT/c/$1" "$OUT/n/files/$2" || { echo "$1 differs from $2"; fail=1; }; }
cmpf GROSS.BIN gross.bin
cmpf VIELE.BIN viele.bin
cmpf FRAG.BIN frag.bin
cmpf SPARSE.DAT sparse.dat
cmpf ZUFALL.BIN zufall.bin
cmpf LANGDOS.TXT 'Langer Dateiname mit DOS.txt'
cmpf EINLA~12.TXT 'Ein langer Name 9.txt'
cmpf DATEI150.TXT VIELE/DATEI150.TXT
mdir -i "$OUT/c.img@@32256" ::/ZAHLEN.TXT >/dev/null 2>&1 && { echo 'the compressed file was copied'; fail=1; }
mdir -i "$OUT/c.img@@32256" ::/ 2>/dev/null | grep -q '^ZAHLEN' && { echo 'C:\ZAHLEN.TXT exists'; fail=1; }
section DENIED | grep -q 'X       TXT' && { echo 'renamed'; fail=1; }
section DENIED | grep -q 'README   TXT' || { echo 'README.TXT gone'; fail=1; }
cmp -s "$OUT/ntfs.img" "$OUT/ntfs-before.img" || { echo 'the IDE NTFS disk changed'; fail=1; }
cmp -s "$OUT/usb.img" "$OUT/usb-before.img" || { echo 'the USB NTFS disk changed'; fail=1; }
if test "$fail" = 0; then echo "NTFS.SYS test passed (qemu rc=$rc)"; else cat "$OUT/serial.txt"; exit 1; fi
