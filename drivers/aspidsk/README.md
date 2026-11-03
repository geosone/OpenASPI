# ASPIDSK.SYS

ASPI disk driver: a DOS block device driver for SCSI direct-access devices
(peripheral type 00h) behind an ASPI manager: hard disks, SSDs, USB sticks
and card readers, used with partitions and drive letters like a hard disk.
LS-120, ZIP and similar removable-media drives are left to `ASPIFDD.SYS`.

    DEVICE=C:\OPENASPI\EUSBASPI.SYS
    DEVICE=C:\OPENASPI\ASPIDSK.SYS

Options (as ASPIDISK has them; `/` or `-`, upper or lower case, values
after `:` or `=`):

- `/ID:[h:]t[,[h:]t...]`: only these targets, up to 8 (`h` = host adapter;
  without it the target on any adapter). `/ID:1` takes only target 1.
- `/NOSPINUP`: a stopped drive is not started. By default, a drive that
  reports "not ready" (sense 02/04) at boot gets START STOP UNIT.
- `/PAUSE`: wait for a key after the messages.
- `/R:n`: each removable device gets at least `n` letters (1 to 8,
  default 1), for media with more volumes inserted later. A letter without
  a volume is "not ready", like an empty floppy drive. An empty card reader
  gets one letter.

Implemented behavior:

- A drive letter for each volume of a device: the FAT partitions (types
  01h, 04h, 06h, 0Eh; 0Bh/0Ch when FAT32 is enabled), then the exFAT ones
  (07h). Primary partitions come in table order, then the logical drives
  along the extended partition's chain (05h, 0Fh, 85h). A superfloppy is one
  volume. Other types, and a 07h partition without exFAT, get no letter;
  neither does a partition whose boot sector is unusable.
- The letters are given at boot. A removable device keeps as many letters as
  the medium in it had then. A later medium with fewer volumes leaves the
  extra letters "not ready", and a later medium with more volumes shows only
  as many as there are letters.
- A media change seen through one letter reaches the device's other letters.
  A PREVENT through one letter locks the device for all of them, and the
  device is ejected only when none of its letters holds a lock.
- READ (READ(10)), WRITE (WRITE(10)) and WRITE WITH VERIFY (WRITE AND
  VERIFY(10), WRITE(10) followed by VERIFY(10) where the combined command is
  unsupported); 512-byte sectors, up to
  64 sectors per command.  A write-protected medium reports DOS error 00h.
  When a medium is read in, MODE SENSE asks for its WP bit; a protected
  medium then fails writes at once, without sending them. A device that
  doesn't report the bit is written to, and its own refusal gives the error.
- Media check and BUILD BPB for devices with the removable bit (USB
  sticks, card readers): a new medium is read again.
- exFAT media (superfloppy, or MBR partition of type 07h) for
  `EXFAT.SYS`: DOS sees an empty, write-protected disk until EXFAT.SYS
  takes the drive letter over; it reads the sectors through the exFAT
  service (`common/dos/exfat_svc.inc`).  See [EXFAT.SYS](../exfat/README.md).
  [EXCHK](../../tools/exchk/README.md) `/F` writes through it, and
  [EXFMT](../../tools/exfmt/README.md) formats any medium of the driver
  through it (sectors of the whole medium, then a reload).
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
