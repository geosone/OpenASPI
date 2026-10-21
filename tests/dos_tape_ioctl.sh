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
    local driver_line='DEVICE=ASPITAP.SYS -w'
    local manager_line='DEVICE=MOCKASPI.SYS'
    local post_tapectl='' expected_tapectl_exit=0
    local initial_tapectl='TAPECTL' post_result='saved' device_marker=''
    local autoexec_lines=()

    case "$variant" in
        tapectl-*)
            defines=(-DBUFFERED_TEST -DBUFFER_ERROR -DBUFFER_WRITE_ERROR)
            test_source="$ROOT/tests/tape_buffered.asm"
            success_text='OpenASPI buffered tape smoke test passed'
            driver_line='DEVICE=ASPITAP.SYS -bw'
            post_tapectl='TAPECTL'
            expected_tapectl_exit=2
            case "$variant" in
                tapectl-ready-error|tapectl-ready-not-ready)
                    defines+=(-DTAPECTL_READY)
                    post_tapectl='TAPECTL /READY'
                    if test "$variant" = tapectl-ready-not-ready; then
                        defines+=(-DTAPECTL_NOT_READY)
                        expected_tapectl_exit=1
                        post_result='not-ready'
                    fi ;;
                tapectl-recovered)
                    defines+=(-DBUFFER_RECOVERY)
                    expected_tapectl_exit=0 ;;
                tapectl-device-renamed|tapectl-device-buffered-renamed|tapectl-device-renamed-ready)
                    defines+=(-DBUFFER_RENAMED)
                    driver_line='DEVICE=ASPITAP.SYS -bwtS$'
                    initial_tapectl='TAPECTL /device:nrst0$'
                    post_tapectl='TAPECTL /DEVICE:NRST0$'
                    device_marker='NRST0$ ASPI address'
                    if test "$variant" = tapectl-device-buffered-renamed; then
                        post_tapectl='TAPECTL -DeViCe:nst0$'
                        device_marker='NST0$ ASPI address'
                    elif test "$variant" = tapectl-device-renamed-ready; then
                        defines+=(-DTAPECTL_READY)
                        post_tapectl='TAPECTL /device:nrst0$ /rEaDy'
                    fi ;;
                tapectl-device-already)
                    post_tapectl='TAPECTL /ALREADY /DEVICE:NRMT0' ;;
                tapectl-device-invalid-rmt|tapectl-device-invalid-path|tapectl-device-empty|tapectl-device-duplicate)
                    post_result='usage'
                    expected_tapectl_exit=1
                    case "$variant" in
                        tapectl-device-invalid-rmt) post_tapectl='TAPECTL /DEVICE:RMT0' ;;
                        tapectl-device-invalid-path) post_tapectl='TAPECTL /DEVICE:C:\NRMT0' ;;
                        tapectl-device-empty) post_tapectl='TAPECTL /DEVICE:' ;;
                        tapectl-device-duplicate) post_tapectl='TAPECTL /READY /DEVICE:NRMT0 /DEVICE:NMT0' ;;
                    esac ;;
                tapectl-device-file)
                    post_result='nondevice'
                    expected_tapectl_exit=1
                    post_tapectl='TAPECTL /DEVICE:NRAT0' ;;
                tapectl-device-unavailable)
                    post_result='open'
                    expected_tapectl_exit=1
                    post_tapectl='TAPECTL /DEVICE:NRMT3' ;;
                tapectl-raw-short)
                    defines+=(-DRAW_WRITE_TEST -DBUFFER_SHORT_WRITE -DRAW_SHORT_WRITTEN)
                    driver_line='DEVICE=ASPITAP.SYS -w' ;;
                tapectl-final-error)
                    defines=(-DBUFFERED_TEST -DBUFFER_ERROR -DBUFFER_CLOSE_ERROR -DFINAL_ERROR -DFINAL_MARK_ERROR) ;;
                tapectl-status16-error)
                    defines+=(-DSTATUS16)
                    driver_line='DEVICE=ASPITAP.SYS -2bw' ;;
            esac
            ;;
        raw-write-*|raw-short-*|raw-eot-*)
            defines=(-DBUFFERED_TEST -DBUFFER_ERROR -DBUFFER_WRITE_ERROR -DRAW_WRITE_TEST)
            test_source="$ROOT/tests/tape_buffered.asm"
            success_text='OpenASPI buffered tape smoke test passed'
            case "$variant" in
                *-legacy) defines+=(-DNO_RESIDUAL) ;;
                *-fixed) defines+=(-DFIXED_BLOCK) ;;
                *-status16) defines+=(-DSTATUS16); driver_line='DEVICE=ASPITAP.SYS -2w' ;;
            esac
            case "$variant" in
                raw-short-*|raw-eot-*) defines+=(-DBUFFER_SHORT_WRITE) ;;
            esac
            case "$variant" in
                raw-short-*|raw-eot-ignored) defines+=(-DRAW_SHORT_WRITTEN) ;;
            esac
            case "$variant" in
                raw-eot-*) defines+=(-DRAW_EOT) ;;
            esac
            case "$variant" in
                raw-eot-ignored) defines+=(-DRAW_EOT_IGNORE) ;;
                raw-eot-hard-ignored|raw-eot-hard-ignored-status16)
                    defines+=(-DRAW_EOT_IGNORE -DRAW_EOT_HARD) ;;
                raw-eot-transport-ignored|raw-eot-transport-ignored-status16)
                    defines+=(-DRAW_EOT_IGNORE -DRAW_EOT_COMPLETION=1) ;;
                raw-eot-aborted-ignored) defines+=(-DRAW_EOT_IGNORE -DRAW_EOT_COMPLETION=2) ;;
                raw-eot-target-ignored) defines+=(-DRAW_EOT_IGNORE -DRAW_EOT_COMPLETION=3) ;;
                raw-eot-busy-ignored) defines+=(-DRAW_EOT_IGNORE -DRAW_EOT_COMPLETION=4) ;;
                raw-eot-deferred-ignored|raw-eot-deferred-ignored-status16)
                    defines+=(-DRAW_EOT_IGNORE -DRAW_EOT_COMPLETION=5) ;;
                raw-eot-deferred-descriptor-ignored)
                    defines+=(-DRAW_EOT_IGNORE -DRAW_EOT_COMPLETION=6) ;;
                raw-write-bad-residual) defines+=(-DRAW_BAD_RESIDUAL) ;;
                *-recovery) defines+=(-DBUFFER_RECOVERY -DBUFFER_RAW_RECOVERY) ;;
                *-retry) defines+=(-DBUFFER_RECOVERY -DBUFFER_RAW_RECOVERY -DRAW_RETRY) ;;
            esac
            ;;
        final-*)
            defines=(-DBUFFERED_TEST -DBUFFER_ERROR -DBUFFER_CLOSE_ERROR -DFINAL_ERROR)
            test_source="$ROOT/tests/tape_buffered.asm"
            success_text='OpenASPI buffered tape smoke test passed'
            driver_line='DEVICE=ASPITAP.SYS -bw'
            case "$variant" in
                final-marks*) defines+=(-DFINAL_MARK_ERROR) ;;
                final-space*) defines+=(-DFINAL_SPACE_ERROR) ;;
                final-rewind*) defines+=(-DFINAL_REWIND_ERROR) ;;
                final-empty*) defines+=(-DFINAL_MARK_ERROR -DFINAL_EMPTY) ;;
            esac
            case "$variant" in
                *-explicit*) defines+=(-DEXPLICIT_MARK_ERROR) ;;
            esac
            case "$variant" in
                *-empty*) defines+=(-DFINAL_EMPTY) ;;
            esac
            case "$variant" in
                *-raw) defines+=(-DFINAL_RAW); driver_line='DEVICE=ASPITAP.SYS -w' ;;
                *-legacy) defines+=(-DNO_RESIDUAL) ;;
                *-fixed) defines+=(-DFIXED_BLOCK) ;;
                *-status16) defines+=(-DSTATUS16); driver_line='DEVICE=ASPITAP.SYS -2bw' ;;
                *-immed) defines+=(-DFINAL_IMMED); driver_line='DEVICE=ASPITAP.SYS -b' ;;
            esac
            ;;
        status16|status16-fixed|status16-buffered|status16-rewind)
            defines=(-DSTATUS16)
            driver_line='DEVICE=ASPITAP.SYS -2w'
            case "$variant" in
                status16-fixed)
                    defines+=(-DFIXED_BLOCK)
                    test_source="$ROOT/tests/tape_fixed.asm"
                    success_text='OpenASPI fixed-block tape smoke test passed' ;;
                status16-buffered)
                    defines+=(-DBUFFERED_TEST)
                    driver_line='DEVICE=ASPITAP.SYS -2bwm'
                    test_source="$ROOT/tests/tape_buffered.asm"
                    success_text='OpenASPI buffered tape smoke test passed' ;;
                status16-rewind)
                    defines+=(-DREWIND_TEST)
                    driver_line='DEVICE=ASPITAP.SYS /2'
                    test_source="$ROOT/tests/tape_rewind.asm"
                    success_text='OpenASPI rewind smoke test passed' ;;
            esac
            ;;
        read-ili-mismatch*)
            defines=(-DREAD_ILI_MISMATCH=1)
            case "$variant" in
                *-short) defines=(-DREAD_ILI_MISMATCH=2) ;;
                *-sense-zero) defines=(-DREAD_ILI_MISMATCH=3) ;;
                *-filemark) defines+=(-DREAD_ILI_FILEMARK) ;;
                *-fixed) defines+=(-DREAD_ILI_FIXED) ;;
                *-status16) defines+=(-DSTATUS16); driver_line='DEVICE=ASPITAP.SYS -2w' ;;
            esac
            ;;
        read-combined-*)
            case "$variant" in
                read-combined-filemark*) defines=(-DREAD_COMBINED=1) ;;
                read-combined-ili*) defines=(-DREAD_COMBINED=2) ;;
                read-combined-all*) defines=(-DREAD_COMBINED=3) ;;
            esac
            case "$variant" in
                *-legacy) defines+=(-DNO_RESIDUAL) ;;
                *-status16) defines+=(-DSTATUS16); driver_line='DEVICE=ASPITAP.SYS -2w' ;;
            esac
            ;;
        read-stream-deferred*|read-stream-transport*|read-stream-aborted*|read-stream-target|read-stream-busy)
            defines=(-DREAD_STREAM_KEY=0 -DREAD_STREAM_REJECT -DREAD_STREAM_ERROR=31)
            case "$variant" in
                read-stream-deferred*) defines+=(-DREAD_STREAM_DEFERRED) ;;
                read-stream-transport*) defines+=(-DREAD_STREAM_TRANSPORT=1) ;;
                read-stream-aborted*) defines+=(-DREAD_STREAM_TRANSPORT=2) ;;
                read-stream-target) defines+=(-DREAD_STREAM_TRANSPORT=3) ;;
                read-stream-busy) defines=(-DREAD_STREAM_KEY=0 -DREAD_STREAM_REJECT -DREAD_STREAM_ERROR=22 -DREAD_STREAM_TRANSPORT=4) ;;
            esac
            case "$variant" in
                *-legacy) defines+=(-DNO_RESIDUAL) ;;
                *-status16) defines+=(-DSTATUS16); driver_line='DEVICE=ASPITAP.SYS -2w' ;;
            esac
            ;;
        read-stream-*)
            defines=(-DREAD_STREAM_KEY=3 -DREAD_STREAM_REJECT)
            case "$variant" in
                read-stream-hardware) defines=(-DREAD_STREAM_KEY=4 -DREAD_STREAM_REJECT) ;;
                read-stream-recovered) defines=(-DREAD_STREAM_KEY=1) ;;
                *-legacy) defines+=(-DNO_RESIDUAL) ;;
                *-status16) defines+=(-DSTATUS16); driver_line='DEVICE=ASPITAP.SYS -2w' ;;
            esac
            ;;
        read-bad-residual*)
            defines=(-DREAD_BAD_RESIDUAL)
            case "$variant" in
                *-high) defines+=(-DREAD_BAD_RESIDUAL_HIGH) ;;
                *-status16) defines+=(-DSTATUS16); driver_line='DEVICE=ASPITAP.SYS -2w' ;;
            esac
            ;;
        legacy) defines=(-DNO_RESIDUAL) ;;
        pathname) driver_line='DEVICE=ASPI-S\ASPITAP.SYS -w' ;;
        verbose) driver_line='DEVICE=ASPITAP.SYS -vw' ;;
        debug) driver_line='DEVICE=ASPITAP.SYS /D /W' ;;
        fixed-verbose)
            defines=(-DFIXED_BLOCK)
            test_source="$ROOT/tests/tape_fixed.asm"
            success_text='OpenASPI fixed-block tape smoke test passed'
            driver_line='DEVICE=ASPITAP.SYS -vw'
            ;;
        fixed-multiblock*)
            defines=(-DFIXED_BLOCK -DFIXED_MULTI_READ)
            test_source="$ROOT/tests/tape_fixed.asm"
            success_text='OpenASPI fixed-block tape smoke test passed'
            case "$variant" in
                *descriptor*) defines+=(-DFIXED_MULTI_DESCRIPTOR) ;;
            esac
            case "$variant" in
                *-legacy) defines+=(-DNO_RESIDUAL) ;;
                *-status16) defines+=(-DSTATUS16); driver_line='DEVICE=ASPITAP.SYS -2w' ;;
            esac
            ;;
        fixed-residual-*)
            defines=(-DFIXED_BLOCK)
            test_source="$ROOT/tests/tape_fixed.asm"
            success_text='OpenASPI fixed-block tape smoke test passed'
            case "$variant" in
                fixed-residual-read*) defines+=(-DFIXED_BAD_READ) ;;
                fixed-residual-write*) defines+=(-DFIXED_BAD_WRITE) ;;
            esac
            case "$variant" in
                *-aligned|*-aligned-legacy) defines+=(-DFIXED_ALIGNED_EOF) ;;
                *-mark) defines+=(-DFIXED_BAD_MARK) ;;
                *-descriptor) defines+=(-DFIXED_BAD_MARK -DFIXED_BAD_DESCRIPTOR) ;;
                *-status16) defines+=(-DSTATUS16); driver_line='DEVICE=ASPITAP.SYS -2w' ;;
            esac
            case "$variant" in
                *-legacy) defines+=(-DNO_RESIDUAL) ;;
            esac
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
            driver_line='DEVICE=ASPITAP.SYS -wvms$tS'
            if test "$variant" = options-separated; then
                driver_line='DEVICE=ASPITAP.SYS /M /S /ts /$ /W'
            fi
            ;;
        rewind-*)
            defines=(-DREWIND_TEST)
            test_source="$ROOT/tests/tape_rewind.asm"
            success_text='OpenASPI rewind smoke test passed'
            driver_line='DEVICE=ASPITAP.SYS'
            case "$variant" in
                rewind-wait) defines+=(-DWAIT_CLOSE); driver_line='DEVICE=ASPITAP.SYS -w' ;;
                rewind-read) defines+=(-DREWIND_READ) ;;
                rewind-fixed-read-invalid) defines+=(-DFIXED_BLOCK -DREWIND_BAD_FIXED_READ) ;;
                rewind-invalid) defines+=(-DREWIND_INVALID) ;;
                rewind-invalid-status16) defines+=(-DREWIND_INVALID -DSTATUS16); driver_line='DEVICE=ASPITAP.SYS -2' ;;
                rewind-write) defines+=(-DREWIND_WRITE) ;;
                rewind-write-single-invalid) defines+=(-DREWIND_BAD_WRITE=1) ;;
                rewind-write-single-invalid-status16)
                    defines+=(-DREWIND_BAD_WRITE=1 -DSTATUS16); driver_line='DEVICE=ASPITAP.SYS -2' ;;
                rewind-write-fixed-invalid) defines+=(-DREWIND_BAD_WRITE=2 -DFIXED_BLOCK) ;;
                rewind-write-fixed-invalid-after-error)
                    defines+=(-DREWIND_BAD_WRITE=2 -DFIXED_BLOCK -DREWIND_ERROR -DREWIND_BAD_WRITE_AFTER_ERROR) ;;
                rewind-write-fixed-invalid-status16)
                    defines+=(-DREWIND_BAD_WRITE=2 -DFIXED_BLOCK -DSTATUS16); driver_line='DEVICE=ASPITAP.SYS -2' ;;
                rewind-write-fixed-single-invalid)
                    defines+=(-DREWIND_BAD_WRITE=3 -DFIXED_BLOCK); driver_line='DEVICE=ASPITAP.SYS -s' ;;
                rewind-write-single-allowed)
                    defines+=(-DREWIND_WRITE -DREWIND_ONE_BYTE); driver_line='DEVICE=ASPITAP.SYS -s' ;;
                rewind-error) defines+=(-DREWIND_ERROR) ;;
                rewind-deferred) defines+=(-DREWIND_ERROR -DREWIND_DEFERRED=1) ;;
                rewind-deferred-descriptor) defines+=(-DREWIND_ERROR -DREWIND_DEFERRED=2) ;;
                rewind-timeout) defines+=(-DREWIND_ERROR -DREWIND_TIMEOUT) ;;
                rewind-midnight) defines+=(-DREWIND_MIDNIGHT) ;;
                rewind-break) defines+=(-DREWIND_BREAK -DREWIND_ERROR); driver_line='DEVICE=ASPITAP.SYS /I' ;;
                rewind-break-disabled) defines+=(-DREWIND_BREAK) ;;
                rewind-interruptible) driver_line='DEVICE=ASPITAP.SYS -i' ;;
                rewind-timeout-i) defines+=(-DREWIND_ERROR -DREWIND_TIMEOUT); driver_line='DEVICE=ASPITAP.SYS -i' ;;
                rewind-error-i) defines+=(-DREWIND_ERROR); driver_line='DEVICE=ASPITAP.SYS -i' ;;
            esac
            ;;
        buffered*)
            defines=(-DBUFFERED_TEST)
            test_source="$ROOT/tests/tape_buffered.asm"
            success_text='OpenASPI buffered tape smoke test passed'
            driver_line='DEVICE=ASPITAP.SYS -bwm'
            case "$variant" in
                buffered-legacy) defines+=(-DNO_RESIDUAL) ;;
                buffered-fixed) defines+=(-DFIXED_BLOCK) ;;
                buffered-fixed-legacy) defines+=(-DFIXED_BLOCK -DNO_RESIDUAL) ;;
                buffered-write-error) defines+=(-DBUFFER_ERROR -DBUFFER_WRITE_ERROR) ;;
                buffered-close-error) defines+=(-DBUFFER_ERROR -DBUFFER_CLOSE_ERROR) ;;
                buffered-write-error-fixed) defines+=(-DBUFFER_ERROR -DBUFFER_WRITE_ERROR -DFIXED_BLOCK) ;;
                buffered-write-error-legacy) defines+=(-DBUFFER_ERROR -DBUFFER_WRITE_ERROR -DNO_RESIDUAL) ;;
                buffered-close-error-fixed) defines+=(-DBUFFER_ERROR -DBUFFER_CLOSE_ERROR -DFIXED_BLOCK) ;;
                buffered-close-error-legacy) defines+=(-DBUFFER_ERROR -DBUFFER_CLOSE_ERROR -DNO_RESIDUAL) ;;
                buffered-write-error-status16)
                    defines+=(-DBUFFER_ERROR -DBUFFER_WRITE_ERROR -DSTATUS16)
                    driver_line='DEVICE=ASPITAP.SYS -2bwm' ;;
                buffered-close-error-status16)
                    defines+=(-DBUFFER_ERROR -DBUFFER_CLOSE_ERROR -DSTATUS16)
                    driver_line='DEVICE=ASPITAP.SYS -2bwm' ;;
                buffered-recovery) defines+=(-DBUFFER_ERROR -DBUFFER_WRITE_ERROR -DBUFFER_RECOVERY) ;;
                buffered-raw-recovery) defines+=(-DBUFFER_ERROR -DBUFFER_WRITE_ERROR -DBUFFER_RECOVERY -DBUFFER_RAW_RECOVERY) ;;
                buffered-short-write) defines+=(-DBUFFER_ERROR -DBUFFER_WRITE_ERROR -DBUFFER_SHORT_WRITE) ;;
                buffered-short-recovery) defines+=(-DBUFFER_ERROR -DBUFFER_WRITE_ERROR -DBUFFER_SHORT_WRITE -DBUFFER_RECOVERY) ;;
                buffered-renamed) defines+=(-DBUFFER_RENAMED); driver_line='DEVICE=ASPITAP.SYS -bwmvtS$' ;;
                buffered-disabled) defines=(-DBUFFER_DISABLED); driver_line='DEVICE=ASPITAP.SYS' ;;
                buffered-discard) defines+=(-DBUFFER_DISCARD) ;;
                buffered-single) defines+=(-DBUFFER_SINGLE); driver_line='DEVICE=ASPITAP.SYS -bwms' ;;
                buffered-exclusive) driver_line='DEVICE=ASPITAP.SYS -bw' ;;
                buffered-refill-*)
                    case "$variant" in
                        buffered-refill-residual*) defines+=(-DBUFFER_REFILL_ERROR=1) ;;
                        buffered-refill-transport) defines+=(-DBUFFER_REFILL_ERROR=2) ;;
                        buffered-refill-not-ready*) defines+=(-DBUFFER_REFILL_ERROR=3) ;;
                        buffered-refill-deferred) defines+=(-DBUFFER_REFILL_ERROR=4) ;;
                        buffered-refill-ili) defines+=(-DBUFFER_REFILL_ERROR=5) ;;
                        buffered-refill-fixed) defines+=(-DBUFFER_REFILL_ERROR=6 -DFIXED_BLOCK) ;;
                    esac
                    case "$variant" in
                        *-legacy) defines+=(-DNO_RESIDUAL) ;;
                        *-status16) defines+=(-DSTATUS16); driver_line='DEVICE=ASPITAP.SYS -2bwm' ;;
                    esac
                    ;;
                buffered-boundary*)
                    defines+=(-DBUFFER_BOUNDARY)
                    case "$variant" in
                        *-fixed|*-fixed-legacy) defines+=(-DFIXED_BLOCK) ;;
                        *-ili|*-ili-legacy|*-ili-status16) defines+=(-DBUFFER_BOUNDARY_ILI) ;;
                    esac
                    case "$variant" in
                        *-legacy) defines+=(-DNO_RESIDUAL) ;;
                        *-status16) defines+=(-DSTATUS16); driver_line='DEVICE=ASPITAP.SYS -2bwm' ;;
                    esac
                    ;;
            esac
            ;;
        invalid-*)
            test_source="$ROOT/tests/tape_absent.asm"
            success_text='OpenASPI missing tape headers verified'
            case "$variant" in
                invalid-target) driver_line='DEVICE=ASPITAP.SYS -t' ;;
                invalid-target-space) driver_line='DEVICE=ASPITAP.SYS -t -s' ;;
                invalid-target-digit) driver_line='DEVICE=ASPITAP.SYS -t1' ;;
                invalid-unsupported) driver_line='DEVICE=ASPITAP.SYS -z' ;;
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
        -I"$ROOT/" -Fo="$run_dir/TAPETEST.COM" "$test_source"
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
    autoexec_lines=(
        '@ECHO OFF'
        'BOOTLOG > AUX'
        'ASPISCAN > AUX'
        "$initial_tapectl > AUX"
        'TAPETEST > AUX'
    )
    if test -n "$post_tapectl"; then
        autoexec_lines+=(
            "$post_tapectl > AUX"
            "IF ERRORLEVEL $((expected_tapectl_exit + 1)) GOTO TOOLFAIL"
            "IF ERRORLEVEL $expected_tapectl_exit GOTO TOOLPASS"
            'GOTO TOOLFAIL'
            ':TOOLPASS'
            'ECHO TAPECTL EXIT CHECK PASSED > AUX'
            'GOTO TOOLDONE'
            ':TOOLFAIL'
            'ECHO TAPECTL EXIT CHECK FAILED > AUX'
            ':TOOLDONE'
        )
    fi
    autoexec_lines+=('QEXIT')
    printf '%s\r\n' "${autoexec_lines[@]}" > "$run_dir/AUTOEXEC.BAT"

    mcopy -o -i "$run_dir/boot.img" \
        "$run_dir/CONFIG.SYS" "$run_dir/AUTOEXEC.BAT" \
        "$run_dir/MOCKASPI.SYS" "$ROOT/build/dos/ASPITAP.SYS" \
        "$ROOT/build/dos/ASPISCAN.COM" "$ROOT/build/dos/TAPECTL.COM" \
        "$run_dir/TAPETEST.COM" "$run_dir/QEXIT.COM" \
        "$run_dir/BOOTLOG.COM" ::/

    if test "$variant" = tapectl-device-file; then
        mcopy -i "$run_dir/boot.img" "$ROOT/LICENSE" ::/NRAT0
    fi

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
    elif [[ "$variant" = options* || "$variant" = invalid-* || "$variant" = buffered-renamed ]]; then
        grep -q 'ASPITAP RMT0 absent' "$run_dir/serial.log"
        grep -q 'Cannot open NRMT0' "$run_dir/serial.log"
    else
        grep -q 'OpenASPI TAPECTL status passed' "$run_dir/serial.log"
    fi
    grep -q "$success_text" "$run_dir/serial.log"
    ! grep -q 'FAILED' "$run_dir/serial.log"
    if test -n "$post_tapectl"; then
        grep -q 'TAPECTL EXIT CHECK PASSED' "$run_dir/serial.log"
        if test "$post_result" = usage; then
            grep -q 'Invalid device selection' "$run_dir/serial.log"
            ! grep -q 'WARNING: saved tape write/finalization failure' "$run_dir/serial.log"
        elif test "$post_result" = nondevice; then
            grep -q 'Selected name is not a DOS character device' "$run_dir/serial.log"
            grep -q 'Cannot open NRAT0' "$run_dir/serial.log"
            mtype -i "$run_dir/boot.img" ::/NRAT0 | cmp - "$ROOT/LICENSE"
        elif test "$post_result" = open; then
            grep -q 'Cannot open NRMT3' "$run_dir/serial.log"
            ! grep -q 'Invalid device selection' "$run_dir/serial.log"
        elif test "$expected_tapectl_exit" -eq 0; then
            ! grep -q 'WARNING: saved tape write/finalization failure' "$run_dir/serial.log"
        else
            grep -q 'WARNING: saved tape write/finalization failure' "$run_dir/serial.log"
            if test "$expected_tapectl_exit" -eq 2; then
                grep -q 'OpenASPI TAPECTL saved write failure reported' "$run_dir/serial.log"
            else
                grep -q 'TEST UNIT READY failed' "$run_dir/serial.log"
            fi
        fi
        if test -n "$device_marker"; then
            grep -Fq "$device_marker" "$run_dir/serial.log"
        fi
        case "$variant" in
            tapectl-ready-error|tapectl-ready-not-ready|tapectl-device-renamed-ready)
                test "$(grep -c 'WARNING: saved tape write/finalization failure' "$run_dir/serial.log")" -eq 2
                grep -q 'flags=0202 driver-error=07 SCSI=02 sense=07' "$run_dir/serial.log"
                if test "$post_result" != not-ready; then
                    grep -q 'TEST UNIT READY completed' "$run_dir/serial.log"
                fi
                ;;
        esac
    fi
    case "$variant" in
      legacy|fixed-legacy|fixed-multiblock*-legacy|fixed-residual-*-legacy|buffered-legacy|buffered-fixed-legacy|buffered-boundary*-legacy|buffered-refill-*-legacy|buffered-write-error-legacy|buffered-close-error-legacy|final-*-legacy|raw-write-error-legacy|read-stream-*-legacy|read-combined-*-legacy)
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
        buffered-renamed)
            grep -q 'ASPITAP: names=.*ST0\$.*NST0\$' "$run_dir/serial.log"
            ;;
        *) ! grep -q 'ASPITAP: adapters=' "$run_dir/serial.log" ;;
    esac
}

