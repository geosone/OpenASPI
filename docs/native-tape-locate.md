# Native logical LOCATE(10)

The native API now supports explicit synchronous movement to a 32-bit logical
object address. It complements [READ POSITION](native-tape-position.md).
Coordinates refer to the current medium and partition, not byte offsets,
archive file names or OTB1 sequence numbers. A saved address is not a media
identity check or a verifier checkpoint.

## Address and partition selection

The request carries an unsigned block/object address `0..4294967295`.
Flags 0 mean the current partition: the request partition field must be zero
and does not select partition 0. `OT_TAPE_LOCATE_PARTITION=1` explicitly selects
partition `0..255`, including partition 0. The caller must establish that an
explicit target partition exists; the provider does not probe, create or infer
partitions. These command semantics follow the
[HPE LOCATE reference](https://support.hpe.com/hpesc/public/docDisplay?docId=sd00006916en_us&docLocale=en_US&page=GUID-D7147C7F-2016-0901-0922-000000000560.html).

Each accepted request issues exactly one ten-byte `2Bh` CDB, without data.
BT=0 requests a logical object; IMMED=0 waits for completion. CP is zero for
the current partition and 1 for explicit selection. The object address is
big-endian in bytes 3..6, partition is byte 8 and all other fields are zero.
There is no hidden READ POSITION, readiness check, separate flush, mark, rewind, retry
or REWIND/SPACE fallback. [LOCATE(16)/64-bit coordinates](native-tape-wide.md)
are now implemented separately; qualified software emulation remains future work. The drive may drain its own pending
buffer as part of LOCATE; the provider sends no additional flush command.

## DOS packet

Use category `80h`, function `05h`, packed size 64, version `0100h` and format
0. `ot_tape_locate_init` validates flags/partition before changing the caller's
packet. `ot_tape_locate_validate` checks returned completion consistency.
The provider capability is `00080000h`; the complete mask is `3FFFFFFFh`.
This indicates the provider entry point, not attached-drive support.

| Offset | Bytes | Meaning |
| --- | --- | --- |
| `00h` | 4 | Magic `OTAP` |
| `04h` | 2+2 | Size 64 / version `0100h` |
| `08h` | 2+2 | Format 0 / flags: explicit partition `0001h` |
| `0Ch` | 2+2 | Result / diagnostic class |
| `10h` | 2 | Session state |
| `12h` | 7+1 | Opcode/host/target/key/response/ASC/ASCQ; reserved zero |
| `1Ah` | 2 | Completion flags |
| `1Ch` | 4 | Echoed requested partition, zero when flags 0 |
| `20h` | 4 | Echoed requested logical object address |
| `24h` | 28 | Reserved, zero |

This is distinct from CONTROL.count and from position validity/output fields.
The echoed target is not a fresh position observation. Function 5 rejects bad
header, format, flags, partition and pointer ranges before changing caller
bytes or submitting a command. DOS callers allocate at least 64 bytes.

## Ownership, stream state and failures

Require one raw no-rewind handle, no active writer, no legacy buffered/written/
saved-error state, no cached data, no pending rewind and no retained native
DIRTY/FAILED. BUSY submits nothing and echoes the target with zero completion
and command diagnostics. Explicit LOCATE cannot recover an uncertain session.

Success returns OK, opcode `2Bh`, completion `0003h` (SUBMITTED|DONE), clean
diagnostics and session 0. It does not claim native BOT even for target block
zero. Successful movement clears any old queued legacy EOF; a position
observation or removal-lock command must preserve that EOF instead.

Submitted failure returns ERROR, completion `0005h` (SUBMITTED|POSITION_UNKNOWN)
and native FAILED (`40h`). Failure may have moved the medium. Host status takes
precedence over plausible sense; checked unsupported, deferred, contradictory,
BUSY and FILEMARK results remain errors. No command is replayed. Data I/O,
SPACE and further LOCATE remain blocked; READY and READ POSITION may inspect
without clearing uncertainty. Only an explicit successful native REWIND after
writer release recovers this binding. A new valid observed address alone cannot
finalize abandoned output or clear the failure gate.

## SDK, CLI and qualification

The shared `ot_native_locate` and DOS wrapper validate arguments before opening,
verify character-device identity, snapshot ownership and the capability bit,
validate guarded replies and the exact echoed target, then close once while
preserving the first error. A valid completion remains available if close fails.
Old provider-header builds reject the CLI verb without opening a device.

```text
OPENTAPE --native-locate 12345 --device NRMT0
OPENTAPE --native-locate 12345 --partition 2 --device NRMT0
OPENTAPE --native-position --device NRMT0
```

The decimal parser accepts the full unsigned address range and partitions
0..255 without signed overflow. Extra/missing/signed operands, overflow,
duplicate options and `--partition` on other commands reject before device I/O.
CLI exit status is 0 for completed movement, 2 for errors and 1 for syntax.
Archive parsing/restore still needs its own valid starting label and sequence;
LOCATE does not resume the archive verifier at an arbitrary object.

Host/ABI/SDK tests and OpenTape's `dos-native-locate-smoke` cover current versus
explicit partition selection, full-width address readback through independent
READ POSITION, target echoes, invalid-packet preservation, multiple handles,
active and abandoned clean/dirty writers, failed movement with an altered
mock cursor, observation without recovery, explicit rewind recovery, queued
legacy EOF, fixed/descriptor/deferred sense, old SDK builds, exact command
counts and both languages. `tests/mocklocate.inc` is memory-only; disposable
DOS images attach no physical tape. Physical-drive and Windows behavior remain
unqualified.

Rewind recovery does not request a partition change. The historical native
BOT completion name means the selected partition's beginning, not a guarantee
that partition 0 is active. Use explicit partition selection when partition 0
is required; the CLI now states that distinction. The
[HPE load/unload reference](https://support.hpe.com/hpesc/public/docDisplay?docId=sd00006916en_us&page=GUID-8BD27D63-06DD-472D-BB7F-9EEB4612A664.html)
likewise distinguishes loading at partition 0 from an ordinary rewind.
