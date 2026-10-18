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

WINCHECK.COM distinguishes DOS, a Windows 3.x DOS box and Windows 9x/ME for
conditional setup choices. WINCHECK.EXE is the companion 16-bit Windows probe
for Windows-specific installation choices.

There is only one dual-mode INSTALL.EXE. Under DOS it starts the DOS setup;
from Windows 3.1 or Windows 95/98/ME the same file opens the native Win16
component-selection window. It uses the standard Windows API without MFC or
another UI framework. Automatic choices remain assigned to the package's DOS
detectors; the embedded DOS engine performs the transactional installation.

The current ASPITAP.SYS finds the first ASPI tape and installs RMT0 and NRMT0.
Status and TEST UNIT READY controls work, but data I/O and positioning are
still rejected. It must not yet be used for backup or restore.

The installer is the GeosOne DOS Installer: https://github.com/geosone/gdi
License: GNU General Public License version 3.
Source:  https://github.com/geosone/OpenASPI
