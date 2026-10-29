# EXFAT.SYS

exFAT drives for DOS, read and write.  DOS knows FAT only, so EXFAT.SYS works as
a network redirector (INT 2Fh AH=11h), as MSCDEX and SHSUCDX do for CD-ROMs:
the drive gets its own letter and DOS sends every file request for it to
EXFAT.SYS.  It needs no ASPI.

```dos
DEVICE=C:\DOS\EXFAT.SYS [/L:x] [/Q] [/C] [/R]
LASTDRIVE=Z
```

- `/L:x` first drive letter to use (default: the first free one)
- `/Q` no messages
- `/C` BIOS disks through CHS only, without the INT 13h extensions (for
  BIOSes with faulty extensions; only the first 8 GB are reachable)
- `/R` read-only: writing, creating, deleting and renaming give "access
  denied"

EXFAT.SYS stays resident with about 24 KB; it loads high with
`DEVICEHIGH`.  The same source built with `EXFAT_LFN` is `EXFATL.SYS`
(about 34 KB) with the long file names below; setup installs one of the
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
  mix long and 8.3 names.  Also the calls that write: make and remove
  directories (7139h, 713Ah), delete (7141h, also by a pattern), rename
  and move (7156h), create with a long name (716Ch), set attributes and
  times (7143h).
  Other drives go on to the next handler, so DOSLFN loaded after
  EXFAT.SYS gives them long names; on MS-DOS 7 COMMAND.COM's DIR shows
  the long names.
- Subdirectories show `.` and `..` as on FAT.
- TexFAT volumes (two FATs and allocation bitmaps) are read through the
  active FAT and bitmap (ActiveFat of the boot sector); writing changes
  both copies alike.
- Writing: files are created, written, extended and cut (also over their
  valid data length), deleted (also by a pattern) and renamed (also into
  another directory); directories are made, removed (empty only) and
  renamed; attributes and times are set (COPY keeps the time of the file).
  Contiguous files stay without FAT chain while they can, and get one
  when they cannot grow in place.  The order is allocation bitmap, FAT,
  data and the directory entry last, so a crash loses clusters at most;
  the VolumeDirty flag is set while a change is under way and cleared when
  it is done, also the PercentInUse field is kept.  Read-only files and
  non-empty directories cannot be removed; a medium that is write
  protected gives the DOS error "write protect".  No retries: an error is
  reported as it is.
- Files of 4 GB and more are shown with the size FFFFFFFFh; only their
  first 4 GB can be read.
- CHKDSK, SCANDISK and DEFRAG do not work on the drive (as on CD-ROM
  drives); [EXCHK](../../tools/exchk/README.md) checks it,
  [EXFMT](../../tools/exfmt/README.md) formats it.

The exFAT code is `common/exfat/exfat.c` (after the Microsoft exFAT file
system specification), shared with the host test and the tools to come.
Plans: [future plans](../../docs/future-plans.md).

Tests: `build/host/test_exfat` (8.3 names; with an image it lists and reads
it), `tests/exfat_image.sh` makes images through the Linux exFAT driver,
`tests/exfat_write.sh` changes images with the write code on the host
(`tests/exfat_write_test.c`, also TexFAT and a full volume) and checks
them with fsck.exfat and the Linux exFAT driver,
`tests/dos_exfat_write.sh` writes through EXFAT.SYS under MS-DOS 7.1
(`SVARDOS=1`, `TEXFAT=0|1`, `OPTS=/R`, `LFN=1`: EXFATL.SYS, `HIGH=DIR`:
DEVICEHIGH) with COPY, MD, RD, REN, DEL, ">>" and 6C00h, and checks the
result on the host,
`tests/dos_exfat.sh` boots MS-DOS 7.1 (`SVARDOS=1`: SvarDOS) in QEMU with
an MBR partition (`SUPER=1`: superfloppy, `HIGH=DIR`: DEVICEHIGH with
HIMEM.SYS, EMM386.EXE and MEM.EXE from DIR, `OPTS=/C`: CHS reads) and
compares DIR, CD, TYPE and
COPY results.  `tests/dos_exfat_aspi.sh` uses EUSBASPI and ASPIDSK with a
removable USB stick and changes the medium exFAT -> FAT16 -> exFAT.
`tests/dos_exfat_lfn.sh` runs `tests/lfntest.c` (LFNTEST.EXE) for the
71xxh calls on MS-DOS 7.1, also the writing ones (`DOSLFN=file`: also
with DOSLFN.COM loaded after EXFAT.SYS).

Known: on SvarDOS the free space shown by DIR counts one sector per
cluster.
