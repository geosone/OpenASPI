# EXCHK

Checks an exFAT drive of [EXFAT.SYS](../../drivers/exfat/README.md), on a
BIOS disk or an ASPIDSK/ASPIFDD medium, and repairs it with `/F`.

```dos
EXCHK D:
EXCHK D: /F
```

Checked:

- boot region: exFAT boot sector, sector and cluster sizes, FAT and cluster
  heap layout, the checksum in sector 11, the signatures of the extended
  boot sectors, the backup boot region (sectors 12-23) against the main one;
  VolumeDirty and MediaFailure flags (warnings)
- FAT entries 0 and 1
- root directory: exactly one allocation bitmap and one up-case table, the
  up-case table checksum
- every entry set of all directories: number of secondary entries, stream
  entry, name length and characters, set checksum, name hash (through the
  volume's up-case table), valid data length, directory sizes
- cluster chains (FAT or contiguous): inside the volume, length matching
  the size, no bad cluster, no loop
- the allocation bitmap against the clusters in use: clusters used twice
  (cross-linked), used but free in the bitmap, allocated but used by
  nothing (lost; clusters marked bad in the FAT do not count)

The clusters in use are kept in a bit map of up to 448 KB of conventional
memory (3.6 million clusters); a larger volume is checked in several passes.

EXCHK finds the drive through EXFAT.SYS (its device header points to its
volume table, `include/openaspi/exfatsys.h`) and reads the sectors itself:
INT 13h for BIOS disks, the exFAT service of ASPIDSK/ASPIFDD for their
media.

Exit codes: 0 no errors (warnings possible), 1 errors found (with `/F`
also when they have been repaired), 2 wrong use or no exFAT drive of
EXFAT.SYS, 3 read error in the boot region.

`/F` writes the repairs at once, each shown as "Corrected:":

- boot region: from the intact copy (main or backup); with both damaged the
  checksum is written new and the backup copied from the main region
- FAT entries 0 and 1; VolumeDirty cleared, PercentInUse set new
- entry sets: checksum and name hash written new, valid data length cut to
  the size, the allocation flag set; a set that is cut off, without stream
  entry or with a wrong name length is deleted (its clusters become free);
  stray secondary entries, unknown critical entries and system entries
  outside the root directory are deleted
- cluster chains: a chain longer than its file is ended; a broken or short
  chain is ended at its last good cluster and the file's size set to the
  clusters there are
- the allocation bitmap is written from the clusters in use: lost clusters
  freed, unmarked ones marked

Not repaired: cross-linked clusters (copy the files named and delete the
originals), invalid characters in names, a damaged allocation bitmap or
up-case table entry.  exFAT has one FAT and one allocation bitmap (two only
with TexFAT), so lost FAT data cannot be taken from a second copy as on
FAT.  Afterwards EXFAT.SYS reads the volume again (the `changed` flag of its
volume table).  For ASPIDSK/ASPIFDD media EXCHK writes through the WRITE
function of their exFAT service.

The check is `common/exfat/exfat_check.c`.  Tests: `tests/exchk_host.sh`
damages images in nine ways (`tests/exchk_corrupt.py`), checks the
messages of `build/host/test_exchk`, also in passes of 100 clusters, and
repairs them; afterwards the check and `fsck.exfat` must find no error.
`tests/dos_exfat.sh` and `tests/dos_exfat_aspi.sh` run EXCHK under DOS
(`DAMAGE=hash` and others: EXCHK /F on a BIOS disk or an ASPI stick).
