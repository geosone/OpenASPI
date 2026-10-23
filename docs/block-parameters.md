# Checked DOS device-parameter updates

ASPIDSK and ASPIFDD implement generic IOCTL `08h/40h` and, with FAT32-capable
DOS, `48h/40h`. These change the logical BPB in driver memory. They do not
write a boot sector, convert a filesystem, change physical sector size or
format a mechanism. The supported packet prefix is the seven-byte descriptor
plus a 25-byte legacy BPB or 53-byte extended BPB, matching GET `60h`.

## Supported requests

- Flags `04h` set the default BPB; `05h` set the current BPB. Uniform sectors
  are required. Track-layout-only requests, variable sector tables and other
  special-function bits are rejected.
- Descriptor type/attributes must continue to describe the actual device:
  type 7 and attributes 0 for removable units, type 5 and attributes 1 for
  fixed units. SET cannot invent door-lock capability or change ownership.
  Media type must be zero. Cylinders must match the BPB geometry's rounded-up
  total-plus-hidden-sector count, as returned by GET `60h`.
- Sector size is 512; heads are 1–256 and sectors/track 1–63. FAT12/16 BPBs
  need nonempty reserved/root/data regions, one or two FATs, a power-of-two
  cluster size and enough FAT entries for the data area. Ambiguous total-size
  fields, cluster-count overflow and undersized FATs fail. FAT32 additionally
  uses the existing extended BPB/root/FSInfo/backup/active-FAT checks.
- A fresh READ CAPACITY and volume discovery must succeed. The candidate's
  hidden sectors must equal the actual selected volume start. Its size must
  fit both physical capacity and the selected MBR partition, where present.
  SET cannot select a different partition or expose neighbouring sectors.

The current implementation requires a recognized existing FAT volume.
Blank-media setup remains available through ASPIFMT's raw interface. Device
profiles and standard DOS physical formatting are separate remaining work.

## State and errors

Input is copied into a bounded staging buffer and validated before committing
any candidate BPB. Capacity/volume preflight uses a shadow unit record. A
failed request never commits the proposed layout or changes the default BPB;
failed media/transport preflight invalidates the current-volume cache so a
stale override cannot remain usable. All device commands here are reads.
Other units, media-lock counts and software access policy are unaffected.
The caller's parameter packet is unchanged; NULL, wrapping and short request
pointers are rejected before the corresponding access.

Changing defaults leaves the active BPB untouched. A current override is
returned by current-parameter queries and BUILD BPB without immediately
replacing it with the on-disk BPB. It remains a temporary DOS view: media
change/error, eject, raw-session release or explicit volume rediscovery
(including Media-ID operations and raw INFO) discards it. An invalidated
fixed disk reports that its BPB needs rebuilding and can recover through
BUILD BPB too; it does not stay permanently inaccessible.

Callers must flush DOS caches before layout changes and restore the current
BPB when abandoning a planned operation. A successful logical SET is not
evidence that a new filesystem has been written. Category `48h` is gated by
the DOS capability probe; Windows native-storage handover is not qualified.

ABI references: [RBIL, parameter packet table 01560](https://fd.lod.bz/rbil/interrup/dos_kernel/21440d.html)
and the [FreeDOS generic block handler](https://github.com/FDOS/kernel/blob/master/kernel/dsk.c).
These describe the interface; implementation is shared OpenASPI code.

## Verification

`tests/block_params.asm` runs both real block-driver variants with memory-only
ASPI. It checks independent default/current state, override GET/BUILD BPB,
per-unit isolation, malformed layouts/descriptors, capacity and partition
limits, forbidden remapping, non-512-byte responses, FAT32, media changes and
fixed-disk recovery. The mock rejects all device-write commands.

`tests/block_ioctl_dos.asm` changes geometry through actual DOS calls on
EUSBASPI disk, ZIP and LS-120 images, reads it back and restores it.
`tests/params_dos.inc` shares the live roundtrip between legacy and extended
clients; `tests/dos_fat32.sh` exercises category `48h` through both ASPIFDD
and ASPIDSK under FreeDOS. Raw-session, ownership and media-control regressions
also run against the shared READ CAPACITY helper in `block_capacity.inc`.
