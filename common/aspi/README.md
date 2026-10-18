# Shared ASPI layer

`dos_aspi.inc` defines the ASPI for DOS SRB offsets and constants used by the
8086 assembly clients.  `include/openaspi/aspi.h` is the matching packed C
contract, with host tests asserting every important size and offset.

`ASPISCAN.COM` and `ASPITAP.SYS` now implement manager discovery through
`SCSIMGR$`, synchronous submission, host/target/LUN enumeration and device-type
selection.  Manager chaining remains the manager's responsibility: a client
sees the combined adapter numbers advertised by the active `SCSIMGR$`.

Pending work includes a bounded elapsed-time policy, reusable execute-SCSI
helpers for resident drivers, and completion posting where asynchronous I/O is
useful.

AHCIASPI and EUSBASPI provide the first free manager implementations used for
integration tests.  The layer must also remain compatible with historical
Adaptec managers.
