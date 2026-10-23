# Future plans

Ideas that are planned but not started yet.  Remaining work on the existing
drivers is in [driver-status.md](driver-status.md).

## exFAT: EXFAT.SYS with ASPIDSK and ASPIFDD

Most USB sticks and SD cards larger than 32 GB come with exFAT.  DOS cannot
read it: a block device driver such as ASPIDSK only gets sector requests, and
the file system is interpreted by DOS itself, which knows FAT only.  So exFAT
needs a redirector (INT 2Fh, functions 11xxh), as SHSUCDX does for CD-ROMs,
while the sectors still come from the block driver.

    DOS  --"open F:\LETTER.TXT"-->  EXFAT.SYS   (redirector, knows exFAT)
                                        |
                                   "read sector n"
                                        v
                                    ASPIDSK.SYS  (sectors, media change)
                                        |
                                      ASPI  -->  EUSBASPI / AHCIASPI  -->  stick

    DEVICE=C:\OPENASPI\EUSBASPI.SYS
    DEVICE=C:\OPENASPI\ASPIDSK.SYS
    DEVICE=C:\OPENASPI\EXFAT.SYS

### The letter stays the one of ASPIDSK

1. ASPIDSK (or ASPIFDD) creates the drive letter, e.g. `F:`, as today.
2. A FAT medium works as today: DOS calls ASPIDSK.
3. On a medium with exFAT (partition type 07h with the OEM name `EXFAT   ` in
   its boot sector, or a superfloppy with exFAT) ASPIDSK gives DOS no FAT BPB
   and tells EXFAT.SYS.  EXFAT.SYS takes `F:` over: it marks the drive's
   entry in the DOS current directory structure (CDS) as redirected, as
   network drives and SHSUCDX do, and DOS sends every file request for `F:`
   to EXFAT.SYS.
4. EXFAT.SYS reads the sectors through an interface of ASPIDSK and gives DOS
   the files and directories.
5. When a FAT medium is inserted again, EXFAT.SYS gives `F:` back to ASPIDSK
   (CDS entry restored, DOS buffers and DPB of the drive invalidated).

### Interface of ASPIDSK and ASPIFDD

- a table of units with exFAT (device, start LBA, sector count, medium
  generation), filled at INIT and at every media check / BUILD BPB;
- read (and later write) sectors of a unit, through the existing ASPI path
  (READ(10)/WRITE(10), private stack, removable-media handling);
- a media-change query: while `F:` is redirected, DOS no longer calls the
  block driver's media check, so EXFAT.SYS asks before each access whether
  the medium is still the same (TEST UNIT READY / unit attention).

Reached through a generic IOCTL or a far entry point that EXFAT.SYS finds
from the device header.  EXFAT.SYS has no ASPI code of its own.

### EXFAT.SYS

- First version read-only: directories, open/read/seek/close, find
  first/next, file attributes and times, free space.
- exFAT names are long Unicode names without 8.3 names: EXFAT.SYS makes
  short names (`LETTER~1.TXT`) and converts the characters to the DOS code
  page (CP437/CP850, upcase table of the volume).  Long names later through
  INT 21h 71xxh (as DOSLFN) for DOS 7.
- Files of 4 GB and more cannot be opened by DOS: hidden or shown with their
  size cut, to be decided.
- Optional: exFAT partitions on BIOS disks (INT 13h extensions) found by
  EXFAT.SYS itself, with `/L:x` for the first letter.
- Writing as a second step: allocation bitmap, FAT chains and contiguous
  (NoFatChain) files, entry set checksums, directory growth.
- Clean-room implementation after the published Microsoft exFAT
  specification (2019).  Check the exFAT patent situation for a DOS driver
  before a release.

Tests: QEMU with EUSBASPI and a USB stick image made by `mkfs.exfat`
(superfloppy and partitioned), stick changes FAT <-> exFAT on the same
letter, MS-DOS 7.1 and FreeDOS.
