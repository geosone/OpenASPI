# Native OpenTape API: fixed-block I/O

The native DOS provider now supports explicit fixed-block READ/WRITE requests.
This is a common tape capability, not a device quirk or an emulation. The
existing variable-record path remains explicit: a zero flag never guesses a
fixed mode from a byte count or a product name.

## Negotiation and wire fields

QUERY operation bit `OT_TAPE_OP_FIXED_IO` (`0400h`) advertises this provider
extension. The complete current operation mask is `FFFFh`. This describes API
support, not the drive's current block configuration. The caller selects a
drive already configured for the requested block size. No request here issues
MODE SELECT, changes density/compression or prepares media.

Packet version remains `0100h` and both packet sizes remain 64 bytes. Two
previously reserved fields now have conditional meanings:

| Packet | Flags | Block-size field |
|---|---|---|
| Record READ (`80h/02h`) / WRITE (`80h/03h`) | `OT_TAPE_IO_FIXED` (`1`) | `block_size`, DWORD at `2Ch` |
| Control BEGIN_WRITE (`80h/01h`, operation 2) | `OT_TAPE_IO_FIXED` (`1`) | `block_size`, DWORD at `1Ch` |
| Variable record or ordinary control | zero | zero |

Record bytes after `30h` (16 bytes) remain reserved. CONTROL now reserves
bytes after `24h` (28 bytes); its signed [SPACE count](native-tape-space.md) at
`20h` must be zero for fixed writer claims and other non-SPACE controls. Constructors and validators are in `tape_api.h` /
`common/tape/tape_api.c`. Old variable clients still send/receive zero in these
formerly reserved fields. New fixed clients check the operation bit before
issuing any extended request; they do not fall back to legacy operations.

Use `ot_tape_record_fixed_init(packet, operation, bytes, block_size)` and
`ot_tape_control_fixed_init(packet, block_size)`. Block size is 1..65535 bytes;
requested capacity is 1..65535 and must be an exact multiple of the block size.
Known actual byte counts must also be exact multiples. The ordinary DOS pointer,
segment-wrap, physical-range and packet/data-overlap checks still apply.

Unsupported flags, missing/oversize block sizes, nonmultiples, a size conflicting
with a fixed-only drive detected by the driver, and a write whose mode differs
from its active claim are rejected before submission without changing the
caller's packet. Legacy buffered/written/error and native ownership guards
continue to take precedence over actual device access.

## Bytes, blocks and stream conditions

The API's `requested`, `actual` and residual diagnostics use **bytes**. The
READ(6)/WRITE(6) CDB has FIXED=1 and an unsigned block count equal to
`requested / block_size`. For example, 1024 bytes with block size 512 requests
two blocks, not 1024 blocks. One request may transfer multiple physical blocks;
it is not a variable-record boundary. READ BLOCK LIMITS describes a physical
block/record size, not the total byte capacity of a multi-block request.

Negotiated ASPI residuals are byte counts. Reject values beyond the request,
nonzero high words and residuals containing fractions of a block before
publishing COUNT_VALID. Current READ sense INFORMATION is a residual block
count in fixed mode: multiply it by the explicit block size, check overflow
and request bounds, then compare with a negotiated residual if both exist.
The same information remains a residual byte count for variable records.

Filemarks and EOM may accompany whole blocks. Report bytes and stream condition
together. Without ASPI residual support, bounded current READ sense information
can establish the byte count; missing information remains unknown rather than
becoming an invented zero-byte EOF. Deferred or host-failed completions never
establish this command's stream/count from plausible sense.

ILI in fixed mode is an error, not the variable-mode short-record success case.
Invalid/contradictory lengths invalidate the count and return MALFORMED. A hard
target error stays an error even with a valid partial whole-block count. Failed
WRITE counts still require the negotiated ASPI extension; this version does
not infer failed WRITE counts from sense.

## Writer lifetime and OpenTape consumer

BEGIN_WRITE with FIXED and a block size binds the claim to that mode. Each
WRITE must match it. FLUSH, FILEMARK, END and ABORT keep their ordinary zero-flag,
zero-block-size packet form; they do not change the claim's data mode. End/abort,
retained uncertainty, no implicit close-time marks and no replay follow the
[existing writer contract](native-tape-write.md).

OpenTape adds `ot_native_reader_open_fixed` / `ot_native_writer_open_fixed` and
DOS `ot_dos_native_*_open_fixed` wrappers. Existing read/write functions use the
mode selected at open, validate alignment locally, and verify echoed mode and
size before exposing results. Invalid byte lengths submit nothing and do not
poison the client. A failed submitted operation still latches the session.

OpenTape now adds fixed archive attachments with separate caller-owned
workspace. Each logical OTB1 block spans whole physical blocks, with verified
zero padding after its unchanged declared logical length/CRCs. Read assembly
bounds and validates the header before consuming the rest. DOS selects this
with `--native --fixed-block N` (1..4096); the common adapter supports up to
65535 with sufficient workspace. Reading requires the same explicit physical
mode/size. Ordinary attachments still reject fixed sessions without workspace.
The low-level provider itself still neither adds padding nor interprets archives.

## Validation scope

`native-fixed-*` DOS provider fixtures and OpenTape `fixed-*` consumer fixtures
use two 512-byte blocks. They verify CDB block counts versus buffer bytes,
guards and unchanged rejected packets, fixed claim consistency, full/partial
transfers, marks/EOM with data, fractional/oversize/conflicting residuals,
sense multiplication overflow, fixed ILI, medium/host/deferred errors and older
ASPI managers with valid/missing sense counts. Exact command/flush/mark counts
exclude retries and implicit finalization. Host tests also check negotiation,
mode echo validation and rejection of archive attachments lacking workspace.
OpenTape archive tests additionally cover fixed framing, padding, exact command
counts and backup/verify/list/restore/compare with 35-KB files under DOS. Tests use memory-only ASPI
mocks and disposable QEMU images; physical-device qualification is still open.
