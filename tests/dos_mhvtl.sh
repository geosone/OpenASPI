#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/dos-mhvtl"
DOS_DIR=${DOS_DIR:-$HOME/Iso/Dos}
SVARDOS_ZIP=${SVARDOS_ZIP:-$DOS_DIR/svardos-20250427-floppy-1.44M.zip}
QEMU_BIN=${QEMU_BIN:-qemu-system-i386}
QEMU_SCSI_CONTROLLER=${QEMU_SCSI_CONTROLLER:-dc390}
JWASM=${JWASM:-$ROOT/build/tools/jwasm/jwasm}

: "${ASPI_MANAGER:?Set ASPI_MANAGER to the DOS ASPI manager matching QEMU_SCSI_CONTROLLER}"
: "${MHVTL_TAPE:?Set MHVTL_TAPE to an mhVTL tape generic device such as /dev/sg6}"

scsi_address() {
    local sg_name sys_device
    sg_name=$(basename "$1")
    sys_device=$(readlink -f "/sys/class/scsi_generic/$sg_name/device") || return 1
    basename "$sys_device"
}

require_scsi_type() {
    local device=$1 expected=$2 description=$3 sg_name actual

    test -c "$device" || {
        echo "$description is not a character device: $device" >&2
        exit 1
    }
    test -r "$device" && test -w "$device" || {
        echo "$description is not readable and writable: $device" >&2
        echo "Run QEMU as root or add its user to the tape group." >&2
        exit 1
    }
    sg_name=$(basename "$device")
    actual=$(cat "/sys/class/scsi_generic/$sg_name/device/type") || exit 1
    test "$actual" = "$expected" || {
        echo "$description has SCSI type $actual, expected $expected: $device" >&2
        exit 1
    }
}

test -f "$ASPI_MANAGER" || {
    echo "DOS ASPI manager not found: $ASPI_MANAGER" >&2
    exit 1
}
test -f "$SVARDOS_ZIP" || {
    echo "SvarDOS fixture not found: $SVARDOS_ZIP" >&2
    exit 1
}
command -v "$QEMU_BIN" >/dev/null
command -v mcopy >/dev/null
command -v mdel >/dev/null
command -v mdir >/dev/null

