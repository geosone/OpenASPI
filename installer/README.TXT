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

The current ASPITAP.SYS is a non-functional loader skeleton. It rejects all
I/O and must not be used with valuable media.

The installer is the GeosOne DOS Installer: https://github.com/geosone/gdi
License: GNU General Public License version 3.
Source:  https://github.com/geosone/OpenASPI