if test "$#" -gt 0; then
    for variant in "$@"; do run_fixture "$variant"; done
else
run_fixture residual
run_fixture legacy
run_fixture read-bad-residual
run_fixture read-bad-residual-high
run_fixture read-bad-residual-status16
run_fixture read-stream-medium
run_fixture read-stream-hardware
run_fixture read-stream-medium-legacy
run_fixture read-stream-medium-status16
run_fixture read-stream-recovered
run_fixture read-stream-transport
run_fixture read-stream-aborted
run_fixture read-stream-target
run_fixture read-stream-busy
run_fixture read-stream-transport-legacy
run_fixture read-stream-aborted-status16
run_fixture read-stream-deferred
run_fixture read-stream-deferred-legacy
run_fixture read-stream-deferred-status16
run_fixture read-combined-filemark
run_fixture read-combined-ili
run_fixture read-combined-all
run_fixture read-combined-all-legacy
run_fixture read-combined-all-status16
run_fixture read-ili-mismatch
run_fixture read-ili-mismatch-short
run_fixture read-ili-mismatch-sense-zero
run_fixture read-ili-mismatch-filemark
run_fixture read-ili-mismatch-fixed
run_fixture read-ili-mismatch-status16
run_fixture fixed
run_fixture fixed-multiblock
run_fixture fixed-multiblock-legacy
run_fixture fixed-multiblock-descriptor
run_fixture fixed-multiblock-descriptor-legacy
run_fixture fixed-multiblock-status16
run_fixture fixed-residual-read
run_fixture fixed-residual-read-mark
run_fixture fixed-residual-read-descriptor
run_fixture fixed-residual-read-status16
run_fixture fixed-residual-write
run_fixture fixed-residual-write-status16
run_fixture fixed-residual-read-aligned
run_fixture fixed-residual-read-aligned-legacy
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
run_fixture rewind-default
run_fixture rewind-wait
run_fixture rewind-read
run_fixture rewind-fixed-read-invalid
run_fixture rewind-invalid
run_fixture rewind-invalid-status16
run_fixture rewind-write
run_fixture rewind-write-single-invalid
run_fixture rewind-write-single-invalid-status16
run_fixture rewind-write-fixed-invalid
run_fixture rewind-write-fixed-invalid-after-error
run_fixture rewind-write-fixed-invalid-status16
run_fixture rewind-write-fixed-single-invalid
run_fixture rewind-write-single-allowed
run_fixture rewind-error
run_fixture rewind-deferred
run_fixture rewind-deferred-descriptor
run_fixture rewind-timeout
run_fixture rewind-midnight
run_fixture rewind-break
run_fixture rewind-break-disabled
run_fixture rewind-interruptible
run_fixture rewind-timeout-i
run_fixture rewind-error-i
run_fixture buffered
run_fixture buffered-legacy
run_fixture buffered-fixed
run_fixture buffered-fixed-legacy
run_fixture buffered-write-error
run_fixture buffered-close-error
run_fixture buffered-write-error-fixed
run_fixture buffered-write-error-legacy
run_fixture buffered-close-error-fixed
run_fixture buffered-close-error-legacy
run_fixture buffered-write-error-status16
run_fixture buffered-close-error-status16
run_fixture buffered-recovery
run_fixture buffered-raw-recovery
run_fixture buffered-short-write
run_fixture buffered-short-recovery
run_fixture buffered-renamed
run_fixture buffered-disabled
run_fixture buffered-discard
run_fixture buffered-single
run_fixture buffered-exclusive
run_fixture buffered-boundary
run_fixture buffered-boundary-legacy
run_fixture buffered-boundary-fixed
run_fixture buffered-boundary-fixed-legacy
run_fixture buffered-boundary-status16
run_fixture buffered-boundary-ili
run_fixture buffered-boundary-ili-legacy
run_fixture buffered-boundary-ili-status16
run_fixture buffered-refill-residual
run_fixture buffered-refill-residual-status16
run_fixture buffered-refill-transport
run_fixture buffered-refill-not-ready
run_fixture buffered-refill-not-ready-legacy
run_fixture buffered-refill-deferred
run_fixture buffered-refill-ili
run_fixture buffered-refill-fixed
run_fixture status16
run_fixture status16-fixed
run_fixture status16-buffered
run_fixture status16-rewind
run_fixture final-marks
run_fixture final-marks-explicit
run_fixture final-marks-explicit-raw
run_fixture final-marks-explicit-status16
run_fixture final-marks-explicit-fixed
run_fixture final-space
run_fixture final-rewind
run_fixture final-marks-raw
run_fixture final-space-raw
run_fixture final-rewind-raw
run_fixture final-marks-legacy
run_fixture final-space-fixed
run_fixture final-rewind-status16
run_fixture final-rewind-immed
run_fixture final-empty
run_fixture final-empty-raw
run_fixture raw-write-error
run_fixture raw-write-error-legacy
run_fixture raw-write-error-fixed
run_fixture raw-write-error-status16
run_fixture raw-short-write
run_fixture raw-write-recovery
run_fixture raw-write-retry
run_fixture raw-short-recovery
run_fixture raw-eot-write
run_fixture raw-eot-ignored
run_fixture raw-eot-hard-ignored
run_fixture raw-eot-hard-ignored-status16
run_fixture raw-eot-transport-ignored
run_fixture raw-eot-aborted-ignored
run_fixture raw-eot-target-ignored
run_fixture raw-eot-busy-ignored
run_fixture raw-eot-transport-ignored-status16
run_fixture raw-eot-deferred-ignored
run_fixture raw-eot-deferred-ignored-status16
run_fixture raw-eot-deferred-descriptor-ignored
run_fixture raw-write-bad-residual
run_fixture tapectl-write-error
run_fixture tapectl-ready-error
run_fixture tapectl-ready-not-ready
run_fixture tapectl-recovered
run_fixture tapectl-raw-short
run_fixture tapectl-final-error
run_fixture tapectl-status16-error
run_fixture tapectl-device-renamed
run_fixture tapectl-device-buffered-renamed
run_fixture tapectl-device-renamed-ready
run_fixture tapectl-device-already
run_fixture tapectl-device-invalid-rmt
run_fixture tapectl-device-invalid-path
run_fixture tapectl-device-empty
run_fixture tapectl-device-duplicate
run_fixture tapectl-device-file
run_fixture tapectl-device-unavailable
fi

echo 'OpenASPI emulated-tape smoke test passed'
