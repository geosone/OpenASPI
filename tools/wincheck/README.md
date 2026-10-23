# WINCHECK

OpenASPI ships two environment probes with platform-specific selectors:

- `WINCHECK.COM` runs in DOS or a Windows DOS box. `/DOS`, `/WIN`, `/3X` and
  `/9X` select the requested environment; `/Q` suppresses output. Exit status
  zero means a match and one means a different environment.
- `WINCHECK.EXE` is a real 16-bit Windows application. `/3X` and `/9X` return
  the equivalent result through the Windows version API. With no arguments it
  displays the detected Windows family.

The DOS installer invokes the `.COM` file explicitly because it must also work
outside Windows. The Win16 executable supplies native Windows-family detection
for setup; it is not the graphical installer itself. GDI provides the shared
DOS/Win16 installer frontend. Neither detector contains installer policy;
`INSTALL.INI` decides which result selects which files.
