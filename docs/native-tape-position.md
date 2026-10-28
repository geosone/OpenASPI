# Native logical tape position observation

The DOS native API exposes non-moving READ POSITION, short logical form.
This is a device position observation, separate from relative SPACE and future
LOCATE. It does not move tape, flush buffers, write marks, change partition,
recover abandoned output or clear native uncertainty.

## Coordinate and provenance rules

Short-form READ POSITION returns a 20-byte device response with a partition
and two 32-bit logical object locations. These include tape stream objects;
they are not byte offsets, filesystem file numbers or OTB1 archive sequence
numbers. The first location describes the host-side next object position;
the last is a distinct drive-reported location, not a capacity or end-of-data
measurement. Do not infer a distance from their difference. Modern drives
also report unknown/overflow flags; short form has a 32-bit coordinate limit.
See the [IBM 3592 SCSI reference](https://www.ibm.com/support/pages/system/files/inline-files/3592%20SCSI%20Reference_GA32-0968-06%20%28EXTERNAL%29.pdf)
and [HPE short-form reference](https://support.hpe.com/hpesc/public/docDisplay?docId=sd00001234en_us&page=GUID-D7147C7F-2016-0901-0922-00000000068A.html).

The provider reports coordinates only with `OT_TAPE_POSITION_VALID=1`.
BPU/LOLU (`04h`) or PERR (`02h`) suppress all coordinates; the successful raw
observation still retains `device_flags`. Unknown coordinates are zeroed but
must not be interpreted as block zero. Raw BOP (`80h`) means beginning of the
reported partition; EOP (`40h`) is the drive's partition/end-warning observation,
not filemark/EOD. Neither sets the native BOT completion bit. Buffer counts
and estimated/unknown byte-count fields are not exposed in this first binding.

A negotiated residual must prove exactly 20 transferred bytes. Short, oversized
or missing residual reports and reserved device fields fail as malformed.
A legacy manager without residual support returns PARTIAL, diagnostic
INCOMPLETE and UNVERIFIED_LENGTH; no coordinates/raw flags are published.
No six-byte vendor position command, cached software counter or retry is used
as a fallback. [LOCATE(10)](native-tape-locate.md) now supplies explicit movement;
[64-bit long-form observation and LOCATE(16)](native-tape-wide.md) are now
implemented separately; verified emulation remains future work.

## DOS wire contract

Use category `80h`, function `04h`, version `0100h`, packed size 64 and format
0. Initialize with `ot_tape_position_init`; validate replies with
`ot_tape_position_validate`. Existing QUERY/CONTROL/record packets are unchanged.
The operation capability is `00040000h`; the complete mask is `1FFFFFFFh`.
This advertises the provider operation, not attached-drive support.

| Offset | Bytes | Field |
| --- | --- | --- |
| `00h` | 4 | Magic `OTAP` |
| `04h` | 2+2 | Size 64 / version `0100h` |
| `08h` | 2+2 | Format 0 / flags 0 |
| `0Ch` | 2+2 | Result / diagnostic class |
| `10h` | 2 | Session state |
| `12h` | 7+1 | Opcode, host, target, key, response, ASC, ASCQ / reserved zero |
| `1Ah` | 2 | Completion facts |
| `1Ch` | 4 | Valid fields: logical location bit 1 |
| `20h` | 4 | Partition, zero unless location valid |
| `24h` | 4 | First logical location, zero unless valid |
| `28h` | 4 | Last logical location, zero unless valid |
| `2Ch` | 4 | Raw device flag byte, widened to DWORD |
| `30h` | 4 | Probe flags: UNVERIFIED_LENGTH bit 1 |
| `34h` | 12 | Reserved, zero |

Each accepted observation submits one ten-byte CDB `34h`, all other bytes zero,
20-byte data-in buffer, 32-byte autosense and negotiated residual flag. BT/service
action zero selects short logical coordinates. Autosense follows the actual
CDB length; the common resident decoder now handles both six and ten bytes.

Invalid format/flags/header or address range is rejected before submission and
leaves the packet unchanged. Require one raw no-rewind handle with no active
writer, pending rewind, legacy written/buffered/saved-error state or cached
data. A queued legacy EOF is preserved. BUSY submits nothing, has no command
facts or coordinates and preserves the session snapshot. Released native
FAILED (`40h`) or DIRTY|FAILED (`60h`) may be inspected and remain unchanged.

Clean hardware completion has flags `0003h` (SUBMITTED|DONE). A valid response
with unknown location is still command success with no location validity.
Malformed completed data returns ERROR/diagnostic MALFORMED with flags `0003h`;
unverified length returns PARTIAL/INCOMPLETE with `0003h`. A failed hardware
command returns ERROR with flags `0001h` and qualified diagnostics. Neither
failure sets POSITION_UNKNOWN or native FAILED: observation does not move tape.
Transport status takes precedence over sense; deferred, contradictory, BUSY
and FILEMARK sense cannot fabricate a successful position. Legacy diagnostics
are saved/restored exactly as with read-only native discovery.

## OpenTape and qualification

```text
OPENTAPE --native-position --device NRMT0
```

`ot_native_position` / `ot_dos_native_position` keep one handle for snapshot,
capability check and callback, validate guarded replies and close once while
preserving the first error. An unusable position returns SDK PARTIAL and CLI
exit 2; malformed arguments return 1. Completed, verified coordinates print
partition and both full unsigned locations. Earlier native uncertainty stays
visible even if a valid position is observed. Builds against older provider
headers reject the new verb before opening a device.

Host packet/ABI/SDK tests and `dos-native-position-smoke` cover exact CDBs,
big-endian full-width addresses, BOP/EOP, unknown/overflow, legacy length,
short/malformed responses, host/target/deferred/unsupported/contradictory errors,
multiple handles, active and abandoned writers, preserved legacy diagnostics
and queued EOF, explicit recovery, exact command counts and both languages.
Memory-only fixtures and disposable DOS images access no physical tape.
Physical-drive and Windows bindings remain unqualified.
