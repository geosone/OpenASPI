#!/bin/bash
# SyQuest EZFlyer 230 (EZ135=1: EZ135) as a native ATA cartridge drive on the
# secondary IDE master, read and written through the BIOS. SQATDRVR=<path>
# also loads SyQuest's SQATDRVR.SYS (not shipped; the Windows 98 driver
# library has 1.75) with SQOPT options. ASPI=1 instead puts the drive on a
# tertiary ISA IDE channel (1E8h) the BIOS does not know and reaches it through
# AHCIASPI's ATA cartridge support and ASPIFDD; ASPI=bios keeps it on the
# BIOS channel and checks that ASPIFDD leaves it to the BIOS. EXFAT=1 (with
# ASPI=1) makes the partition exFAT (type 07h, tests/exfat_image.sh) for
# EXFAT.SYS on ASPIFDD's drive, checked with EXCHK and fsck.exfat. ASPI=1
# also runs ASPITEST, whose MODE SENSE header must have WP clear; WP=1 (with
# ASPI=1) write-protects the cartridge (wp://): WP set, the files readable,
# the image unchanged; tests/disk_protect.asm checks that writes fail with
# DOS error 00h before they reach the drive's refusal. PROT=1 (with ASPI=1)
# sets the cartridge's software write protection with ASPICTL PROTECT
# (SyQuest C0h through AHCIASPI), checks it with tests/disk_protect.asm,
# lifts it with ASPICTL UNPROTEC and writes; on the EZ135 (EZ135=1), which
# has only the tab, PROTECT must fail with ILLEGAL REQUEST. Writes are
# restricted to this disposable image; it is checked after the VM shuts down.
# Needs an 86Box with the SyQuest ATA drives of geosone/86Box lpt-zip (or
# syquest-ata on 86Box master, with TYPES="31 32").
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOX=${BOX:-$ROOT/../86Box/build-upc/src/86Box}
ROMDIR=${ROMDIR:-$HOME/.local/share/86Box/roms}
EZ135=${EZ135:-0}
EZ135CART=${EZ135CART:-$EZ135}
SQATDRVR=${SQATDRVR:-}
SQOPT=${SQOPT:-}
ASPI=${ASPI:-0}
EXFAT=${EXFAT:-0}
WP=${WP:-0}
PROT=${PROT:-0}
if { [ "$EXFAT" = 1 ] || [ "$WP" = 1 ] || [ "$PROT" = 1 ]; } && [ "$ASPI" != 1 ]; then
    echo "EXFAT=1, WP=1 and PROT=1 need ASPI=1" >&2
    exit 1
