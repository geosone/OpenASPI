# OpenASPI

OpenASPI is a free DOS driver suite for storage devices reached through an
ASPI manager.  The planned suite consists of `ASPIDSK.SYS`, `ASPIFDD.SYS`,
`ASPICDA.SYS`, and `ASPITAP.SYS`.  The first component under development is
`ASPITAP.SYS`, a SCSI tape driver intended to be compatible with the
documented interface of Greg Shenaut's historical `ASPITAPE.SYS`.

This repository is at the bootstrap stage.  It currently contains:

- byte-exact ASPI for DOS SRB definitions shared by C and assembly code;
- `ASPISCAN.COM`, a read-only host/target/LUN and SCSI-INQUIRY diagnostic;
- generic installer probes for ASPI device classes and the running DOS/Windows environment;
- `ASPITAP.SYS` initialization-time ASPI discovery for the first tape device;
- linked `RMT0`/`NRMT0` device names with read-only `mtget`, EOT-policy and
  `MTNOP` generic IOCTL support;
- the documented ASPITAPE compatibility ABI;
- portable builders for the initial SCSI sequential-access commands;
- fixed-format SCSI sense decoding;
- host-side unit tests for those protocol helpers;
- 8086 DOS binaries built with JWasm.

The generated `ASPITAP.SYS` installs `RMT0` and `NRMT0` only when it finds an
ASPI sequential-access device. Runtime data I/O and positioning are still
deliberately rejected; do not use it for backup or restore. Compatible read
handling and the remaining control operations are the next implementation
stage.

The installer runs package-defined probes rather than containing OpenASPI
hardware rules. `ASPISCAN /Q /TAPE`, `/DISK`, `/FDD` and `/CDA` preselect the
matching DOS components. `WINCHECK.COM` distinguishes DOS, Windows 3.x and
Windows 9x/ME DOS boxes; the companion `WINCHECK.EXE` is a real Win16 probe
for the future Windows setup. All automatic selections remain editable.

## Build

JWasm and JWlink are pinned Git submodules and are built locally without
writing generated files into their checkouts:

```text
build/tools/jwasm/jwasm
build/tools/jwlink/jwlink
```

Build the DOS loader skeleton and run the protocol tests:

```sh
make
make test
```

`make dos-smoke` boots the local SvarDOS fixture in QEMU, loads the sibling
AHCIASPI manager, verifies the no-tape driver path and runs `ASPISCAN` against
an emulated ATAPI CD-ROM.  It requires the private test media described in
`docs/reference-material.md` and is therefore not part of `make check`.

`make dos-tape-smoke` boots a test-only ASPI manager that exposes an emulated
tape. It verifies both device names, DOS raw-mode setup, `mtget`, EOT policy,
and `MTNOP` without touching real tape media. It uses the same SvarDOS fixture.

`make check` also compiles the portable C modules as 16-bit DOS objects with
OpenWatcom from `/opt/watcom`.

Clone with `git clone --recursive`, or initialize an existing checkout with
`git submodule update --init --recursive`. Override `JWASM`, `JWLINK`, or `CC`
on the make command line when required. Build products are written below
`build/`.

`make dist` creates an installable directory with the existing GeosOne DOS
Installer. Its component choices cover all four OpenASPI drivers; drivers not
yet present in the distribution remain unavailable to the installer.

## Planned projects

OpenASPI owns the DOS drivers and low-level ASPI/SCSI support.  OpenTape is a
separate sibling project and consumes the ASPITAPE-compatible character-device
interface; it must work with both OpenASPI's `ASPITAP.SYS` and the historical
`ASPITAPE.SYS`.

See [docs/architecture.md](docs/architecture.md) and
[docs/aspitape-compat.md](docs/aspitape-compat.md).  The complete driver split
is defined in [docs/driver-suite.md](docs/driver-suite.md), and local reference
material is catalogued in [docs/reference-material.md](docs/reference-material.md).
The planned Windows 95/98/98SE/ME miniport and ASPI-runtime architecture is
documented in [docs/windows9x-storage.md](docs/windows9x-storage.md).

OpenASPI command-line tools follow the shared Open386MAX UI language described
by OpenTape. Installation and removal are delegated to GDI rather than being
implemented again here.

## License

OpenASPI is licensed under the GNU General Public License version 3. See
`LICENSE`.
