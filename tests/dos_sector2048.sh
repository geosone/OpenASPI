#!/bin/bash
# ASPIDSK with 2048-byte sectors (MO media): a QEMU USB disk with 2048-byte
# logical blocks and a FAT16 filesystem with 2048 bytes per sector. DOS reads a
# file, copies one larger than a READ(10) chunk, also with VERIFY ON; the host
# then checks the image with fsck and file comparisons.
#   KERNEL=msdos (default)  MS-DOS 7.1 boot floppy
#   KERNEL=svardos          SvarDOS boot floppy (EDR-DOS kernel)
#   KERNEL=freedos          FreeDOS 1.4, whose kernel takes 512-byte sectors
#                           only: the medium must be refused, DOS stay usable
#                           and the image unchanged
#   LAYOUT=super (default)  superfloppy; LAYOUT=mbr: one partition in an MBR
#   SEC=1                   the drive is empty at boot, ASPIDSK /SEC:2048, and
#                           the medium is inserted afterwards (QEMU monitor)
#   SEC=none                the same without /SEC: DOS has 512-byte buffers,
#                           the medium must be refused and stay unchanged
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL=${KERNEL:-msdos}
LAYOUT=${LAYOUT:-super}
SEC=${SEC:-0}
SUFFIX=; NOTE=; SKIP=0
[ "$SEC" = 1 ] && SUFFIX=-sec && NOTE=', /SEC:2048, medium inserted later'
[ "$SEC" = none ] && SUFFIX=-nosec && NOTE=', medium inserted later'
# FreeDOS (512-byte buffers only) and SEC=none: the medium must be refused
REFUSE=0
[ "$KERNEL" = freedos ] && REFUSE=1
[ "$SEC" = none ] && REFUSE=1
LATE=0
[ "$SEC" != 0 ] && LATE=1
[ "$LAYOUT" = mbr ] && SKIP=16
OUT=${OUT:-$ROOT/build/dos-sector2048-$KERNEL-$LAYOUT$SUFFIX}
EUSBASPI_DIR=${EUSBASPI_DIR:-$ROOT/../eusbaspi}
AHCIASPI_DIR=${AHCIASPI_DIR:-$ROOT/../ahciaspi}
MSDOS_IMG=${MSDOS_IMG:-$ROOT/../msdosinst/out/DISK1.IMG}
FREEDOS_IMG=${FREEDOS_IMG:-$HOME/Iso/Dos/freedos/FD14LITE.img}
SVARDOS_ZIP=${SVARDOS_ZIP:-$HOME/Iso/Dos/svardos-20250427-floppy-1.44M.zip}

make -C "$ROOT" build/dos/ASPIDSK.SYS >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"
nasm -f bin -o "$OUT/QEXIT.COM" "$AHCIASPI_DIR/tools/qexit.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX \
    -Fo="$OUT/DRVPROBE.COM" "$ROOT/tests/drive_probe.asm"
nasm -f bin -w-reloc-abs-word -I"$EUSBASPI_DIR/src/" \
    -o "$OUT/EUSBASPI.SYS" "$EUSBASPI_DIR/src/eusbaspi.asm"

# the medium: 64 MB in 2048-byte sectors
truncate -s 64M "$OUT/mo.img"
if [ "$LAYOUT" = mbr ]; then
    echo 'start=16, type=6' | sfdisk -q --sector-size 2048 "$OUT/mo.img"
    mkfs.fat -F16 -S 2048 -n MO2048 -i 20482048 --offset 16 "$OUT/mo.img" \
        $(( (64 * 512 - 16) * 2 )) >/dev/null
    PART="@@$((16 * 2048))"
else
    mkfs.fat -F16 -S 2048 -n MO2048 -i 20482048 "$OUT/mo.img" >/dev/null
    PART=
fi
printf 'Read from 2048-byte sectors\r\n' > "$OUT/MO.TXT"
head -c 300000 /dev/urandom > "$OUT/BIG.BIN"
mcopy -i "$OUT/mo.img$PART" "$OUT/MO.TXT" "$OUT/BIG.BIN" ::/
sum_before=$(sha256sum < "$OUT/mo.img")

OPT=
if [ "$SEC" = 1 ]; then OPT=' /SEC:2048'; fi
HOT=
# MS-DOS boots from a floppy: the MO is C:; FreeDOS boots from a hard disk
D=C
[ "$KERNEL" = freedos ] && D=D
AUTO=('ECHO === START > AUX' "TYPE $D:\\MO.TXT > AUX" "COPY $D:\\BIG.BIN $D:\\PLAIN.BIN > AUX"
    'VERIFY ON' "COPY $D:\\BIG.BIN $D:\\VERIFY.BIN > AUX" 'VERIFY OFF'
    "ECHO Written to 2048-byte sectors>$D:\\NEW.TXT" "TYPE $D:\\NEW.TXT > AUX" "DIR $D: > AUX"
    'ECHO === END > AUX')
# refusal: only whether the medium is refused, without the critical error prompt
[ "$REFUSE" = 1 ] && AUTO=('ECHO === START > AUX' "DRVPROBE $D:\\MO.TXT > AUX"
    'ECHO === END > AUX')
