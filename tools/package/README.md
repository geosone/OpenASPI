# Package generation helpers

These helpers assemble language-specific installation text and disk images.
The installer itself belongs to GDI; installation rules live in
[`installer/INSTALL.INI`](../../installer/INSTALL.INI). Use
[`make dist` or `make disksets`](../../docs/building.md) for the complete build.

## localize.py

```sh
python3 tools/package/localize.py US build/example-package
python3 tools/package/localize.py GR build/example-package
```

The destination must already exist. The helper writes `INSTALL.INI` and
`README.TXT` there as ASCII/CRLF. US retains English package prose; GR overlays
`installer/lang/GR.json`. The `Texts=` setting chooses GDI's matching UI texts.
Option labels are translated by position while installation conditions/actions
remain from the shared rule source. A changed option count needs matching
translations or generation fails.

This does not build/copy drivers, choose GUI executables or make a complete
package by itself. The Makefile selects language-specific ASPIMGR/ASPIDDG and
shared driver/CLI binaries. The two output files are written sequentially;
failed generation is not a completed release.

For the exFAT package a third argument selects `installer/exfat/` (its
INSTALL.INI, GR.json and READMEs):

```sh
python3 tools/package/localize.py GR build/example-exfat exfat
```

## mkexfat.sh

```sh
bash tools/package/mkexfat.sh US build/packages/exfat-US build/example-release/US 0.2
```

From a package directory of `make exfat-dist` it writes
`exfat-<version>-<lang>.zip` (fixed timestamps) and the nonbootable 1.44 MB
disk `exfat-<lang>-disk1.img`. It checks that the package holds exactly the
files of `[Files]` plus INSTALL.EXE/INI, all 8.3 names, runs `fsck.fat` on
the disk and compares every file on it and tests the zip.
`tests/dos_install_exfat.sh` installs both languages in QEMU, then OpenASPI
with its exFAT option over it, then the exFAT package again (refused by
`Conflicts=`).

## mkdisks.sh

Run from the repository root with a fully assembled package:

```sh
bash tools/package/mkdisks.sh US build/packages/US build/example-release/US
```

The helper creates/replaces `openaspi-us-disk1.img` (or the GR equivalent) as a
nonbootable 1.44 MB FAT12 image, copies package files, runs read-only FAT
validation and checks actual image contents against the package. It requires
mtools, `fsck.fat` and Python. There is no overflow splitter or bundled DOS.

A failed copy/validation can leave an incomplete image; success is the script's
completed result, not file existence. Generated files belong under build/release
output directories. See [installation media](../../installer/README.md) for
normal release paths and the disposable-image installation tests.
