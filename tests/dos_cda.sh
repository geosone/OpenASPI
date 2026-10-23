#!/bin/bash
# Boot SvarDOS with AHCIASPI, ASPICDA and SHSUCDX (deps/shsucd): the CD on
# the AHCI controller (or IDE with BUS=ide) must be readable through
# ASPICDA's cooked READ LONG, including a file larger than one 16-sector
# chunk.  ASPICDA /V shows the audio capabilities; CDAUDIO switches the CD
# audio mode of SHSUCDX (/A:AUTO) between analog and digital.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/dos-cda"
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
DOS_DIR=${DOS_DIR:-$HOME/Iso/Dos}
SVARDOS_ZIP=${SVARDOS_ZIP:-$DOS_DIR/svardos-20250427-floppy-1.44M.zip}
BUS=${BUS:-ahci}

make -C "$ROOT" all >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT/cdroot/SUB"

"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX \
    -Fo="$OUT/CDACMD.COM" "$ROOT/tests/cda_commands.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX \
    -Fo="$OUT/CDASUB.COM" "$ROOT/tests/cda_subchannel.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX \
    -Fo="$OUT/CDASTATE.COM" "$ROOT/tests/cda_audio_state.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX \
    -Fo="$OUT/CDACHAN.COM" "$ROOT/tests/cda_audio_channels.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX \
    -Fo="$OUT/CDAUPC.COM" "$ROOT/tests/cda_upc.asm"

nasm -f bin -w-reloc-abs-word -DE9LOG -I"$AHCIASPI_DIR/src/" \
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

printf '%s\r\n' \
    'DEVICE=AHCIASPI.SYS /Q' \
    'DEVICE=ASPICDA.SYS /D:ASPICDA0 /V' \
    'LASTDRIVE=Z' \
    'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
printf '%s\r\n' \
    '@ECHO OFF' \
    'SHSUCDX /D:ASPICDA0,R /A:AUTO > AUX' \
    'CDACMD > AUX' \
    'CDASUB > AUX' \
    'CDASTATE > AUX' \
    'CDACHAN > AUX' \
    'CDAUPC > AUX' \
    'CDAUDIO > AUX' \
    'CDAUDIO ON > AUX' \
    'CDAUDIO OFF > AUX' \
    'CDAUDIO X > AUX' \
    'TYPE R:\README.TXT > AUX' \
    'COPY R:\SUB\BIG.BIN BIG.BIN > NUL' \
    'IF NOT EXIST BIG.BIN ECHO BIG MISSING > AUX' \
    'TYPE R:\SUB\TAIL.TXT > AUX' \
    'QEXIT' > "$OUT/AUTOEXEC.BAT"

mcopy -o -i "$OUT/boot.img" \
    "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" "$OUT/AHCIASPI.SYS" \
    "$ROOT/build/dos/ASPICDA.SYS" "$ROOT/build/dos/SHSUCDX.COM" \
    "$ROOT/build/dos/CDAUDIO.COM" \
    "$OUT/CDACMD.COM" \
    "$OUT/CDASUB.COM" \
    "$OUT/CDASTATE.COM" \
    "$OUT/CDACHAN.COM" \
    "$OUT/CDAUPC.COM" \
    "$OUT/QEXIT.COM" ::/

printf 'OpenASPI ASPICDA read test\r\n' > "$OUT/cdroot/README.TXT"
head -c 100000 /dev/urandom > "$OUT/cdroot/SUB/BIG.BIN"
printf 'ASPICDA TAIL PASSED\r\n' > "$OUT/cdroot/SUB/TAIL.TXT"
# A real CD track must have at least 300 sectors (four seconds). Add enough
# zero padding for catalog-aware CUE/TOC backends, not only raw ISO readers.
xorriso -outdev "$OUT/cd.iso" -volid OPENASPI \
    -map "$OUT/cdroot" / -padding 1m -end 2>/dev/null

# Preserve the catalog alongside the ISO for a CUE-capable CD backend.
# Native QEMU ide-cd reads only cd.iso, NOT this CUE or its subchannel data.
cp "$ROOT/tests/fixtures/cd-catalog.cue" "$OUT/cd.cue"

if [ "$BUS" = ide ]; then
    cd_args=(-drive "id=cd,if=none,format=raw,media=cdrom,file=$OUT/cd.iso"
             -device "ide-cd,drive=cd,bus=ide.1,model=OPENASPI CD-ROM")
else
    cd_args=(-device ich9-ahci,id=ahci
             -drive "id=cd,if=none,format=raw,media=cdrom,file=$OUT/cd.iso"
             -device "ide-cd,drive=cd,bus=ahci.0,model=OPENASPI CD-ROM")
fi

printf '\xf8\x02' > "$OUT/sercon-port"           # COM2, little endian
set +e
timeout "${TIMEOUT:-60}" qemu-system-i386 \
    -machine pc -m 32 -display none -vga std \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    "${cd_args[@]}" \
    -debugcon file:"$OUT/debug.log" -serial file:"$OUT/serial.log" \
    -serial file:"$OUT/console.log" -fw_cfg name=etc/sercon-port,file="$OUT/sercon-port" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04
rc=$?
set -e

if [ "$rc" -eq 124 ]; then
    echo 'QEMU timeout' >&2
    exit 1
fi

# BIG.BIN copied to the floppy must equal the file on the CD
mcopy -o -i "$OUT/boot.img" ::/BIG.BIN "$OUT/BIG.BIN"
cmp "$OUT/BIG.BIN" "$OUT/cdroot/SUB/BIG.BIN"

tr -d '\r' < "$OUT/serial.log"
grep -q 'OpenASPI ASPICDA read test' "$OUT/serial.log"
grep -q 'ASPICDA TAIL PASSED' "$OUT/serial.log"
grep -q 'ASPICDA seek/prefetch/address/play tests passed' "$OUT/serial.log"
grep -q 'ASPICDA installed seek/prefetch boundary tests passed' "$OUT/serial.log"
grep -q 'ASPICDA head/Q-channel packet/error/guard tests passed' "$OUT/serial.log"
grep -q 'ASPICDA per-unit audio state/busy/failure tests passed' "$OUT/serial.log"
grep -q 'ASPICDA audio channels/masks/preservation/error tests passed' "$OUT/serial.log"
grep -q 'ASPICDA UPC/MCVAL/BCD/error/guard tests passed' "$OUT/serial.log"
grep -q 'SHSUCDX UPC forwarding in analog/digital modes passed' "$OUT/serial.log"
! grep -q 'BIG MISSING' "$OUT/serial.log"

# QEMU's drive reports Audio Play but no CD-DA in MODE SENSE page 2Ah
# (the screen, CONFIG.SYS output included, goes to COM2 through SeaBIOS)
grep -a -q 'DVD-ROM.*(analog audio, no digital audio)' "$OUT/console.log"
log=$(tr -d '\r' < "$OUT/serial.log")
# AUTO without a player: analog; ON: digital; OFF: analog
grep -A2 'CD audio mode: AUTO' <<<"$log" | grep -q 'PLAY goes to: the drive'
grep -A2 'CD audio mode: ON' <<<"$log" | grep -q 'PLAY goes to: the player'
grep -A2 'CD audio mode: OFF' <<<"$log" | grep -q 'PLAY goes to: the drive'
grep -q 'CDAUDIO \[ON | OFF | AUTO\]' <<<"$log"

echo "OpenASPI ASPICDA read test ($BUS) passed"
