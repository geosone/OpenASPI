# Native OpenTape API: DOS controls v1

The native binding adds READY and synchronous REWIND independently of legacy
ASPITAPE category `07h`. Discover provider support through the operation mask
in the [native query](native-tape-query.md); mask bits QUERY=1, READY=2,
REWIND=4 and READ=8 describe implemented API operations, not proof of inserted media.
The [writer binding](native-tape-write.md) adds operation bits `0010h..0200h`
and control operations 2..6 using this same versioned 64-byte packet.

## Caller contract

Open the raw no-rewind alias (`NRMT0`) and send `INT 21h AX=440Ch`, `CH=80h`,
`CL=01h`, `DS:DX` pointing at `struct ot_tape_control_v1` from
`include/openaspi/tape_api.h`. Initialize with `ot_tape_control_init`.
The pointer-free packet uses little-endian integers, magic `OTAP`, size at
least 64 and version `0100h`. The provider writes exactly 64 bytes and returns
size=64. Operation 0 is READY; operation 1 is REWIND. Operations 2..6 belong to the
explicit writer contract. Flags are zero except fixed-mode BEGIN_WRITE; see
[the fixed extension](native-tape-fixed.md).

Invalid function/header/flags/operation, null or wrapping pointers and ranges
above the first megabyte are rejected without changing caller bytes or legacy
diagnostics. DOS callers must allocate the declared buffer. Validate returned
packets with `ot_tape_control_validate`, and verify the echoed operation.
Successful DOS IOCTL delivery alone does not mean the command succeeded.

| Offset | Bytes | Meaning |
|---:|---:|---|
| `00h` | 4 | `OTAP` magic |
| `04h` | 2+2 | Size / version |
| `08h` | 2+2 | Operation / flags |
| `0Ch` | 2+2 | Native result / diagnostic class |
| `10h` | 2 | Session flags, as in the query packet |
| `12h` | 1 | SCSI opcode |
| `13h` | 3 | Host status / target status / sense key |
| `16h` | 3 | Sense response / ASC / ASCQ |
| `19h` | 1 | Reserved, zero |
| `1Ah` | 2 | Completion flags |
| `1Ch` | 4 | Explicit fixed BEGIN block size, otherwise zero |
| `20h` | 4 | Signed SPACE count; zero for non-SPACE operations |
| `24h` | 28 | Reserved, zero |

Completion flags: submitted=`0001h`, completed=`0002h`, position unknown=
`0004h`, beginning of tape confirmed=`0008h`, ready=`0010h`.

## Execution and errors

READY submits one TEST UNIT READY command. REWIND submits one six-byte REWIND
with IMMED clear, waiting for completion. Both commands have no data buffer.
Success returns result OK (`0`), clear diagnostics and completion `0013h`
for READY or `000Bh` for REWIND. READY does not claim a position; only a
successfully completed REWIND confirms beginning of tape.

READY/REWIND return BUSY (`2`) without submission for an active native writer,
another open handle,
a buffered/written session, retained write/finalization error, pending buffered
data, or a non-raw/non-no-rewind alias. An already pending rewind also blocks
REWIND; READY may poll it and clears the pending state only on success.
BUSY has zero completion flags and no command diagnostics.

A submitted failure returns ERROR (`3`) with retained host/target/sense fields.
Transport failure takes precedence over plausible target sense. Unsupported
is classified only from trustworthy current sense (70h/72h), key 5 and
ASC 20h/24h; deferred sense remains a target error. A failed REWIND returns
completion `0005h` (submitted, position unknown), never completed/BOT. A failed
READY returns `0001h`. Neither command is retried or replaced with a legacy
operation. Explicit controls update live legacy diagnostics; query snapshots
and rejected requests do not.

READY/REWIND do not flush/finalize a written session, write marks or prepare
media. The separate [read binding](native-tape-read.md) supports variable records;
the [writer binding](native-tape-write.md) defines explicit flush/mark/end/abort. The OpenTape consumer
keeps the handle through snapshot and command, closes once, and preserves a valid completion even if
the subsequent close fails.

## Validation scope

Host packet tests, installed DOS provider tests and OpenTape consumer tests
cover successful completion, busy ownership, rejected packets, guards, exact
command counts, host failure, not-ready media, deferred sense, unsupported
command and contradictory completion/status. QEMU uses a memory-only ASPI
fixture and disposable images. Physical tape and Windows bindings are not
qualified by these tests.


## Further positioning

The same CONTROL envelope now carries [signed SPACE](native-tape-space.md)
operations 7..9 and 14..16 and a count DWORD at offset `20h`. READY/REWIND continue to use
zero there and keep their existing completion flags. A failed SPACE retains
native uncertainty; READY does not clear it, while successful explicit REWIND
confirms BOT and clears the native state. [Synchronous LOAD/UNLOAD](native-tape-media.md) now use operations 10/11 with
zero count. They permit media recovery while preserving earlier native
uncertainty. [Logical position observation](native-tape-position.md) now uses
its own function/packet. [Logical LOCATE(10)](native-tape-locate.md) uses function
5 and a distinct target/partition packet; larger coordinate formats remain open.

[Medium removal control](native-tape-removal.md) adds LOCK/UNLOCK (12/13).
These non-moving commands preserve earlier native uncertainty and queued legacy
EOF; a failed lock command does not introduce POSITION_UNKNOWN or FAILED.
The exception is a current [Unit Attention](aspi-sense.md#tape-unit-attention-latch)
on any command: it reports FAILED until a successful REWIND.

With partitioned media, the historical BOT completion flag does not force or
prove partition 0. REWIND has no change-partition field; explicitly select a
known partition with [LOCATE](native-tape-locate.md) when required.
