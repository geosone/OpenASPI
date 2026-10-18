# Driver suite

All four drivers consume the same ASPI-manager layer and SCSI helpers.  Device
claiming is centralized so two OpenASPI drivers cannot attach to the same
host/target/LUN.

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

## Development order

1. shared ASPI-manager discovery, enumeration, SRB submission and sense data;
2. ASPITAP read-only discovery/status path and `TAPECTL`;
3. ASPIDSK baseline block I/O;
4. ASPICDA data-disc path and redirector integration;
5. ASPIFDD removable-media policy and verified device extensions;
6. write paths and destructive operations only after emulator and hardware
   tests cover timeout, write protection, media change and partial transfer.
