#!/bin/bash
# Actual resident-code memory tests and drive-letter CD controls on a local VM.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/media-control-qemu}
make -C "$ROOT" all >/dev/null
mkdir -p "$OUT"
if [ ! -f "$ROOT/build/dos-cda/cd.iso" ]; then
    bash "$ROOT/tests/dos_cda.sh" >/dev/null
fi
cp "$ROOT/build/dos-cda/boot.img" "$ROOT/build/dos-cda/cd.iso" "$OUT/"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX \
    -Fo="$OUT/SENSE.COM" "$ROOT/tests/aspi_result.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX \
    -Fo="$OUT/INQTEST.COM" "$ROOT/tests/aspi_inquiry.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX \
    -Fo="$OUT/TOCTEST.COM" "$ROOT/tests/cda_toc.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX \
    -Fo="$OUT/PENDTEST.COM" "$ROOT/tests/aspi_pending.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX \
    -Fo="$OUT/FDDMEDIA.COM" "$ROOT/tests/media_control.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX -DTEST_CDA \
    -Fo="$OUT/CDAMEDIA.COM" "$ROOT/tests/media_control.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX \
    -Fo="$OUT/RAWTEST.COM" "$ROOT/tests/raw_media.asm"
"$ROOT/build/tools/jwasm/jwasm" -q -bin -0 -W4 -WX \
    -Fo="$OUT/F32TEST.COM" "$ROOT/tests/fat32_driver.asm"
printf '%s\r\n' '@ECHO OFF' 'SENSE > AUX' \
    'IF ERRORLEVEL 1 GOTO FAILED' 'INQTEST > AUX' \
    'IF ERRORLEVEL 1 GOTO FAILED' 'TOCTEST > AUX' \
    'IF ERRORLEVEL 1 GOTO FAILED' 'PENDTEST > AUX' \
    'IF ERRORLEVEL 1 GOTO FAILED' 'FDDMEDIA > AUX' \
    'IF ERRORLEVEL 1 GOTO FAILED' 'CDAMEDIA > AUX' \
    'IF ERRORLEVEL 1 GOTO FAILED' 'RAWTEST > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'F32TEST > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'SHSUCDX /D:ASPICDA0,R /A:AUTO > AUX' \
    'ASPICTL LOCK R: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'EJECT R: > AUX' 'IF NOT ERRORLEVEL 1 GOTO FAILED' \
    'ASPICTL EJECT R: /FORCE > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'CLOSE R: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'ASPICTL EJECT R: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'ASPICTL CLOSE R: > AUX' 'IF ERRORLEVEL 1 GOTO FAILED' \
    'ASPICTL STATUS R: > AUX' \
    'ASPICTL CLOSE R: /FORCE > AUX' 'IF NOT ERRORLEVEL 2 GOTO FAILED' \
    'TYPE R:\README.TXT > AUX' \
    'GOTO DONE' ':FAILED' 'ECHO Media controls FAILED > AUX' ':DONE' \
    'ECHO OPENASPI MEDIA CONTROL DONE > AUX' 'QEXIT' > "$OUT/AUTOEXEC.BAT"
mcopy -o -i "$OUT/boot.img" "$OUT/AUTOEXEC.BAT" "$OUT/SENSE.COM" "$OUT/INQTEST.COM" "$OUT/TOCTEST.COM" "$OUT/PENDTEST.COM" "$OUT/FDDMEDIA.COM" \
    "$OUT/CDAMEDIA.COM" "$OUT/RAWTEST.COM" "$OUT/F32TEST.COM" "$ROOT/build/dos/ASPICDA.SYS" \
    "$ROOT/build/dos/ASPICTL.EXE" "$ROOT/build/dos/EJECT.EXE" \
    "$ROOT/build/dos/CLOSE.EXE" "$ROOT/build/dos-cda/QEXIT.COM" ::/
set +e
timeout "${TIMEOUT:-60}" qemu-system-i386 -machine pc -m 32 -display none \
    -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
    -device ich9-ahci,id=ahci \
    -drive "id=cd,if=none,format=raw,media=cdrom,file=$OUT/cd.iso" \
    -device ide-cd,drive=cd,bus=ahci.0 \
    -serial file:"$OUT/serial.log" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/process.log" 2>&1
test_rc=$?
set -e
test "$test_rc" = 1 || { echo "QEMU failed/timeout: $test_rc" >&2; exit 1; }
cat "$OUT/serial.log"
! grep -Fq 'FAILED' "$OUT/serial.log"
grep -Fq 'ASPI completion/sense validation passed' "$OUT/serial.log"
grep -Fq 'INQUIRY completion/length/stale-byte validation passed' "$OUT/serial.log"
grep -Fq 'ASPICDA TOC/capacity short-reply tests passed' "$OUT/serial.log"
grep -Fq 'ASPI pending/abort completion tests passed' "$OUT/serial.log"
test "$(grep -Fc 'Media control resident tests passed' "$OUT/serial.log")" = 2
grep -Fq 'OpenASPI ASPICDA read test' "$OUT/serial.log"
grep -Fq 'LOCK R: OK (CD)' "$OUT/serial.log"
grep -Fq 'EJECT R: OK (CD)' "$OUT/serial.log"
grep -Fq 'CLOSE R: OK (CD)' "$OUT/serial.log"
grep -Fq 'Raw media session/bounds/error tests passed' "$OUT/serial.log"
grep -Fq 'FAT32 BPB/IOCTL/validation tests passed' "$OUT/serial.log"
echo 'Block/CD resident media controls and CD ASPICTL aliases passed'
