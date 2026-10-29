#!/bin/bash
# Writing through EXFAT.SYS: MS-DOS 7.1 (SVARDOS=1: SvarDOS, EDR-DOS kernel)
# with C: FAT16 and an exFAT disk of tests/exfat_image.sh (BIOS 81h, MBR
# partition) as D:.  COMMAND.COM copies files to D: (also a large one and
# into subdirectories), appends with ">>", makes, renames and removes
# directories, deletes (also by a pattern), sets attributes (4301h through
# LFNTEST), opens with 6C00h (create, replace, fail), and the errors: an existing directory, a directory that is not
# empty, a read-only file.  Then the files are copied back to C:, EXCHK
# checks D:, and on the host fsck.exfat checks the volume and the Linux
# exFAT driver must read what DOS wrote.  COPY keeps the time of the file.
#   OPTS=/R: read-only; every change must fail and the volume stay unchanged
#   FREEDOS=1: FreeDOS 1.4 (FD14LITE.img) as C:, which also holds the files
#   to copy; the programs are on C: instead of A:
#   HIGH=DIR: HIMEM.SYS and EMM386.EXE from DIR, DEVICEHIGH=EXFAT.SYS
#   LFN=1: EXFATL.SYS (long file names) as EXFAT.SYS
#   TEXFAT=0|1: the exFAT disk as TexFAT (tests/exfat_texfat.py, 1: the
#   second FAT active); both FATs must stay equal and test_exchk find no
#   error (fsck.exfat and Linux do not take TexFAT)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/dos-exfat-write}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
MSDOS_IMG=${MSDOS_IMG:-$ROOT/../msdosinst/out/DISK1.IMG}
SVARDOS=${SVARDOS:-0}
FREEDOS=${FREEDOS:-}
FREEDOS_IMG=${FREEDOS_IMG:-$HOME/Iso/Dos/freedos/FD14LITE.img}
OPTS=${OPTS:-}
TEXFAT=${TEXFAT:-}
HIGH=${HIGH:-}
LFN=${LFN:-}
SVARDOS_ZIP=${SVARDOS_ZIP:-$HOME/Iso/Dos/svardos-20250427-floppy-1.44M.zip}

make -C "$ROOT" build/dos/EXFAT.SYS build/dos/EXFATL.SYS build/dos/EXCHK.EXE build/dos/LFNTEST.EXE \
    build/host/test_exfat build/host/test_exchk >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"
nasm -f bin -o "$OUT/QEXIT.COM" "$AHCIASPI_DIR/tools/qexit.asm"

# B: the drive with the programs; FAT: C:, the files to copy
B=A
FAT="$OUT/fat.img@@32256"
if test -n "$FREEDOS"; then
    B=C
    cp "$FREEDOS_IMG" "$OUT/boot.img"
    FAT="$OUT/boot.img@@32256"
    printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' "DEVICE=C:\\EXFAT.SYS $OPTS" \
        'SHELL=C:\COMMAND.COM C:\ /P=C:\FDAUTO.BAT' > "$OUT/FDCONFIG.SYS"
    mcopy -o -i "$FAT" "$OUT/FDCONFIG.SYS" ::/
else
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
fi
if test -n "$HIGH"; then
    printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' 'DEVICE=A:\HIMEM.SYS' 'DEVICE=A:\EMM386.EXE NOEMS' \
        'DOS=HIGH,UMB' "DEVICEHIGH=A:\\EXFAT.SYS $OPTS" > "$OUT/CONFIG.SYS"
    mcopy -o -i "$OUT/boot.img" "$HIGH/HIMEM.SYS" "$HIGH/EMM386.EXE" ::/
else
    printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' "DEVICE=A:\\EXFAT.SYS $OPTS" > "$OUT/CONFIG.SYS"
