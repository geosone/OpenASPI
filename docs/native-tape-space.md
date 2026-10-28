# Native tape positioning: SPACE

The native DOS binding adds synchronous relative movement over data blocks or
filemarks/setmarks, consecutive mark sequences and positioning to end-of-data. These are common sequential-access
operations, not device quirks. Unsupported hardware returns a checked error;
there is no automatic retry or REWIND-plus-forward emulation.

## Packet and negotiation

Use category `80h`, CONTROL function `01h`, version `0100h`, size 64. Existing
field offsets remain unchanged. A formerly reserved DWORD at offset `20h`
now carries a signed requested count for SPACE; bytes `24h..3Fh` remain zero.
For older operations the count must be zero. FIXED flags and block_size remain
zero for SPACE, even when the drive is in fixed-block data mode.

| Operation | Number | Provider bit | SPACE(6) code | Count |
| --- | ---: | ---: | ---: | --- |
| SPACE_RECORDS | 7 | `0800h` | 0 | signed -8388608..8388607 |
| SPACE_FILEMARKS | 8 | `1000h` | 1 | signed -8388608..8388607 |
| SPACE_EOD | 9 | `2000h` | 3 | zero |
| SPACE_SEQ_FILEMARKS | 14 | `00800000h` | 2 | signed -8388608..8388607 |
| SPACE_SETMARKS | 15 | `01000000h` | 4 | signed -8388608..8388607 |
| SPACE_SEQ_SETMARKS | 16 | `02000000h` | 5 | signed -8388608..8388607 |

The complete current provider operation mask is `3FFFFFFFh`. These bits advertise
entry points, not proof that the drive supports a particular spacing code or direction.
Check the particular bit before submission; an older provider without it is
unsupported without issuing a movement CDB. Positive counts move forward,
negative counts backward. Zero remains an explicit single SPACE command.

`ot_tape_space_init(packet, operation, count)` checks the signed 24-bit range
before changing the packet. Counts are little-endian signed DWORDs in the DOS
packet and two's-complement big-endian 24-bit values in CDB bytes 2..4. They
are requested movement, not transferred bytes or a returned residual. EOD uses
code 3 with count zero. Invalid count/flag/mode combinations are rejected before
submission and leave the caller packet untouched by the provider.

Data-block counts describe physical tape records/blocks, not files inside an
OpenTape archive and not OTB1 logical block numbers. A fixed-mode logical OTB1
block can span multiple physical blocks. The archive verifier still requires
a valid starting label/sequence; arbitrary spacing does not resume its state.

## Mark and sequence semantics

Filemarks and setmarks are distinct tape objects. Ordinary mark spacing counts
individual marks; consecutive spacing searches for a contiguous run of at least
N matching marks and stops beyond the Nth in the requested direction. It does
not mean N separate runs. Counts are signed in both cases; zero remains an
explicit command. All operations act in the current partition. They do not
write marks, select partitions or create an archive bookmark.

The [HP C1533A OEM manual, SPACE section](https://www.bitsavers.org/pdf/hp/tape/dat/C1533A/C1533-90900_C1533A_DDS-2_OEM_Product_Manual_199305.pdf)
defines codes 2/4/5 and signed sequence counts. It also requires setmark
reporting mode for its setmark operations. The provider does not enable that
mode automatically; mode/device requirements need separate qualification.
The [Quantum DDS-4 interface manual](https://qsupport.quantum.com/freedownloads/Certance/manuals/misc/scsi_man_cdxxxxxx_stdxxxxxx_en.pdf)
also distinguishes individual marks from consecutive runs. Modern drive
support can differ: a provider capability is not evidence of device acceptance.

Unsupported commands retain their checked diagnostic and native uncertainty;
no read loop, backward emulation or mode change follows. [Explicit setmark writing](native-tape-setmark-write.md) is a separate owned
writer operation.
[Classified native READ](native-tape-setmarks.md) now exposes observed setmarks
without promoting them into ordinary filemark/EOF success.

## Ownership and completion

Require one raw no-rewind handle, no buffered/legacy write state or saved error,
no native writer, no pending rewind and no retained native DIRTY/FAILED state.
Busy requests submit nothing. A hardware command is issued once with no data
buffer. Successful completion is exactly `0003h` (SUBMITTED|DONE), opcode `11h`,
clean diagnostics and zero session state. It proves completion of the requested
operation, not BOT or an absolute position coordinate.

Submitted failure returns ERROR, completion `0005h` (SUBMITTED|POSITION_UNKNOWN)
and native FAILED session bit `0040h`. Qualified current ILLEGAL REQUEST with
ASC 20h/24h can report diagnostic UNSUPPORTED; host/deferred/contradictory results
remain their own errors. A filemark/EOM sense flag cannot turn a failed movement
into success. Partial movement is not reconstructed from the requested count.

Uncertainty survives close/reopen. Native data I/O and further SPACE stay
blocked until a successful explicit native REWIND after any writer release.
READY/status can inspect the session but do not clear uncertainty. No failed
SPACE is replayed, including a command rejected as unsupported.

## OpenTape and checks

OpenTape supplies `ot_native_space` and `ot_dos_native_space`. The shared
adapter validates arguments before opening, verifies character-device identity
and the operation capability, checks guarded replies and echoed count, and
closes once while retaining the first error. CLI commands are:

```dos
OPENTAPE --native-space-records 1 --device NRMT0
OPENTAPE --native-space-records -1 --device NRMT0
OPENTAPE --native-space-filemarks -2 --device NRMT0
OPENTAPE --native-eod --device NRMT0
OPENTAPE --native-space-seq-filemarks 2 --device NRMT0
OPENTAPE --native-space-setmarks -1 --device NRMT0
OPENTAPE --native-space-seq-setmarks 2 --device NRMT0
```

Counts use decimal digits with an optional minus sign. No count is accepted
for `--native-eod`. No `--refresh`, block-mode change, inferred position or
implicit rewind is added. English/German output uses the existing native
result/diagnostic contract. Exit 0 is successful movement, 1 invalid arguments,
2 failed/busy/unsupported operations. Defaults use `NRMT0`.

Host packet/SDK tests cover limits, malformed replies, echoed count, individual
capability bits, session guards and cleanup precedence. OpenTape's
`tests/dos_native_space.sh` runs an installed provider/SDK and real CLI against
`tests/mockspace.inc` in this repository. It checks exact CDB bytes and command
counts, untouched invalid packets, multiple handles, poisoned writer ownership,
host/target/deferred/contradictory failures, unsupported commands and recovery.
All media are memory-only; physical-drive positioning remains unqualified.
READ POSITION/LOCATE and load/unload have separate bindings; optional movement
emulation and physical qualification remain open. See [native controls](native-tape-control.md) and
[device/quirk policy](tape-device-profiles.md).

For codes 2/4/5 the sibling OpenTape `tests/dos_native_extended_space.sh` runs
all three operations with signed extrema, zero, both directions, invalid
requests, exclusive handles, active/abandoned/dirty writers and exact CDB
counts. Fault variants cover each operation with transport, current/deferred
sense, contradictory status, filemark and descriptor-sense errors. Separate
GUI tests exercise the native **S** chooser entries 4/5/6 and older headers.
