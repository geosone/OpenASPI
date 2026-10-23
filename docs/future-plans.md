# Future plans

Ideas that are planned but not started yet.  Remaining work on the existing
drivers is in [driver-status.md](driver-status.md).

## exFAT: EXFAT.SYS

Most USB sticks and SD cards larger than 32 GB come with exFAT.  DOS cannot
read it: a block device driver only gets sector requests, and the file system
is interpreted by DOS itself, which knows FAT only.  So exFAT needs a
redirector (INT 2Fh, functions 11xxh), as SHSUCDX does for CD-ROMs, while the
sectors still come from a disk driver.

EXFAT.SYS is a driver of its own and works without ASPI.  It has two sector
back ends:

- **BIOS disks (INT 13h, with the extensions for LBA)**: the general case.
  EXFAT.SYS looks for exFAT partitions itself and gives them their own drive
  letters (the next free ones, or the first from `/L:x`).  This covers
  disks, CF cards and USB sticks that the BIOS emulates as hard disks.
- **ASPIDSK and ASPIFDD**: the special case for OpenASPI.  The drive letter
  stays the one of ASPIDSK or ASPIFDD, and EXFAT.SYS takes it over while an
  exFAT medium is in (see below).

Neither back end needs the other: with only `DEVICE=EXFAT.SYS` the BIOS
disks are used; ASPIDSK or ASPIFDD loaded before it are found and used too.
No ASPI code is in EXFAT.SYS.

    DOS  --"open F:\LETTER.TXT"-->  EXFAT.SYS   (redirector, knows exFAT)
                                        |
                                   "read sector n"
                         +--------------+--------------+
                         v                             v
                   INT 13h (BIOS)              ASPIDSK / ASPIFDD
                                                       |
                                          ASPI  -->  EUSBASPI / AHCIASPI

    DEVICE=C:\DOS\EXFAT.SYS                    BIOS disks only

    DEVICE=C:\OPENASPI\EUSBASPI.SYS
    DEVICE=C:\OPENASPI\ASPIDSK.SYS
    DEVICE=C:\OPENASPI\EXFAT.SYS               BIOS disks and ASPIDSK

### BIOS disks

- Partition tables MBR (type 07h with the OEM name `EXFAT   ` in the boot
  sector) and GPT (basic data partitions), and superfloppies without a
  partition table.
- Each exFAT volume gets a drive letter at INIT; the CDS entry of the letter
  is marked as redirected (LASTDRIVE must be high enough).
- Removable media emulated by the BIOS (USB sticks) are read again when the
  boot sector serial number changes; the BIOS gives no reliable media change
  for hard disk emulation.
- `/X` leaves the BIOS disks out (only ASPIDSK/ASPIFDD).

### ASPIDSK and ASPIFDD: the letter stays theirs

1. ASPIDSK (or ASPIFDD) creates the drive letter, e.g. `F:`, as today.
2. A FAT medium works as today: DOS calls ASPIDSK.
3. On a medium with exFAT ASPIDSK gives DOS no FAT BPB and tells EXFAT.SYS.
   EXFAT.SYS takes `F:` over: it marks the drive's CDS entry as redirected,
   as network drives and SHSUCDX do, and DOS sends every file request for
   `F:` to EXFAT.SYS.
4. EXFAT.SYS reads the sectors through an interface of ASPIDSK and gives DOS
   the files and directories.
5. When a FAT medium is inserted again, EXFAT.SYS gives `F:` back to ASPIDSK
   (CDS entry restored, DOS buffers and DPB of the drive invalidated).

The interface of ASPIDSK and ASPIFDD:

- a table of units with exFAT (device, start LBA, sector count, medium
  generation), filled at INIT and at every media check / BUILD BPB;
- read (and later write) sectors of a unit, through the existing ASPI path
  (READ(10)/WRITE(10), private stack, removable-media handling);
- a media-change query: while `F:` is redirected, DOS no longer calls the
  block driver's media check, so EXFAT.SYS asks before each access whether
  the medium is still the same (TEST UNIT READY / unit attention).

Reached through a generic IOCTL or a far entry point that EXFAT.SYS finds
from the device header.

### Tools: EXFMT and EXCHK

DOS FORMAT and CHKDSK know FAT only, and they need a block device, which an
exFAT drive of EXFAT.SYS is not.  So exFAT gets its own two tools.  They
work like EXFAT.SYS without ASPI: they use the sector interface of
EXFAT.SYS, so BIOS disks and ASPIDSK/ASPIFDD media are handled the same way.

- **EXFMT**: creates exFAT (boot region with its backup and checksum,
  allocation bitmap, upcase table, root directory with volume label),
  cluster size by medium size as Windows does.  The target is an exFAT
  drive letter, a FAT drive (reformatted in its partition, as ASPIFMT does),
  or a blank medium: BIOS disk number (`/D:80`) or ASPIDSK/ASPIFDD letter.
  Like ASPIFMT: without `/YES` only the layout is shown; read check of the
  data area, bad clusters marked in the FAT and allocation bitmap.
- **EXCHK**: checks an exFAT volume: boot sector checksums, entry set
  checksums, allocation bitmap against the cluster chains, lost and cross
  linked clusters, the VolumeDirty flag.  First version only reports;
  `/F` repairs later, with the writing of EXFAT.SYS.
