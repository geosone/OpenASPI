# Architecture

OpenASPI is split into protocol code, DOS integration, drivers, and tools.

```text
OpenASPI/
|-- common/
|   |-- aspi/          shared ASPI-manager access
|   |-- dos/           shared DOS driver support
|   |-- scsi/          portable SCSI command and sense handling
|   `-- tape/          native tape packet construction and validation
|-- include/openaspi/ public ABI and protocol headers
|-- drivers/
|   |-- aspidsk/       fixed and generic direct-access media
|   |-- aspifdd/       LS-120/240, ZIP, Clik and similar media
|   |-- aspicda/       CD/DVD plus digital audio support
|   `-- aspitap/       sequential-access tape devices
|-- tools/
|   |-- aspictl/       drive-letter media controls and command aliases
|   |-- aspidd/        sector imaging/copying and DOS copy UI
|   |-- aspifmt/       FAT formatting and bad-cluster marking
|   |-- aspimgr/       DOS ASPI inventory UI
|   |-- aspiscan/      installer-facing device detection
|   |-- otapinfo/      native tape capability/session diagnostic
|   |-- tapectl/       legacy tape status/readiness diagnostic
|   `-- wincheck/      DOS and Win16 environment probes
`-- tests/             host, assembly-fixture and DOS integration tests
```

`ASPITAP.SYS` talks to an already installed DOS ASPI manager.  It owns device
enumeration, buffering, SCSI command submission, request completion, and the
ASPITAPE compatibility ABI.  It does not implement backup formats.

The sibling OpenTape project owns backup, restore, verification, cataloguing,
and the user interface. Legacy ASPITAPE compatibility and native OTAP packets
are separate interfaces: legacy I/O retains historical EOF/close behavior;
native calls expose explicit record counts, stream conditions and writer
ownership. The DOS native provider remains part of ASPITAP, not another ASPI
manager. See [native-tape-api.md](native-tape-api.md).

Backup framing and archive-format policy belong to OpenTape. OpenASPI transfers
records and exposes controls/capabilities; it does not parse TAR, LTFS or
Bacula-style archive metadata. Optional positioning, partitioning or device
features need an implemented and qualified interface before an archive backend
can rely on them. A format requirement is not proof that a transport operation
or a particular drive already supports it.

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


## Reading the implementation

The [source guide](source-guide.md) follows block, CD and tape requests through
validation, transport and completion. It maps resident state, buffer ownership,
error reporting and the corresponding tests. Local comments explain the wire
fields and arithmetic at their use sites; the per-interface documents define
the external contracts.
