# Block IOCTL: current implementation

ASPIDSK and ASPIFDD share these handlers in `common/dos/blkdrv.inc`.
Parameter and Media-ID queries are read-only. Removable-media locking/eject
are implemented separately below; this is not complete GUEST/MKELS120 compatibility.

## Supported calls

- DOS device request `13h`, category `08h`, minor `60h`: get parameters.
- Category `08h`, minor `66h`: read the current Media-ID.
- With FAT32-capable DOS, category `48h` supports `60h` extended parameters
  (seven-byte descriptor plus 53-byte BPB) and `66h` Media-ID.
- ASPIFDD additionally supplies checked category `80h` [raw-media sessions](raw-media.md)
  for filesystem formatting and copying, separate from standard track IOCTLs.
- Removable units additionally support `08h/48h` lock/unlock/count and
  `08h/49h` eject; see [media controls](media-control.md).
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

Each unit retains its installation-time BPB separately from the current
one. An empty ASPIFDD drive starts with the existing 1.44 MB placeholder;
that is a default, not a measurement of the drive's maximum capacity.
Current-parameter requests reread removable media and rediscover the first
supported FAT partition or superfloppy. Fixed disks use the cached BPB.
Read errors and absent/unrecognized media fail instead of returning a stale
current BPB. Default requests do not read media.

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

This path never writes to the medium. Setting Media-ID (`46h`) remains
unsupported and is not advertised. In particular it does not reproduce the
historical reference handlers' suppression of Media-ID write failures.

## EDR-DOS query compatibility

The SvarDOS test environment uses EDR-DOS. Its INT 21h/4411h path sends a
22-byte legacy IOCTL packet: category/minor remain in the count word at
`12h`, instead of the standard generic fields at `0Dh/0Eh`. It also obtains
the returned AX value from that count. The driver recognizes this layout
only for request `19h`, exact length `16h`, zero media byte and supported
count `0860h`, `0866h`, or removable-unit `0848h`/`0849h`, then returns count zero. This alternate layout is never
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
  level, short-buffer offset bounds and rejection of setting Media-ID.
- `tests/block_ioctl_dos.asm`, calling DOS INT 21h/440Dh and 4411h on the
  installed E: stick, F: ZIP and G: LS-120 image-backed drives; checks BPBs,
  hidden sectors, buffer boundaries, known serial/label/filesystem fields
  and rejection of format capability. Disposable test images have fixed
  serials `11112222h`, `33334444h`, `55556666h` for reproducibility.
- Existing fallback, device ownership/detection and image read/write tests.

The parameter/Media-ID handlers never write the medium. The separate media
controls send PREVENT/ALLOW and START STOP; their tests are documented in
[media controls](media-control.md).
`tests/fat32_driver.asm` checks extended descriptors and malformed BPBs;
`tests/dos_fat32.sh` qualifies actual FAT32 creation and DOS read/write
through both ASPIFDD and ASPIDSK. See [raw-media sessions](raw-media.md)
for the independent formatter/copy protocol and its error handling.
Setting Media-ID, media/protection sensing, track I/O,
formatting, private legacy ABI support and real-hardware qualification
remain separate work. Unsupported functions must continue to fail until
their real implementation and tests are added.
