# ASPIDSK.SYS

ASPI disk driver: a DOS block device driver for SCSI direct-access devices
(peripheral type 00h) behind an ASPI manager: hard disks, SSDs, USB sticks
and card readers, used with partitions and drive letters like a hard disk.
LS-120, ZIP and similar removable-media drives are left to `ASPIFDD.SYS`.

    DEVICE=C:\OPENASPI\EUSBASPI.SYS
    DEVICE=C:\OPENASPI\ASPIDSK.SYS

Version 0.1:

- One drive letter per device: the first FAT12/FAT16 partition (types 01h,
  04h, 06h, 0Eh), or the whole medium without a partition table.
- READ (READ(10)), WRITE (WRITE(10)) and WRITE WITH VERIFY (WRITE AND
  VERIFY(10), WRITE(10) where the device lacks it); 512-byte sectors, up to
  64 sectors per command.  A write-protected medium reports DOS error 00h.
- Media check and BUILD BPB for devices with the removable bit (USB
  sticks, card readers): a new medium is read again.
- A private stack for the ASPI manager.

Not yet: more partitions, FAT32, generic IOCTL (FORMAT, SYS), skipping
disks the BIOS already serves; see
[ASPIDISK compatibility](../../docs/aspidisk-compat.md).  Tested in QEMU
with EUSBASPI and USB mass storage (`make dos-disk-smoke`).
