# NTFS.SYS

NTFS drives for DOS, read-only.  Like EXFAT.SYS it is a network redirector
(INT 2Fh AH=11h): every NTFS volume gets a drive letter of its own, and DOS
sends the file requests for it to NTFS.SYS.

```dos
DEVICE=C:\DOS\NTFS.SYS [/L:x] [/Q] [/C] [/Z:h]
LASTDRIVE=Z
```

- `/L:x` first drive letter to use (default: the first free one)
- `/Q` no messages
- `/C` BIOS disks through CHS only, without the INT 13h extensions
- `/Z:h` time zone: NTFS keeps the times in UTC; `/Z:1` shows them one hour
  later (CET), `/Z:-5` five hours earlier, `/Z:5:30` with minutes

NTFS.SYS reads the volumes through INT 13h: on the BIOS hard disks and on
the USB, SCSI and other ASPI disks that `ASPIDSK.SYS /I13` makes BIOS disks
(load NTFS.SYS after ASPIDSK).  It finds superfloppies, MBR partitions of
type 07h (primary and logical) and GPT basic data partitions, up to eight
volumes.  The letters are taken when the first program starts, as with
EXFAT.SYS; LASTDRIVE must leave free letters.  EXFAT.SYS and NTFS.SYS can be
loaded together: type 07h is used by both, each takes its own volumes.

What it reads:

- directories of any size (the $I30 index with its index blocks), files
  in many pieces (also with an attribute list), sparse files (the holes
  are zeros), small files kept in the MFT record;
- names: the 8.3 name Windows gave a file (its DOS name), else an 8.3 name
  made as EXFAT.SYS does (`EINLAN~1.TXT`) in the DOS code page (437, or 850
  when that is active); the system files ($MFT ...) are not shown;
- the volume label (`VOL`, `DIR`) and the free space.

Not (yet): compressed and encrypted files ("access denied"), long file
names (INT 21h AX=71xxh), writing (creating, deleting, renaming, writing
give "access denied"), ASPIDSK/ASPIFDD units without `/I13`, sectors other
than 512 bytes.  A volume Windows left without unmounting (hibernation,
fast startup) is read anyway; the start message says "not cleanly
unmounted", and what Windows still had in its log is missing.

NTFS.SYS stays resident with about 32 KB, 13 KB of which are buffers for
MFT records and index blocks.  The NTFS part is openfat's `src/ntfs/ntfs.c`
(ntfs-3g's `layout.h` is the reference for the structures); the assembler
frame is EXFAT.SYS's (`drivers/exfat/exfatsys.asm`, built with `NTFS_SYS`).

Tests: `tests/dos_ntfs.sh` (MS-DOS 7.1, SvarDOS with `SVARDOS=1`, `OPTS=/C`)
with an IDE disk from openfat's `tests/ntfs_image.sh` and a USB disk through
EUSBASPI and `ASPIDSK /I13`; openfat's `tests/ntfs_host.sh` checks the
library on the host.
