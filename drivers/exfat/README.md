# EXFAT.SYS

exFAT drives for DOS, read-only.  DOS knows FAT only, so EXFAT.SYS works as
a network redirector (INT 2Fh AH=11h), as MSCDEX and SHSUCDX do for CD-ROMs:
the drive gets its own letter and DOS sends every file request for it to
EXFAT.SYS.  It needs no ASPI.

```dos
DEVICE=C:\DOS\EXFAT.SYS [/L:x] [/Q]
LASTDRIVE=Z
```

- `/L:x` first drive letter to use (default: the first free one)
- `/Q` no messages

Version 0.1 finds the exFAT volumes on the BIOS disks (INT 13h, with the
extensions for LBA when the BIOS has them): superfloppies, MBR partitions
of type 07h (primary and logical) and GPT basic data partitions, up to four
volumes.  The drive letters are taken when the first program starts, since
DOS builds its drive table only after CONFIG.SYS; LASTDRIVE must leave free
letters.

- Names: exFAT stores long Unicode names only.  EXFAT.SYS shows them as 8.3
  names in the DOS code page (437, or 850 when that is active): names that
  fit stay as they are (`README.TXT`, `klein.txt` as `KLEIN.TXT`), others
  get `~n` in the order of the directory (`EINLAN~1.TXT`, `EINLA~10.TXT`).
- Subdirectories show `.` and `..` as on FAT.
- Writing, creating, deleting and renaming give "access denied".
- Files of 4 GB and more are shown with the size FFFFFFFFh; only their
  first 4 GB can be read.
- CHKDSK, SCANDISK and DEFRAG do not work on the drive (as on CD-ROM
  drives); EXFMT and EXCHK will.

The exFAT code is `common/exfat/exfat.c` (after the Microsoft exFAT file
system specification), shared with the host test and the tools to come.
Plans (ASPIDSK/ASPIFDD media, writing): [future plans](../../docs/future-plans.md).

Tests: `build/host/test_exfat` (8.3 names; with an image it lists and reads
it), `tests/exfat_image.sh` makes images through the Linux exFAT driver,
`tests/dos_exfat.sh` boots MS-DOS 7.1 (`SVARDOS=1`: SvarDOS) in QEMU with
an MBR partition (`SUPER=1`: superfloppy) and compares DIR, CD, TYPE and
COPY results.

Known: on SvarDOS the free space shown by DIR counts one sector per
cluster.
