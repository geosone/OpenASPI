# ASPIFDD.SYS

ASPI removable-media driver: a DOS block device driver for LS-120/240, ZIP,
Clik!, Jaz, SuperDisk and similar drives behind an ASPI manager.  It is
selected separately from ASPIDSK while reusing its block core; removable
policy and the raw tool service remain within that common implementation.

    DEVICE=C:\OPENASPI\AHCIASPI.SYS
    DEVICE=C:\OPENASPI\ASPIFDD.SYS

A device is taken when it is a direct-access device with the removable bit
and its INQUIRY vendor/product contains `ZIP`, `LS-120`, `LS-240`, `CLIK`,
`SUPERDISK` or `JAZ`; ASPIDSK skips exactly these devices.

Implemented behavior:

- Every drive gets its letter, also without a disk (until the first BUILD
  BPB DOS sees a 1.44 MB placeholder).  Media check returns "don't know",
  so DOS reads the disk again when it may have changed.
- Partitioned disks (ZIP) and superfloppies (LS-120); FAT12/FAT16 and
  conditional FAT32 with extended BPBs, qualified on FreeDOS 1.4.
- READ, WRITE and WRITE WITH VERIFY as ASPIDSK.
- exFAT media for `EXFAT.SYS` as ASPIDSK; see [EXFAT.SYS](../exfat/README.md).
- Verified Media-ID writes (`46h`), including a validated FAT32 backup.
- Checked default/current logical BPBs (`40h`); see
  [parameter behavior](../../docs/block-parameters.md) for supported modes.
- Logical track read/write/verify; see [track behavior](../../docs/block-track.md).
- Per-unit DOS access control and independent logical mapping queries;
  [software policy](../../docs/block-access.md) is separate from media locks
  and hardware write protection.
- INIT checks manager-reported BIOS/DOS ownership before allocating a letter;
  see [ownership behavior and limits](../../docs/block-ownership.md).
- Read-only generic IOCTL `08h/60h` returns installation-time defaults or
  freshly read current-media parameters; `08h/66h` reads the current serial,
  label and filesystem text. Capability queries cover the implemented block
  functions; category `48h` additionally requires FAT32-capable DOS.
  Removable-media `08h/48h` adds checked, reference-counted
  locking; `08h/49h` ejects only when unlocked. Hardware errors propagate.

- Checked [raw-media sessions](../../docs/raw-media.md) support
  [ASPIFMT](../../tools/aspifmt/README.md) filesystem creation/bad-cluster
  marking and [ASPIDD/ASPIDDG](../../tools/aspidd/README.md) copying/rescue.

Not yet: physical formatting (generic IOCTL 42h with FORMAT UNIT), the
LS-120-specific media sensing/format profiles, a runtime loader
like Iomega GUEST.EXE; see
[ASPIDISK and MKELS120 compatibility](../../docs/aspidisk-compat.md).
Original drivers are compatibility fixtures only and are not distributed.

See [media controls](../../docs/media-control.md) for lock/eject semantics,
ASPICTL/EJECT usage, tests and hardware qualification limits.

See [block IOCTL behavior and tests](../../docs/block-ioctl.md) for the
supported parameter layout and limitations. ZIP and LS-120 device-function
research is recorded separately in the
[reference investigation](../../docs/aspifdd-reference.md).

Native ATAPI LS-120 read/write testing and the local 86Box 6.0 emulator
backport are documented in [86Box LS-120](../../docs/86box-ls120.md).
