# ASPIDSK.SYS

ASPI disk driver: a DOS block device driver for SCSI direct-access devices
(peripheral type 00h) behind an ASPI manager: hard disks, SSDs, USB sticks
and card readers, used with partitions and drive letters like a hard disk.
LS-120, ZIP and similar removable-media drives are left to `ASPIFDD.SYS`.

    DEVICE=C:\OPENASPI\EUSBASPI.SYS
    DEVICE=C:\OPENASPI\ASPIDSK.SYS

Implemented behavior:

- One drive letter per device: the first supported FAT partition (types 01h,
  04h, 06h, 0Eh; 0Bh/0Ch when FAT32 is enabled), or a superfloppy.
- READ (READ(10)), WRITE (WRITE(10)) and WRITE WITH VERIFY (WRITE AND
  VERIFY(10), WRITE(10) followed by VERIFY(10) where the combined command is
  unsupported); 512-byte sectors, up to
  64 sectors per command.  A write-protected medium reports DOS error 00h.
- Media check and BUILD BPB for devices with the removable bit (USB
  sticks, card readers): a new medium is read again.
- A private stack for the ASPI manager.
- Per-unit DOS access control (`47h`/`67h`) and independent logical mapping
  requests (`17h`/`18h`); see [access behavior](../../docs/block-access.md).
- Verified Media-ID writes (`46h`), including the FAT32 backup boot sector.
- Checked logical BPB updates (`40h`); [scope and state](../../docs/block-parameters.md).
- Logical track read/write/verify (`41h`/`61h`/`62h`); see the
  [addressing contract](../../docs/block-track.md).
- INIT skips devices the manager reports as already exposed to DOS;
  unsupported queries continue with a warning. See
  [ownership behavior and limits](../../docs/block-ownership.md).
- Read-only generic IOCTL `08h/60h` (parameters), `08h/66h` (Media-ID) and
  matching capability queries; default
  parameters stay stable while removable media change. See
  [block IOCTL behavior](../../docs/block-ioctl.md).

FAT32 extended BPBs and `48h/60h`, `48h/66h` are qualified on FreeDOS 1.4;
MS-DOS 7.1/Windows 9x qualification remains open.

Not yet: more partitions, variable track tables, physical format IOCTLs and independent detection of
BIOS mappings that the ASPI manager does not report; see
[ASPIDISK compatibility](../../docs/aspidisk-compat.md).  Tested in QEMU
with EUSBASPI and USB mass storage (`make dos-disk-smoke`).
