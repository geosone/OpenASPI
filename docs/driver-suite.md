# Driver suite

All four drivers consume the same ASPI-manager layer and SCSI helpers
(`common/aspi/aspi_client.inc`, `aspi_init.inc`) and the DOS request
definitions (`common/dos/devreq.inc`).  Two OpenASPI drivers never attach to
the same host/target/LUN: each takes a device class that the others skip.

## DSK, FDD, CDA: the differences

| | ASPIDSK | ASPIFDD | ASPICDA |
|---|---|---|---|
| devices | type 00h: disks, SSDs, USB sticks, card readers | type 00h with the removable bit and a known model: LS-120/240, ZIP, Clik!, Jaz | type 05h: CD/DVD |
| DOS driver kind | block device | block device | character device with the CD-ROM extension |
| drive letters | from DOS at boot, one per volume | from DOS at boot, one per drive, also without a disk | from MSCDEX/SHSUCDX (`/D:name`) |
| file system | FAT, read by DOS | FAT, read by DOS | ISO 9660/High Sierra, read by the redirector |
| sector | 512 bytes | 512 bytes | 2048 cooked, 2352 raw |
| medium | partitioned, or a whole-disk volume | superfloppy (LS-120) or partitioned (ZIP) | a disc with data and audio tracks |
| media change | sticks and card readers: UNIT ATTENTION | always "don't know": DOS reads the disk again | IOCTL "media changed" for the redirector |
| special | many partitions, FAT32, large disks | eject/lock, format (FORMAT UNIT), media types | audio play, TOC, raw/digital audio, tray |
| shared core | `common/dos/blkdrv.inc` | `common/dos/blkdrv.inc` (`FDD_DRIVER`) | own |

ASPIDSK and ASPIFDD share one block driver core; ASPIFDD only changes the
device selection and the removable-media policy. Selection uses the same
`common/aspi/removable.inc` policy in both drivers and ASPISCAN, so installer
preselection agrees with device ownership. Ordinary removable USB sticks
belong to ASPIDSK, not ASPIFDD. Model matching stays within the 24 INQUIRY
vendor/product bytes and cannot match a suffix in the revision field.

## Functional compatibility target

The target is functional coverage of Adaptec ASPIDISK in ASPIDSK, Adaptec
ASPICD in ASPICDA, and **both MKELS120 and GUEST's ZIP device functions in
ASPIFDD**. GUEST is a reference for the ZIP-specific functions, not a separate
replacement driver project. Those functions belong inside ASPIFDD, with common
block transport reused from `blkdrv.inc`. Its EXE versus SYS packaging does
not remove ZIP functionality from ASPIFDD's scope. Runtime-loading mechanics
are a separate concern, not a substitute for implementing device functions.

ASPIFDD is the combined removable-device service for ZIP and LS-120: expose
common capability/media/control operations through the driver, with validated
device-specific sequences behind that interface. Dedicated formatting or other
drive utilities consume this interface rather than embedding a second ASPI/
controller/ZIP/LS-120 driver. Unsupported operations must report failure, not
pretend success. Destructive utility actions require explicit confirmation,
media identification and write-protection checks. These utilities and the
remaining special operations are requirements, not implemented 0.1 features.

Version 0.1 is not full compatibility. Follow the linked command matrices:
media sensing/change, formatting, eject/lock and verified device-specific
behavior still need implementation and tests. Unsupported functions and no-op
handlers must not be counted as completed reference-driver functionality.

## ASPIDSK.SYS

`ASPIDSK.SYS` is the general DOS block driver for SCSI direct-access devices.
Its baseline scope is fixed disks, SSDs, USB sticks, memory-card readers, and
removable devices that are intentionally used with hard-disk-style partition
and drive-letter semantics.

The driver must support media-change detection, READ CAPACITY, 512-byte DOS
logical sectors, partition discovery, and safe residual/error reporting.  It
must not silently claim a device selected for `ASPIFDD.SYS`.

## ASPIFDD.SYS

`ASPIFDD.SYS` owns removable-media behavior requiring more than generic disk
I/O: LS-120/240, ZIP, Clik!, and compatible devices.  These devices often
report as SCSI direct-access devices, so INQUIRY peripheral type alone cannot
select this driver.

Selection will use the removable-media bit plus an explicit device table or
configuration override.  Planned extensions include eject/lock, geometry and
capacity changes, media-change reporting, and device-specific formatting.
Formatting is never inferred merely from a model name; each command sequence
requires a verified implementation and test device.

## ASPICDA.SYS

`ASPICDA.SYS` owns SCSI multimedia devices (peripheral type `05h`).  It exposes
the DOS CD-ROM device-driver interface consumed by MSCDEX or SHSUCDX and adds
digital CD-audio access where supported.  Initial work covers data reads,
media change, TOC access, tray control, and the configured `/D:` device name.

## ASPITAP.SYS

`ASPITAP.SYS` owns sequential-access devices (peripheral type `01h`).  It is a
DOS character driver compatible with the documented ASPITAPE interface and
provides rewind/no-rewind names.  See `aspitape-compat.md`.

Compatibility notes on the historical drivers (command coverage, options,
what is still missing): [ASPICD.SYS](aspicd-compat.md),
[ASPIDISK.SYS, MKELS120.SYS and Iomega GUEST.EXE](aspidisk-compat.md).

## Development order

1. shared ASPI-manager discovery, enumeration, SRB submission and sense data;
2. ASPITAP read-only discovery/status path and `TAPECTL`;
3. ASPIDSK baseline block I/O;
4. ASPICDA data-disc path and redirector integration;
5. ASPIFDD removable-media policy and verified device extensions;
6. write paths and destructive operations only after emulator and hardware
   tests cover timeout, write protection, media change and partial transfer.
