# Building OpenASPI

## Checkout and requirements

Clone with `git clone --recursive`, or initialize an existing checkout with:

```sh
git submodule update --init --recursive
```

The build uses GNU make, a host C compiler, the pinned JWasm/JWlink
submodules and OpenWatcom. The default OpenWatcom location is `/opt/watcom`;
override `WATCOM` when necessary. JWasm and JWlink are built locally without
writing generated files into their checkouts:

```text
build/tools/jwasm/jwasm
build/tools/jwlink/jwlink
```

The DOS `ASPIMGR.EXE` and `ASPIDDG.EXE` interfaces link the pinned Open386MAX QUILIB
submodule. Its library and compatible assembler are built locally below
`build/tools/quilib-US` (or `quilib-GR`) and `build/tools/qui-jwasm`.
Use `make MAXLANG=US` or `make MAXLANG=GR` for English or German. See
[ASPIMGR](../tools/aspimgr/README.md) for the native DOS GUI test.
`ASPICTL.EXE` and its EJECT/CLOSE/LOCK/UNLOCK/STATUS aliases provide drive-letter media
controls. `bash tests/dos_media_control.sh` tests the resident block/CD
handlers and the complete CD command-line path in QEMU; `make dos-disk-smoke`
also checks removable-media locks and forced eject. See
[media controls](media-control.md).

`ASPIFMT.EXE` and `ASPIDD.EXE` are under `build/dos`; the copy GUI is
`build/US/dos/ASPIDDG.EXE` or `build/GR/dos/ASPIDDG.EXE`. Disposable-image
integration tests are `tests/dos_removable_tools.sh`, `tests/dos_diskcopy_swap.sh`,
`tests/dos_format_partition.sh`, `tests/dos_format_bad.sh`,
`tests/dos_fat32.sh` and `tests/dos_rescue.sh`. The Rescue test accepts
`MAXLANG=GR`; use a distinct `OUT` directory for each simultaneous run.

Override `JWASM`, `JWLINK` or `CC` on the make command line when required.
All build products are written below `build/`.

## Build and local checks

```sh
make
make test
make check
```

`make dos-disk-smoke` runs the real INIT path against memory-only ownership
fixtures for both block drivers; see [ownership checks](block-ownership.md).
It also runs a memory-only test of the real block request
core: rejected WRITE AND VERIFY must fall back to WRITE plus separate VERIFY
with the original 32-bit LBA, buffer and chunk count. VERIFY has no data
payload; WRITE/VERIFY failures preserve their error and stop before the next
chunk. A failed verification cannot be reported as a successful verified write.
It checks the shared removable-model policy, then boots a removable generic
USB stick alone to require `/DISK` success and `/FDD` absence. Disk writes in
these tests target disposable QEMU image files, never host block devices.

It also runs `tests/block_ioctl.asm` against both block-driver variants:
the actual strategy/interrupt handlers use a memory-only ASPI callback to
check parameter/query behavior, media changes, errors and buffer boundaries.
`tests/block_ioctl_dos.asm` checks the DOS INT 21h parameter/query calls on
all three installed image-backed drives. See [block IOCTL behavior](block-ioctl.md).

`make disksets` builds both language packages sequentially and creates
`release/US/openaspi-us-disk1.img` and `release/GR/openaspi-gr-disk1.img`.
Each current package fits on one nonbootable 1.44 MB FAT12 disk; GDI,
package pages, README and the QUILIB programs select English or German.
The build verifies actual image contents, language binaries and common
installation rules. Run `bash tests/dos_install_disks.sh` to check and install
both sets in disposable QEMU DOS images. See [installation](../installer/README.md).
GDI builds into private `build/gdi`, overridable with `GDI_OUT`.

`make dist` includes SHSUCDX.COM, CDAUDIO.COM and the upstream SHSUCD license
and readme, and validates the payload with `tests/dist_layout.sh`. To check
packaging with an already built installer without rebuilding shared GDI:

```sh
make -o gdi-install DISTDIR=build/package-check dist
```

The fallback, ordinary/removable disk, ZIP/LS-120 image read/write, detector,
CD AHCI/IDE and distribution tests passed on 2026-10-23. This is emulator
coverage, not qualification of destructive operations on physical media.

`make` builds the DOS driver, diagnostic tools, Win16 environment probe and
host test programs. `make test` runs the host protocol/SRB tests and checks
the DOS device-header layout. `make check` also builds the tools and compiles
the portable C modules and tape ABI checks as 16-bit DOS objects with
OpenWatcom. These local checks do not access tape media.
The [portable tape helper notes](../common/scsi/README.md) describe sense-buffer
boundary tests and an optional sanitizer run.

