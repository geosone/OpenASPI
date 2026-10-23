#!/bin/bash
# Current OpenASPI payload fits on one 1.44 MB disk per language.
# These are installation disks, without a bundled DOS or boot files.
set -euo pipefail
language=${1:?US or GR}
package=${2:?package directory}
release=${3:?release directory}
case "$language" in US|GR) ;; *) exit 2 ;; esac
mkdir -p "$release"
image="$release/openaspi-${language,,}-disk1.img"
mformat -C -f 1440 -v "OA_${language}_1" -i "$image" ::
mcopy -i "$image" "$package"/* ::/
fsck.fat -vn "$image" > "$release/disk1-fsck.txt"
python3 tests/disksets.py "$language" "$package" "$image"
echo "$image"
