# Block IOCTL: current implementation

ASPIDSK and ASPIFDD share these handlers in `common/dos/blkdrv.inc`.
Parameter and Media-ID queries are read-only; `46h` writes Media-ID metadata.
Removable-media locking/eject
are implemented separately below; this is not complete GUEST/MKELS120 compatibility.

## Supported calls

- DOS device request `13h`, category `08h`, minor `60h`: get parameters.
- Minor `40h`: checked logical default/current BPB updates, without device
  writes; see [parameter setting and limits](block-parameters.md).
- Minors `41h`/`61h`/`62h`: [track write/read/verify](block-track.md), with
  checked CHS conversion, physical/volume bounds and split transfers.
- Category `08h`, minor `66h`: read the current Media-ID.
- Category `08h`, minor `46h`: set the boot-sector Media-ID with read-back
  verification; FAT32 updates its declared backup too.
- Categories `08h` and conditional `48h`, minors `47h`/`67h`: set/get
  the per-unit DOS block-access policy; see [access and mapping](block-access.md).
- With FAT32-capable DOS, category `48h` supports `60h` extended parameters
  (seven-byte descriptor plus 53-byte BPB), `40h` BPB updates and `46h`/`66h` Media-ID.
- ASPIFDD additionally supplies checked category `80h` [raw-media sessions](raw-media.md)
  for filesystem formatting and copying, separate from standard track IOCTLs.
- Removable units additionally support `08h/48h` lock/unlock/count and
  `08h/49h` eject; see [media controls](media-control.md).
- Device requests `17h`/`18h`: no alternate logical-drive mapping; return
  zero for a valid independent unit. They do not swap or merge devices.
- Device request `19h`: query support for the implemented operations,
  including the two controls only on removable units, even when no medium
  is present. Query does not access ASPI or inspect a parameter buffer.
- Driver-header bits advertise generic IOCTL and query, not legacy IOCTL
  input/output or a private GUEST packet API.

