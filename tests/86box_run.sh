# Shared isolated VM launcher. Caller provides ROOT, OUT, BOX and ROMDIR;
# arguments are passed to the DOS automation probe. Only owned PIDs are stopped.
run_86box_dos()
{
    test_xvfb_pid=
    test_vm_pid=
    cleanup_86box_test()
    {
        if [ -n "$test_vm_pid" ]; then
            kill "$test_vm_pid" 2>/dev/null || true
            wait "$test_vm_pid" 2>/dev/null || true
        fi
        if [ -n "$test_xvfb_pid" ]; then
            kill "$test_xvfb_pid" 2>/dev/null || true
            wait "$test_xvfb_pid" 2>/dev/null || true
        fi
    }
    trap cleanup_86box_test EXIT
    : > "$OUT/display"
    Xvfb -displayfd 3 -screen 0 1024x768x24 -nolisten tcp \
        3>"$OUT/display" >"$OUT/xvfb.log" 2>&1 &
    test_xvfb_pid=$!
    for ((test_attempt=0; test_attempt<100; test_attempt++)); do
        [ -s "$OUT/display" ] && break
        kill -0 "$test_xvfb_pid"
        sleep 0.1
    done
    read -r test_display_number < "$OUT/display"
    test_control_flags=(--automation "unix:$OUT/control.sock" --automation-hold)
    test_stdout="$OUT/process.log"
    if [ "${LEGACY86BOX:-0}" = 1 ]; then
        test_control_flags=()
        test_stdout="$OUT/serial.log"
    fi
    DISPLAY=":$test_display_number" QT_QPA_PLATFORM=xcb SDL_AUDIODRIVER=dummy \
        ALSOFT_DRIVERS=null "$BOX" -P "$OUT" -R "$ROMDIR" -N -L "$OUT/emulator.log" \
        "${test_control_flags[@]}" < /dev/null >"$test_stdout" 2>"$OUT/process.log.stderr" &
    test_vm_pid=$!
    if [ "${LEGACY86BOX:-0}" = 1 ]; then
        DISPLAY=":$test_display_number" python3 "$ROOT/tests/86box_upc_probe.py" \
            "$OUT" --legacy-pid "$test_vm_pid" "$@" | tee "$OUT/result.log"
        wait "$test_vm_pid"
        test_vm_pid=
        return
    fi
    for ((test_attempt=0; test_attempt<100; test_attempt++)); do
        [ -S "$OUT/control.sock" ] && break
        kill -0 "$test_vm_pid"
        sleep 0.1
    done
    python3 "$ROOT/tests/86box_upc_probe.py" "$OUT" "$@" | tee "$OUT/result.log"
    wait "$test_vm_pid"
    test_vm_pid=
}
