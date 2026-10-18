# Local reference and compatibility material

These paths are development inputs on the current machine.  They are not
dependencies of a source release and their binaries must not be copied into
OpenASPI packages unless redistribution rights are independently established.

## Free ASPI managers

- `/home/mario/mars/ahciaspi`: AHCI/IDE ATAPI ASPI manager, ASPI constants,
  `ASPITEST`, emulator tests, and the Adaptec ASPI for DOS specification.
- `/home/mario/mars/eusbaspi`: USB mass-storage ASPI manager, including
  manager chaining, hotplug behavior, `ASPITEST`, and `USBSYNC`.

OpenASPI must be tested as a normal client of both managers and of historical
Adaptec-compatible managers.  Shared protocol code may be imported later once
the OpenASPI license is selected; until then the sibling trees remain
read-only references.

## Historical binaries and media

The DOS archive is mounted as `/home/mario/Iso/Dos` (capital `I` and `D`), not
`/iso/dos` in the current environment.  Relevant examples include:

- `ez-scsi/ASPIDISK.SYS` and `ez-scsi/ASPICD.SYS`;
- compressed Adaptec ASPI manager files in `ez-scsi/`;
- `LS-120_IDE_KIT.zip`;
- `Zip_100_Parallel_Port-xp-2k.zip`, `zip100.rar`, `zipdrivers.rar`, and
  `zipdrivers100-250-95-98-parallel.zip`;
- `USBASPI.sys`, `USBASPIS.zip`, and `usbaspi-v2.20.zip`.

These are black-box compatibility fixtures.  Record hashes, command-line
options and observed behavior in test logs; do not check the binaries into the
OpenASPI repository.
