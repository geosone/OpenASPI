#!/bin/bash
# EUSBASPI on 86Box's USB host controllers: the USB mass storage bridge
# (usb_msd.c) carries a SCSI hard disk, a CD-ROM and a ZIP 100 as LUNs 0-2
# of one USB device. ASPIDSK, ASPIFDD and ASPICDA (SHSUCDX) must read them,
# ASPIDSK and ASPIFDD must also write.
# Needs 86Box master from 2026-10-25 on (USB devices and PCI cards).
#   MACH=p3bf       Intel PIIX4 UHCI on the board (default). Other boards
#                   with USB need it enabled in their BIOS setup first (the
#                   p55t2p4 and p5a BIOS defaults leave it off).
#   USBCARD=opti_82c861 (OHCI) or via_vt83c572 (UHCI): that PCI card on a
#                   board without USB (p54tp4xe)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOX=${BOX:-$ROOT/../86Box/build-zip/src/86Box}
ROMDIR=${ROMDIR:-$HOME/.local/share/86Box/roms}
EUSBASPI_DIR=${EUSBASPI_DIR:-$ROOT/../eusbaspi}
USBCARD=${USBCARD:-}
if [ -n "$USBCARD" ]; then MACH=p54tp4xe; else MACH=${MACH:-p3bf}; fi
case $MACH in
    p3bf) CPU='pentium2_deschutes 133333333 2.0' GFX=cl_gd5446_pci ;;
    p54tp4xe) CPU='pentium_p54c 100000000 1.5' GFX=et4000ax ;;
    *)    CPU='pentium_p54c 100000000 1.5' GFX=cl_gd5446_pci ;;
esac
set -- $CPU
OUT=${OUT:-$ROOT/build/86box-usb-${USBCARD:-$MACH}}
test -x "$BOX"
test -d "$ROMDIR"
mkdir -p "$OUT"
if [ -e "$OUT/control.sock" ]; then
    echo "Refusing to reuse an existing control socket: $OUT/control.sock" >&2
    exit 1
fi
make -C "$ROOT" all >/dev/null
if [ ! -f "$ROOT/build/dos-cda/boot.img" ]; then
    bash "$ROOT/tests/dos_cda.sh" >/dev/null
fi
cp "$ROOT/build/dos-cda/boot.img" "$OUT/"
rm -f "$OUT/nvr/"* 2>/dev/null || true
nasm -f bin -w-reloc-abs-word -I"$EUSBASPI_DIR/src/" \
    -o "$OUT/EUSBASPI.SYS" "$EUSBASPI_DIR/src/eusbaspi.asm"

cat > "$OUT/86box.cfg" <<CFG
[General]
vid_renderer = qt_software
confirm_exit = 0

[Machine]
machine = $MACH
cpu_family = $1
cpu_speed = $2
cpu_multi = $3
cpu_use_dynarec = 1
mem_size = 16384
time_sync = disabled

[Video]
gfxcard = $GFX

[Input devices]
mouse_type = none

[Ports (COM & LPT)]
serial1_enabled = 1
serial1_device = automation
serial2_enabled = 0
usb_msd = usb_msd
${USBCARD:+usb_card = $USBCARD}

[Hard disks]
hdd_01_parameters = 63, 16, 65, 0, scsi
hdd_01_fn = disk.img
hdd_01_scsi_location = 0:00

[Floppy and CD-ROM drives]
fdd_01_type = 35_2hd
fdd_01_fn = boot.img
fdd_02_type = none
cdrom_01_parameters = 1, scsi
cdrom_01_scsi_location = 0:01
cdrom_01_type = 86cd
cdrom_01_image_path = cd.iso

[Other removable devices]
rdisk_01_parameters = 1, scsi
rdisk_01_scsi_location = 0:02
rdisk_01_image_path = zip.img
CFG

printf '%s\r\n' 'DEVICE=EUSBASPI.SYS /V' 'DEVICE=ASPIDSK.SYS' 'DEVICE=ASPIFDD.SYS' \
    'DEVICE=ASPICDA.SYS /D:ASPICDA0' 'LASTDRIVE=Z' 'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
