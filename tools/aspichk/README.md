# ASPICHK

Checks a FAT12, FAT16 or FAT32 drive and repairs it with `/F`: any DOS
drive, and the media of ASPIDSK/ASPIFDD also when DOS has not mounted them.
exFAT drives are checked by [EXCHK](../exchk/README.md).

```dos
ASPICHK D:
ASPICHK D: /F
```

Checked (the rules of `fsck.fat` of dosfstools 4.2):

- boot sector and BPB: signature, sector and cluster sizes, FAT layout,
  cluster count against the FAT type; the dirty flags of the boot sector
  and of FAT entry 1 (warnings)
- FAT32: the backup boot sector (sector 6) against the main one, the FSInfo
  sector (signatures, free count, next free cluster)
- FAT entries 0 and 1, the FAT copies against each other
- every directory entry: 8.3 name characters, `.` and `..` entries, volume
  labels, directory sizes, empty files with a first cluster, sizes larger
  than the volume; VFAT long names (order, checksum, orphans)
- cluster chains: inside the volume, no free or bad cluster in them, no
  loop, length matching the size; directories pointing to the root or a
  parent
- clusters used twice (cross-linked), allocated but used by nothing (lost)

The clusters in use are kept in a bit map of up to 448 KB of conventional
memory (3.6 million clusters); a larger volume is checked in several passes.

Sector access:

- ASPIDSK/ASPIFDD drives (found by the "EXF1" mark of their device header):
  the physical sector functions of their exFAT service; the driver reads
  the volume again before the check (the medium may have changed) and after
  `/F`.
- other drives: INT 21h 7305h (DOS 7.1, all FAT types), else INT 25h/26h
  with a packet.  Under DOS 7 `/F` takes the level 0 lock of the drive
  (INT 21h 440Dh, 084Ah).

Exit codes: 0 no errors (warnings possible), 1 errors found (with `/F`
also when they have been repaired), 2 wrong use or no FAT drive, 3 read
error in the boot sector.

`/F` writes the repairs at once, each shown as "Corrected:":

- boot sector from the backup, or the backup from the boot sector (FAT32);
  dirty flags cleared; FSInfo free count and next free cluster
- FAT entries 0 and 1; a FAT entry broken in the active FAT is taken from
  another copy when that one is valid, then the other copies are written
  from the active one
- chains: a chain longer than its file is ended; a broken chain is ended at
  its last good cluster and the size set to the clusters there are; of two
  cross-linked files the one met later is cut before the shared cluster;
  a loop is cut
- entries: invalid long name entries deleted, `.` and `..` corrected or
  created, a directory size set to 0, the first cluster of an empty file
  cleared
- lost clusters freed

Not repaired: invalid characters in 8.3 names, a missing `.` or `..` entry
whose slot holds another entry.

Tests: `tests/aspichk_host.sh` (the check core `common/fat/fat_check.c` on
FAT12/16/32 images of `tests/fat_image.sh` with the damages of
`tests/fatchk_corrupt.py`, one pass and passes of 100 clusters, `fsck.fat`
after `/F`), `tests/dos_aspichk.sh` (MS-DOS 7.1: FAT16 and FAT32 BIOS
disks; `ASPI=1`: a FAT16 USB stick through ASPIDSK).
