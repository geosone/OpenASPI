#!/bin/bash
# The exFAT package (make disksets): each language disk installed silently
# into a fresh disposable DOS hard disk (SvarDOS), then the OpenASPI disk of
# the same language with its exFAT option over it.  CONFIG.SYS must have
# the EXFAT.SYS line of the exFAT package first, then only the one of
# OpenASPI.  Then the exFAT package once more: it conflicts with OpenASPI,
# and INSTALL /S takes Cancel, so CONFIG.SYS stays.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/install-exfat}
RELEASEDIR=${RELEASEDIR:-$ROOT/release}
SVARDOS_ZIP=${SVARDOS_ZIP:-$HOME/Iso/Dos/svardos-20250427-floppy-1.44M.zip}
mkdir -p "$OUT"
for language in US GR; do
    lang=${language,,}
    work="$OUT/$language"
    rm -rf "$work"
    mkdir -p "$work"
    unzip -p "$SVARDOS_ZIP" svdos-1.44M-disk-1.img > "$work/boot.img"
    truncate -s 32M "$work/storage.img"
    printf 'start=63,type=6\n' | sfdisk -q "$work/storage.img"
    mkfs.fat -F16 -h63 --offset 63 "$work/storage.img" $(((32*2048-63)/2)) > /dev/null
    printf '%s\r\n' 'LASTDRIVE=Z' 'SHELL=COMMAND.COM /P' > "$work/CONFIG.SYS"
    # OpenASPI: the five options as detected/proposed, exFAT on, FAT tools
    # proposed, exFAT with long file names on (EXFATL.SYS as EXFAT.SYS)
    printf '%s\r\n' '[Answers]' 'Options=22222121' > "$work/ANSWERS.INI"
    # step 1 installs the exFAT disk, step 2 (after the disk change) OpenASPI
    printf '%s\r\n' '@ECHO OFF' 'IF EXIST C:\STEP2 GOTO STEP3' 'IF EXIST C:\STEP1 GOTO STEP2' \
        'ECHO REM scratch test > C:\CONFIG.SYS' 'ECHO REM scratch test > C:\AUTOEXEC.BAT' \
        'B:\INSTALL /CHECK B:\INSTALL.INI > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
        'B:\INSTALL /B:C: /S B:\INSTALL.INI > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
        'IF NOT EXIST C:\EXFAT\EXFAT.SYS GOTO FAILED' 'IF NOT EXIST C:\EXFAT\EXFMT.EXE GOTO FAILED' \
        'IF NOT EXIST C:\EXFAT\EXCHK.EXE GOTO FAILED' 'IF NOT EXIST C:\EXFAT\EXFAT.TXT GOTO FAILED' \
        'ECHO === CONFIG1 > AUX' 'TYPE C:\CONFIG.SYS > AUX' 'ECHO === END1 > AUX' \
        'ECHO X > C:\STEP1' 'ECHO STEP1 DONE > AUX' 'QEXIT' ':STEP2' \
        'B:\INSTALL /B:C: /S:A:\ANSWERS.INI B:\INSTALL.INI > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
        'IF NOT EXIST C:\OPENASPI\EXFAT.SYS GOTO FAILED' 'IF NOT EXIST C:\OPENASPI\EXFMT.EXE GOTO FAILED' \
        'ECHO === CONFIG2 > AUX' 'TYPE C:\CONFIG.SYS > AUX' 'ECHO === END2 > AUX' \
        'ECHO X > C:\STEP2' 'ECHO STEP2 DONE > AUX' 'QEXIT' ':STEP3' \
        'B:\INSTALL /B:C: /S B:\INSTALL.INI > AUX' 'IF NOT ERRORLEVEL 1 GOTO FAILED' \
        'ECHO === CONFIG3 > AUX' 'TYPE C:\CONFIG.SYS > AUX' 'ECHO === END3 > AUX' \
        'ECHO INSTALL EXFAT PASSED > AUX' 'GOTO DONE' ':FAILED' \
        'ECHO INSTALL EXFAT FAILED > AUX' ':DONE' 'QEXIT' > "$work/AUTOEXEC.BAT"
    printf '\xba\xf4\x00\xb0\x00\xee\xeb\xfe' > "$work/QEXIT.COM"
    mcopy -o -i "$work/boot.img" "$work/CONFIG.SYS" "$work/AUTOEXEC.BAT" "$work/QEXIT.COM" "$work/ANSWERS.INI" ::/
    for disk in "exfat-$lang-disk1.img" "openaspi-$lang-disk1.img" "exfat-$lang-disk1.img"; do
        set +e
        timeout "${TIMEOUT:-120}" qemu-system-i386 -machine pc -m 32 -display none \
            -drive "if=floppy,index=0,format=raw,file=$work/boot.img" -boot a \
            -drive "if=floppy,index=1,format=raw,readonly=on,file=$RELEASEDIR/$language/$disk" \
            -drive "if=ide,format=raw,file=$work/storage.img" \
            -serial "file:$work/serial.log" -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
            > "$work/process.log" 2>&1
        rc=$?
        set -e
        tr -d '\0' < "$work/serial.log" >> "$work/serial.txt"
        test "$rc" = 1 || { cat "$work/serial.txt"; echo "qemu rc $rc"; exit 1; }
    done
    fail=0
    grep -Fq 'STEP1 DONE' "$work/serial.txt" || fail=1
    grep -Fq 'INSTALL EXFAT PASSED' "$work/serial.txt" || fail=1
    config1=$(sed -n '/=== CONFIG1/,/=== END1/p' "$work/serial.txt" | tr -d '\r')
    config2=$(sed -n '/=== CONFIG2/,/=== END2/p' "$work/serial.txt" | tr -d '\r')
    echo "$config1" | grep -Fxq 'DEVICE=C:\EXFAT\EXFAT.SYS' || { echo "no EXFAT.SYS line of the exFAT package"; fail=1; }
    test "$(echo "$config2" | grep -ci 'EXFAT.SYS')" = 1 || { echo "not exactly one EXFAT.SYS line"; fail=1; }
    echo "$config2" | grep -Eq '^DEVICE(HIGH)?=C:\\OPENASPI\\EXFAT\.SYS$' || { echo "no EXFAT.SYS line of OpenASPI"; fail=1; }
    config3=$(sed -n '/=== CONFIG3/,/=== END3/p' "$work/serial.txt" | tr -d '\r')
    test "$(echo "$config3" | sed "1d;\$d")" = "$(echo "$config2" | sed "1d;\$d")" || { echo "CONFIG.SYS changed by the conflicting exFAT setup"; fail=1; }
    mcopy -o -i "$work/storage.img@@32256" '::/EXFAT/EXFAT.TXT' "$work/EXFAT.TXT"
    cmp "$work/EXFAT.TXT" "$ROOT/build/packages/exfat-$language/README.TXT" || fail=1
    # the exFAT package by default without, OpenASPI here with long names
    mcopy -o -i "$work/storage.img@@32256" '::/EXFAT/EXFAT.SYS' "$work/EXFAT-PKG.SYS"
    cmp "$work/EXFAT-PKG.SYS" "$ROOT/build/dos/EXFAT.SYS" || fail=1
    mcopy -o -i "$work/storage.img@@32256" '::/OPENASPI/EXFAT.SYS' "$work/EXFAT.SYS"
    cmp "$work/EXFAT.SYS" "$ROOT/build/dos/EXFATL.SYS" || fail=1
    if mdir -i "$work/storage.img@@32256" ::/OPENASPI/EXFATL.SYS >/dev/null 2>&1; then
        echo "EXFATL.SYS installed under its own name"; fail=1
    fi
    dd if="$work/storage.img" of="$work/partition.img" bs=512 skip=63 status=none
    fsck.fat -vn "$work/partition.img" > "$work/fsck.log" || fail=1
    if test "$fail" != 0; then cat "$work/serial.txt"; echo "$language FAILED"; exit 1; fi
done
echo 'English and German exFAT packages: installation, and OpenASPI with exFAT over it, passed'
