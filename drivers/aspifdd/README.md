# ASPIFDD.SYS

ASPI removable-media driver: a DOS block device driver for LS-120/240, ZIP,
Clik!, Jaz, SuperDisk and similar drives behind an ASPI manager.  It is
separate from ASPIDSK so media change, eject/lock, format and device quirks
do not complicate the generic disk path.

    DEVICE=C:\OPENASPI\AHCIASPI.SYS
    DEVICE=C:\OPENASPI\ASPIFDD.SYS

A device is taken when it is a direct-access device with the removable bit
and its INQUIRY vendor/product contains `ZIP`, `LS-120`, `LS-240`, `CLIK`,
`SUPERDISK` or `JAZ`; ASPIDSK skips exactly these devices.

Version 0.1:

- Every drive gets its letter, also without a disk (until the first BUILD
  BPB DOS sees a 1.44 MB placeholder).  Media check returns "don't know",
  so DOS reads the disk again when it may have changed.
- Partitioned disks (ZIP) and superfloppies (LS-120); FAT12/FAT16.
- READ, WRITE and WRITE WITH VERIFY as ASPIDSK.

Not yet: eject/lock, formatting (generic IOCTL 42h with FORMAT UNIT), the
LS-120 media types (720 KB, 1.44 MB, 1.25 MB, 120 MB), a runtime loader
like Iomega GUEST.EXE; see
[ASPIDISK and MKELS120 compatibility](../../docs/aspidisk-compat.md).
Original drivers are compatibility fixtures only and are not distributed.
