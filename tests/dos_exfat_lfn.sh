#!/bin/bash
# The long file names of EXFATL.SYS, installed as EXFAT.SYS when setup's long
# file name option is on (INT 21h AX=71xxh), under MS-DOS 7.1:
# C: FAT16, D: an exFAT disk of tests/exfat_image.sh (BIOS 81h).  LFNTEST
# (tests/lfntest.c) lists D: with long names (also by a pattern and in a
# subdirectory), changes into a directory by its long name and shows the
# current directory long, TRUENAME in its three forms, opens and reads files
# by long and 8.3 names, reads attributes and the volume information;
# makes, replaces, renames (into a new directory), protects and removes
# files and directories by long names; read-only refuses DEL and the full
# directory RD (error 5); fsck.exfat and the Linux driver check the result.
# C: is not EXFAT.SYS's:
# without DOSLFN the call goes on to DOS (7100h).  COMMAND.COM's DIR on D:
# shows long names and dates (71A7h), and "> AUX" there is the device.
#   DOSLFN=FILE: DOSLFN.COM -f- loaded after it (from Calmira's
#   tools/fetch_doslfn.sh); -f- (no fallback mode) makes it pass the calls
#   for D: on, and C: then has long names too.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/dos-exfat-lfn}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
MSDOS_IMG=${MSDOS_IMG:-$ROOT/../msdosinst/out/DISK1.IMG}
DOSLFN=${DOSLFN:-}

make -C "$ROOT" build/dos/EXFATL.SYS build/dos/LFNTEST.EXE >/dev/null
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
printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' 'DEVICE=A:\EXFAT.SYS' > "$OUT/CONFIG.SYS"
L='A:\LFNTEST'
{
    if test -n "$DOSLFN"; then printf '%s\r\n' 'DOSLFN.COM -f- > AUX'; fi
    printf '%s > AUX\r\n' \
        'ECHO === VOL' "$L VOL D:\\" \
        'ECHO === DIR' "$L DIR D:\\*" \
        'ECHO === PATTERN' "$L DIR \"D:\\Ein*name 1?.txt\"" \
        'ECHO === SUB' "$L DIR \"D:\\Unterordner mit langem Namen\\*.*\"" \
        'ECHO === TRUE' "$L TRUE \"d:\\unterordner mit langem namen\\tiefer\\datei.dat\"" \
        'ECHO === CD' "$L CD \"D:\\Unterordner mit langem Namen\\Tiefer\"" 'D:' "$L TRUE Datei.dat" "$L CD D:..\\.." 'A:' \
        'ECHO === TYPE' "$L TYPE \"D:\\Ärger über Größe.txt\"" "$L TYPE D:\\EINLAN~1.TXT" "$L TYPE D:\\archiv.tar.gz" \
        'ECHO === ATTR' "$L ATTR \"D:\\Unterordner mit langem Namen\"" "$L ATTR D:\\README.TXT" \
        'ECHO === INFO' "$L INFO \"D:\\Ärger über Größe.txt\"" \
        'ECHO === LEAK' "$L LEAK D:\\*" "$L DIR \"D:\\Ein langer Name 1?.txt\"" \
        'ECHO === MISSING' "$L TYPE D:\\gibt-es-nicht.txt" "$L DIR D:\\Fehlt\\*" \
        'ECHO === WRITE' "$L MAKE \"D:\\Neue lange Datei.txt\" Inhalt" \
        "$L MAKE \"D:\\Neue lange Datei.txt\" Ersetzt" "$L MD \"D:\\Neuer Ordner\"" \
        "$L REN \"D:\\Neue lange Datei.txt\" \"D:\\Neuer Ordner\\Umbenannt mit Länge.txt\"" \
        "$L SETATTR \"D:\\Neuer Ordner\\Umbenannt mit Länge.txt\" 21" \
        'ECHO === PROTECT' "$L DEL \"D:\\Neuer Ordner\\Umbenannt mit Länge.txt\"" "$L RD \"D:\\Neuer Ordner\"" \
        'ECHO === REMOVE' "$L SETATTR \"D:\\Neuer Ordner\\Umbenannt mit Länge.txt\" 20" \
        "$L DEL \"D:\\Neuer Ordner\\Umbenannt mit Länge.txt\"" "$L RD \"D:\\Neuer Ordner\"" \
        "$L DELW \"D:\\Ein langer Name 1?.txt\"" "$L DEL D:\\README.TXT" \
        "$L MD \"D:\\Bleibt hier\"" "$L MAKE \"D:\\Bleibt hier\\Lange Datei.txt\" bleibt" \
        'ECHO === OTHER' "$L DIR C:\\*" \
        'ECHO === CMDDIR' 'D:' 'DIR' 'A:' \
        'ECHO === END'
    printf '%s\r\n' 'A:\QEXIT'
} | iconv -f utf-8 -t cp850 > "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$ROOT/build/dos/EXFATL.SYS" ::/EXFAT.SYS
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" \
    "$ROOT/build/dos/LFNTEST.EXE" "$OUT/QEXIT.COM" ::/
