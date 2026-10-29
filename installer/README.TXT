OpenASPI 0.1 - open ASPI device drivers for DOS
================================================

OpenASPI is a free DOS driver suite for devices reached through an installed
ASPI manager. The drivers are:

  ASPIDSK.SYS  disks and disk-style devices
  ASPIFDD.SYS  LS-120/240, ZIP, Clik! and removable media
  ASPICDA.SYS  CD/DVD and digital CD audio
  ASPITAP.SYS  SCSI tape, compatible with the ASPITAPE interface

SHSUCDX.COM and CDAUDIO.COM are included for the CD/DVD redirector and CD
audio mode selection. SHSUCD.LIC contains the upstream license notice and
SHSUCD.TXT its documentation.

Place an ASPI manager such as AHCIASPI, EUSBASPI or an Adaptec manager before
these drivers in CONFIG.SYS. Run INSTALL.EXE to install or update OpenASPI.
The drivers go to C:\OPENASPI (shared with AHCIASPI and EUSBASPI); run
INSTALL /U in C:\OPENASPI\ASPI to remove OpenASPI.

ASPISCAN.COM lists the active ASPI adapters and devices and identifies tape
devices without reading or changing their media. During setup it is also run
quietly to preselect Tape, Disk, removable-media and CD/DVD components from
the devices actually reported by the active ASPI manager. You can change every
suggested selection before installation.

ASPIMGR.EXE provides the shared Open386MAX-style DOS interface for all ASPI
adapters and devices. Use Up/Down to select, R to scan again and Esc to exit.
ASPIMGR /TEXT prints an inventory suitable for redirection. This first version
shows device information; formatting and media actions are not implemented.

ASPICTL EJECT|CLOSE|LOCK|UNLOCK|STATUS X: controls the installed driver.
EJECT/CLOSE/LOCK/UNLOCK/STATUS.EXE are copies of the same program.
Each command also works directly, for example EJECT F: or LOCK F:.
EJECT /FORCE releases media locks before ejecting (EJECT F: /FORCE).
Hardware errors still fail the operation. CLOSE applies only to CD drives.

ASPIFMT D: previews an ASPIFDD medium; /YES creates FAT12/16 and scans
data sectors, marking unreadable clusters bad. /FAT:32 needs FAT32 DOS support.
ASPIDD D: E: copies equal-sized media; ASPIDD D: uses a temporary image and
prompts for exchange. /RESCUE records unreadable sectors and fills them with
zeros (exit status 3). ASPIDDG adds the shared DOS progress/selection UI.
See tools/aspifmt/README.md and tools/aspidd/README.md in the source tree.

EXFAT.SYS (setup option "exFAT drives") gives exFAT volumes drive letters:
BIOS disks, and the exFAT media of ASPIDSK and ASPIFDD (USB sticks, ZIP).
It reads and writes (/R: read-only). It needs about 24 KB and can load
high; the option "exFAT with long file names" installs it with the long
names for LFN programs (about 34 KB). EXFMT D:
formats a drive as exFAT (layout only without /YES; /TEXFAT keeps two FATs,
worth it for old ZIP and SuperDisk media), EXCHK D: checks it and
EXCHK D: /F repairs it.

ASPICHK and DEFRAG (setup option "FAT tools") work on every FAT12, FAT16
and FAT32 drive, and on ASPIDSK/ASPIFDD media also when DOS has not mounted
them. ASPICHK D: checks a drive, ASPICHK D: /F repairs it. DEFRAG D:
defragments it (files contiguous, directories first, free space at the
end; /U only joins fragmented files, /A analyzes, /B without the screen).
DEFRAG checks the drive first and moves whole files in an order that is
safe against power loss: after an interruption ASPICHK D: /F repairs the
drive without losing data.

TAPECTL.COM opens NRMT0 in raw mode and reports the ASPITAPE-compatible status
block. TAPECTL /READY additionally sends the non-destructive TEST UNIT READY
command.

TAPECTL exit status: 0 = queried, 1 = query/readiness error, 2 = saved write
failure. Successful readiness does not confirm that earlier writes succeeded.
Warning fields describe the saved failure; the tool does not perform recovery.
For renamed drivers, use TAPECTL /DEVICE:NRST0$ (or the configured non-rewinding
name). Rewinding aliases and paths are rejected; the default remains NRMT0.

OTAPINFO.EXE queries the new native tape API. Without options it sends no
SCSI command; /REFRESH requests identity, record limits and optional mode
pages without moving or writing the tape. Missing capabilities remain unknown.
Exit 0 means query completed, 1 means usage/DOS/API failure, and 2 means a
partial/busy query or a retained write failure. See docs/native-tape-query.md
in the source tree.

WINCHECK.COM distinguishes DOS, a Windows 3.x DOS box and Windows 9x/ME for
conditional setup choices. WINCHECK.EXE is the companion 16-bit Windows probe
for Windows-specific installation choices.

There is only one dual-mode INSTALL.EXE. Under DOS it starts the DOS setup;
from Windows 3.1 or Windows 95/98/ME the same file opens the native Win16
component-selection window. It uses the standard Windows API without MFC or
another UI framework. Automatic choices remain assigned to the package's DOS
detectors; the embedded DOS engine performs the transactional installation.

The current ASPITAP.SYS finds the first ASPI tape and installs RMT0 and NRMT0.
Variable-block reads and writes, status, readiness, forward/backward spacing,
rewind, unload and explicit filemark controls work. Short-record ILI, filemark
EOF, write protection, fixed/descriptor sense and the selectable EOM policy are
supported. Fixed-block drives are detected with READ BLOCK LIMITS and use their
required block size.
Tape data transfer requires one exclusive open handle and DOS raw mode;
single-byte cooked-mode requests are rejected by default. Add -m to the
ASPITAP.SYS CONFIG.SYS line to permit multiple-open transfers, and -s to permit
single-byte transfers. The -tX option replaces the M in the device names with
letter X; -$ appends a collision-avoiding dollar sign.
Malformed or unsupported options stop the driver from loading and print an
error. Use -v (or -d) for adapter, tape, block-mode and device-name details
during loading, including discovery failure reasons. Fixed block sizes are
shown in hexadecimal. Add -b for MT0/NMT0 software-buffered aliases: physical
transfers use 1024-byte records and close zero-pads a partial written record.
Tape-moving controls discard the cache, including pending written bytes.
Do not mix raw and buffered data access within a session. Check tape status
for delayed write errors, since DOS may ignore a failed device-close request.
Only one tape drive is exposed; medium-changer/library control is not part of
this stage. The write path is not yet qualified for production backups on real
media. Closing a written session adds two terminating filemarks; NRMT0 then
backspaces one mark, while RMT0 rewinds.
RMT0 normally starts rewind and returns; status reports rewind pending. Later
tape I/O waits for readiness for up to about three minutes. Add -w to the
CONFIG.SYS line to wait for rewind completion during close instead.
Add -i to allow Ctrl-Break to abort a pending rewind readiness wait. Rewind
remains pending and a later request can retry; the physical rewind continues.

The installer is the GeosOne DOS Installer: https://github.com/geosone/gdi
License: GNU General Public License version 3.
Source:  https://github.com/geosone/OpenASPI