- While a tool writes, EXFAT.SYS locks the drive (no open files, caches
  flushed) and reads the volume again afterwards.
- ASPIFMT stays the FAT formatter for ASPIFDD; it can get `/FS:EXFAT`
  calling the same format code.

### The exFAT part

The same for both back ends; the back ends only give "read sector n of
volume v" and "has the medium changed".

- First version read-only: directories, open/read/seek/close, find
  first/next, file attributes and times, free space.
- exFAT names are long Unicode names without 8.3 names: EXFAT.SYS makes
  short names (`LETTER~1.TXT`) and converts the characters to the DOS code
  page (CP437/CP850, upcase table of the volume).  Long names later through
  INT 21h 71xxh (as DOSLFN) for DOS 7.
- Files of 4 GB and more cannot be opened by DOS: hidden or shown with their
  size cut, to be decided.
- Writing as a second step: allocation bitmap, FAT chains and contiguous
  (NoFatChain) files, entry set checksums, directory growth.
- Tools that read sectors themselves (CHKDSK, SCANDISK, DEFRAG) do not work
  on the drive, as on CD-ROM drives; EXFMT and EXCHK take their place.
- No exFAT in a DOS kernel: EXFAT.SYS works with every DOS that has a
  redirector interface (MS-DOS 5 and later, FreeDOS, EDR-DOS).
- Clean-room implementation after the published Microsoft exFAT
  specification (2019).  Check the exFAT patent situation for a DOS driver
  before a release.

Release: EXFAT.SYS, EXFMT and EXCHK are part of the OpenASPI release, and
the release files also get a separate exFAT package for systems without
ASPI.  Like every package it comes with the GeosOne DOS Installer: an
`exfat-<version>.zip` with INSTALL.EXE and its own INSTALL.INI (Id=EXFAT,
default directory `%BOOT%\EXFAT`, the DEVICE line in CONFIG.SYS with `/L:x`
and `/X` as options), plus the disk images as for OpenASPI.  In the
OpenASPI installer exFAT is one more option (EXFAT.SYS after ASPIDSK and
ASPIFDD in CONFIG.SYS); both installers install the same files, so the
exFAT package can later be replaced by OpenASPI and the other way round.

Tests: QEMU with an exFAT disk image made by `mkfs.exfat` (MBR, GPT and
superfloppy) as IDE disk and USB stick through the BIOS, without ASPI; then
with EUSBASPI and ASPIDSK, stick changes FAT <-> exFAT on the same letter;
MS-DOS 7.1, FreeDOS and EDR-DOS.

## ASPICHK and DEFRAG for all FAT variants

DOS 7.1 has CHKDSK and SCANDISK but no DEFRAG any more (the DEFRAG of
Windows 98 runs in Windows only), and the DOS tools stop at the limits of
their DOS version.  OpenASPI gets its own two tools, even though DOS has a
checker:

- **ASPICHK**: checks FAT12, FAT16 and FAT32: boot sector and BPB, both FAT
  copies against each other, cluster chains (lost, cross linked, loops),
  directory entries and VFAT long name entries (checksums, orphans), file
  sizes against chains, FAT32 FSInfo free counts.  Reports first, repairs
  with `/F`.  Works on every DOS drive (absolute disk read/write, INT 25h/
  26h and INT 21h 7305h for FAT32), and on ASPIDSK/ASPIFDD media through
  their raw-media service, also when DOS has not mounted them.
- **DEFRAG**: defragments FAT12, FAT16 and FAT32 (and exFAT through the
  sector interface of EXFAT.SYS once that can write): files contiguous,
  directories first, free space at the end, optionally sorted directories.
  Safe against power loss: data is copied first, the FAT and the directory
  entry are changed after, both FAT copies, a journal of the current move.
  Text UI like MS DEFRAG (cluster map).

Both are adapted from existing free code instead of written new:

| Source | License | Use |
|---|---|---|
| FreeDOS DEFRAG 1.3.1 (Imre Leber), with its FAT transformation engine | GPL | DEFRAG; the engine is shared with FreeDOS CHKDSK and RECOVER |
| FreeDOS CHKDSK (Imre Leber) | GPL | ASPICHK, same engine |
| dosfsck 2.11 (FreeDOS port, Eric Auer) / fsck.fat of dosfstools 4.x | GPL v2 / GPL v3 or later | ASPICHK checks and repairs, FAT32 |
| exfatprogs (mkfs.exfat, fsck.exfat) | GPL v2 or later | EXFMT and EXCHK |

OpenASPI is GPL version 3: code under "GPL v2 only" cannot be taken over,
"v2 or later" can.  The license text in each source archive has to be
checked before anything is copied (the project pages are not enough).

Tests: QEMU disk images made by `mkfs.fat` with fragmented files (written
and deleted in turns), checked by `fsck.fat` on the host after DEFRAG and
after ASPICHK `/F`; power loss in the middle of a DEFRAG (QEMU stopped) and
ASPICHK afterwards.

Release: both in the OpenASPI release and its installer (options ASPICHK
and DEFRAG, no CONFIG.SYS line).
