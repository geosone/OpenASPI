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
    local manager_line='DEVICE=MOCKASPI.SYS'

    case "$variant" in
        legacy) defines=(-DNO_RESIDUAL) ;;
        pathname) driver_line='DEVICE=ASPI-S\ASPITAP.SYS' ;;
        verbose) driver_line='DEVICE=ASPITAP.SYS -v' ;;
        debug) driver_line='DEVICE=ASPITAP.SYS /D' ;;
        fixed-verbose)
            defines=(-DFIXED_BLOCK)
            test_source="$ROOT/tests/tape_fixed.asm"
            success_text='OpenASPI fixed-block tape smoke test passed'
            driver_line='DEVICE=ASPITAP.SYS -v'
            ;;
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
        options|options-separated)
            defines=(-DOPTION_OVERRIDES)
            test_source="$ROOT/tests/tape_options.asm"
            success_text='OpenASPI tape option smoke test passed'
            driver_line='DEVICE=ASPITAP.SYS -vms$tS'
            if test "$variant" = options-separated; then
                driver_line='DEVICE=ASPITAP.SYS /M /S /ts /$'
            fi
            ;;
        invalid-*)
            test_source="$ROOT/tests/tape_absent.asm"
            success_text='OpenASPI missing tape headers verified'
            case "$variant" in
                invalid-target) driver_line='DEVICE=ASPITAP.SYS -t' ;;
                invalid-target-space) driver_line='DEVICE=ASPITAP.SYS -t -s' ;;
                invalid-target-digit) driver_line='DEVICE=ASPITAP.SYS -t1' ;;
                invalid-unsupported) driver_line='DEVICE=ASPITAP.SYS -b' ;;
                invalid-empty) driver_line='DEVICE=ASPITAP.SYS -' ;;
            esac
            ;;
        no-manager|no-tape|no-adapters|bad-inquiry)
            test_source="$ROOT/tests/tape_absent.asm"
            success_text='OpenASPI missing tape headers verified'
            driver_line='DEVICE=ASPITAP.SYS -v'
            case "$variant" in
                no-manager) manager_line='' ;;
                no-tape) defines=(-DNO_TAPE) ;;
                no-adapters) defines=(-DNO_ADAPTERS) ;;
                bad-inquiry) defines=(-DBAD_INQUIRY) ;;
            esac
            ;;
    esac

    mkdir -p "$run_dir"
    "$JWASM" -q -bin -0 -W4 -WX "${defines[@]}" -I"$ROOT/" \
        -Fo="$run_dir/MOCKASPI.SYS" "$ROOT/tests/mockaspi.asm"
    "$JWASM" -q -bin -0 -W4 -WX "${defines[@]}" \
        -Fo="$run_dir/TAPETEST.COM" "$test_source"
    "$JWASM" -q -bin -0 -W4 -WX \
        -Fo="$run_dir/QEXIT.COM" "$ROOT/tests/qexit.asm"
    "$JWASM" -q -bin -0 -W4 -WX \
        -Fo="$run_dir/BOOTLOG.COM" "$ROOT/tests/boot_screen.asm"

    unzip -p "$SVARDOS_ZIP" svdos-1.44M-disk-1.img > "$run_dir/boot.img"
    while IFS= read -r file; do
        file=${file#::/}
        case "${file^^}" in
            KERNEL.SYS|COMMAND.COM) ;;
            *) mdel -i "$run_dir/boot.img" "::/$file" ;;
        esac
    done < <(mdir -b -i "$run_dir/boot.img" ::/)

    printf '%s\r\n' \
        "$manager_line" \
        "$driver_line" \
        'SHELL=COMMAND.COM /P' > "$run_dir/CONFIG.SYS"
    printf '%s\r\n' \
        '@ECHO OFF' \
        'BOOTLOG > AUX' \
        'ASPISCAN > AUX' \
        'TAPECTL > AUX' \
        'TAPETEST > AUX' \
        'QEXIT' > "$run_dir/AUTOEXEC.BAT"

    mcopy -o -i "$run_dir/boot.img" \
        "$run_dir/CONFIG.SYS" "$run_dir/AUTOEXEC.BAT" \
        "$run_dir/MOCKASPI.SYS" "$ROOT/build/dos/ASPITAP.SYS" \
        "$ROOT/build/dos/ASPISCAN.COM" "$ROOT/build/dos/TAPECTL.COM" \
        "$run_dir/TAPETEST.COM" "$run_dir/QEXIT.COM" \
        "$run_dir/BOOTLOG.COM" ::/

    if test "$variant" = pathname; then
        mmd -i "$run_dir/boot.img" ::/ASPI-S
        mcopy -i "$run_dir/boot.img" "$ROOT/build/dos/ASPITAP.SYS" ::/ASPI-S/
    fi

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

    tr -d '\r' < "$run_dir/serial.log" | sed '/^[[:space:]]*$/d'
    if [[ "$variant" = no-* || "$variant" = bad-inquiry ]]; then
        grep -q 'Cannot open NRMT0' "$run_dir/serial.log"
    elif [[ "$variant" = options* || "$variant" = invalid-* ]]; then
        grep -q 'ASPITAP RMT0 absent' "$run_dir/serial.log"
        grep -q 'Cannot open NRMT0' "$run_dir/serial.log"
    else
        grep -q 'OpenASPI TAPECTL status passed' "$run_dir/serial.log"
    fi
    grep -q "$success_text" "$run_dir/serial.log"
    ! grep -q 'FAILED' "$run_dir/serial.log"
    case "$variant" in
      legacy|fixed-legacy)
        grep -q 'extensions=0000' "$run_dir/serial.log"
        ;;
      no-manager|no-adapters|bad-inquiry) ;;
      *) grep -q 'extensions=0002' "$run_dir/serial.log" ;;
    esac
    case "$variant" in
        verbose|debug|fixed-verbose|options)
            grep -q 'ASPITAP: adapters=01' "$run_dir/serial.log"
            grep -q 'ASPITAP: HA 00 extensions=0002' "$run_dir/serial.log"
            grep -Fq 'manager="MOCK$.ASPI      "' "$run_dir/serial.log"
            grep -q 'ASPITAP: tape 00:00:00' "$run_dir/serial.log"
            if test "$variant" = fixed-verbose; then
                grep -q 'fixed block=0400h bytes' "$run_dir/serial.log"
            else
                grep -q 'variable blocks' "$run_dir/serial.log"
            fi
            if test "$variant" = options; then
                grep -q 'ASPITAP: names=RST0\$.*NRST0\$' "$run_dir/serial.log"
            fi
            ;;
        invalid-*)
            grep -q 'invalid or unsupported option; not installed' "$run_dir/serial.log"
            ;;
        no-manager)
            grep -q 'ASPITAP: ASPI manager unavailable or entry point invalid' "$run_dir/serial.log"
            ;;
        no-tape)
            grep -q 'ASPITAP: no sequential-access device found' "$run_dir/serial.log"
            ;;
        no-adapters)
            grep -q 'ASPITAP: manager reports no host adapters' "$run_dir/serial.log"
            ;;
        bad-inquiry)
            grep -q 'ASPITAP: host adapter inquiry failed' "$run_dir/serial.log"
            ;;
        *) ! grep -q 'ASPITAP: adapters=' "$run_dir/serial.log" ;;
    esac
}

run_fixture residual
run_fixture legacy
run_fixture fixed
run_fixture fixed-legacy
run_fixture options
run_fixture options-separated
run_fixture pathname
run_fixture invalid-target
run_fixture invalid-target-space
run_fixture invalid-target-digit
run_fixture invalid-unsupported
run_fixture invalid-empty
run_fixture verbose
run_fixture debug
run_fixture fixed-verbose
run_fixture no-manager
run_fixture no-tape
run_fixture no-adapters
run_fixture bad-inquiry

echo 'OpenASPI emulated-tape smoke test passed'