fi
L="$B:\\LFNTEST"
{
printf '%s > AUX\r\n' \
    'ECHO === COPY' "COPY $B:\\QEXIT.COM D:\\NEU.COM" 'COPY C:\BIG.BIN D:\' \
    'COPY C:\BIG.BIN D:\UNTERO~1\TIEFER\BIG2.BIN' \
    'ECHO === MD' 'MD D:\NEU' 'MD D:\NEU\TIEF' 'COPY C:\SMALL.TXT D:\NEU\TIEF' \
    'ECHO === APPEND'
# these two write into the file themselves
printf '%s\r\n' 'ECHO Zeile 1>D:\NEU\LOG.TXT' 'ECHO Zeile 2>>D:\NEU\LOG.TXT'
printf '%s > AUX\r\n' 'TYPE D:\NEU\LOG.TXT' \
    'ECHO === REN' 'REN D:\KLEIN.TXT GROSS.TXT' 'REN D:\UNTERO~1 ORDNER' \
    'ECHO === DEL' 'DEL D:\README.TXT' 'DEL D:\*.GZ' 'DEL D:\SUB\A.B' 'RD D:\SUB' \
    'ECHO === ATTR' "$L DOSATTR D:\\NEU.COM 21" 'DEL D:\NEU.COM' \
    'ECHO === XOPEN' "$L XOPEN D:\\NEU\\X.TXT 12 neu" "$L XOPEN D:\\NEU\\X.TXT 12 zwei" \
    "$L XOPEN D:\\NEU\\X.TXT 10 nein" \
    'ECHO === ERRORS' 'MD D:\NEU' 'RD D:\NEU' \
    'ECHO === READ' 'COPY D:\BIG.BIN C:\BACK.BIN' 'COPY D:\NEU\TIEF\SMALL.TXT C:\SMALL2.TXT' \
    'ECHO === DIR' 'DIR D:' \
    'ECHO === EXCHK' 'EXCHK D:' 'IF ERRORLEVEL 1 ECHO EXCHK FAILED' \
    'ECHO === END'
printf '%s\r\n' 'QEXIT'
} > "$OUT/AUTOEXEC.BAT"
sys=EXFAT.SYS
if test -n "$LFN"; then sys=EXFATL.SYS; fi
if test -n "$FREEDOS"; then
    mv "$OUT/AUTOEXEC.BAT" "$OUT/FDAUTO.BAT"
    mcopy -o -i "$FAT" "$ROOT/build/dos/$sys" ::/EXFAT.SYS
    mcopy -o -i "$FAT" "$OUT/FDAUTO.BAT" "$ROOT/build/dos/EXCHK.EXE" "$ROOT/build/dos/LFNTEST.EXE" \
        "$OUT/QEXIT.COM" ::/
else
mcopy -o -i "$OUT/boot.img" "$ROOT/build/dos/$sys" ::/EXFAT.SYS
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" \
    "$ROOT/build/dos/EXCHK.EXE" "$ROOT/build/dos/LFNTEST.EXE" "$OUT/QEXIT.COM" ::/

# C: FAT16 with the files to copy
truncate -s 32M "$OUT/fat.img"
echo 'start=63, type=6' | sfdisk -q "$OUT/fat.img"
mkfs.fat -F16 -n FATDISK --offset 63 "$OUT/fat.img" $(( (32*2048 - 63) / 2 )) >/dev/null
fi
# BIG.BIN with a fixed time
head -c 400000 /dev/urandom > "$OUT/BIG.BIN"
touch -d '2021-03-04 05:06:08' "$OUT/BIG.BIN"
printf 'klein und fein\r\n' > "$OUT/SMALL.TXT"
mcopy -m -i "$FAT" "$OUT/BIG.BIN" "$OUT/SMALL.TXT" ::/

sh "$ROOT/tests/exfat_image.sh" "$OUT/x" 64 >/dev/null
if test -n "$TEXFAT"; then python3 "$ROOT/tests/exfat_texfat.py" "$OUT/x/exfat.img" "$TEXFAT"; fi
cp "$OUT/x/exfat.img" "$OUT/before.img"
truncate -s 65M "$OUT/exfat-disk.img"
echo 'start=2048, type=7' | sfdisk -q "$OUT/exfat-disk.img"
dd if="$OUT/x/exfat.img" of="$OUT/exfat-disk.img" bs=512 seek=2048 conv=notrunc status=none

if test -n "$FREEDOS"; then
    disks=(-drive if=ide,index=0,format=raw,file="$OUT/boot.img" -boot c)
else
    disks=(-drive if=floppy,format=raw,file="$OUT/boot.img" -boot a
           -drive if=ide,index=0,format=raw,file="$OUT/fat.img")
fi
set +e
timeout "${TIMEOUT:-180}" qemu-system-i386 -machine pc -m 32 -display none "${disks[@]}" \
    -drive if=ide,index=1,format=raw,file="$OUT/exfat-disk.img" \
    -serial file:"$OUT/serial.log" -device isa-debug-exit,iobase=0xf4,iosize=0x04
rc=$?
set -e
tr -d '\0' < "$OUT/serial.log" > "$OUT/serial.txt"
dd if="$OUT/exfat-disk.img" of="$OUT/after.img" bs=512 skip=2048 count=$((64 * 2048)) status=none

fail=0
grep -q '=== END' "$OUT/serial.txt" || { echo "the batch did not end"; fail=1; }
if test -n "$OPTS"; then
    cmp -s "$OUT/before.img" "$OUT/after.img" || { echo "/R: the volume was changed"; fail=1; }
    mcopy -n -i "$FAT" ::/BACK.BIN "$OUT/BACK.BIN" 2>/dev/null &&
        { echo "/R: BIG.BIN was copied to D:"; fail=1; }
    if test "$fail" = 0; then echo "EXFAT.SYS /R test passed (qemu rc=$rc)"; else cat "$OUT/serial.txt"; exit 1; fi
    exit 0
