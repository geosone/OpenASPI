# Native 64-bit logical positioning

The native API adds long READ POSITION and LOCATE(16) alongside the existing
32-bit commands. Each 64-bit quantity is represented by low/high DWORDs in
little-endian packets. The 16-bit DOS compiler needs neither `long long` nor
floating point. No address is silently narrowed to a short-form coordinate.

The [IBM READ POSITION reference](https://www.ibm.com/support/pages/system/files/inline-files/LTO%20SCSI%20Reference_GA32-0928-05%20%28EXTERNAL%29_0.pdf)
defines service action `06h`, its 32-byte response and zero CDB allocation
length. The [HPE LOCATE reference](https://support.hpe.com/hpesc/public/docDisplay?docId=sd00006916en_us&docLocale=en_US&page=GUID-D7147C7F-2016-0901-0922-000000000560.html)
defines the sixteen-byte movement command. These are logical stream positions,
not tape byte offsets or OpenTape archive sequence numbers.

## Format and capability negotiation

Version `0100h` and packet size 64 remain unchanged. Format **1** explicitly
selects the new packet layouts on existing POSITION function 4 and LOCATE
function 5. Format 0 and its original structures/helpers remain unchanged.

| Operation | Capability | Packet | Hardware command |
| --- | --- | --- | --- |
| Long position | `00100000h` | `ot_tape_position64_v1` | READ POSITION(10), SA `06h` |
| Wide locate | `00200000h` | `ot_tape_locate64_v1` | LOCATE(16), opcode `92h` |

The complete provider mask is `1FFFFFFFh`. Check each specific bit: short-form
support does not imply support for a wide entry point, and a provider bit does
not prove attached-drive command support. No silent short-form fallback or
rewind/SPACE emulation is performed, even when the high DWORD is zero.

Both structures retain the diagnostic prefix through byte `1Bh`: magic,
size/version, format/flags, result/diagnostic/session, command status/sense,
reserved byte and completion flags. Every unused/reserved reply byte is zero.

Long position payload:

| Offset | Bytes | Field |
| --- | --- | --- |
| `1Ch` | 4 | Validity: block/partition `0001h`, logical file `0002h` |
| `20h` | 4 | Partition number |
| `24h` | 4+4 | Logical object number: low DWORD, high DWORD |
| `2Ch` | 4+4 | Logical file identifier: low DWORD, high DWORD |
| `34h` | 4 | Raw long-form device flags |
| `38h` | 4 | Probe flags: UNVERIFIED_LENGTH |
| `3Ch` | 4 | Reserved |

LONU (`04h`) suppresses the partition/object group. MPU (`08h`) independently
suppresses the file identifier. Unknown groups are zeroed and must not be
interpreted as valid zero positions. The file identifier counts tape filemarks,
not filesystem files. BOP/EOP/BPEW are raw partition observations, not rewind
completion or a recovery signal. Reserved flag bits and header bytes fail as
malformed; the obsolete final eight device bytes are not interpreted.

LOCATE(16) payload:

| Offset | Bytes | Field |
| --- | --- | --- |
| `1Ch` | 4 | Echoed requested partition |
| `20h` | 4+4 | Echoed logical object address: low DWORD, high DWORD |
| `28h` | 24 | Reserved |

Flags 0 retain the current partition and require request partition zero.
`OT_TAPE_LOCATE_PARTITION` selects an explicit known partition `0..255`. The
long observation may report a wider partition field; that does not expand the
one-byte partition selector supported by LOCATE(16). No partition is created
or inferred. The caller establishes media identity and partition availability.

## Submission, validity and recovery

Long observation issues one ten-byte `34h` CDB with byte 1=`06h`, remaining
bytes zero, a 32-byte data-in allocation and negotiated residual reporting.
The CDB allocation-length field stays zero. A negotiated residual must prove
all 32 bytes arrived. Short/missing/oversized residuals are malformed; legacy
managers without residual support return PARTIAL/INCOMPLETE with unverified
length and no coordinate validity. Successful observation returns completion
`0003h`; failed hardware observation returns `0001h`. Native state, legacy
diagnostics and queued EOF are preserved. Neither result moves tape or clears
an existing native failure gate.

LOCATE(16) issues one sixteen-byte `92h` CDB without a data buffer. CP, if
requested, is byte 1 bit 1; partition is byte 3. The full logical object address
is big-endian in bytes 4..11. DEST_TYPE=logical object, IMMED=0 and BAM=0; all
remaining bytes are zero. Autosense follows the actual CDB, so the shared
resident parser now supports 6-, 10- and 16-byte envelopes independently.

Movement has the same strict clean-session/ownership rules as
[LOCATE(10)](native-tape-locate.md). Success returns `0003h`, echoes the complete
target and clears old queued EOF without claiming BOT. Failure returns `0005h`
and native FAILED, with no retry or opposite command. A failed move may have
changed both halves of the position. READ POSITION can inspect it but cannot
recover a session. Explicit successful native REWIND remains the recovery path;
it does not force partition zero. Active/abandoned writers, buffered state,
other handles and pending rewind cannot be bypassed with a wider command.

## SDK, DOS commands and testing

The SDK provides `ot_native_position64` / `ot_dos_native_position64` and
`ot_native_locate64` / `ot_dos_native_locate64`. Callers pass address halves
explicitly. Guard checks, individual capabilities, echoed targets and first
errors survive callback/close handling. SDK PARTIAL and CLI exit 2 mean no
verified logical block position; a known block with unknown file number can
succeed while file validity remains clear. Old SDK builds reject both new
verbs before opening a device.

```text
OPENTAPE --native-position64 --device NRMT0
OPENTAPE --native-locate64 4294967296 --device NRMT0
OPENTAPE --native-locate64 18446744073709551615 --partition 2 --device NRMT0
```

`ot_tape_u64_parse` and `ot_tape_u64_format` use bounded 16-bit limbs with
32-bit intermediates. Decimal parsing rejects signs, trailing junk and values
above `18446744073709551615` without changing outputs. Formatting requires
room for the full decimal string plus NUL (up to 21 bytes); inadequate buffers
are unchanged. CLI argument errors precede device I/O.

Host/16-bit ABI/SDK tests and OpenTape's `dos-native-wide-smoke` cover unsigned
boundaries, high-word target echoes, full cursor readback, independent LONU/MPU,
large reported partitions, legacy/short/malformed responses, six-/ten-/sixteen-
byte sense placement, failure after movement, exclusive ownership, abandoned
writers, queued EOF, explicit recovery and localized decimal output. Short
position reports an out-of-range wide cursor as unknown rather than truncating.
The memory-only fixture `tests/mockwide.inc` uses disposable DOS images with
no host tape attached. Physical-drive and Windows qualification remain open.