printf '%s\r\n' '@ECHO OFF' 'SHSUCDX /D:ASPICDA0,R > AUX' \
    'TYPE C:\DISK.TXT > AUX' 'TYPE D:\ZIP.TXT > AUX' 'TYPE R:\README.TXT > AUX' \
    'COPY R:\BIG.BIN C:\BIG.BIN > NUL' 'COPY C:\BIG.BIN D:\BIG.BIN > NUL' \
    'COPY D:\BIG.BIN BIG2.BIN > NUL' 'IF NOT EXIST BIG2.BIN ECHO COPY FAILED > AUX' \
    'ECHO OPENASPI 86BOX USB DONE > AUX' > "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" "$OUT/EUSBASPI.SYS" \
    "$ROOT/build/dos/ASPIDSK.SYS" "$ROOT/build/dos/ASPIFDD.SYS" ::/
mdel -i "$OUT/boot.img" ::/BIG.BIN ::/BIG2.BIN 2>/dev/null || true

head -c 60000 /dev/urandom > "$OUT/BIG.BIN"
# hard disk: 63*16*65 sectors, one FAT16 partition
truncate -s 0 "$OUT/disk.img"
truncate -s $((63*16*65*512)) "$OUT/disk.img"
echo 'start=63, type=6' | sfdisk -q "$OUT/disk.img"
mkfs.fat -F16 -n USBHDD --offset 63 "$OUT/disk.img" $(( (63*16*65 - 63) / 2 )) >/dev/null
printf 'USB hard disk read by ASPIDSK\r\n' > "$OUT/DISK.TXT"
mcopy -i "$OUT/disk.img@@32256" "$OUT/DISK.TXT" ::/
# ZIP 100: superfloppy FAT16
truncate -s 0 "$OUT/zip.img"
truncate -s $((196608*512)) "$OUT/zip.img"
mkfs.fat -F16 -s4 -g64/32 -n USBZIP "$OUT/zip.img" >/dev/null
printf 'USB ZIP read by ASPIFDD\r\n' > "$OUT/ZIP.TXT"
mcopy -i "$OUT/zip.img" "$OUT/ZIP.TXT" ::/
# CD
mkdir -p "$OUT/cdroot"
printf 'USB CD read by ASPICDA\r\n' > "$OUT/cdroot/README.TXT"
cp "$OUT/BIG.BIN" "$OUT/cdroot/BIG.BIN"
rm -f "$OUT/cd.iso"
xorriso -outdev "$OUT/cd.iso" -volid USBCD86BOX -map "$OUT/cdroot" / \
    -padding 1m -end 2>/dev/null

source "$ROOT/tests/86box_run.sh"
run_86box_dos --done 'OPENASPI 86BOX USB DONE' --steps 120 \
    --expect 'USB CD read by ASPICDA' --count 1 \
    --read-text 'USB hard disk read by ASPIDSK'
log=$(tr -d '\r' < "$OUT/serial.log")
grep -q 'USB hard disk read by ASPIDSK' <<<"$log"
grep -q 'USB ZIP read by ASPIFDD' <<<"$log"
! grep -q 'FAILED' <<<"$log"
mcopy -o -i "$OUT/boot.img" ::/BIG2.BIN "$OUT/BIG2.BIN"
cmp "$OUT/BIG.BIN" "$OUT/BIG2.BIN"
mcopy -o -i "$OUT/disk.img@@32256" ::/BIG.BIN "$OUT/BIGHDD.BIN"
cmp "$OUT/BIG.BIN" "$OUT/BIGHDD.BIN"
mcopy -o -i "$OUT/zip.img" ::/BIG.BIN "$OUT/BIGZIP.BIN"
cmp "$OUT/BIG.BIN" "$OUT/BIGZIP.BIN"
fsck.fat -vn "$OUT/zip.img" > "$OUT/fsck-zip.log"
echo "86Box USB ($MACH${USBCARD:+, $USBCARD}): hard disk, ZIP and CD-ROM through EUSBASPI passed"
