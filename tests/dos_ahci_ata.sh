#!/bin/bash
# An ATA cartridge drive on an AHCI port (a SyQuest EZFlyer behind an IDE to
# SATA adapter), in QEMU: an ide-cf device named "SyQuest EZFlyer 230" with
# its geometry 880/16/32 on an ICH9 AHCI port. CompactFlash answers IDENTIFY
# with 848Ah, a removable ATA device, like the cartridge drive.
#   default       SeaBIOS uses the drive as hard disk 80h: AHCIASPI must
#                 report it as BIOS-owned, ASPIFDD take DOS's C: over;
#                 DOS reads and writes it through ASPI
#   NOAHCI_BIOS=  a SeaBIOS built without AHCI (out/bios.bin of
#                 ref/seabios of ahciaspi with CONFIG_AHCI off): the drive
#                 is AHCIASPI's, ASPIFDD gives it C:
# Each run copies 100 000 bytes on C:, plain and with VERIFY ON; the image is
# checked on the host afterwards.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/dos-ahci-ata}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
DOS_DIR=${DOS_DIR:-$HOME/Iso/Dos}
SVARDOS_ZIP=${SVARDOS_ZIP:-$DOS_DIR/svardos-20250427-floppy-1.44M.zip}
NOAHCI_BIOS=${NOAHCI_BIOS:-}
[ -z "$NOAHCI_BIOS" ] || test -f "$NOAHCI_BIOS"
make -C "$ROOT" all >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"
nasm -f bin -w-reloc-abs-word -I"$AHCIASPI_DIR/src/" \
    -o "$OUT/AHCIASPI.SYS" "$AHCIASPI_DIR/src/ahciaspi.asm"
nasm -f bin -o "$OUT/QEXIT.COM" "$AHCIASPI_DIR/tools/qexit.asm"
unzip -p "$SVARDOS_ZIP" svdos-1.44M-disk-1.img > "$OUT/boot.img"
while IFS= read -r file; do
    file=${file#::/}
    case "${file^^}" in
        KERNEL.SYS|COMMAND.COM) ;;
        *) mdel -i "$OUT/boot.img" "::/$file" ;;
    esac
done < <(mdir -b -i "$OUT/boot.img" ::/)
printf '%s\r\n' 'DEVICE=AHCIASPI.SYS /V' 'DEVICE=ASPIFDD.SYS /V' \
    'LASTDRIVE=Z' 'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
printf '%s\r\n' '@ECHO OFF' 'TYPE C:\HELLO.TXT > AUX' \
    'COPY C:\HELLO.TXT C:\COPY.TXT > NUL' 'TYPE C:\COPY.TXT > AUX' \
    'COPY C:\BIG.BIN C:\PLAIN.BIN > NUL' 'VERIFY ON' \
    'COPY C:\BIG.BIN C:\VERIFY.BIN > NUL' 'VERIFY OFF' \
    'ECHO OPENASPI AHCI ATA DONE > AUX' 'QEXIT' > "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" \
    "$OUT/AHCIASPI.SYS" "$ROOT/build/dos/ASPIFDD.SYS" "$OUT/QEXIT.COM" ::/

python3 -I "$ROOT/tests/86box_syquest_cart.py" "$OUT/cart.img" 450560
printf '%s\r\n' 'Hello from the SyQuest cartridge' > "$OUT/HELLO.TXT"
head -c 100000 /dev/urandom > "$OUT/BIG.BIN"
mcopy -i "$OUT/cart.img@@16384" "$OUT/HELLO.TXT" "$OUT/BIG.BIN" ::/

bios_args=()
[ -z "$NOAHCI_BIOS" ] || bios_args=(-bios "$NOAHCI_BIOS")
printf '\xf8\x02' > "$OUT/sercon-port"           # COM2, little endian
set +e
timeout "${TIMEOUT:-90}" qemu-system-i386 \
    -machine pc -m 32 -display none -vga std "${bios_args[@]}" \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    -device ich9-ahci,id=ahci \
    -drive id=cart,if=none,format=raw,file="$OUT/cart.img" \
    -device "ide-cf,drive=cart,bus=ahci.1,model=SyQuest EZFlyer 230,cyls=880,heads=16,secs=32" \
    -serial file:"$OUT/serial.log" \
    -serial file:"$OUT/console.log" -fw_cfg name=etc/sercon-port,file="$OUT/sercon-port" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04
rc=$?
set -e
if [ "$rc" -eq 124 ]; then
    echo 'QEMU timeout' >&2
    exit 1
fi
tr -d '\r' < "$OUT/serial.log"
console=$(tr -d '\r\0' < "$OUT/console.log" | sed 's/\x1b\[[0-9;]*[A-Za-z]//g')
grep -q 'SyQuest EZFlyer 230 (direct access, ATA' <<<"$console"
if [ -z "$NOAHCI_BIOS" ]; then
    grep -q 'ATA, BIOS 80h' <<<"$console"
    grep -q 'C: (BIOS drive taken over)' <<<"$console"
else
    ! grep -q 'ATA, BIOS' <<<"$console"
    grep -q 'C: 0:.:0 ATA     SyQuest EZFlyer' <<<"$console"
fi
grep -q 'OPENASPI AHCI ATA DONE' "$OUT/serial.log"
[ "$(grep -c 'Hello from the SyQuest cartridge' "$OUT/serial.log")" -eq 2 ]
dd if="$OUT/cart.img" of="$OUT/part.img" bs=512 skip=32 status=none
fsck.fat -n "$OUT/part.img" >/dev/null
rm -f "$OUT/part.img"
cmp <(mcopy -i "$OUT/cart.img@@16384" ::/COPY.TXT -) "$OUT/HELLO.TXT"
cmp <(mcopy -i "$OUT/cart.img@@16384" ::/PLAIN.BIN -) "$OUT/BIG.BIN"
cmp <(mcopy -i "$OUT/cart.img@@16384" ::/VERIFY.BIN -) "$OUT/BIG.BIN"
echo "ATA cartridge drive on AHCI $([ -n "$NOAHCI_BIOS" ] && echo 'through AHCIASPI/ASPIFDD' || echo 'taken over from the BIOS') passed"
