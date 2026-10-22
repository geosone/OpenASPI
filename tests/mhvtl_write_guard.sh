#!/bin/bash
# Read-only identity gate for destructive virtual scratch-media acceptance.
set -euo pipefail

test "$#" -eq 4 || { echo 'Expected tape, verification changer, drive index and scratch barcode' >&2; exit 1; }
tape=$1 changer=$2 drive=$3 barcode=$4
[[ "$drive" =~ ^[0-9]+$ ]] && [[ "$barcode" =~ ^[A-Z0-9]{6,16}$ ]] || {
    echo 'Invalid verification drive or scratch barcode' >&2; exit 1;
}

virtual_address() {
    local node=$1 expected=$2 name device
    test -c "$node" || { echo "Not a character device: $node" >&2; return 1; }
    name=$(basename "$(readlink -f "$node")")
    [[ "$name" =~ ^sg[0-9]+$ ]] || return 1
    device=$(readlink -f "/sys/class/scsi_generic/$name/device")
    case "$device" in
        /sys/devices/mhvtl_pseudo/*) ;;
        *) echo "Refusing non-mhVTL device: $node ($device)" >&2; return 1 ;;
    esac
    test "$(<"$device/type")" = "$expected" || return 1
    basename "$device"
}

tape_address=$(virtual_address "$tape" 1)
changer_address=$(virtual_address "$changer" 8)
IFS=: read -r tape_host tape_channel tape_target tape_lun <<< "$tape_address"
IFS=: read -r changer_host changer_channel changer_target changer_lun <<< "$changer_address"
test "$tape_host" = "$changer_host" || { echo 'Different mhVTL adapters' >&2; exit 1; }

# Bind the selected changer element to this exact tape address, not merely
# to another virtual drive that happens to contain the expected barcode.
awk -v tc="$tape_channel" -v tt="$tape_target" -v tl="$tape_lun" \
    -v cc="$changer_channel" -v ct="$changer_target" -v cl="$changer_lun" \
    -v wanted_slot="$((10#$drive + 1))" '
    BEGIN { RS="" }
    {
        kind=""; owner=0; slot=0;
        count=split($0, lines, "\n");
        for (i=1; i<=count; i++) {
            if (lines[i] ~ /^(Library|Drive):/) {
                split(lines[i], field, /[ \t]+/);
                kind=field[1]; id=field[2]+0;
                channel=field[4]+0; target=field[6]+0; lun=field[8]+0;
            }
            if (lines[i] ~ /^[ \t]*Library ID:/) {
                line=lines[i]; sub(/^[ \t]+/, "", line);
                split(line, field, /[ \t]+/);
                owner=field[3]+0; slot=field[5]+0;
            }
        }
        if (kind=="Library:" && channel==cc && target==ct && lun==cl) {
            library=id; libraries++;
        }
        if (kind=="Drive:" && channel==tc && target==tt && lun==tl) {
            drive_owner=owner; drive_slot=slot; drives++;
        }
    }
    END {
        if (libraries!=1 || drives!=1 || drive_owner!=library || drive_slot!=wanted_slot)
            exit 1;
    }' "${MHVTL_DEVICE_CONF:-/etc/mhvtl/device.conf}" || {
    echo 'Tape address does not match the selected mhVTL library drive' >&2; exit 1;
}

inventory=$(LC_ALL=C mtx -f "$changer" status)
loaded=$(printf '%s\n' "$inventory" | awk -v drive="$((10#$drive))" '
    $0 ~ "^Data Transfer Element " drive ":Full" {
        value=$0;
        if (value !~ /VolumeTag[[:space:]]*=/) exit 1;
        sub(/^.*VolumeTag[[:space:]]*=[[:space:]]*/, "", value);
        sub(/[[:space:]]+$/, "", value);
        print value; found++;
    }
    END { if (found!=1) exit 1; }')
test "$loaded" = "$barcode" || {
    echo "Scratch identity mismatch: expected $barcode, found $loaded" >&2; exit 1;
}
echo "Verified virtual scratch tape $barcode: $tape ($tape_address), library drive $drive"
