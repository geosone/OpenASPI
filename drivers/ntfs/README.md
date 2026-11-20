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
- compressed files (NTFS compression, LZNT1), decompressed 4 KB at a time
  in the index block buffer;
- names: the 8.3 name Windows gave a file (its DOS name), else an 8.3 name
  in the DOS code page (437, or 850 when that is active): as much of the
  name as fits, "~" and the file's MFT record number in base 36
  (`EINLA~5E.TXT`).  Unique, the same on every run, and found without a
  search of the directory; the system files ($MFT ...) are not shown;
- the volume label (`VOL`, `DIR`) and the free space.

Not (yet): encrypted files ("access denied"), writing (creating, deleting, renaming, writing
give "access denied"), ASPIDSK/ASPIFDD units without `/I13`, sectors other
than 512 bytes.  A volume Windows left without unmounting (hibernation,
fast startup) is read anyway; the start message says "not cleanly
unmounted", and what Windows still had in its log is missing.

## Long file names: NTFSL.SYS

NTFSL.SYS is the same driver with the long file names of Windows 95 and
DOSLFN (INT 21h AX=71xxh) for its drives, read-only, as EXFATL.SYS has them
for exFAT: find (714Eh, 714Fh, 71A1h), open (716Ch), change and current
directory (713Bh, 7147h), attributes, size and times (7143h), TRUENAME
(7160h), volume information (71A0h, "NTFS"), file information by handle
(71A6h) and the time conversion (71A7h).  Paths may use the long names and
the 8.3 names of NTFS.SYS.  Making, removing, deleting, renaming and setting
attributes give "access denied".  The calls for other drives go on to DOS,
or to DOSLFN when it is loaded after NTFSL.SYS (`DOSLFN -f-`, which then
gives the FAT drives long names too).  COMMAND.COM of MS-DOS 7 then shows
the long names in DIR.  It takes about 9 KB more than NTFS.SYS.

NTFS.SYS stays resident with about 36 KB, 13 KB of which are buffers for
MFT records and index blocks.  The NTFS part is OpenFileSystem's `src/ntfs/ntfs.c`
(ntfs-3g's `layout.h` is the reference for the structures); the assembler
frame is EXFAT.SYS's (`drivers/exfat/exfatsys.asm`, built with `NTFS_SYS`).

Tests: `tests/dos_ntfs.sh` (MS-DOS 7.1, SvarDOS with `SVARDOS=1`, `OPTS=/C`),
`tests/dos_ntfs_lfn.sh` (NTFSL.SYS, `DOSLFN=` DOSLFN.COM)
with an IDE disk from OpenFileSystem's `tests/ntfs_image.sh` and a USB disk through
EUSBASPI and `ASPIDSK /I13`; OpenFileSystem's `tests/ntfs_host.sh` checks the
library on the host.
