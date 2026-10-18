# Architecture

OpenASPI is split into protocol code, DOS integration, drivers, and tools.

```text
OpenASPI/
|-- common/
|   |-- aspi/          shared ASPI-manager access
|   |-- dos/           shared DOS driver support
|   `-- scsi/          portable SCSI command and sense handling
|-- include/openaspi/ public ABI and protocol headers
|-- drivers/
|   |-- aspidsk/       fixed and generic direct-access media
|   |-- aspifdd/       LS-120/240, ZIP, Clik and similar media
|   |-- aspicda/       CD/DVD plus digital audio support
|   `-- aspitap/       sequential-access tape devices
|-- tools/
|   |-- tapectl/       planned diagnostic/control utility
|   `-- wincheck/      DOS and Win16 environment probes
`-- tests/             host-side protocol tests
```

`ASPITAP.SYS` talks to an already installed DOS ASPI manager.  It owns device
enumeration, buffering, SCSI command submission, request completion, and the
ASPITAPE compatibility ABI.  It does not implement backup formats.

The sibling OpenTape project owns backup, restore, verification, cataloguing,
and the user interface.  Its first backend uses only the historical character
device contract so the same executable can operate with either `ASPITAP.SYS`
or a compatible historical `ASPITAPE.SYS`.  A direct-ASPI backend is optional
and must remain separate from that compatibility backend.

AHCIASPI and EUSBASPI remain independent ASPI managers.  OpenASPI is their
client, just as it is a client of an Adaptec or other compatible manager.  The
driver suite must never depend on manager-specific identity strings for normal
operation.

The planned Windows 9x port uses a different operating-system integration
boundary.  Its preferred design follows the Adaptec miniport model: an
`OAHCI.MPD` hardware miniport is shared by native Windows storage and the ASPI
application interface through the installed Windows SCSI/IOS stack.  See
[windows9x-storage.md](windows9x-storage.md) for the component split, staged
ASPI-runtime plan, compatibility with official vendor miniports and the
controller-ownership rule.

## Compatibility boundary

The portable ABI header describes byte-exact parameter blocks.  DOS interrupt
wrappers belong in OpenTape or command-line tools, not in the portable SCSI
layer.  The driver converts compatibility operations into SCSI CDBs and maps
sense results back to DOS errors and `mtget` state.
