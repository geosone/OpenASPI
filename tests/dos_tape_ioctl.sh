#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/dos-tape-ioctl"
DOS_DIR=${DOS_DIR:-$HOME/Iso/Dos}
SVARDOS_ZIP=${SVARDOS_ZIP:-$DOS_DIR/svardos-20250427-floppy-1.44M.zip}
JWASM=${JWASM:-$ROOT/build/tools/jwasm/jwasm}
QEMU_BIN=${QEMU_BIN:-qemu-system-i386}

make -C "$ROOT" all >/dev/null
rm -rf -- "$OUT"
mkdir -p "$OUT"

run_fixture() {
    local variant=$1 run_dir="$OUT/$1" defines=()
    local test_source="$ROOT/tests/tape_ioctl.asm"
    local success_text='OpenASPI tape IOCTL smoke test passed'
    local driver_line='DEVICE=ASPITAP.SYS'

    case "$variant" in
        legacy) defines=(-DNO_RESIDUAL) ;;
        fixed)
            defines=(-DFIXED_BLOCK)
            test_source="$ROOT/tests/tape_fixed.asm"
            success_text='OpenASPI fixed-block tape smoke test passed'
            ;;
        fixed-legacy)
            defines=(-DFIXED_BLOCK -DNO_RESIDUAL)
            test_source="$ROOT/tests/tape_fixed.asm"
            success_text='OpenASPI fixed-block tape smoke test passed'
            ;;
        options)
            defines=(-DOPTION_OVERRIDES)
            test_source="$ROOT/tests/tape_options.asm"
            success_text='OpenASPI tape option smoke test passed'
            driver_line='DEVICE=ASPITAP.SYS -m -s'
            ;;
    esac

    mkdir -p "$run_dir"
    "$JWASM" -q -bin -0 -W4 -WX "${defines[@]}" -I"$ROOT/" \
        -Fo="$run_dir/MOCKASPI.SYS" "$ROOT/tests/mockaspi.asm"
    "$JWASM" -q -bin -0 -W4 -WX "${defines[@]}" \
        -Fo="$run_dir/TAPETEST.COM" "$test_source"
    "$JWASM" -q -bin -0 -W4 -WX \
        -Fo="$run_dir/QEXIT.COM" "$ROOT/tests/qexit.asm"

    unzip -p "$SVARDOS_ZIP" svdos-1.44M-disk-1.img > "$run_dir/boot.img"
    while IFS= read -r file; do
        file=${file#::/}
        case "${file^^}" in
            KERNEL.SYS|COMMAND.COM) ;;
            *) mdel -i "$run_dir/boot.img" "::/$file" ;;
        esac
    done < <(mdir -b -i "$run_dir/boot.img" ::/)

    printf '%s\r\n' \
        'DEVICE=MOCKASPI.SYS' \
        "$driver_line" \
        'SHELL=COMMAND.COM /P' > "$run_dir/CONFIG.SYS"
    printf '%s\r\n' \
        '@ECHO OFF' \
        'ASPISCAN > AUX' \
        'TAPECTL > AUX' \
        'TAPETEST > AUX' \
        'QEXIT' > "$run_dir/AUTOEXEC.BAT"

    mcopy -o -i "$run_dir/boot.img" \
        "$run_dir/CONFIG.SYS" "$run_dir/AUTOEXEC.BAT" \
        "$run_dir/MOCKASPI.SYS" "$ROOT/build/dos/ASPITAP.SYS" \
        "$ROOT/build/dos/ASPISCAN.COM" "$ROOT/build/dos/TAPECTL.COM" \
        "$run_dir/TAPETEST.COM" "$run_dir/QEXIT.COM" ::/

    set +e
    timeout "${TIMEOUT:-60}" "$QEMU_BIN" \
        -machine pc -m 16 -display none -vga std \
        -drive if=floppy,format=raw,file="$run_dir/boot.img" -boot a \
        -serial file:"$run_dir/serial.log" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04
    rc=$?
    set -e

    if test "$rc" -eq 124; then
        echo "QEMU timeout in $variant fixture" >&2
        exit 1
    fi

    tr -d '\r' < "$run_dir/serial.log"
    grep -q 'OpenASPI TAPECTL status passed' "$run_dir/serial.log"
    grep -q "$success_text" "$run_dir/serial.log"
    ! grep -q 'FAILED' "$run_dir/serial.log"
    case "$variant" in
      legacy|fixed-legacy)
        grep -q 'extensions=0000' "$run_dir/serial.log"
        ;;
      *) grep -q 'extensions=0002' "$run_dir/serial.log" ;;
    esac
}

run_fixture residual
run_fixture legacy
run_fixture fixed
run_fixture fixed-legacy
run_fixture options

echo 'OpenASPI emulated-tape smoke test passed'
