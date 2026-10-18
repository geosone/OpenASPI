# OpenASPI

OpenASPI is a free DOS driver suite for storage devices reached through an
ASPI manager.  The planned suite consists of `ASPIDSK.SYS`, `ASPIFDD.SYS`,
`ASPICDA.SYS`, and `ASPITAP.SYS`.  The first component under development is
`ASPITAP.SYS`, a SCSI tape driver intended to be compatible with the
documented interface of Greg Shenaut's historical `ASPITAPE.SYS`.

This repository is at the bootstrap stage.  It currently contains:

- the documented ASPITAPE compatibility ABI;
- portable builders for the initial SCSI sequential-access commands;
- fixed-format SCSI sense decoding;
- host-side unit tests for those protocol helpers;
- an 8086 DOS character-device loader skeleton built with JWasm.

The generated `ASPITAP.SYS` is deliberately a loader skeleton.  It installs
as `RMT0`, prints a prototype warning, and rejects all I/O.  Do not use it for
data.  ASPI-manager discovery and tape I/O are the next implementation stage.

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

OpenASPI command-line tools follow the shared Open386MAX UI language described
by OpenTape. Installation and removal are delegated to GDI rather than being
implemented again here.

## License

OpenASPI is licensed under the GNU General Public License version 3. See
`LICENSE`.
