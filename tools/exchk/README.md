# EXCHK

Checks an exFAT drive of [EXFAT.SYS](../../drivers/exfat/README.md), on a
BIOS disk or an ASPIDSK/ASPIFDD medium.  This version only reads and
reports; nothing is changed.

```dos
EXCHK D:
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

Exit codes: 0 no errors (warnings possible), 1 errors found, 2 wrong use or
no exFAT drive of EXFAT.SYS, 3 read error in the boot region.

Repairing (`/F`) comes with the writing of EXFAT.SYS.

The check is `common/exfat/exfat_check.c`.  Tests: `tests/exchk_host.sh`
damages images in nine ways (`tests/exchk_corrupt.py`) and checks the
messages of `build/host/test_exchk`, also in passes of 100 clusters;
`tests/dos_exfat.sh` and `tests/dos_exfat_aspi.sh` run EXCHK under DOS
(`DAMAGE=bitmap-set`: a lost cluster).
