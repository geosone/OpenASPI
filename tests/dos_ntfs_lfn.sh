#!/bin/bash
# The long file names of NTFSL.SYS, installed as NTFS.SYS when setup's long
# file name option is on (INT 21h AX=71xxh, read-only), under MS-DOS 7.1:
# C: FAT16, D: an NTFS disk of OpenFileSystem's tests/ntfs_image.sh (BIOS
# 81h).  LFNTEST (tests/lfntest.c) lists D: with long names (also by a
# pattern and in a subdirectory), changes into a directory by its long name
# and shows the current directory long, TRUENAME in its three forms, opens
# and reads files by long and 8.3 names (a compressed one too), reads
# attributes and the volume information; making, deleting, renaming and
# protecting give "access denied" (error 5) and the disk is not changed.
# C: is not NTFS.SYS's: without DOSLFN the call goes on to DOS (7100h).
# COMMAND.COM's DIR on D: shows long names and dates (71A7h).
#   DOSLFN=FILE: DOSLFN.COM -f- loaded after it (from Calmira's
#   tools/fetch_doslfn.sh); -f- makes it pass the calls for D: on, and C:
#   then has long names too.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/dos-ntfs-lfn}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
MSDOS_IMG=${MSDOS_IMG:-$ROOT/../msdosinst/out/DISK1.IMG}
DOSLFN=${DOSLFN:-}

make -C "$ROOT" build/dos/NTFSL.SYS build/dos/LFNTEST.EXE >/dev/null
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
printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' 'DEVICE=A:\NTFS.SYS' > "$OUT/CONFIG.SYS"
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
        'ECHO === TYPE' "$L TYPE \"D:\\Ärger über Größe.txt\"" "$L TYPE \"D:\\Ein langer Name 9.txt\"" \
        "$L TYPE D:\\EINLA~5E.TXT" "$L TYPE D:\\archiv.tar.gz" "$L TYPE \"D:\\Langer Dateiname mit DOS.txt\"" \
        "$L TYPE D:\\KOMPR\\zahlen.txt" \
        'ECHO === ATTR' "$L ATTR \"D:\\Unterordner mit langem Namen\"" "$L ATTR D:\\README.TXT" \
        'ECHO === INFO' "$L INFO \"D:\\Ärger über Größe.txt\"" \
        'ECHO === LEAK' "$L LEAK D:\\*" "$L DIR \"D:\\Ein langer Name 1?.txt\"" \
        'ECHO === MISSING' "$L TYPE D:\\gibt-es-nicht.txt" "$L DIR D:\\Fehlt\\*" \
        'ECHO === DENIED' "$L MAKE \"D:\\Neue lange Datei.txt\" Inhalt" "$L MAKE D:\\README.TXT Ersetzt" \
        "$L MD \"D:\\Neuer Ordner\"" "$L RD D:\\SUB" "$L DEL \"D:\\Ein langer Name 1.txt\"" \
        "$L DELW \"D:\\Ein langer Name 1?.txt\"" "$L REN D:\\README.TXT \"D:\\Neuer Name.txt\"" \
        "$L SETATTR D:\\README.TXT 21" \
        'ECHO === OTHER' "$L DIR C:\\*" \
        'ECHO === CMDDIR' 'D:' 'DIR' 'A:' \
        'ECHO === END'
    printf '%s\r\n' 'A:\QEXIT'
} | iconv -f utf-8 -t cp850 > "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$ROOT/build/dos/NTFSL.SYS" ::/NTFS.SYS
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" \
    "$ROOT/build/dos/LFNTEST.EXE" "$OUT/QEXIT.COM" ::/
test -z "$DOSLFN" || mcopy -o -i "$OUT/boot.img" "$DOSLFN" ::/DOSLFN.COM

truncate -s 32M "$OUT/fat.img"
echo 'start=63, type=6' | sfdisk -q "$OUT/fat.img"
mkfs.fat -F16 -n FATDISK --offset 63 "$OUT/fat.img" $(( (32*2048 - 63) / 2 )) >/dev/null
printf 'auf C\r\n' > "$OUT/Langer Name auf C.txt"
mcopy -i "$OUT/fat.img@@32256" "$OUT/Langer Name auf C.txt" ::/
sh "$ROOT/deps/OpenFileSystem/tests/ntfs_image.sh" "$OUT/n" 64 4096 >/dev/null
truncate -s 65M "$OUT/ntfs-disk.img"
echo 'start=2048, type=7' | sfdisk -q "$OUT/ntfs-disk.img"
dd if="$OUT/n/ntfs.img" of="$OUT/ntfs-disk.img" bs=512 seek=2048 conv=notrunc status=none
cp "$OUT/ntfs-disk.img" "$OUT/ntfs-before.img"