The `60h` parameter packet has a seven-byte descriptor followed by the 25-byte
FAT12/FAT16 BPB; the driver writes exactly 32 bytes and leaves the caller's
first flags byte intact. Flags bit 0 selects the current BPB instead of the
installation-time default. Bit 2 (uniform sector size) is accepted. All
other bits are rejected. Track-layout fields are unsupported. Category
`48h/60h` writes exactly 60 bytes; legacy `08h/60h` rejects FAT32 rather
than returning a truncated BPB. Layout reference: RBIL release 61, INT 21h/440Dh table 01560,
available from the [author's distribution](https://www.cs.cmu.edu/~ralf/files.html).

Each unit retains its default BPB separately from the current one. Defaults
initially come from installation and can be explicitly changed with `40h`.
An empty ASPIFDD drive starts with the existing 1.44 MB placeholder;
that is a default, not a measurement of the drive's maximum capacity.
Current-parameter requests normally reread removable media and rediscover the first
supported FAT partition or superfloppy. Fixed disks use the cached BPB.
Read errors and absent/unrecognized media fail instead of returning a stale
current BPB. Default requests do not read media.
A checked current override from `40h` is retained until media invalidation
or explicit volume rediscovery; see [state rules](block-parameters.md).

Device type is 5 for fixed disks and 7 (other block device) for removable
devices. The nonremovable attribute reflects the actual unit flag; no
hardware-lock capability is claimed. Cylinders are a rounded-up logical
translation using the BPB heads/sectors and total-plus-hidden sectors, not
a claim about physical geometry or supported formatting profiles. Zero or
unrepresentable geometry fails safely, without division overflow.

No output is written before flags, buffer-offset bounds, media and geometry
validation complete. A NULL pointer and a buffer crossing the end of
its 64-KB offset range are rejected (32 bytes for `08h/60h`, 60 for
`48h/60h`, 25 for `66h`). As with other DOS driver calls, the
caller remains responsible for supplying valid accessible memory.

## Read Media-ID (`08h/66h`)

The caller supplies a 25-byte packet whose first word is information level
zero. The result contains the four-byte serial at offset `02h`, eleven
label bytes at `06h` and eight filesystem-type bytes at `11h`. Strings are
fixed-width boot-sector fields, not NUL-terminated names; no root-directory
label scan or synchronization is performed. Layout reference: RBIL table
01565 in the distribution linked above.

Every Media-ID request reads the selected unit's volume again, including
partition discovery, even for fixed disks. It never reuses another unit's
shared sector buffer or returns the installation-time default identity.
Only a valid FAT boot sector with full extended-BPB signature `29h`
is accepted (FAT32 uses its extended metadata offsets through `48h/66h`).
Missing metadata, unsupported info levels, absent media and read
errors fail without partially filling the output. There is no fabricated
serial/label fallback. FAT32 requires the DOS capability probe to succeed;
the extended path is qualified on FreeDOS 1.4, not yet on Windows 9x.

This query path never writes to the medium.

## Set Media-ID (`08h/46h`, conditional `48h/46h`)

SET validates the same 25-byte, info-level-zero packet and fresh volume as
GET. It copies the 23 serial/label/filesystem-text bytes into the extended
boot-sector metadata at `27h` (FAT12/16) or `43h` (FAT32), preserving every
other byte. Full signature `29h` is required; truncated `28h` metadata is
not fabricated or expanded. The caller's packet is never modified.
Copying filesystem-type text follows the reference-driver/older DOS packet
behavior; this text does not convert the filesystem or change its BPB.

For FAT32, a declared backup boot sector must be within reserved sectors,
have valid signatures and match the primary's 53-byte BPB before any write.
Each sector retains its own unrelated boot code. The backup is updated and
read back first; the primary is then updated and read back. Backup values
zero or `FFFFh` mean there is no declared backup to update. The selected
MBR extent must be nonempty, nonwrapping and contain the BPB volume; a
partition cannot start at LBA zero. Superfloppies need a nonzero BPB size.

Writes use WRITE(10), with no automatic retries. A failed write, failed
read-back or byte mismatch returns failure and invalidates the cached
current volume. Unlike the historical reference, write errors are never
masked. This is not an atomic two-sector transaction: a failed operation
may have changed one copy already, and no speculative rollback is attempted.
Hardware write protection propagates normally. An active ASPIFDD raw session
blocks competing SET calls. Software access flag `47h` governs normal DOS
data requests; it does not disable this administrative metadata operation.

This updates boot-sector metadata, not the root-directory volume-label
entry used by DOS LABEL/DIR. Callers must flush DOS caches before changing
metadata. See [RBIL's Media-ID packet and DOS-version notes](https://fd.lod.bz/rbil/interrup/dos_kernel/21440d.html)
and the [reference investigation](aspifdd-reference.md).

## EDR-DOS query compatibility

The SvarDOS test environment uses EDR-DOS. Its INT 21h/4411h path sends a
22-byte legacy IOCTL packet: category/minor remain in the count word at
`12h`, instead of the standard generic fields at `0Dh/0Eh`. It also obtains
the returned AX value from that count. The driver recognizes this layout
only for request `19h`, exact length `16h`, zero media byte and supported
count `0840h`, `0841h`, `0861h`, `0862h`, `0846h`, `0847h`, `0867h`,
`0860h`, `0866h`, or removable-unit `0848h`/`0849h`,
then returns count zero. This alternate layout is never
accepted for generic execution. The native observation was checked against
the [EDR-DOS IOCTL implementation](https://github.com/SvarDOS/edrdos/blob/main/drdos/ioctl.asm);
FreeDOS uses the standard generic fields in its
[IOCTL implementation](https://github.com/FDOS/kernel/blob/master/kernel/ioctl.c).
These kernels are references, not imported dependencies or copied code.

## Verification and remaining scope

`make dos-disk-smoke` runs:

- Two builds of `tests/block_ioctl.asm`, exercising the real resident
  entry points with memory-only ASPI: defaults/current parameters, a changed
  medium, partition offset, no medium, fixed/removable attributes, output
  guards, non-CS output segment, bad flags/length/unit/pointer, geometry
  overflow, every queried minor and both query packet layouts. Media-ID cases
  include fresh superfloppy/partition reads, a changed serial, stale shared
  sector contents, absent/invalid media, missing extended BPB, invalid info
  level, short-buffer offset bounds and malformed SET-packet rejection.
- `tests/media_id_write.asm` for both driver variants: complete boot-sector
  preservation, FAT12/16 and FAT32 metadata, backup preservation/no-backup,
  write protection, partial-write/read-back failures, malformed backup BPBs
  and empty/wrapping/out-of-range MBR extents. Write counts rule out retries.
- `tests/media_id_dos.asm` sets, reads back and restores the serial through
  actual DOS IOCTLs on the disk/ZIP/LS-120 fixtures; `tests/dos_fat32.sh`
  runs the extended category through both ASPIFDD and ASPIDSK under FreeDOS.
- `tests/block_ioctl_dos.asm`, calling DOS INT 21h/440Dh and 4411h on the
  installed E: stick, F: ZIP and G: LS-120 image-backed drives; checks BPBs,
  hidden sectors, buffer boundaries, known serial/label/filesystem fields
  and rejection of format capability. Disposable test images have fixed
  serials `11112222h`, `33334444h`, `55556666h` for reproducibility.
- Existing fallback, device ownership/detection and image read/write tests.

The parameter and Media-ID query handlers never write the medium; SET
Media-ID writes only the selected boot-sector metadata. The separate media
controls send PREVENT/ALLOW and START STOP; their tests are documented in
[media controls](media-control.md).
`tests/fat32_driver.asm` checks extended descriptors and malformed BPBs;
`tests/dos_fat32.sh` qualifies actual FAT32 creation and DOS read/write
through both ASPIFDD and ASPIDSK. See [raw-media sessions](raw-media.md)
for the independent formatter/copy protocol and its error handling.
Media/protection sensing, physical formatting/track tables,
private legacy ABI support and real-hardware qualification
remain separate work. Unsupported functions must continue to fail until
their real implementation and tests are added.
