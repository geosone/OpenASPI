# EXFAT.SYS

exFAT drives for DOS, read-only.  DOS knows FAT only, so EXFAT.SYS works as
a network redirector (INT 2Fh AH=11h), as MSCDEX and SHSUCDX do for CD-ROMs:
the drive gets its own letter and DOS sends every file request for it to
EXFAT.SYS.  It needs no ASPI.

```dos
DEVICE=C:\DOS\EXFAT.SYS [/L:x] [/Q] [/C]
LASTDRIVE=Z
```

- `/L:x` first drive letter to use (default: the first free one)
- `/Q` no messages
- `/C` BIOS disks through CHS only, without the INT 13h extensions (for
  BIOSes with faulty extensions; only the first 8 GB are reachable)

EXFAT.SYS stays resident with about 13.5 KB; it loads high with
`DEVICEHIGH`.  The initialisation code and the unused code page table are
freed after loading.

EXFAT.SYS finds exFAT volumes in two places:

- BIOS disks (INT 13h, with the extensions for LBA when the BIOS has them):
  superfloppies, MBR partitions of type 07h (primary and logical) and GPT
  basic data partitions.  They get free drive letters, taken when the
  first program starts, since DOS builds its drive table only after
  CONFIG.SYS; LASTDRIVE must leave free letters.
- ASPIDSK and ASPIFDD units (USB sticks, card readers, ZIP): load
  `EXFAT.SYS` after them.  Such a unit keeps the drive letter of ASPIDSK or
  ASPIFDD; while an exFAT medium is in, EXFAT.SYS takes the letter over and
  reads the sectors through the drivers' exFAT service (`EXF1` in the
  device header, see `common/dos/exfat_svc.inc`).  When a FAT medium is
  inserted, the letter goes back to DOS; an exFAT medium inserted later is
  taken over again.  A volume that is both a BIOS disk and an ASPI unit
  (SeaBIOS and many BIOSes show USB sticks as BIOS disks) is used once,
  through the ASPI letter.

Up to eight volumes.

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
Plans (writing, EXFMT, EXCHK): [future plans](../../docs/future-plans.md).

Tests: `build/host/test_exfat` (8.3 names; with an image it lists and reads
it), `tests/exfat_image.sh` makes images through the Linux exFAT driver,
`tests/dos_exfat.sh` boots MS-DOS 7.1 (`SVARDOS=1`: SvarDOS) in QEMU with
an MBR partition (`SUPER=1`: superfloppy, `HIGH=DIR`: DEVICEHIGH with
HIMEM.SYS, EMM386.EXE and MEM.EXE from DIR, `OPTS=/C`: CHS reads) and
compares DIR, CD, TYPE and
COPY results.  `tests/dos_exfat_aspi.sh` uses EUSBASPI and ASPIDSK with a
removable USB stick and changes the medium exFAT -> FAT16 -> exFAT.

Known: on SvarDOS the free space shown by DIR counts one sector per
cluster.
