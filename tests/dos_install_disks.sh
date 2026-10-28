#!/bin/bash
# Install each built language disk into a fresh disposable DOS hard disk.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/install-disks}
RELEASEDIR=${RELEASEDIR:-$ROOT/release}
SVARDOS_ZIP=${SVARDOS_ZIP:-$HOME/Iso/Dos/svardos-20250427-floppy-1.44M.zip}
mkdir -p "$OUT"
for language in US GR; do
    work="$OUT/$language"
    mkdir -p "$work"
    unzip -p "$SVARDOS_ZIP" svdos-1.44M-disk-1.img > "$work/boot.img"
    truncate -s 32M "$work/storage.img"
    printf 'start=63,type=6\n' | sfdisk -q "$work/storage.img" > "$work/partition.log"
    mkfs.fat -F16 -h63 --offset 63 "$work/storage.img" $(((32*2048-63)/2)) > "$work/mkfs.log" 2>&1
    printf '%s\r\n' 'LASTDRIVE=Z' 'SHELL=COMMAND.COM /P' > "$work/CONFIG.SYS"
    printf '%s\r\n' '@ECHO OFF' 'ECHO REM scratch test > C:\CONFIG.SYS' \
        'ECHO REM scratch test > C:\AUTOEXEC.BAT' \
        'B:\INSTALL /CHECK B:\INSTALL.INI > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
        'B:\INSTALL /B:C: /S B:\INSTALL.INI > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
        'IF NOT EXIST C:\OPENASPI\ASPIDDG.EXE GOTO FAILED' \
        'IF NOT EXIST C:\OPENASPI\OPENASPI.TXT GOTO FAILED' \
        'ECHO INSTALL DISK PASSED > AUX' 'GOTO DONE' ':FAILED' \
        'ECHO INSTALL DISK FAILED > AUX' ':DONE' 'QEXIT' > "$work/AUTOEXEC.BAT"
    printf '\xba\xf4\x00\xb0\x00\xee\xeb\xfe' > "$work/QEXIT.COM"
    mcopy -o -i "$work/boot.img" "$work/CONFIG.SYS" "$work/AUTOEXEC.BAT" "$work/QEXIT.COM" ::/
    set +e
    timeout "${TIMEOUT:-90}" qemu-system-i386 -machine pc -m 32 -display none \
        -drive "if=floppy,index=0,format=raw,file=$work/boot.img" -boot a \
        -drive "if=floppy,index=1,format=raw,readonly=on,file=$RELEASEDIR/$language/openaspi-${language,,}-disk1.img" \
        -drive "if=ide,format=raw,file=$work/storage.img" \
        -serial "file:$work/serial.log" -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        > "$work/process.log" 2>&1
    rc=$?
    set -e
    cat "$work/serial.log"
    test "$rc" = 1
    grep -Fq 'INSTALL DISK PASSED' "$work/serial.log"
    ! grep -Fq 'INSTALL DISK FAILED' "$work/serial.log"
    for file in ASPIMGR.EXE ASPIDDG.EXE; do
        mcopy -o -i "$work/storage.img@@32256" "::/OPENASPI/$file" "$work/$file"
        cmp "$work/$file" "$ROOT/build/$language/dos/$file"
    done
    # the FAT tools option is on by default
    for file in ASPICHK.EXE DEFRAG.EXE; do
        mcopy -o -i "$work/storage.img@@32256" "::/OPENASPI/$file" "$work/$file"
        cmp "$work/$file" "$ROOT/build/dos/$file"
    done
    mcopy -o -i "$work/storage.img@@32256" '::/OPENASPI/OPENASPI.TXT' "$work/README.TXT"
    cmp "$work/README.TXT" "$ROOT/build/packages/$language/README.TXT"
    dd if="$work/storage.img" of="$work/partition.img" bs=512 skip=63 status=none
    fsck.fat -vn "$work/partition.img" > "$work/fsck.log"
    python3 "$ROOT/tests/install_disk_ui.py" "$work" "$language" "$RELEASEDIR"
done
echo 'English and German disk sets: DOS package check, installation and installed language binaries passed'
