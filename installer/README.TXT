OpenASPI 0.1 - open ASPI device drivers for DOS
================================================

OpenASPI is a free DOS driver suite for devices reached through an installed
ASPI manager. The planned drivers are:

  ASPIDSK.SYS  disks and disk-style devices
  ASPIFDD.SYS  LS-120/240, ZIP, Clik! and removable media
  ASPICDA.SYS  CD/DVD and digital CD audio
  ASPITAP.SYS  SCSI tape, compatible with the ASPITAPE interface

Place an ASPI manager such as AHCIASPI, EUSBASPI or an Adaptec manager before
these drivers in CONFIG.SYS. Run INSTALL.EXE to install or update OpenASPI.
Run INSTALL /U from the installation directory to remove it.

ASPISCAN.COM lists the active ASPI adapters and devices and identifies tape
devices without reading or changing their media. During setup it is also run
quietly to preselect Tape, Disk, removable-media and CD/DVD components from
the devices actually reported by the active ASPI manager. You can change every
suggested selection before installation.

TAPECTL.COM opens NRMT0 in raw mode and reports the ASPITAPE-compatible status
block. TAPECTL /READY additionally sends the non-destructive TEST UNIT READY
command.

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
shown in hexadecimal. The historical -b, -w and -i switches are not implemented.
Only one tape drive is exposed; medium-changer/library control is not part of
this stage. The write path is not yet qualified for production backups on real
media. Closing a written session adds two terminating filemarks; NRMT0 then
backspaces one mark, while RMT0 rewinds.

The installer is the GeosOne DOS Installer: https://github.com/geosone/gdi
License: GNU General Public License version 3.
Source:  https://github.com/geosone/OpenASPI
