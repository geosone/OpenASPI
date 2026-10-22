#!/bin/bash
# Additional read-only gate; callers must first verify scratch identity.
set -euo pipefail
test "$#" -eq 1 || { echo 'Expected one verified virtual tape node' >&2; exit 1; }
node=$(readlink -f "$1")
name=$(basename "$node")
test -c "$node" && [[ "$name" =~ ^sg[0-9]+$ ]] || exit 1
device=$(readlink -f "/sys/class/scsi_generic/$name/device")
case "$device" in /sys/devices/mhvtl_pseudo/*) ;; *) echo 'Refusing non-mhVTL protection probe' >&2; exit 1 ;; esac
test "$(<"$device/type")" = 1 || exit 1
# MODE SENSE(6), current values, no block descriptors, four-byte header.
# Open is read-only by sg_modes default. Pipefail preserves command errors.
header=$(LC_ALL=C sg_modes --six --dbd --maxlen=4 --raw "$node" | od -An -tu1)
read -r -a bytes <<< "$header"
if test "${#bytes[@]}" != 4 || (( bytes[0] < 3 || (bytes[2] & 128) == 0 )); then
    echo 'Refusing write-protect test: MODE SENSE does not confirm write protection' >&2
    exit 1
fi
echo "Verified device write-protection bit: $node"
