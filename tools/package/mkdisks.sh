#!/bin/bash
# Current OpenASPI payload fits on one 1.44 MB disk per language.
# These are installation disks, without a bundled DOS or boot files.
set -euo pipefail
# Run from the repository root: tests/disksets.py is relative to that root.
# The caller supplies the fully assembled, localized package; this script does
# not select English/German binaries or apply installer translations.
language=${1:?US or GR}
package=${2:?package directory}
release=${3:?release directory}
case "$language" in US|GR) ;; *) exit 2 ;; esac
mkdir -p "$release"
image="$release/openaspi-${language,,}-disk1.img"
# Create/replace this language's disk1 image, then copy package files into its
# root. There is no overflow/multi-disk splitter: a payload that no longer fits
# must fail rather than silently omit files.
mformat -C -f 1440 -v "OA_${language}_1" -i "$image" ::
mcopy -i "$image" "$package"/* ::/
# Read-only FAT validation plus package-content checks qualify the produced
# image. set -e stops on failure, but the partial image remains on disk; callers
# must use successful completion, not mere file existence, as the release gate.
fsck.fat -vn "$image" > "$release/disk1-fsck.txt"
python3 tests/disksets.py "$language" "$package" "$image"
echo "$image"
