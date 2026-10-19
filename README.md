# OpenASPI

OpenASPI is a free DOS driver suite for storage devices reached through an
installed ASPI manager, such as AHCIASPI, EUSBASPI or an Adaptec-compatible
manager. It supplies device drivers, not a replacement ASPI manager or a
backup application.

## Status

The current focus is `ASPITAP.SYS`, an ASPITAPE-compatible tape driver.
`ASPIDSK.SYS` (disks), `ASPIFDD.SYS` (removable media) and `ASPICDA.SYS`
(CD/DVD) are planned components. See the [driver suite](docs/driver-suite.md)
for their responsibilities.

This is development software. The tape write path is emulator-tested but is
not yet qualified for production backups on real media.

## Build

Clone with submodules, then build and run the local checks:

```sh
git clone --recursive https://github.com/geosone/OpenASPI.git
cd OpenASPI
make check
```

Build products are written below `build/`. Requirements, tool overrides,
emulator tests and distribution packaging are described in the
[build guide](docs/building.md).

## Documentation

- [ASPITAP driver](drivers/aspitap/README.md): setup, options and tape behavior.
- [ASPITAPE compatibility](docs/aspitape-compat.md): application interface and ABI.
- [Installation](installer/README.md): shared GDI installer and package probes.
- [Architecture](docs/architecture.md) and [Windows 9x plans](docs/windows9x-storage.md).
- Tools: [ASPISCAN](tools/aspiscan/README.md),
  [TAPECTL](tools/tapectl/README.md), [WINCHECK](tools/wincheck/README.md).
- [Reference material](docs/reference-material.md) and
  [mhVTL integration](docs/qemu-mhvtl.md).

OpenTape is a separate sibling project for backup, restore and the user
interface. OpenASPI owns the drivers and low-level ASPI/SCSI support;
installation and removal reuse GDI.

## License

GNU General Public License version 3. See [LICENSE](LICENSE).