fi
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
OUT=${OUT:-$ROOT/build/86box-syquest}
# rdisk type numbers in 86box.cfg: 9/10 in geosone/86Box lpt-zip, 31/32
# (EZ135A/EZ230A) since the rdisk refactor of 86Box master: TYPES="31 32"
TYPES=${TYPES:-9 10}
if [ "$EZ135" = 1 ]; then TYPE=${TYPES% *}; else TYPE=${TYPES#* }; fi
if [ "$EZ135CART" = 1 ]; then SECTORS=262144; else SECTORS=450560; fi
test -x "$BOX"
test -d "$ROMDIR"
[ -z "$SQATDRVR" ] || test -f "$SQATDRVR"
mkdir -p "$OUT"
if [ -e "$OUT/control.sock" ]; then
    echo "Refusing to reuse an existing control socket: $OUT/control.sock" >&2
    exit 1
fi
if [ ! -f "$ROOT/build/dos-cda/boot.img" ]; then
    bash "$ROOT/tests/dos_cda.sh" >/dev/null
fi
cp "$ROOT/build/dos-cda/boot.img" "$OUT/"
sed -e "s/^rdisk_01_parameters = 7, atapi$/rdisk_01_parameters = $TYPE, ide/" \
    -e 's/^rdisk_01_image_path = ls120.img$/rdisk_01_image_path = cart.img/' \
    "$ROOT/tests/fixtures/86box-ls120.cfg" > "$OUT/86box.cfg"
grep -q "^rdisk_01_parameters = $TYPE, ide$" "$OUT/86box.cfg"
[ "$WP" = 0 ] || sed -i 's|^rdisk_01_image_path = cart.img$|rdisk_01_image_path = wp://cart.img|' "$OUT/86box.cfg"
if [ "$ASPI" = 1 ]; then
    sed -i 's/^rdisk_01_ide_channel = 1:0$/rdisk_01_ide_channel = 2:0/' "$OUT/86box.cfg"
    printf '\n[Storage controllers]\nhdc_2 = ide_ter\n' >> "$OUT/86box.cfg"
    DRIVE=C
else
    DRIVE=C
fi
rm -f "$OUT/cart.img"
python3 -I "$ROOT/tests/86box_syquest_cart.py" "$OUT/cart.img" "$SECTORS"
printf '%s\r\n' 'Hello from the SyQuest cartridge' > "$OUT/HELLO.TXT"
mcopy -i "$OUT/cart.img@@16384" "$OUT/HELLO.TXT" ::/
head -c 100000 /dev/urandom > "$OUT/BIG.BIN"
if [ "$EXFAT" = 1 ]; then
    sh "$ROOT/tests/exfat_image.sh" "$OUT/x" 64 >/dev/null
    dd if="$OUT/x/exfat.img" of="$OUT/cart.img" bs=512 seek=32 conv=notrunc status=none
    printf '\007' | dd of="$OUT/cart.img" bs=1 seek=450 conv=notrunc status=none
    HELLO='hallo'
else
    mcopy -i "$OUT/cart.img@@16384" "$OUT/BIG.BIN" ::/
    HELLO='Hello from the SyQuest cartridge'
fi
{
    if [ -n "$SQATDRVR" ]; then
        cp "$SQATDRVR" "$OUT/SQATDRVR.SYS"
        mcopy -o -i "$OUT/boot.img" "$OUT/SQATDRVR.SYS" ::/
        printf 'DEVICE=SQATDRVR.SYS %s\r\n' "$SQOPT"
    fi
    if [ "$ASPI" = 1 ]; then
        printf '%s\r\n' 'DEVICE=AHCIASPI.SYS /V /P:1E8,3EE' 'DEVICE=ASPIFDD.SYS /V'
        [ "$EXFAT" = 0 ] || printf '%s\r\n' 'DEVICE=EXFAT.SYS'
    elif [ "$ASPI" = bios ]; then
        printf '%s\r\n' 'DEVICE=AHCIASPI.SYS /V' 'DEVICE=ASPIFDD.SYS /V'
    fi
    printf '%s\r\n' 'LASTDRIVE=Z' 'SHELL=COMMAND.COM /P'
} > "$OUT/CONFIG.SYS"
COUNT=2
if [ "$WP" = 1 ]; then
    COUNT=1
    printf '%s\r\n' '@ECHO OFF' 'ASPITEST > AUX' 'PROTECT > AUX' "TYPE $DRIVE:\\HELLO.TXT > AUX" \
        "COPY $DRIVE:\\BIG.BIN NUL > NUL" \
        'ECHO OPENASPI 86BOX SYQUEST DONE > AUX' > "$OUT/AUTOEXEC.BAT"
elif [ "$EXFAT" = 1 ]; then
    printf '%s\r\n' '@ECHO OFF' "TYPE $DRIVE:\\README.TXT > AUX" \
        "COPY $DRIVE:\\README.TXT $DRIVE:\\COPY.TXT > NUL" "TYPE $DRIVE:\\COPY.TXT > AUX" \
        "COPY $DRIVE:\\ZUFALL.BIN $DRIVE:\\PLAIN.BIN > NUL" 'VERIFY ON' \
        "COPY $DRIVE:\\ZUFALL.BIN $DRIVE:\\VERIFY.BIN > NUL" 'VERIFY OFF' \
        "EXCHK $DRIVE: > AUX" \
        'ECHO OPENASPI 86BOX SYQUEST DONE > AUX' > "$OUT/AUTOEXEC.BAT"
else
    printf '%s\r\n' '@ECHO OFF' "TYPE $DRIVE:\\HELLO.TXT > AUX" \
        "COPY $DRIVE:\\HELLO.TXT $DRIVE:\\COPY.TXT > NUL" "TYPE $DRIVE:\\COPY.TXT > AUX" \
        "COPY $DRIVE:\\BIG.BIN $DRIVE:\\PLAIN.BIN > NUL" 'VERIFY ON' \
        "COPY $DRIVE:\\BIG.BIN $DRIVE:\\VERIFY.BIN > NUL" 'VERIFY OFF' \
        'ECHO OPENASPI 86BOX SYQUEST DONE > AUX' > "$OUT/AUTOEXEC.BAT"
fi
if [ "$PROT" = 1 ]; then
    if [ "$EZ135" = 1 ]; then
        sed -i "1a ASPICTL PROTECT $DRIVE: > AUX\r" "$OUT/AUTOEXEC.BAT"
    else
        sed -i "1a ASPICTL PROTECT $DRIVE: > AUX\r\nPROTECT > AUX\r\nASPICTL UNPROTEC $DRIVE: > AUX\r" \
            "$OUT/AUTOEXEC.BAT"
    fi
fi
if [ "$ASPI" = 1 ] && [ "$WP" = 0 ]; then
    # /R: REASSIGN BLOCKS too; the drive has no SyQuest super-user mode
    sed -i '1a ASPITEST /R > AUX\r' "$OUT/AUTOEXEC.BAT"
fi
mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" ::/
if [ "$ASPI" != 0 ]; then
    make -C "$ROOT" all >/dev/null
    nasm -f bin -w-reloc-abs-word -I"$AHCIASPI_DIR/src/" \
        -o "$OUT/AHCIASPI.SYS" "$AHCIASPI_DIR/src/ahciaspi.asm"
    nasm -f bin -I"$AHCIASPI_DIR/tools/" -o "$OUT/ASPITEST.COM" "$AHCIASPI_DIR/tools/aspitest.asm"
    mcopy -o -i "$OUT/boot.img" "$OUT/AHCIASPI.SYS" "$ROOT/build/dos/ASPIFDD.SYS" \
        "$OUT/ASPITEST.COM" ::/
    mcopy -o -i "$OUT/boot.img" "$ROOT/build/dos/ASPICTL.EXE" ::/
    if [ "$WP" = 1 ] || [ "$PROT" = 1 ]; then
        "$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX -DPROTECT_DRIVE=2 \
            -Fo="$OUT/PROTECT.COM" "$ROOT/tests/disk_protect.asm"
        mcopy -o -i "$OUT/boot.img" "$OUT/PROTECT.COM" ::/
    fi
    if [ "$EXFAT" = 1 ]; then
        make -C "$ROOT" build/dos/EXFAT.SYS build/dos/EXCHK.EXE >/dev/null
        mcopy -o -i "$OUT/boot.img" "$ROOT/build/dos/EXFAT.SYS" "$ROOT/build/dos/EXCHK.EXE" ::/
    fi
fi
source "$ROOT/tests/86box_run.sh"
run_86box_dos --done 'OPENASPI 86BOX SYQUEST DONE' \
    --expect "$HELLO" --count "$COUNT" --read-text "$HELLO"
if [ -n "$SQATDRVR" ]; then
    grep -q 'has been taken over' "$OUT/screen.txt"
fi
if [ "$ASPI" = bios ]; then
    grep -q 'BIOS/DOS-owned device skipped' "$OUT/screen.txt"
fi
if [ "$ASPI" = 1 ]; then
    want=00
    [ "$WP" = 0 ] || want=80
    tr -d '\r' < "$OUT/serial.log" | grep -q "mode header: .. .. $want "
fi
if [ "$PROT" = 1 ]; then
    log=$(tr -d '\r' < "$OUT/serial.log")
    if [ "$EZ135" = 1 ]; then
        grep -q "PROTECT $DRIVE: failed (status 8116, sense 05/20)" <<<"$log"
    else
        grep -q "^PROTECT $DRIVE: OK" <<<"$log"
        grep -q 'Live block write protection passed' <<<"$log"
        grep -q "^UNPROTEC $DRIVE: OK" <<<"$log"
    fi
fi
if [ "$ASPI" = 1 ] && [ "$WP" = 0 ]; then
    # refused at the super-user confirmation: invalid opcode, no F8h sent
    tr -d '\r' < "$OUT/serial.log" | grep -q 'reassign: .*sense 05/20/00'
fi
if [ "$WP" = 1 ]; then
    grep -q 'Live block write protection passed' "$OUT/serial.log"
    mcopy -i "$OUT/cart.img@@16384" ::/BIG.BIN "$OUT/BIG.CHK"
    cmp "$OUT/BIG.CHK" "$OUT/BIG.BIN"
fi
dd if="$OUT/cart.img" of="$OUT/part.img" bs=512 skip=32 status=none
if [ "$WP" = 1 ]; then
    fsck.fat -n "$OUT/part.img" >/dev/null
    [ "$(mdir -b -i "$OUT/cart.img@@16384" ::/ | wc -l)" -eq 2 ]
elif [ "$EXFAT" = 1 ]; then
    grep -q 'No errors found' "$OUT/serial.log"
    dd if="$OUT/cart.img" of="$OUT/part.img" bs=512 skip=32 count=$((64 * 2048)) status=none
    fsck.exfat -n "$OUT/part.img" >/dev/null
    loop=$(udisksctl loop-setup --no-user-interaction -r -f "$OUT/part.img" |
        sed -n 's/.* as \(\/dev\/[a-z0-9]*\)\.$/\1/p')
    mnt=$(udisksctl mount --no-user-interaction -b "$loop" | sed -n 's/.* at \(.*\)$/\1/p')
    fail=0
    for f in COPY.TXT PLAIN.BIN VERIFY.BIN; do
        want="$OUT/x/files/zufall.bin"
        [ "$f" = COPY.TXT ] && want="$OUT/x/files/README.TXT"
        cmp "$mnt/$f" "$want" || fail=1
    done
    udisksctl unmount --no-user-interaction -b "$loop" >/dev/null
    udisksctl loop-delete --no-user-interaction -b "$loop" >/dev/null
    [ "$fail" = 0 ]
else
    fsck.fat -n "$OUT/part.img" >/dev/null
    cmp <(mcopy -i "$OUT/cart.img@@16384" ::/COPY.TXT -) "$OUT/HELLO.TXT"
    cmp <(mcopy -i "$OUT/cart.img@@16384" ::/PLAIN.BIN -) "$OUT/BIG.BIN"
    cmp <(mcopy -i "$OUT/cart.img@@16384" ::/VERIFY.BIN -) "$OUT/BIG.BIN"
fi
rm -f "$OUT/part.img"
echo "SyQuest ATA cartridge test passed"