fi
grep -q 'EXCHK FAILED' "$OUT/serial.txt" && { echo "EXCHK finds errors"; fail=1; }
grep -q 'Zeile 2' "$OUT/serial.txt" || { echo "the appended line is missing"; fail=1; }
# 6C00h: create if missing, replace, and "fail if it exists" (error 80)
test "$(sed -n '/=== XOPEN/,/=== ERRORS/p' "$OUT/serial.txt" | tr -d '\r' | grep -E 'action|error' | tr '\n' ' ')" = \
    'action 2 action 3 error 80 ' || { echo "XOPEN: wrong actions"; fail=1; }
"$ROOT/build/host/test_exchk" "$OUT/after.img" > "$OUT/exchk.txt" || { cat "$OUT/exchk.txt"; echo "test_exchk finds errors"; fail=1; }
if test -n "$TEXFAT"; then
    python3 - "$OUT/after.img" <<'PY' || fail=1
import struct, sys
f = open(sys.argv[1], 'rb'); b = f.read(512)
ss = 1 << b[108]; fat, fatlen = struct.unpack_from('<II', b, 80)
f.seek(fat * ss); a = f.read(fatlen * ss); c = f.read(fatlen * ss)
if a != c: sys.exit('the two FATs differ')
PY
else
fsck.exfat -n "$OUT/after.img" > "$OUT/fsck.txt" 2>&1 || { cat "$OUT/fsck.txt"; echo "fsck.exfat finds errors"; fail=1; }

# what DOS wrote, through the Linux exFAT driver
loop=$(udisksctl loop-setup --no-user-interaction -r -f "$OUT/after.img" | sed -n 's/.* as \(\/dev\/[a-z0-9]*\)\.$/\1/p')
udisksctl mount --no-user-interaction -b "$loop" >/dev/null
mnt=$(lsblk -no MOUNTPOINT "$loop")
same() { cmp -s "$mnt/$1" "$2" || { echo "differs: $1"; fail=1; }; }
gone() { test ! -e "$mnt/$1" || { echo "still there: $1"; fail=1; }; }
same NEU.COM "$OUT/QEXIT.COM"
same BIG.BIN "$OUT/BIG.BIN"
same ORDNER/TIEFER/BIG2.BIN "$OUT/BIG.BIN"
same ORDNER/TIEFER/Datei.dat "$OUT/x/files/Unterordner mit langem Namen/Tiefer/Datei.dat"
same NEU/TIEF/SMALL.TXT "$OUT/SMALL.TXT"
printf 'Zeile 1\r\nZeile 2\r\n' > "$OUT/LOG.TXT"
same NEU/LOG.TXT "$OUT/LOG.TXT"
printf zwei > "$OUT/X.TXT"
same NEU/X.TXT "$OUT/X.TXT"
same GROSS.TXT "$OUT/x/files/klein.txt"
same "Ärger über Größe.txt" "$OUT/x/files/Ärger über Größe.txt"
gone README.TXT; gone klein.txt; gone archiv.tar.gz; gone SUB
gone "Unterordner mit langem Namen"
udisksctl unmount --no-user-interaction -b "$loop" >/dev/null
udisksctl loop-delete --no-user-interaction -b "$loop" >/dev/null
fi

# attributes and times: the host listing (8.3 name, attributes, size, date)
"$ROOT/build/host/test_exfat" "$OUT/after.img" > "$OUT/list.txt" 2>/dev/null
grep -qE '^  NEU\.COM +21 ' "$OUT/list.txt" || { echo "NEU.COM is not read-only"; fail=1; }
grep -qE '^  BIG\.BIN +20 +400000  04\.03\.2021 05:06' "$OUT/list.txt" ||
    { echo "BIG.BIN lost its time"; grep BIG "$OUT/list.txt"; fail=1; }
grep -qE '^  NEU +10 ' "$OUT/list.txt" || { echo "NEU is no directory"; fail=1; }
# the copies back to C:
mcopy -n -i "$FAT" ::/BACK.BIN ::/SMALL2.TXT "$OUT/" || fail=1
cmp -s "$OUT/BACK.BIN" "$OUT/BIG.BIN" || { echo "differs: C:\\BACK.BIN"; fail=1; }
cmp -s "$OUT/SMALL2.TXT" "$OUT/SMALL.TXT" || { echo "differs: C:\\SMALL2.TXT"; fail=1; }
if test "$fail" = 0; then echo "EXFAT.SYS write test (SvarDOS=$SVARDOS${TEXFAT:+, TexFAT=$TEXFAT}${FREEDOS:+, FreeDOS}${HIGH:+, high}${LFN:+, LFN}) passed (qemu rc=$rc)"; else cat "$OUT/serial.txt"; exit 1; fi
