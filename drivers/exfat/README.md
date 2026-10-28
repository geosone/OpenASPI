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
`DEVICEHIGH`.  The same source built with `EXFAT_LFN` is `EXFATL.SYS`
(about 21.5 KB) with the long file names below; setup installs one of the
two as `EXFAT.SYS` (option "long file names").  The initialisation code and the unused code page table are
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
- EXFATL.SYS only: long names (INT 21h AX=71xxh, the calls of DOSLFN and
  Windows 95) for the own drives: find first/next/close (six searches; when a program
  ends without closing its search, the least used one is reused), open
  (716Ch), change and current directory, attributes, times and size
  (7143h), TRUENAME in its three forms, file information by handle
  (71A6h), volume information and the time conversion (71A7h).  Paths may
  mix long and 8.3 names.  The calls that write give "access denied".
  Other drives go on to the next handler, so DOSLFN loaded after
  EXFAT.SYS gives them long names; on MS-DOS 7 COMMAND.COM's DIR shows
  the long names.
- Subdirectories show `.` and `..` as on FAT.
- TexFAT volumes (two FATs and allocation bitmaps) are read through the
  active FAT and bitmap (ActiveFat of the boot sector).
- Writing, creating, deleting and renaming give "access denied".
- Files of 4 GB and more are shown with the size FFFFFFFFh; only their
  first 4 GB can be read.
- CHKDSK, SCANDISK and DEFRAG do not work on the drive (as on CD-ROM
  drives); [EXCHK](../../tools/exchk/README.md) checks it,
  [EXFMT](../../tools/exfmt/README.md) formats it.

The exFAT code is `common/exfat/exfat.c` (after the Microsoft exFAT file
system specification), shared with the host test and the tools to come.
Plans (writing): [future plans](../../docs/future-plans.md).

Tests: `build/host/test_exfat` (8.3 names; with an image it lists and reads
it), `tests/exfat_image.sh` makes images through the Linux exFAT driver,
`tests/dos_exfat.sh` boots MS-DOS 7.1 (`SVARDOS=1`: SvarDOS) in QEMU with
an MBR partition (`SUPER=1`: superfloppy, `HIGH=DIR`: DEVICEHIGH with
HIMEM.SYS, EMM386.EXE and MEM.EXE from DIR, `OPTS=/C`: CHS reads) and
compares DIR, CD, TYPE and
COPY results.  `tests/dos_exfat_aspi.sh` uses EUSBASPI and ASPIDSK with a
removable USB stick and changes the medium exFAT -> FAT16 -> exFAT.
`tests/dos_exfat_lfn.sh` runs `tests/lfntest.c` (LFNTEST.EXE) for the
71xxh calls on MS-DOS 7.1 (`DOSLFN=file`: also with DOSLFN.COM loaded
after EXFAT.SYS).

Known: on SvarDOS the free space shown by DIR counts one sector per
cluster.
