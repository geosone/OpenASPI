#!/bin/bash
# The exFAT package of one language: exfat-<version>-<lang>.zip and a
# nonbootable 1.44 MB installation disk, from a package directory assembled
# by "make exfat-dist" (INSTALL.EXE, the localized INSTALL.INI and
# README.TXT, EXFAT.SYS, EXFATL.SYS, EXFMT.EXE, EXCHK.EXE, LICENSE.TXT).
# Run from the repository root.
set -euo pipefail
language=${1:?US or GR}
package=${2:?package directory}
release=${3:?release directory}
version=${4:?version}
case "$language" in US|GR) ;; *) exit 2 ;; esac
lang=${language,,}
mkdir -p "$release"
zip="$release/exfat-$version-$lang.zip"
image="$release/exfat-$lang-disk1.img"
# the INI must name every file it installs, and GDI's check must pass
python3 - "$package" "$zip" <<'PY'
import sys, zipfile
from pathlib import Path
package, out = Path(sys.argv[1]), Path(sys.argv[2])
ini = (package / "INSTALL.INI").read_text(encoding="ascii")
files, section = [], ""
for line in ini.splitlines():
    if line.startswith("["):
        section = line
    elif section == "[Files]" and line and not line.startswith(";"):
        files.append(line.split("|")[-1].split("=")[0])
for name in files + ["INSTALL.EXE", "INSTALL.INI"]:
    assert (package / name).is_file(), name
names = sorted(p.name for p in package.iterdir())
assert set(names) == set(files + ["INSTALL.EXE", "INSTALL.INI"]), names
for name in names:
    assert len(Path(name).stem) <= 8 and len(Path(name).suffix) <= 4, name
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for name in names:
        info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(info, (package / name).read_bytes())
PY
mformat -C -f 1440 -v "EXFAT_$language" -i "$image" ::
mcopy -i "$image" "$package"/* ::/
fsck.fat -vn "$image" > "$release/exfat-disk1-fsck.txt"
for file in "$package"/*; do
    mtype -i "$image" "::/$(basename "$file")" | cmp -s - "$file" || { echo "differs on the disk: $file"; exit 1; }
done
unzip -tq "$zip" >/dev/null
echo "$zip"
echo "$image"
