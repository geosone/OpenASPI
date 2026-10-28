OpenASPI exFAT 0.3 - exFAT drives for DOS
==========================================

  EXFAT.SYS  exFAT volumes as DOS drives (read only)
  EXFMT.EXE  formats exFAT
  EXCHK.EXE  checks and repairs exFAT

EXFAT.SYS is a redirector: it works with every DOS that has one (MS-DOS 5
and later, FreeDOS, EDR-DOS). It finds exFAT volumes on the BIOS disks
(superfloppy or MBR partition of type 07h) and, with OpenASPI, the exFAT
media of ASPIDSK.SYS and ASPIFDD.SYS, also when a medium is changed. It
needs about 14 KB (22 KB with long file names) and can be loaded high:

  DEVICE=C:\EXFAT\EXFAT.SYS [/L:x] [/Q] [/C]

  /L:x  first drive letter to use (default: the first free one)
  /Q    no messages
  /C    BIOS disks through CHS only, without the INT 13h extensions

With OpenASPI, EXFAT.SYS must come after ASPIDSK.SYS and ASPIFDD.SYS.
DOS shows long names as 8.3 names (LETTER~1.TXT) in code page 437 or 850.
With the setup option "Long file names" (EXFATL.SYS, installed as
EXFAT.SYS), programs for long file names (INT 21h AX=71xxh, as with DOSLFN
or Windows 95: the DIR of MS-DOS 7, file managers) see the long names;
DOSLFN may be loaded after EXFAT.SYS for the other drives.
Writing, creating, deleting and renaming give "access denied". Files of
4 GB and more show the size FFFFFFFFh. CHKDSK, SCANDISK and DEFRAG do not
work on the drives; EXFMT and EXCHK take their place.

EXFMT d: | /D:nn [/P:n | /WHOLE] [/V:label] [/A:size] [/TEXFAT] [/Q] [/YES]
formats a drive of EXFAT.SYS, ASPIDSK or ASPIFDD, or BIOS disk nn (80 =
the first hard disk). Without /YES only the layout is shown. The volume is
the drive's partition, partition n with /P:n, the whole medium with /WHOLE.
The data area is read first (not with /Q) and unreadable clusters are
marked bad. /TEXFAT writes two FATs and allocation bitmaps: worth it for
old ZIP and SuperDisk media, EXCHK /F repairs a damaged chain from the
second copy. On a BIOS disk a FAT partition must be named with /P:n.

EXCHK d: [/F] checks a drive of EXFAT.SYS: boot region and its backup,
checksums and name hashes of all directory entries, cluster chains against
the allocation bitmap. /F repairs what can be repaired and shows each
repair. Exit codes: 0 no errors, 1 errors, 2 wrong use, 3 read error.

This package and the exFAT option of OpenASPI install the same files. With
OpenASPI installed, use its exFAT option instead (this setup warns). To go
over to OpenASPI, remove this package first with INSTALL /U in C:\EXFAT:
INSTALL /U removes every EXFAT.SYS line from CONFIG.SYS, also one written
by OpenASPI's setup (run that setup again then).

The installer is the GeosOne DOS Installer: https://github.com/geosone/gdi
License: GNU General Public License version 3.
Source:  https://github.com/geosone/OpenASPI
