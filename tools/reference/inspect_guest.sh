#!/bin/bash
# Read-only, version-pinned static inspection. Never executes the input.
# Vendor bytes/disassembly are emitted locally, not stored in the repository.
set -euo pipefail

if [[ $# != 1 || ! -f $1 ]]; then
    echo "Usage: bash tools/reference/inspect_guest.sh /path/to/GUEST.EXE" >&2
    exit 2
fi

for dependency in sha256sum od tr dd ndisasm; do
    if ! command -v "$dependency" >/dev/null; then
        echo "Missing dependency: $dependency" >&2
        exit 2
    fi
done

guest_file=$1
# Hash stdin so filenames cannot affect the checksum record's escaping.
actual_hash=$(sha256sum < "$guest_file")
actual_hash=${actual_hash%% *}
case $actual_hash in
    8ca1ca07ceb37372b23175e934d6a95d30814b322ba2510ef552090320e8228e)
        guest_version=6.0 ;;
    8634b6ffccb098fd124c7d7c4e1c5a94df8c2c4c10f0fc50b7cbec1e03e71646)
        guest_version=8.5 ;;
    *)
        echo "Unsupported GUEST binary: $actual_hash" >&2
        echo "Offsets apply only to the documented GUEST 6.0/8.5 references." >&2
        exit 2 ;;
esac

# Offsets below refer to the DOS load image, not file byte zero: this pinned
# MZ reference has a 0200h-byte header. Guard expected instruction/table bytes
# before disassembly; a known filename alone is never a version check.
check_bytes()
{
    local image_offset=$1 byte_count=$2 expected=$3 actual
    actual=$(od -An -v -tx1 -j "$((0x200 + image_offset))" \
        -N "$byte_count" "$guest_file" | tr -d ' \n')
    if [[ $actual != "$expected" ]]; then
        echo "Reference byte check failed at image offset $image_offset" >&2
        exit 1
    fi
}

# Report half-open image ranges [first,end). dd extracts file bytes after
# the MZ header; ndisasm -o preserves image-relative addresses in the report.
# This is textual static inspection and does not load a DOS executable.
disassemble_range()
{
    local title=$1 first=$2 end=$3
    printf '\n%s (load-image offsets)\n' "$title"
    dd if="$guest_file" bs=1 skip="$((0x200 + first))" \
        count="$((end - first))" status=none |
        ndisasm -b 16 -o "$first" -
}

if [[ $guest_version == 6.0 ]]; then
    # DOS IOCTL input/output and generic IOCTL table entries, plus dispatch.
    check_bytes 0x41df 2 5b21
    check_bytes 0x41f1 2 5b21
    check_bytes 0x41ff 2 a508
    check_bytes 0x26a2 4 ff97d941
    # Count/signature checks and private CDB-forwarding call.
    check_bytes 0x2166 5 26837f1218
    check_bytes 0x2185 5 26813f4d49
    check_bytes 0x224b 3 e80feb
    # Unsupported PREVENT/ALLOW is converted to success and cached.
    check_bytes 0x1599 3 3d0380
    check_bytes 0x159e 5 c746fe0000
    check_bytes 0x15a7 5 26804f4802
    # The media-ID write call is followed by unconditional AX=0.
    check_bytes 0x176d 8 e80af883c40e2bc0

    printf 'Verified GUEST 6.0 SHA-256: %s\n' "$actual_hash"
    printf 'DOS request 03h and 0Ch -> 215Bh; 13h -> 08A5h.\n'
    printf 'Private packet: count=0018h, signature=494Dh, subcommand at +04h.\n'
    disassemble_range 'DOS command dispatcher' 0x25bc 0x2723
    disassemble_range 'Private packet handler' 0x215b 0x2426
    disassemble_range 'Private CDB forwarding' 0x0d5d 0x0f2a
    disassemble_range 'Generic IOCTL and software lock count' 0x08a5 0x0bd0
    disassemble_range 'START STOP UNIT helper' 0x0bd0 0x0c3d
    disassemble_range 'PREVENT/ALLOW helper' 0x1510 0x15b3
    disassemble_range 'Media-ID read/write' 0x16f4 0x1785
    disassemble_range 'ASPI bridge and transfer flags' 0x2b60 0x2de0
else
    check_bytes 0x128c 2 9f31
    check_bytes 0x129e 2 9f31
    check_bytes 0x12ac 2 8a1c
    check_bytes 0x335c 4 ff978612
    check_bytes 0x319f 10 558becb80380eb005dc3
    check_bytes 0x2072 4 201f3f20
    check_bytes 0x2b9a 4 81fe0380
    check_bytes 0x2ba0 2 33f6
    check_bytes 0x2ba6 5 26834f5802
    check_bytes 0x2db3 10 e872f683c40e8bf033c0

    printf 'Verified GUEST 8.5 SHA-256: %s\n' "$actual_hash"
    printf 'DOS request 03h and 0Ch -> 319Fh: returns 8003h (unsupported).\n'
    printf 'Generic IOCTL 13h -> 1C8Ah; no 6.0 MI packet handler on this route.\n'
    disassemble_range 'DOS command dispatcher and tables' 0x3280 0x3467
    disassemble_range 'IOCTL unsupported handler' 0x319f 0x31a9
    disassemble_range 'Generic IOCTL handler and minor table' 0x1c8a 0x207e
    disassemble_range 'START STOP UNIT helper' 0x207e 0x210b
    disassemble_range 'PREVENT/ALLOW helper' 0x2af6 0x2bb3
    disassemble_range 'Media-ID read/write' 0x2d2f 0x2e41
    disassemble_range 'CDB helper (presence does not prove DOS reachability)' 0x21ef 0x23cc
fi
