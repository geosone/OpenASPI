# Public interfaces

These headers define shared contracts used by drivers, tools and protocol
consumers. They do not all describe the same transport or memory layout.

| Header | Boundary |
| --- | --- |
| [`types.h`](types.h) | Fixed-width scalar types for host tests and 16-bit DOS builds. |
| [`aspi.h`](aspi.h) | Packed DOS ASPI SRBs, status/direction codes and FAR pointer fields. |
| [`aspitape.h`](aspitape.h) | Packed historical category-07h controls and distinct 14/16-byte status layouts. |
| [`tape_api.h`](tape_api.h) | Native OTAP v1 packets, capabilities, completion facts and construction/validation helpers. |
| [`scsi_tape.h`](scsi_tape.h) | Portable six-byte CDB builders and decoded sense; no submission. |
| [`raw_media.h`](raw_media.h) | DOS RAW1 client/session state and physical-sector operations. |
| [`fat_format.h`](fat_format.h) | Host-side FAT layout and metadata builders; no I/O. |
| [`rescue.h`](rescue.h) | Bounded reader/error-report callbacks and conservative rescue policy. |

Packed DOS packets use little-endian scalar fields. SCSI CDB/sense multi-byte
fields use their wire byte order and explicit encoding/decoding. A FAR pointer
is offset then segment, not a host C pointer. Host-side layout/client structures
are not automatically packed wire packets.

Use initialization helpers before submission and validate returned native
packets before consuming result/validity fields. Valid packet syntax is distinct
from successful hardware I/O. Keep SRB/transfer memory alive through manager
completion; keep an acquired raw/native session until explicit cleanup.

Assembly mirrors live in `common/aspi/dos_aspi.inc`,
`common/aspi/native_tape_defs.inc` and the resident DOS drivers. ABI tests include
[`test_aspi.c`](../../tests/test_aspi.c) and [`tape_abi.c`](../../tests/tape_abi.c).
`make check` checks host layouts and compiles the tape ABI as 16-bit DOS code.
Windows bindings must define their own layouts rather than cast DOS SRBs.
