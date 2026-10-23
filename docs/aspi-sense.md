# Completion and autosense validation

ASPIDSK, ASPIFDD and ASPICDA use `common/aspi/aspi_client.inc`.
The same checked sense decoder supplies ASPIFDD's raw-service error packet
and the block track-VERIFY unsupported-command classification.

Successful execute-SCSI completion requires `SS_COMP`, zero host status and
GOOD target status. An inconsistent completion fails. Errors are translated
from sense only for execute-SCSI `SS_ERR`, zero host status and CHECK CONDITION.
Aborted, pending, BUSY and host-error requests cannot acquire a media error
from plausible stale sense bytes. Missing/unusable sense yields the general
DOS error; it does not imply success, write protection or a retry.

DOS sense starts immediately after the actual CDB. The decoder accepts the
client's supported 6/10/12/16-byte CDBs and bounds sense length to the requested
14 bytes. A response needs at least its eight-byte header. Fixed current and
deferred responses (`70h`/`71h`, with optional VALID bit) supply the sense key;
ASC is read only when byte 12 fits both the allocation and the response's
additional-length field. Descriptor responses (`72h`/`73h`) supply key and ASC
from the header. Descriptor VALID-bit aliases and other response types are
rejected. This decoder does not traverse descriptors or return ASCQ.

`aspi_result` returns carry clear only on successful completion; on failure
AL is the checked key, or zero if unavailable. `aspi_sense` returns carry
clear for valid sense, AL=key and AH=ASC (zero if unavailable), and preserves
all other registers. Invalid sense returns carry set and AX=0. The raw packet
retains its existing key/ASC output layout. Track VERIFY recognizes invalid
opcode only with checked key 5 and ASC `20h`.

The SRB is zeroed before every new command. `SRB_SenseLen` is an allocation
length, **not a reliable returned byte count**. Header/bounds checks and
clearing prevent stale-buffer reuse; they cannot prove that every byte of
a manager's short autosense transfer arrived. Transfer-count qualification
and command-specific Unit Attention policy remain separate work items.
This change adds no command replay or transport recovery.

ASPITAP has its own fixed/descriptor decoder and stream semantics, including
FILEMARK, EOM and ILI. Its resident decoder now checks the execute-SCSI command,
completion envelope, six-byte CDB and 8..32-byte sense allocation before
interpreting any key, flags or information. It resets decoded state on every
call. Descriptor traversal is bounded by both the allocation and additional
length; incomplete descriptors do not contribute flags or residuals. Fixed
ASC/ASCQ need both bytes within those bounds. Rewind polling uses these checked
fields, so undeclared progress bytes cannot trigger another poll. Clean
completion checks also guard reads, writes, controls and READ BLOCK LIMITS.

The resident tape decoder is shared with `tests/tape_sense.asm`; DOS integration
tests inject short/oversized sense allocations, invalid descriptor response
codes, contradictory success and undeclared rewind progress. The portable
C decoder also rejects descriptor responses with the reserved high bit set.
The C decoder retains its existing partial-header API for callers that supply
an actual byte count; it does not itself validate an ASPI completion envelope.
Production hardware and actual short-transfer qualification remain separate.

`tests/aspi_result.asm` executes the resident helper under DOS with all four
CDB lengths, fixed/deferred/descriptor formats, unavailable ASC, bad lengths,
wrong SRB commands/statuses, host errors, BUSY, contradictory success and
clearing between commands. `tests/dos_media_control.sh` runs it alongside
resident block/CD controls and raw-session tests. Disk and CD regression
fixtures now produce valid fixed-sense headers for intended media failures.


## Choose the decoder for its boundary

These implementations share format rules but deliberately expose different
contracts; they are not interchangeable drop-in parsers.

| Decoder | Inputs and outputs | Caller responsibility |
| --- | --- | --- |
| [`aspi_sense`](../common/aspi/aspi_client.inc) | Resident execute-SCSI SRB; carry, key and ASC. | Check operation policy; preserve original sense when DOS error conversion loses detail. |
| [`remember_sense_key`](../common/aspi/tape_sense.inc) | Tape SRB with six-byte CDB; resident fields and separate validity flags. | Check current/deferred response and command-specific residual/stream rules; carry is not a decode result. |
| [`oa_scsi_decode_sense`](../common/scsi/tape_sense.c) | Explicit byte buffer/length; decoded C structure and 0/-1. | Qualify transport independently, inspect information validity, and discard partial output on failure. |

Portable decoding accepts a recognized four-byte header without requiring a
complete autosense allocation. Resident decoders instead consume SRB allocations
and qualify manager/host/target state. Neither an allocation size nor cleared
backing storage proves how many sense bytes the manager actually returned.
The portable output has no separate ASC-presence flag, so zero ASC/ASCQ from a
partial reply is not positive evidence that the device returned zero.

The tape descriptor walk bounds every header/body by the smaller of allocation
and declared additional length. Optional unknown descriptors are skipped;
truncated descriptors cannot contribute information. A 64-bit information value
with nonzero upper 32 bits is not silently truncated into the resident/portable
32-bit output. Stream flags and information validity are independent: a valid
FILEMARK bit does not make an unavailable count valid.

## Error conversion loses information

`sense_to_doserr` maps a checked key to a DOS driver error; it is not a completion
checker and does not return success/failure in carry. DATA PROTECT maps to AL=0,
which is the DOS write-protection error code when the dispatcher adds ERROR.
Do not interpret that zero as clean completion. Unavailable sense maps to a
general error, not an inferred write-protection or unsupported-command result.

Use the original key/ASC and completed CDB when deciding whether an opcode is
unsupported, a source read fault is rescuable, or a cache must be invalidated.
A DOS error is a compressed application-facing report and cannot reconstruct
those distinctions. RAW1 therefore returns driver/sense diagnostics alongside
the mapped DOS error; native OTAP keeps diagnostic, count and completion facts
in separate fields.
