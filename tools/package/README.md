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
