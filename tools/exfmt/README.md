# EXFMT

Creates an exFAT file system: on a drive of
[EXFAT.SYS](../../drivers/exfat/README.md), on a drive of ASPIDSK or
ASPIFDD (a FAT or blank medium), or on a BIOS disk.

```dos
EXFMT D:
EXFMT D: /V:Daten /YES
EXFMT D: /TEXFAT /YES
EXFMT /D:81 /P:2 /A:32K /YES
EXFMT /D:82 /WHOLE /Q /YES
```

Without `/YES` only the layout is shown: medium, partition, size, cluster
size, FAT and data area.  Options:

| Option | |
|---|---|
| `d:` | a drive of EXFAT.SYS, ASPIDSK or ASPIFDD |
| `/D:nn` | BIOS disk nn (hex, 80 = the first hard disk) |
| `/P:n` | partition n (1-4) of the MBR |
| `/WHOLE` | the whole medium without partition table (superfloppy) |
| `/V:label` | volume label, up to 11 characters in the DOS code page (437 or 850) |
| `/A:size` | cluster size: 512 bytes to 32M, a power of two (`4K`, `32K`, ...) |
| `/TEXFAT` | two FATs and two allocation bitmaps (TexFAT) |
| `/Q` | no surface read |
| `/YES` | format |

The volume: the partition of the EXFAT.SYS drive, else with `/P:n` that
partition, with `/WHOLE` the whole medium.  Without either, a medium
with a FAT or exFAT boot sector in sector 0 (superfloppy) or without a
partition table is formatted whole, and a partitioned one in its first FAT
or exFAT partition (types 01h, 04h, 06h, 07h, 0Bh, 0Ch, 0Eh).  The MBR is
not created or moved; only the partition type becomes 07h.  On a BIOS
disk a FAT partition is only formatted when it is named with `/P:n` (DOS
may have it as a drive), and never the first FAT partition of disk 80h
when DOS was booted from C:.

Cluster size by volume size, as Windows does: 4 KB up to 256 MB, 32 KB up
to 32 GB, 128 KB above.  The FAT and the data area start on cluster
boundaries.

Formatting:

1. Surface read (without `/Q`): all sectors of the data area, in 16 KB
   blocks, a failed block again sector by sector.  Clusters with an
   unreadable sector are marked bad in the FAT (FFFFFFF7h) and allocated in
   the bitmap; at most 256 of them.  This is a read check, not a write test.
2. The partition type set to 07h.
3. Sector 0 cleared, so that an interrupted format leaves no old file
   system behind; the backup boot region (sectors 12-23); the FAT(s); the
   allocation bitmap(s), the up-case table and the root directory (volume
   label, bitmap and up-case entries), placed round bad clusters; the main
   boot region (sectors 0-11, with its checksum) last.

The up-case table is the recommended one of the exFAT specification
(compressed, 5836 bytes, `common/exfat/upcase.c`).  The boot code only halts:
an exFAT volume does not boot DOS.

TexFAT (`/TEXFAT`): NumberOfFats 2, both FATs and both bitmaps written the
same, ActiveFat 0.  Worth it for aging removable media such as ZIP and
SuperDisk: [EXCHK](../exchk/README.md) `/F` repairs a chain damaged in
one FAT from the other.  EXFAT.SYS reads TexFAT; `fsck.exfat` of
exfatprogs rejects it.

Afterwards the drives read the medium again: EXFAT.SYS gets the `changed`
flag of its volume table, ASPIDSK/ASPIFDD its RELOAD function (the next
MEDIA CHECK reports "changed"; an exFAT medium goes to EXFAT.SYS, which
takes the drive letter over from DOS).  A BIOS disk given with `/D:nn`
that EXFAT.SYS has no drive for needs a restart: EXFAT.SYS finds BIOS
volumes when it is loaded.

For ASPIDSK/ASPIFDD media EXFMT reads and writes through the exFAT service
of the driver (functions PREAD, PWRITE, CAPACITY and RELOAD, see
`common/dos/exfat_svc.inc`), for BIOS disks through INT 13h (extensions,
else CHS).

Exit codes: 0 formatted or the layout shown, 1 format failed (too many bad
clusters, or bad ones where the file system must go), 2 wrong use or no
such drive, 3 read or write error.

The format is `common/exfat/exfat_format.c`.  Tests: `tests/exfmt_host.sh`
formats images of 1 MB to 40 GB with all default and some chosen cluster
sizes, TexFAT and bad clusters (`build/host/test_exfmt`), checks them with
`build/host/test_exchk` and `fsck.exfat`, and fills one through the Linux
exFAT driver.  `tests/dos_exfmt.sh` runs EXFMT under MS-DOS 7.1: an
EXFAT.SYS drive on a BIOS disk and a blank BIOS disk with a read error
(QEMU blkdebug); `ASPI=1` a FAT stick of ASPIDSK (`FDD=1` ASPIFDD) made
exFAT and taken over by EXFAT.SYS, then formatted again; `TEXFAT=1` all of
it with `/TEXFAT`.