require_scsi_type "$MHVTL_TAPE" 1 "mhVTL tape"
tape_address=$(scsi_address "$MHVTL_TAPE")
IFS=: read -r _tape_host _tape_channel tape_target tape_lun <<< "$tape_address"
guest_tape_target=${QEMU_TAPE_TARGET:-$((10#$tape_target % 8))}
guest_tape_lun=${QEMU_TAPE_LUN:-$tape_lun}

qemu_scsi=(-device "$QEMU_SCSI_CONTROLLER,id=scsi0")
hotplug=0
case "$QEMU_SCSI_CONTROLLER" in
    dc390|am53c974) hotplug=1 ;;
esac

hotplug_commands=()
if test "$hotplug" = 1; then
    hotplug_commands+=(
        "drive_add 0 if=none,id=mhvtl_tape,format=raw,file=$MHVTL_TAPE"
        "device_add scsi-generic,drive=mhvtl_tape,bus=scsi0.0,scsi-id=$guest_tape_target,lun=$guest_tape_lun"
    )
else
    qemu_scsi+=(
        -blockdev "driver=host_device,filename=$MHVTL_TAPE,node-name=mhvtl_tape"
        -device "scsi-generic,drive=mhvtl_tape,bus=scsi0.0,scsi-id=$guest_tape_target,lun=$guest_tape_lun"
    )
fi

if test -n "${MHVTL_CHANGER:-}"; then
    require_scsi_type "$MHVTL_CHANGER" 8 "mhVTL medium changer"
    changer_address=$(scsi_address "$MHVTL_CHANGER")
    IFS=: read -r _changer_host _changer_channel changer_target changer_lun <<< "$changer_address"
    guest_changer_target=${QEMU_CHANGER_TARGET:-$((10#$changer_target % 8))}
    guest_changer_lun=${QEMU_CHANGER_LUN:-$changer_lun}
    test "$guest_changer_target:$guest_changer_lun" != "$guest_tape_target:$guest_tape_lun" || {
        echo "Tape and changer resolve to the same QEMU SCSI address" >&2
        exit 1
    }
    if test "$hotplug" = 1; then
        hotplug_commands+=(
            "drive_add 0 if=none,id=mhvtl_changer,format=raw,file=$MHVTL_CHANGER"
            "device_add scsi-generic,drive=mhvtl_changer,bus=scsi0.0,scsi-id=$guest_changer_target,lun=$guest_changer_lun"
        )
    else
        qemu_scsi+=(
            -blockdev "driver=host_device,filename=$MHVTL_CHANGER,node-name=mhvtl_changer"
            -device "scsi-generic,drive=mhvtl_changer,bus=scsi0.0,scsi-id=$guest_changer_target,lun=$guest_changer_lun"
        )
    fi
fi

manager_name=$(basename "$ASPI_MANAGER")
manager_stem=${manager_name%.*}
manager_extension=${manager_name##*.}
case "$manager_name" in
    *[[:space:]]*|.*|*.*.*)
        echo "ASPI manager must have a DOS 8.3 filename: $manager_name" >&2
        exit 1
        ;;
esac
test "$manager_stem" != "$manager_name" &&
    test "${#manager_stem}" -le 8 && test "${#manager_extension}" -le 3 || {
    echo "ASPI manager must have a DOS 8.3 filename: $manager_name" >&2
    exit 1
}
manager_line=${ASPI_MANAGER_LINE:-DEVICE=$manager_name}

make -C "$ROOT" all >/dev/null
rm -rf -- "$OUT"
mkdir -p "$OUT"
"$JWASM" -q -bin -0 -W4 -WX -Fo="$OUT/QEXIT.COM" "$ROOT/tests/qexit.asm"
if test "$hotplug" = 1; then
    "$JWASM" -q -bin -0 -W4 -WX -Fo="$OUT/DELAY.SYS" "$ROOT/tests/delay.asm"
fi

unzip -p "$SVARDOS_ZIP" svdos-1.44M-disk-1.img > "$OUT/boot.img"
while IFS= read -r file; do
    file=${file#::/}
    case "${file^^}" in
        KERNEL.SYS|COMMAND.COM) ;;
        *) mdel -i "$OUT/boot.img" "::/$file" ;;
    esac
done < <(mdir -b -i "$OUT/boot.img" ::/)

if test "$hotplug" = 1; then
    printf '%s\r\n' \
        'DEVICE=DELAY.SYS' \
        "$manager_line" \
        'DEVICE=ASPITAP.SYS' \
        'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
else
    printf '%s\r\n' \
        "$manager_line" \
        'DEVICE=ASPITAP.SYS' \
        'SHELL=COMMAND.COM /P' > "$OUT/CONFIG.SYS"
fi

tapectl_command='TAPECTL > AUX'
test "${CHECK_READY:-0}" = 0 || tapectl_command='TAPECTL /READY > AUX'
printf '%s\r\n' \
    '@ECHO OFF' \
    'ASPISCAN > AUX' \
    "$tapectl_command" \
    'QEXIT' > "$OUT/AUTOEXEC.BAT"

mcopy -o -i "$OUT/boot.img" \
    "$OUT/CONFIG.SYS" "$OUT/AUTOEXEC.BAT" "$ASPI_MANAGER" \
    "$ROOT/build/dos/ASPITAP.SYS" "$ROOT/build/dos/ASPISCAN.COM" \
    "$ROOT/build/dos/TAPECTL.COM" "$OUT/QEXIT.COM" ::/
if test "$hotplug" = 1; then
    mcopy -o -i "$OUT/boot.img" "$OUT/DELAY.SYS" ::/
fi

set +e
if test "$hotplug" = 1; then
    monitor_fifo="$OUT/monitor.fifo"
    mkfifo "$monitor_fifo"
    {
        sleep "${HOTPLUG_DELAY:-3}"
        printf '%s\n' "${hotplug_commands[@]}"
    } > "$monitor_fifo" &
    monitor_writer=$!
    timeout "${TIMEOUT:-60}" "$QEMU_BIN" \
        -machine pc -m 16 -display none -vga std -monitor stdio \
        -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
        -serial file:"$OUT/serial.log" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        "${qemu_scsi[@]}" < "$monitor_fifo" >"$OUT/qemu.log" 2>&1
    rc=$?
    wait "$monitor_writer"
    rm -- "$monitor_fifo"
else
    timeout "${TIMEOUT:-60}" "$QEMU_BIN" \
        -machine pc -m 16 -display none -vga std \
        -drive if=floppy,format=raw,file="$OUT/boot.img" -boot a \
        -serial file:"$OUT/serial.log" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        "${qemu_scsi[@]}"
    rc=$?
fi
set -e

if test "$rc" -eq 124; then
    echo "QEMU timeout; see $OUT/serial.log and $OUT/qemu.log" >&2
    exit 1
fi

tr -d '\r' < "$OUT/serial.log"
grep -q ' TAPE ' "$OUT/serial.log"
grep -q 'ASPITAP RMT0 resident' "$OUT/serial.log"
grep -q 'OpenASPI TAPECTL status passed' "$OUT/serial.log"

echo "OpenASPI $QEMU_SCSI_CONTROLLER/mhVTL smoke test passed for $MHVTL_TAPE ($tape_address -> $guest_tape_target:$guest_tape_lun)"
