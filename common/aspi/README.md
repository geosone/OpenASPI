# Shared ASPI layer

These helpers translate checked driver requests into DOS ASPI operations.
They do not replace the installed host-adapter manager or its command timeouts.
AHCIASPI, EUSBASPI and historical Adaptec managers remain transport providers.
Manager chaining belongs to the active `SCSIMGR$`; clients see its combined
adapter numbering.

| File | Responsibility |
| --- | --- |
| [`dos_aspi.inc`](dos_aspi.inc) | SRB offsets/constants matching the packed C definitions in [`aspi.h`](../../include/openaspi/aspi.h). |
| [`aspi_init.inc`](aspi_init.inc) | Transient manager discovery and host/target/LUN enumeration for block/CD drivers. |
| [`aspi_client.inc`](aspi_client.inc) | Resident SRB preparation, synchronous submission and checked completion/autosense. |
| [`removable.inc`](removable.inc) | Shared disk/FDD ownership classification from checked INQUIRY identity. |
| [`media_control.inc`](media_control.inc) | No-data START STOP / PREVENT ALLOW submission; callers own state/error policy. |
| [`tape_sense.inc`](tape_sense.inc) | Resident ASPITAP completion and bounded fixed/descriptor sense decoding. |
| [`native_tape_defs.inc`](native_tape_defs.inc) | Native QUERY/CONTROL/record packet offsets matching [`tape_api.h`](../../include/openaspi/tape_api.h). |
| [`native_tape.inc`](native_tape.inc) | Native packet dispatch, read-only queries, capability parsing and controls. |
| [`native_tape_read.inc`](native_tape_read.inc) | Shared record/buffer validation, READ and residual-count handling. |
| [`native_tape_write.inc`](native_tape_write.inc) | Explicit writer claims, WRITE, flush/filemarks and release/error state. |

## Submission and completion

The shared resident client uses DS=CS, one SRB and serialized calls. The caller
selects the unit address, prepares the command, fills CDB/buffer fields, submits,
and checks completion before changing its device state. Hardware interrupts
are enabled while waiting; the caller's flags are restored afterward. A pending
SRB is never abandoned after a CPU polling limit: the manager still owns the
SRB and buffer until completion. Posting/asynchronous client I/O would require
its own lifetime and cancellation design.

Execute-SCSI success requires agreement between manager, host and target status.
Sense is trusted only within a qualified error completion. DOS autosense follows
the **actual** CDB: `64 + SRB_CDBLen`, not always offset 80. The C structure's
`sense_tail` is extra storage, not a universal sense pointer. See
[`aspi-sense.md`](../../docs/aspi-sense.md) for completion and sense rules.

## Native tape binding

The native includes are part of ASPITAP's resident implementation. They share
transport resources with the legacy character interface but retain separate
writer ownership and completion rules. BEGIN/ABORT manage ownership in memory;
FLUSH/FILEMARK/END may submit hardware commands. Legacy close must not add
implicit filemarks to a native stream. The public packet helpers in
[`tape_api.c`](../tape/tape_api.c) construct/validate packets without I/O;
[`native-tape-api.md`](../../docs/native-tape-api.md) documents the binding.

Native packet enums, capability masks, completion flags and session bits are
different namespaces, even when numbers coincide. The assembly comments explain
those translations and the byte-versus-block units at each boundary.
