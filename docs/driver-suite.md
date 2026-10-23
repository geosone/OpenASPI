# Driver suite

All four drivers use an installed DOS ASPI manager. ASPIDSK, ASPIFDD and
ASPICDA share resident transport and transient discovery helpers from
[`common/aspi`](../common/aspi/README.md); ASPITAP retains its own submission
and discovery implementation plus shared tape includes. DOS request layouts
are defined in [`devreq.inc`](../common/dos/devreq.inc).

## Device responsibilities

| | ASPIDSK | ASPIFDD | ASPICDA | ASPITAP |
| --- | --- | --- | --- | --- |
| Device type | 00h direct access | 00h, removable bit and recognized model | 05h multimedia | 01h sequential access |
| Examples | Disk, SSD, ordinary USB stick/card reader | LS-120/240, ZIP, Clik!, Jaz | CD/DVD | Tape drive |
| DOS interface | Block device | Block device | CD-ROM character device | Tape character device |
| Selection exposed to applications | One letter per accepted device/first supported volume | One letter per accepted drive, including empty drives | MSCDEX/SHSUCDX letters via `/D:name` | Raw rewind/no-rewind aliases; optional buffered aliases |
| Data unit | 512-byte sectors | 512-byte sectors | 2048-byte cooked or 2352-byte raw sectors | Variable records or qualified fixed blocks |
| Filesystem/archive owner | DOS FAT support | DOS FAT support | MSCDEX/SHSUCDX | Backup application |
| Implementation | Shared `blkdrv.inc` | Shared `blkdrv.inc`, `FDD_DRIVER` policy | Own request handlers | Own legacy handlers and native OTAP binding |

ASPIDSK and ASPIFDD use the same
[`removable.inc`](../common/aspi/removable.inc) classification as ASPISCAN.
A generic removable USB stick belongs to ASPIDSK unless its checked INQUIRY
vendor/product identifies a recognized ASPIFDD model. Matching excludes the
revision field. The two block drivers therefore make complementary selections;
CD and tape use separate peripheral types.

Classification does not establish hardware command support or exclusive access
through every BIOS/Windows alias. Manager-reported DOS ownership is checked
separately for block devices; see [block-ownership.md](block-ownership.md).

## Current behavior and limits

- [ASPIDSK](../drivers/aspidsk/README.md) exposes a superfloppy or the first
  supported primary FAT partition. It implements block I/O, checked parameter
  and track IOCTLs, software access control and verified Media-ID updates.
  FAT32 is conditional on DOS support, with a tested FreeDOS path. Multiple
  partition units, extended/GPT traversal and broad Windows qualification
  remain open.
- [ASPIFDD](../drivers/aspifdd/README.md) shares those block operations and adds
  removable-media policy, checked lock/eject and RAW1 sessions.
  [ASPIFMT](../tools/aspifmt/README.md) creates FAT filesystems and marks bad
  clusters; [ASPIDD](../tools/aspidd/README.md) copies/images media and supports
  rescue. Physical FORMAT UNIT profiles, vendor protection commands and
  GUEST-style runtime attachment remain open.
- [ASPICDA](../drivers/aspicda/README.md) implements data/raw reads, checked
  positioning, media/tray controls, TOC/subchannel/catalog queries and audio
  playback/routing. Reset is still a success-only no-op. Physical audio and
  device-specific behavior need further qualification.
- [ASPITAP](../drivers/aspitap/README.md) exposes the first tape through the
  legacy ASPITAPE ABI and the separate native OTAP query/control/record API.
  Legacy final close can add marks/rewind; native writing uses explicit
  ownership and finalization. Multiple tape units, changers, remaining native
  operations and production hardware recovery qualification remain open.

## Compatibility targets

The targets are functional coverage of Adaptec ASPIDISK, Adaptec ASPICD and
both MKELS120 and Iomega GUEST's ZIP device functions. ZIP/LS-120 special
functions belong behind ASPIFDD's common service; tools reuse that service
rather than implementing another controller driver. Runtime EXE/SYS loading
mechanics are a separate requirement from device functionality.

Source comments describe implemented checks, not complete compatibility.
The [remaining-work ledger](driver-status.md) separates tested paths from open
work. Detailed comparisons are in [ASPICD compatibility](aspicd-compat.md),
[ASPIDISK/MKELS120/GUEST compatibility](aspidisk-compat.md),
[removable-device research](aspifdd-reference.md) and
[ASPITAPE compatibility](aspitape-compat.md).

For implementation flow, state ownership and corresponding tests, start with
the [source guide](source-guide.md). Windows 3.x/9x providers and integration
are separate from these DOS drivers; see [native tape architecture](native-tape-api.md)
and [Windows storage plans](windows9x-storage.md).