test -z "$DOSLFN" || mcopy -o -i "$OUT/boot.img" "$DOSLFN" ::/DOSLFN.COM

truncate -s 32M "$OUT/fat.img"
echo 'start=63, type=6' | sfdisk -q "$OUT/fat.img"
mkfs.fat -F16 -n FATDISK --offset 63 "$OUT/fat.img" $(( (32*2048 - 63) / 2 )) >/dev/null
printf 'auf C\r\n' > "$OUT/Langer Name auf C.txt"
mcopy -i "$OUT/fat.img@@32256" "$OUT/Langer Name auf C.txt" ::/
sh "$ROOT/tests/exfat_image.sh" "$OUT/x" 64 >/dev/null
truncate -s 65M "$OUT/exfat-disk.img"
echo 'start=2048, type=7' | sfdisk -q "$OUT/exfat-disk.img"
dd if="$OUT/x/exfat.img" of="$OUT/exfat-disk.img" bs=512 seek=2048 conv=notrunc status=none

set +e
timeout "${TIMEOUT:-120}" qemu-system-i386 -machine pc -m 32 -display none \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    -drive if=ide,index=0,format=raw,file="$OUT/fat.img" \
    -drive if=ide,index=1,format=raw,file="$OUT/exfat-disk.img" \
    -serial file:"$OUT/serial.log" -device isa-debug-exit,iobase=0xf4,iosize=0x04
rc=$?
set -e
tr -d '\0\r' < "$OUT/serial.log" | iconv -f cp850 -t utf-8 > "$OUT/serial.txt"