if [ "$KERNEL" = freedos ]; then
    cp "$FREEDOS_IMG" "$OUT/boot.img"
    BOOTFS="$OUT/boot.img@@32256"
    printf '%s\r\n' "DEVICE=C:\\EUSBASPI.SYS$HOT" "DEVICE=C:\\ASPIDSK.SYS$OPT" 'LASTDRIVE=Z' \
        'SHELL=C:\COMMAND.COM C:\ /P=C:\FDAUTO.BAT' > "$OUT/FDCONFIG.SYS"
    { printf '@ECHO OFF\r\n'
      [ "$LATE" = 1 ] && printf '%s\r\n' 'ECHO WAIT FOR MEDIUM > AUX' 'PAUSE > NUL'
      printf '%s\r\n' "${AUTO[@]}"
      printf 'QEXIT\r\n'; } > "$OUT/FDAUTO.BAT"
    mcopy -o -i "$BOOTFS" "$OUT/FDCONFIG.SYS" "$OUT/FDAUTO.BAT" "$OUT/EUSBASPI.SYS" \
        "$ROOT/build/dos/ASPIDSK.SYS" "$OUT/QEXIT.COM" "$OUT/DRVPROBE.COM" ::/
    BOOT=(-drive if=ide,format=raw,file="$OUT/boot.img" -boot c)
else
    if [ "$KERNEL" = svardos ]; then
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
    printf '%s\r\n' 'FILES=30' 'LASTDRIVE=Z' "DEVICE=A:\\EUSBASPI.SYS$HOT" \
        "DEVICE=A:\\ASPIDSK.SYS$OPT" > "$OUT/CONFIG.SYS"
    { [ "$LATE" = 1 ] && printf '%s\r\n' 'ECHO WAIT FOR MEDIUM > AUX' 'PAUSE > NUL'
      printf '%s\r\n' "${AUTO[@]}"
      printf 'QEXIT\r\n'; } > "$OUT/AUTOEXEC.BAT"
    mcopy -o -i "$OUT/boot.img" "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" "$OUT/EUSBASPI.SYS" \
        "$ROOT/build/dos/ASPIDSK.SYS" "$OUT/QEXIT.COM" "$OUT/DRVPROBE.COM" ::/
    BOOT=(-drive if=floppy,format=raw,file="$OUT/boot.img" -boot a)
fi

DISK=(-drive "id=mo,if=none,format=raw,file=$OUT/mo.img"
    -device scsi-hd,bus=bot1.0,drive=mo,removable=on,vendor=OPENASPI,product=MO,logical_block_size=2048,physical_block_size=2048)
PAUSED=()
[ "$LATE" = 1 ] && PAUSED=(-S)

set +e
timeout "${TIMEOUT:-180}" qemu-system-i386 \
    -machine pc -m 32 -display none -vga std "${PAUSED[@]}" "${BOOT[@]}" \
    -device pci-ohci,id=usbhc \
    -device usb-bot,id=bot1,bus=usbhc.0,port=1 "${DISK[@]}" \
    -serial file:"$OUT/serial.log" -monitor unix:"$OUT/monitor.sock",server,nowait \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/process.log" 2>&1 &
qpid=$!
if [ "$LATE" = 1 ]; then
    # boot with the drive empty, insert the medium at the PAUSE
    mon() { printf '%s\n' "$1" | socat - UNIX-CONNECT:"$OUT/monitor.sock" >/dev/null; sleep 1; }
    for _ in $(seq 20); do [ -S "$OUT/monitor.sock" ] && break; sleep 0.5; done
    mon 'eject -f mo'
    mon 'cont'
    for _ in $(seq 120); do
        grep -q 'WAIT FOR MEDIUM' "$OUT/serial.log" 2>/dev/null && break
        sleep 1
    done
    mon "change mo $OUT/mo.img raw"
    mon 'sendkey ret'
fi
wait $qpid
rc=$?
set -e
tr -d '\0\r' < "$OUT/serial.log" > "$OUT/serial.txt"

fail=0
if [ "$REFUSE" = 1 ]; then
    grep -q '=== END' "$OUT/serial.txt" || fail=1
    grep -q 'PROBE REFUSED' "$OUT/serial.txt" || fail=1
    test "$(sha256sum < "$OUT/mo.img")" = "$sum_before" || fail=1
    if [ "$fail" = 0 ]; then
        echo "ASPIDSK refuses 2048-byte sectors with 512-byte DOS buffers ($KERNEL, $LAYOUT$NOTE) (qemu rc=$rc)"
        exit 0
    fi
    cat "$OUT/serial.txt"
    exit 1
fi
grep -q 'Read from 2048-byte sectors' "$OUT/serial.txt" || fail=1
grep -q 'Written to 2048-byte sectors' "$OUT/serial.txt" || fail=1
grep -q '=== END' "$OUT/serial.txt" || fail=1
if [ "$fail" = 0 ]; then
    dd if="$OUT/mo.img" of="$OUT/fs.img" bs=2048 skip=$SKIP status=none
    fsck.fat -n "$OUT/fs.img" > "$OUT/fsck.log" 2>&1 || fail=1
    for f in PLAIN.BIN VERIFY.BIN; do
        mcopy -o -i "$OUT/mo.img$PART" "::/$f" "$OUT/$f" && cmp -s "$OUT/BIG.BIN" "$OUT/$f" || fail=1
    done
    mtype -i "$OUT/mo.img$PART" ::/NEW.TXT | grep -q 'Written to 2048-byte sectors' || fail=1
fi
if [ "$fail" = 0 ]; then
    echo "ASPIDSK 2048-byte sectors ($KERNEL, $LAYOUT$NOTE) passed (qemu rc=$rc)"
else
    cat "$OUT/serial.txt"
    exit 1
fi
