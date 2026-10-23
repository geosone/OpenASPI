# OpenASPI

OpenASPI is a free DOS driver suite for storage devices reached through an
installed ASPI manager, such as AHCIASPI, EUSBASPI or an Adaptec-compatible
manager. It supplies device drivers, not a replacement ASPI manager or a
backup application.

## Status

`ASPITAP.SYS` is an ASPITAPE-compatible tape driver.  `ASPICDA.SYS`
(CD/DVD), `ASPIDSK.SYS` (disks) and `ASPIFDD.SYS` (LS-120, ZIP and similar)
have a first version: CD/DVD reads (cooked and raw) for MSCDEX or SHSUCDX,
FAT12/FAT16 volumes read and written, plus conditional FAT32 tested with
FreeDOS 1.4. See the
[driver suite](docs/driver-suite.md) for their responsibilities and
differences.

`deps/shsucd` is SHSUCDX with digital CD audio for VSBHDA (`/A:ON`,
`/A:OFF` analog from the drive, `/A:AUTO` digital while VSBHDA is loaded)
and `CDAUDIO.COM` to switch the mode at run time; the build writes
`build/dos/SHSUCDX.COM` and `build/dos/CDAUDIO.COM`.

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
`make disksets` produces separate English (`release/US`) and German
(`release/GR`) installation floppy images, following Open386MAX's language
layout. See [installation media](installer/README.md).

## Documentation

- [ASPITAP driver](drivers/aspitap/README.md): setup, options and tape behavior.
- [ASPITAPE compatibility](docs/aspitape-compat.md): application interface and ABI.
- [Installation](installer/README.md): shared GDI installer and package probes.
- [Architecture](docs/architecture.md) and [Windows 9x plans](docs/windows9x-storage.md).
- Tools: [ASPISCAN](tools/aspiscan/README.md),
  [ASPIMGR DOS interface](tools/aspimgr/README.md),
  [ASPICTL media controls](tools/aspictl/README.md),
  [ASPIFMT formatting](tools/aspifmt/README.md),
  [ASPIDD copying and DOS GUI](tools/aspidd/README.md),
  [TAPECTL](tools/tapectl/README.md), [WINCHECK](tools/wincheck/README.md).
- [Reference material](docs/reference-material.md) and
  [mhVTL integration](docs/qemu-mhvtl.md).
- [Remaining driver work](docs/driver-status.md).
- [Future plans](docs/future-plans.md): exFAT through EXFAT.SYS with ASPIDSK/ASPIFDD.

OpenTape is a separate sibling project for backup, restore and the user
interface. OpenASPI owns the drivers and low-level ASPI/SCSI support;
installation and removal reuse GDI.

## License

GNU General Public License version 3. See [LICENSE](LICENSE).
