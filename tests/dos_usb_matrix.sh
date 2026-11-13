#!/bin/bash
# EUSBASPI with every QEMU USB host controller (UHCI, OHCI, EHCI, xHCI):
# plugged in after the BIOS (DELAY.SYS), a usb-bot with three LUNs (SCSI
# hard disk, CD-ROM, removable ZIP 100) and a plain usb-storage stick.
# ASPIDSK, ASPIFDD and ASPICDA (SHSUCDX) must read every medium; the disks
# and the ZIP must take a copy of the CD's BIG.BIN, checked on the host.
#   HCS="..."  controllers to test (default: all four)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTBASE=${OUT:-$ROOT/build/dos-usb-matrix}
EUSBASPI_DIR=${EUSBASPI_DIR:-$ROOT/../eusbaspi}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
DOS_DIR=${DOS_DIR:-$HOME/Iso/Dos}
SVARDOS_ZIP=${SVARDOS_ZIP:-$DOS_DIR/svardos-20250427-floppy-1.44M.zip}
HCS=${HCS:-piix3-usb-uhci pci-ohci usb-ehci qemu-xhci}

make -C "$ROOT" all >/dev/null
mkdir -p "$OUTBASE"
nasm -f bin -w-reloc-abs-word -I"$EUSBASPI_DIR/src/" \
    -o "$OUTBASE/EUSBASPI.SYS" "$EUSBASPI_DIR/src/eusbaspi.asm"
nasm -f bin -o "$OUTBASE/QEXIT.COM" "$AHCIASPI_DIR/tools/qexit.asm"
nasm -f bin -o "$OUTBASE/DELAY.SYS" "$EUSBASPI_DIR/tools/delay.asm"
head -c 60000 /dev/urandom > "$OUTBASE/BIG.BIN"
mkdir -p "$OUTBASE/cdroot"
printf 'MATRIX CD read by ASPICDA\r\n' > "$OUTBASE/cdroot/CD.TXT"
cp "$OUTBASE/BIG.BIN" "$OUTBASE/cdroot/BIG.BIN"
rm -f "$OUTBASE/cd.iso"
xorriso -outdev "$OUTBASE/cd.iso" -volid MATRIXCD -map "$OUTBASE/cdroot" / \
    -padding 1m -end 2>/dev/null

partdisk() { # image MB label text-file text
    truncate -s 0 "$1"; truncate -s "$2M" "$1"
    echo 'start=63, type=6' | sfdisk -q "$1"
    mkfs.fat -F16 -n "$3" --offset 63 "$1" $(( ($2*2048 - 63) / 2 )) >/dev/null
    printf '%s\r\n' "$5" > "$OUTBASE/$4"
    mcopy -i "$1@@32256" "$OUTBASE/$4" ::/
}