fail=0
section() { sed -n "/=== $1 *\$/,/=== $2 *\$/p" "$OUT/serial.txt"; }
need() { section "$1" "$2" | grep -qF -- "$3" || { echo "missing in $1: $3"; fail=1; }; }
need VOL DIR 'fs exFAT flags 4006 name 255 path 260'
for f in "$OUT"/x/files/*; do need DIR PATTERN "$(basename "$f")|"; done
need DIR PATTERN 'Ein langer Name 10.txt|EINLA~10.TXT|20|'
need DIR PATTERN 'README.TXT||20|7|'
need DIR PATTERN 'klein.txt|KLEIN.TXT|20|18|'
need DIR PATTERN 'end 18'
need PATTERN SUB 'Ein langer Name 12.txt|'
section PATTERN SUB | grep -q 'Name 1.txt|' && { echo "PATTERN: Name 1.txt matched"; fail=1; }
need SUB TRUE '.||10|'
need SUB TRUE '..||10|'
need SUB TRUE 'Tiefer|TIEFER|10|'
need TRUE CD '0 D:\unterordner mit langem namen\tiefer\datei.dat'
need TRUE CD '1 D:\UNTERO~1\TIEFER\DATEI.DAT'
need TRUE CD '2 D:\Unterordner mit langem Namen\Tiefer\Datei.dat'
need CD TYPE 'cwd \Unterordner mit langem Namen\Tiefer'
need CD TYPE '2 D:\Unterordner mit langem Namen\Tiefer\Datei.dat'
need CD TYPE 'cwd \'
need TYPE ATTR 'read 9: Umlaute'
need TYPE ATTR 'read 9: Datei 1'
need TYPE ATTR 'action 1'
need TYPE ATTR 'read 13: zwei Punkte'
need ATTR INFO 'attr 10'
need ATTR INFO 'attr 20'
need ATTR INFO 'size 7'
need INFO LEAK 'info attr 20 size 9 links 1 serial'
need LEAK MISSING 'leak 8 searches'
need LEAK MISSING 'Ein langer Name 12.txt|'
need MISSING WRITE 'error 2'
need MISSING WRITE 'error 3'
need WRITE PROTECT 'action 2'
need WRITE PROTECT 'action 3'
need WRITE PROTECT 'wrote 7'
test "$(section WRITE PROTECT | grep -c 'done')" = 3 || { echo "WRITE: not three times done"; fail=1; }
test "$(section PROTECT REMOVE | grep -c 'error 5')" = 2 || { echo "PROTECT: not two times error 5"; fail=1; }
test "$(section REMOVE OTHER | grep -c 'done')" = 6 || { echo "REMOVE: not six times done"; fail=1; }
need REMOVE OTHER 'wrote 6'
# what was written, through the Linux exFAT driver and fsck.exfat
dd if="$OUT/exfat-disk.img" of="$OUT/after.img" bs=512 skip=2048 count=$((64 * 2048)) status=none
fsck.exfat -n "$OUT/after.img" > "$OUT/fsck.txt" 2>&1 || { cat "$OUT/fsck.txt"; echo "fsck.exfat finds errors"; fail=1; }
loop=$(udisksctl loop-setup --no-user-interaction -r -f "$OUT/after.img" | sed -n 's/.* as \(\/dev\/[a-z0-9]*\)\.$/\1/p')
udisksctl mount --no-user-interaction -b "$loop" >/dev/null
mnt=$(lsblk -no MOUNTPOINT "$loop")
test "$(cat "$mnt/Bleibt hier/Lange Datei.txt" 2>/dev/null)" = bleibt || { echo "Lange Datei.txt is wrong"; fail=1; }
for gone in README.TXT "Neuer Ordner" "Neue lange Datei.txt" "Ein langer Name 10.txt" "Ein langer Name 12.txt"; do
    test ! -e "$mnt/$gone" || { echo "still there: $gone"; fail=1; }
done
cmp -s "$mnt/Ein langer Name 1.txt" "$OUT/x/files/Ein langer Name 1.txt" || { echo "Ein langer Name 1.txt is lost"; fail=1; }
udisksctl unmount --no-user-interaction -b "$loop" >/dev/null
udisksctl loop-delete --no-user-interaction -b "$loop" >/dev/null
# COMMAND.COM's DIR with long names and dates (71A7h); its "> AUX" on D:
# is a device (716Ch passes it to DOS)
section CMDDIR END | grep -q '[0-9][0-9][.-][0-9][0-9][.-][0-9][0-9].*Ein langer Name 1.txt' ||
    { echo "CMDDIR: no long name with a date"; fail=1; }
if test -n "$DOSLFN"; then need OTHER CMDDIR 'Langer Name auf C.txt|'; else need OTHER CMDDIR 'error 28928'; fi
if test "$fail" = 0; then echo "EXFAT.SYS long names ${DOSLFN:+with DOSLFN }passed (qemu rc=$rc)"; else cat "$OUT/serial.txt"; exit 1; fi