set +e
timeout "${TIMEOUT:-120}" qemu-system-i386 -machine pc -m 32 -display none \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    -drive if=ide,index=0,format=raw,file="$OUT/fat.img" \
    -drive if=ide,index=1,format=raw,file="$OUT/ntfs-disk.img" \
    -serial file:"$OUT/serial.log" -device isa-debug-exit,iobase=0xf4,iosize=0x04
rc=$?
set -e
tr -d '\0\r' < "$OUT/serial.log" | iconv -f cp850 -t utf-8 > "$OUT/serial.txt"

fail=0
section() { sed -n "/=== $1 *\$/,/=== $2 *\$/p" "$OUT/serial.txt"; }
need() { section "$1" "$2" | grep -qF -- "$3" || { echo "missing in $1: $3"; fail=1; }; }
need VOL DIR 'fs NTFS flags 4006 name 255 path 260'
for f in "$OUT"/n/files/*; do need DIR PATTERN "$(basename "$f")|"; done
need DIR PATTERN 'Langer Dateiname mit DOS.txt|LANGDOS.TXT|'
need DIR PATTERN 'Ein langer Name 9.txt|EINLA~5E.TXT|'
need DIR PATTERN 'README.TXT||'
need DIR PATTERN 'klein.txt|KLEIN.TXT|'
need DIR PATTERN 'KOMPR||10|'
need DIR PATTERN 'end 18'
need PATTERN SUB 'Ein langer Name 12.txt|'
section PATTERN SUB | grep -q 'Name 1.txt|' && { echo "PATTERN: Name 1.txt matched"; fail=1; }
need SUB TRUE '.||10|'
need SUB TRUE '..||10|'
need SUB TRUE 'Tiefer|TIEFER|30|'
need TRUE CD '0 D:\unterordner mit langem namen\tiefer\datei.dat'
section TRUE CD | grep -q '^1 D:\\UNTERO~[0-9A-Z]*\\TIEFER\\DATEI.DAT$' || { echo 'TRUE: no 8.3 path'; fail=1; }
need TRUE CD '2 D:\Unterordner mit langem Namen\Tiefer\Datei.dat'
need CD TYPE 'cwd \Unterordner mit langem Namen\Tiefer'
need CD TYPE '2 D:\Unterordner mit langem Namen\Tiefer\Datei.dat'
need CD TYPE 'cwd \'
need TYPE ATTR 'read 9: Umlaute'
test "$(section TYPE ATTR | grep -c 'read 9: Datei 9')" = 2 || { echo 'TYPE: Ein langer Name 9.txt not read twice'; fail=1; }
need TYPE ATTR 'action 1'
need TYPE ATTR 'read 13: zwei Punkte'
need TYPE ATTR 'read 10: DOS-Name'
need TYPE ATTR "read 299: $(seq 1 20000 | head -c 299 | head -1)"
need ATTR INFO 'attr 30'
need ATTR INFO 'size 7'
need INFO LEAK 'info attr'
need INFO LEAK 'size 9 links 1 serial'
need LEAK MISSING 'leak 8 searches'
need LEAK MISSING 'Ein langer Name 12.txt|'
need MISSING DENIED 'error 2'
need MISSING DENIED 'error 3'
test "$(section DENIED OTHER | grep -c 'error 5')" = 8 || { echo "DENIED: not eight times error 5"; fail=1; }
section DENIED OTHER | grep -q 'done\|action' && { echo 'DENIED: something was done'; fail=1; }
cmp -s "$OUT/ntfs-disk.img" "$OUT/ntfs-before.img" || { echo 'the NTFS disk changed'; fail=1; }
section CMDDIR END | grep -q '[0-9][0-9][.-][0-9][0-9][.-][0-9][0-9].*Ein langer Name 1.txt' ||
    { echo "CMDDIR: no long name with a date"; fail=1; }
if test -n "$DOSLFN"; then need OTHER CMDDIR 'Langer Name auf C.txt|'; else need OTHER CMDDIR 'error 28928'; fi
if test "$fail" = 0; then echo "NTFS.SYS long names ${DOSLFN:+with DOSLFN }passed (qemu rc=$rc)"; else cat "$OUT/serial.txt"; exit 1; fi
