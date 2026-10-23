#!/bin/bash
# Only disposable image files: blank-media format and raw disk/image copies.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/removable-tools}
make -C "$ROOT" all >/dev/null
mkdir -p "$OUT"
test ! -e "$OUT/qmp.sock"
test -f "$ROOT/build/dos-cda/boot.img" || bash "$ROOT/tests/dos_cda.sh" >/dev/null
cp "$ROOT/build/dos-cda/boot.img" "$OUT/boot.img"
truncate -s 512M "$OUT/storage.img"
printf 'start=63,type=6\n' | sfdisk -q "$OUT/storage.img" > "$OUT/partition.log"
mkfs.fat -F16 --offset 63 "$OUT/storage.img" $(((512*2048-63)/2)) > "$OUT/mkfs.log" 2>&1
truncate -s $((196608*512)) "$OUT/source.img"
truncate -s $((196608*512)) "$OUT/target.img"
nasm -f bin -w-reloc-abs-word -I"$ROOT/../eusbaspi/src/" \
    -o "$OUT/EUSBASPI.SYS" "$ROOT/../eusbaspi/src/eusbaspi.asm"
printf '%s\r\n' 'DEVICE=EUSBASPI.SYS' 'DEVICE=ASPIFDD.SYS /V' \
    'LASTDRIVE=Z' 'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
printf '%s\r\n' '@ECHO OFF' 'ASPIFMT D: /YES > AUX' \
    'IF ERRORLEVEL 1 GOTO FAILED' 'ECHO FORMAT PASSED > AUX' 'GOTO DONE' \
    ':FAILED' 'ECHO FORMAT FAILED > AUX' ':DONE' 'QEXIT' > "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" \
    "$OUT/EUSBASPI.SYS" "$ROOT/build/dos/ASPIFDD.SYS" \
    "$ROOT/build/dos/ASPIFMT.EXE" "$ROOT/build/dos/ASPIDD.EXE" \
    "$ROOT/build/dos/ASPICTL.EXE" "$ROOT/build/dos/LOCK.EXE" \
    "$ROOT/build/dos/UNLOCK.EXE" "$ROOT/build/dos/STATUS.EXE" \
    "$ROOT/build/dos-cda/QEXIT.COM" ::/
printf '\xf8\x02' > "$OUT/sercon-port"
run_vm()
{
    set +e
    timeout "${TIMEOUT:-600}" qemu-system-i386 -machine pc -m 32 -display none \
        -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
        -drive if=ide,format=raw,file="$OUT/storage.img" \
        -device usb-ehci,id=usb \
        -device usb-bot,id=bot1,bus=usb.0,port=1 \
        -drive "id=src,if=none,format=raw,file=$OUT/source.img" \
        -device scsi-hd,bus=bot1.0,drive=src,removable=on,vendor=IOMEGA,product=ZIP-100 \
        -device usb-bot,id=bot2,bus=usb.0,port=2 \
        -drive "id=dst,if=none,format=raw,file=$OUT/target.img" \
        -device scsi-hd,bus=bot2.0,drive=dst,removable=on,vendor=IOMEGA,product=ZIP-100 \
        -serial file:"$OUT/serial-$1.log" \
        -serial file:"$OUT/console-$1.log" -fw_cfg name=etc/sercon-port,file="$OUT/sercon-port" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/process-$1.log" 2>&1
    vm_rc=$?
    set -e
    cat "$OUT/serial-$1.log"
    test "$vm_rc" = 1
    ! grep -Fq 'FAILED' "$OUT/serial-$1.log"
}
run_vm format
grep -Fq 'FORMAT PASSED' "$OUT/serial-format.log"
fsck.fat -vn "$OUT/source.img" > "$OUT/fsck-source.log"
printf 'Long filenames survive raw-sector copies.\r\n' > "$OUT/long.txt"
mcopy -i "$OUT/source.img" "$OUT/long.txt" '::/Ein langer Dateiname.txt'
cp "$OUT/source.img" "$OUT/expected.img"
printf '%s\r\n' '@ECHO OFF' \
    'LOCK D: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'STATUS D: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'UNLOCK D: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'ASPIDD D: E: /YES > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'ASPIDD READ D: C:\SOURCE.IMG > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'ASPIDD WRITE E: C:\SOURCE.IMG /YES > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'ASPIDD READ D: C:\SOURCE.IMG > AUX' 'IF NOT ERRORLEVEL 1 GOTO FAILED' \
    'ASPIDD READ D: D:\BAD.IMG > AUX' 'IF NOT ERRORLEVEL 1 GOTO FAILED' \
    'ECHO COPY PASSED > AUX' 'GOTO DONE' \
    ':FAILED' 'ECHO COPY FAILED > AUX' ':DONE' 'QEXIT' > "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/AUTOEXEC.BAT" ::/
run_vm copy
grep -Fq 'COPY PASSED' "$OUT/serial-copy.log"
cmp "$OUT/source.img" "$OUT/expected.img"
cmp "$OUT/target.img" "$OUT/expected.img"
mcopy -o -i "$OUT/storage.img@@32256" ::/SOURCE.IMG "$OUT/captured.img"
cmp "$OUT/captured.img" "$OUT/expected.img"
mtype -i "$OUT/target.img" '::/Ein langer Dateiname.txt' > "$OUT/long-copy.txt"
cmp "$OUT/long.txt" "$OUT/long-copy.txt"
fsck.fat -vn "$OUT/target.img" > "$OUT/fsck-target.log"
echo 'ASPIFMT blank media and ASPIDD ZIP-100 disk/image copy tests passed'