## Emulator and integration tests

- `make dos-smoke` boots the local SvarDOS fixture in QEMU, loads the sibling
  AHCIASPI manager, verifies clean rejection when no tape is present and runs
  the scanner and installer probes against an emulated ATAPI CD-ROM.
- `make dos-cda-smoke` boots SvarDOS with AHCIASPI, ASPICDA and SHSUCDX
  (from `deps/shsucd`) and reads files from a CD on AHCI and on IDE. It also
  runs `tests/cda_commands.asm`: the actual driver against memory-only ASPI
  for seek/prefetch/address/play packet and failure checks, then installed
  driver positioning at sector zero, the last sector and one past capacity.
  `tests/cda_reset.asm` resets the installed drive through AHCIASPI, and
  `tests/dos_cda_swap.sh` exchanges the CD over QMP and checks the single
  change report, the new capacity and SHSUCDX reading the new disc.
  `tests/cda_subchannel.asm` adds memory-only head-position/Q-channel tests:
  exact HSG/MSF and binary/BCD fields, aliased far buffers, guards, malformed
  replies and no-medium/unsupported-command failures.
  `tests/cda_audio_state.asm` uses a two-unit memory manager to test audio
  play/pause/resume state, saved ranges, completion, busy/error status,
  guarded outputs, failed transitions and media-loss/replacement handling.
  `tests/cda_audio_channels.asm` adds two-unit Audio Control page tests:
  four-port readback/set, change masks, mute round trips, descriptor layouts,
  opaque field preservation, failures, guarded buffers and capability flags.
  `tests/cda_upc.asm` checks MCN/BCD/CONTROL conversion and guarded failures
  with memory ASPI, then tests installed SHSUCDX UPC error forwarding in
  analog and digital modes on the catalog-less QEMU fixture, restoring its
  original mode. Positive catalog data is not yet a physical-disc test.
  A catalog-bearing CUE manifest is also generated alongside the ISO; see
  [CD catalog image and native QEMU limits](qemu-cd-catalog.md). Native QEMU
  10.2.3 lacks READ SUB-CHANNEL: those forwarding checks specifically verify
  an unsupported-command error, not a positive image-backed catalog read.
  A separate patched-86Box positive test is available through
  `bash tests/dos_86box_upc.sh` and `HIGH=1 bash tests/dos_86box_upc.sh`.
  See the same guide for the local binary, required ROMs/JEMMEX and the
  version-specific Portage backport. No system package is remerged by tests.
- `make dos-disk-smoke` boots SvarDOS with EUSBASPI, ASPIDSK and ASPIFDD and
  three USB devices (a stick, a ZIP, an LS-120 superfloppy) and reads and
  writes each of them; the images are checked afterwards (`fsck.fat`).
  `bash tests/dos_86box_ls120.sh` separately tests a native ATAPI LS-120
  through AHCIASPI and ASPIFDD, including host file comparisons. See
  [86Box LS-120](86box-ls120.md) for the 6.0 backport and test prerequisites.
- `make dos-tape-smoke` boots a test-only ASPI manager exposing an emulated
  tape. Driver scenarios and focused runs are documented in
  [ASPITAP testing](../drivers/aspitap/TESTING.md).
- `make dos-mhvtl-smoke` uses QEMU's Tekram-compatible DC-390 controller and
  `scsi-generic` passthrough to an mhVTL tape. It requires an external DOS ASPI
  manager and explicitly selected `/dev/sgN` nodes. Follow the separate
  [mhVTL setup and safety instructions](qemu-mhvtl.md).
- `make dos-mhvtl-roundtrip` overwrites an explicitly selected virtual scratch
  cartridge and verifies raw/buffered write/read, append, padding and filemarks.
  It adds mandatory
  library/drive/barcode checks; see the same integration guide before use.
- `make dos-mhvtl-write-protect` runs the protected-media probe only after a
  read-only WP-bit check. It needs manually prepared write-protected scratch
  media; its current mock/device qualification status is in the integration guide.

The boot tests require external tools and local test media described in
[reference material](reference-material.md) and the test scripts. They are
not part of `make check`. Do not substitute a physical tape device for the
virtual test target without reviewing the integration instructions.

## Distribution

`make dist` creates an installable directory under `build/dist/` using the
existing GeosOne DOS Installer. Component choices cover all four OpenASPI
drivers; drivers not present in the distribution remain unavailable to the
installer. See [installation](../installer/README.md).
