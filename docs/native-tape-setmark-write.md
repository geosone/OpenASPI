# Native writer: explicit SETMARK

SETMARK writes exactly one setmark in an already claimed native writer session.
It uses the common writer state machine and remains separate from FILEMARK,
flush, archive completion and [setmark read classification](native-tape-setmarks.md).
It never changes block mode or enables setmark reporting automatically.

The [Sony SDT-9000 DDS-3 product description, WRITE FILEMARKS section](https://bitsavers.trailing-edge.com/pdf/sony/dat/SDT-9000_DDS-3/SDT-9000_DDS-3_Product_Description_V1.1_199802.pdf)
documents WSMK selection, synchronous completion with IMMED clear and the
mark-count field. Drive support and physical media behavior require separate
qualification; no INQUIRY-name-based workaround is enabled here.

## Wire contract

Use the existing category `80h`, CONTROL function `01h`, version `0100h` and
64-byte `ot_tape_control_v1` envelope. Operation `OT_TAPE_CONTROL_SETMARK=17`
requires flags, block size, count and reserved fields zero. The count field
is not a mark count: this entry always requests exactly one mark. Invalid
requests are rejected before submission without changing caller bytes.
The capability is `OT_TAPE_OP_SETMARK=08000000h`; the complete current provider
mask is `1FFFFFFFh`. Read classification has its own independent capability.

An accepted owned operation submits one six-byte CDB `10 02 00 00 01 00`:
WRITE FILEMARKS with WSMK=1, IMMED=0 and transfer length 1. It requests no data
buffer and 32 sense bytes. Fixed and variable writer claims use this same
zero-flag control packet; the active claim retains the data block size.

A successful reply has opcode `10h`, completion SUBMITTED|DONE (`0003h`), clear
diagnostics and session WRITER|DIRTY (`30h`). Ownership remains claimed.
Before submission the driver marks the session dirty, including a session
that has written no data records. A target/transport failure returns ERROR,
completion SUBMITTED|POSITION_UNKNOWN (`0005h`), diagnostics and
WRITER|DIRTY|FAILED (`70h`). Unsupported sense is an error result with diagnostic
UNSUPPORTED, not permission to use FILEMARK, change mode or retry.
BUSY submits nothing and carries no opcode/status/completion facts.

No active writer, competing handles, rewind/buffered aliases, cached data,
legacy activity or a failed claim prevent submission. Failure leaves the
writer owned until ABORT or close cleanup releases it. Dirty/failed state
then remains `60h`; explicit successful native REWIND provides recovery.
END is available only after successful writing and performs the existing
zero-filemark flush/release. ABORT and unfinished close add no hardware
command, mark, flush, rewind or rollback.

## SDK contract

With matching provider headers, OpenTape defines `OT_NATIVE_TAPE_WRITE_SETMARK`
and exposes `ot_native_writer_setmark` / `ot_dos_native_writer_setmark`.
The writer captures provider operations from its checked opening snapshot.
Opening for ordinary writing does not require the optional SETMARK capability.

The setter requires an open, claimed writer and checks its saved SETMARK bit
before calling the provider. A missing bit returns `OT_NATIVE_UNSUPPORTED`
without a command, changed diagnostic, failure latch or lost claim. Ordinary
writer operations remain available. A submitted failure follows the existing
first-error policy: subsequent write/mark/flush/end requests do not issue
commands; ABORT/close retain the original error and packet through cleanup.
Malformed, mismatched or overrun replies likewise stop that SDK writer.

SETMARK is an owned writer operation, not a one-shot administrative movement
or SPACE command. OTB1 archive writers continue to request their ordinary
filemark delimiter explicitly; they do not insert setmarks automatically.
An older SDK without this feature still builds and runs ordinary writer
sessions, without invoking the new operation.

## Qualification

`tests/mocksetwrite.inc` checks the complete CDB, no-data envelope and sense
allocation. Its mark-attempt counter is independent of data writes, ordinary
filemarks and zero-mark flushes. OpenTape's
`tests/dos_native_setwrite.sh` boots installed provider/SDK consumers in
disposable QEMU images and checks exact counters.

Coverage includes fixed/variable claims, missing capability, raw invalid
requests and no-owner/competing-handle guards, clean and dirty mark writes,
unfinished close, explicit abort, retained failures and explicit recovery.
Fault profiles include host, unsupported, deferred, contradictory, target,
BUSY, filemark sense, descriptor sense and write protection. Only an explicit
caller retry after rewind and a new writer can issue the second attempt.
Host tests also check packet states, guard corruption, request echoes,
callback errors and cleanup error precedence. No physical tape is attached.