fail=0
for hc in $HCS; do
    OUT=$OUTBASE/$hc
    rm -rf "${OUT:?}"; mkdir -p "$OUT"
    opt=; [ "$hc" = qemu-xhci ] && opt=' /X'
    unzip -p "$SVARDOS_ZIP" svdos-1.44M-disk-1.img > "$OUT/boot.img"
    while IFS= read -r file; do
        file=${file#::/}
        case "${file^^}" in KERNEL.SYS|COMMAND.COM) ;; *) mdel -i "$OUT/boot.img" "::/$file" ;; esac
    done < <(mdir -b -i "$OUT/boot.img" ::/)
    printf '%s\r\n' 'DEVICE=DELAY.SYS' 'DEVICE=DELAY.SYS' "DEVICE=EUSBASPI.SYS$opt /V" \
        'DEVICE=ASPIDSK.SYS' 'DEVICE=ASPIFDD.SYS' 'DEVICE=ASPICDA.SYS /D:ASPICDA0' \
        'LASTDRIVE=Z' 'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
    printf '%s\r\n' '@ECHO OFF' 'SHSUCDX /D:ASPICDA0,R > AUX' 'TYPE R:\CD.TXT > AUX' \
        'COMMAND /C CHECK.BAT > AUX' 'ECHO MATRIX DONE > AUX' 'QEXIT' > "$OUT/AUTOEXEC.BAT"
    {   # output redirected as a whole: IF EXIST ... > AUX is not redirected
        printf '%s\r\n' '@ECHO OFF'
        for d in C D E F G; do
            printf '%s\r\n' "IF EXIST $d:\\HDD.TXT TYPE $d:\\HDD.TXT" \
                "IF EXIST $d:\\STICK.TXT TYPE $d:\\STICK.TXT" \
                "IF EXIST $d:\\ZIP.TXT TYPE $d:\\ZIP.TXT" \
                "IF EXIST $d:\\NUL COPY R:\\BIG.BIN $d:\\BIG.BIN"
        done
    } > "$OUT/CHECK.BAT"
    mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" "$OUT/CHECK.BAT" \
        "$OUTBASE/EUSBASPI.SYS" "$OUTBASE/DELAY.SYS" "$OUTBASE/QEXIT.COM" \
        "$ROOT/build/dos/ASPIDSK.SYS" "$ROOT/build/dos/ASPIFDD.SYS" \
        "$ROOT/build/dos/ASPICDA.SYS" "$ROOT/build/dos/SHSUCDX.COM" ::/
    partdisk "$OUT/hdd.img" 32 MATRIXHDD HDD.TXT 'MATRIX HDD read by ASPIDSK'
    partdisk "$OUT/stick.img" 16 MATRIXSTK STICK.TXT 'MATRIX STICK read by ASPIDSK'
    truncate -s 0 "$OUT/zip.img"; truncate -s $((196608*512)) "$OUT/zip.img"
    mkfs.fat -F16 -s4 -g64/32 -n MATRIXZIP "$OUT/zip.img" >/dev/null
    printf 'MATRIX ZIP read by ASPIFDD\r\n' > "$OUTBASE/ZIP.TXT"
    mcopy -i "$OUT/zip.img" "$OUTBASE/ZIP.TXT" ::/
    bus=usbhc.0
    plug=(
        "drive_add 0 if=none,id=hdd,format=raw,file=$OUT/hdd.img"
        "drive_add 0 if=none,id=cd,format=raw,media=cdrom,readonly=on,file=$OUTBASE/cd.iso"
        "drive_add 0 if=none,id=zip,format=raw,file=$OUT/zip.img"
        "device_add usb-bot,id=bot1,bus=$bus,port=1"
        "device_add scsi-hd,bus=bot1.0,lun=0,drive=hdd,vendor=OPENASPI,product=HDD"
        "device_add scsi-cd,bus=bot1.0,lun=1,drive=cd"
        "device_add scsi-hd,bus=bot1.0,lun=2,drive=zip,removable=on,vendor=IOMEGA,product=ZIP-100"
        "qom-set /machine/peripheral/bot1 attached true"
        "drive_add 0 if=none,id=stick,format=raw,file=$OUT/stick.img"
        "device_add usb-storage,id=stick2,bus=$bus,port=2,drive=stick")
    set +e
    { sleep 2; printf '%s\n' "${plug[@]}"; sleep "${TIMEOUT:-120}"; } |
    timeout "${TIMEOUT:-120}" qemu-system-i386 \
        -machine pc -m 32 -display none -vga std -monitor stdio \
        -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
        -device "$hc,id=usbhc" \
        -serial file:"$OUT/serial.log" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/monitor.log" 2>&1
    rc=$?
    set -e
    log=$(tr -d '\r\0' < "$OUT/serial.log")
    ok=1
    [ "$rc" = 1 ] || ok=0
    for t in 'MATRIX CD read by ASPICDA' 'MATRIX HDD read by ASPIDSK' \
             'MATRIX STICK read by ASPIDSK' 'MATRIX ZIP read by ASPIFDD' 'MATRIX DONE'; do
        [ "$(grep -c "$t" <<<"$log")" = 1 ] || ok=0
    done
    for img in "hdd.img@@32256" "stick.img@@32256" "zip.img"; do
        rm -f "$OUT/got.bin"
        mcopy -o -i "$OUT/$img" ::/BIG.BIN "$OUT/got.bin" 2>/dev/null &&
            cmp -s "$OUTBASE/BIG.BIN" "$OUT/got.bin" || ok=0
    done
    if [ "$ok" = 1 ]; then echo "ok   $hc"; else echo "FAIL $hc (rc=$rc)"; echo "$log"; fail=1; fi
done
exit $fail
