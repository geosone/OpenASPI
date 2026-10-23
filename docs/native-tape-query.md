# Native OpenTape API: DOS query v1

ASPITAP now provides the first runtime part of the
[native OpenTape API](native-tape-api.md). This is separate from the historical
ASPITAPE category `07h`. The provider advertises operation mask `FFFFh`:
QUERY, READY, REWIND, READ, WRITE, BEGIN_WRITE, FLUSH, FILEMARK, END_WRITE and
ABORT_WRITE, FIXED_IO, SPACE_RECORDS/SPACE_FILEMARKS/SPACE_EOD and LOAD/UNLOAD.
See [native positioning](native-tape-space.md) for the new movement counts and guards and [media loading](native-tape-media.md) for LOAD/UNLOAD recovery.
See the [control](native-tape-control.md), [read](native-tape-read.md)
and [writer](native-tape-write.md) bindings and the
[fixed-block extension](native-tape-fixed.md), including OpenTape's explicit
fixed archive adaptation. Remaining movement/configuration operations, Windows
bindings and physical qualification remain open.

## Caller and wire contract

Use a raw **no-rewind** device alias, normally `NRMT0`. A DOS handle sends
`INT 21h AX=440Ch`, `CH=80h`, `CL=00h`, `DS:DX` pointing at
`struct ot_tape_info_v1` from `include/openaspi/tape_api.h`. This binding uses
little-endian fixed-width integers and no embedded pointers. Other platform
bindings must marshal according to their own calling conventions.

Initialize with `ot_tape_info_init`, set flags to zero or `OT_TAPE_API_REFRESH`,
and retain a complete 128-byte buffer. Input magic is `OTAP`, size is at least
128 and version is `0100h`. Larger declared caller capacity is accepted; the
provider writes exactly 128 bytes and returns size=128. Unsupported function,
version, flags, short size, null pointer, segment wrapping or a physical range
above the first megabyte is rejected without changing caller bytes or legacy
diagnostics. DOS callers are responsible for allocating the claimed buffer.

| Offset | Bytes | Meaning |
|---:|---:|---|
| `00h` | 4 | `OTAP` magic |
| `04h` | 2+2 | Size / version |
| `08h` | 2+2 | Request flags / native result |
| `0Ch` | 4 | Valid-field groups |
| `10h` | 4 | Native provider operation mask; See operation masks in `tape_api.h` and the writer binding |
| `14h` | 4+4 | Known / supported hardware-feature masks |
| `1Ch` | 4 | Current settings, gated by valid-field groups |
| `20h` | 4+4+4 | Minimum / maximum / current block size |
| `2Ch` | 4 | Host / target / LUN / transport kind |
| `30h` | 8+16+4 | Fixed-width vendor / product / revision |
| `4Ch` | 2+2 | Provider session state / query diagnostic class |
| `50h` | 4 | Host / target / sense key / response code |
| `54h` | 1+1+2 | ASC / ASCQ / reserved word |
| `58h` | 4 | Probe qualifications, including unverified legacy byte counts |
| `5Ch` | 4 | Block-size granularity in bytes |
| `60h` | 32 | Reserved, zero |

`ot_tape_info_validate` checks the returned packet and consistency before a
client uses it. `ot_tape_info_feature` then returns unknown (-1), unsupported
(0) or supported (1). Missing optional compression pages leave support unknown;
an actual valid page with DCC clear establishes unsupported compression.
Hardware capability does not advertise an unimplemented native setter.

## Snapshot and explicit probing

Flags=0 sends no SCSI request. It reports provider/address/session metadata;
identity, physical record limits and mode state remain unknown. It does not
reuse stale capability data from an earlier query.

REFRESH sends at most four read-only commands, once each: INQUIRY (36 bytes),
READ BLOCK LIMITS (6), MODE SENSE(6) page `0Fh` (compression) and page `10h`
(device configuration), each mode buffer allocated 64 bytes. It does not
issue TUR, wait for pending rewind, read/write records, change mode, partition,
erase, load/unload or retry a command. Checked unsupported optional-page
responses permit the next read-only query; transport errors, malformed replies
and other target failures stop the sequence.

Refresh returns BUSY without submitting a command if the provider sees a
written/buffered/rewinding session, a retained write failure, another open
handle, pending buffered data, or a buffered/rewind-on-close alias. These are
local provider ownership checks; they cannot detect an unrelated client that
bypasses the driver and submits directly to an old ASPI manager.

| Native result | Meaning |
|---|---|
| OK (`0`) | Requested snapshot/probes completed; use valid bits for each field. A snapshot alone establishes no device readiness. |
| PARTIAL (`1`) | Completed fields remain available; the first failed query's checked diagnostic is retained. Missing fields stay unknown. |
| BUSY (`2`) | Refresh was not attempted; session metadata remains available. |

The native result is distinct from DOS IOCTL delivery. A successful DOS call
can return PARTIAL or BUSY. Legacy status, saved write/finalization failures,
transfer counts and decoded sense state are restored after native probing.
Discovery can consume target-side Unit Attention; this is another reason to
avoid probes during active sessions. Multi-command information is not an
atomic media snapshot and must be revalidated before future mode changes.

## Parsing and record sizes

INQUIRY must identify a connected sequential device, advertise sufficient
identity bytes and provide printable fixed-width identity fields. Buffers
are poisoned before each command. Negotiated ASPI residuals must remain
enabled and within the allocation, including the high word; the parser uses
the resulting actual length. A legacy manager cannot prove that length, so
the response explicitly sets `OT_TAPE_PROBE_UNVERIFIED_LENGTH` and still
applies response-header, bounds and poison checks.

MODE SENSE validates the total returned length, block-descriptor area,
page headers and every page extent before publishing fields. It handles
DBD/no-DBD response layouts, preceding unrelated pages and the PS bit;
duplicate requested pages, subpage-form responses, truncated pages and absent
requested pages fail conservatively. Current block size is unknown without
a complete block descriptor, even when the write-protection header is valid.
Compression DCC/DCE and configuration RSM are reported independently.

READ BLOCK LIMITS retains minimum, maximum and granularity. Maximum=0 means
no specified upper limit, not an unusable drive or an unlimited provider
transfer. A supported size `n` must satisfy the limits and make `n-minimum`
a multiple of the granularity. `ot_tape_info_block_valid` checks that device
constraint; it does not establish a DOS buffer/CDB transfer limit or perform
a write. This follows the tape block-limit semantics described in
[IBM's LTO SCSI reference](https://www.ibm.com/support/pages/system/files/inline-files/%5BAPPROVED%5D%20LTO%20SCSI%20Reference%20GA32-0928-07%20%28EXTERNAL%29.pdf).

## DOS diagnostic client

```dos
OTAPINFO
OTAPINFO NRMT0 /REFRESH
OTAPINFO NRST0$ /REFRESH
```

`OTAPINFO.EXE` validates the name and DOS character-device flag, then queries
the native API. It rejects rewinding aliases, paths and ordinary files and
does not fall back to a different API after a native-query failure. It uses
the public initialization/validation/capability helpers that OpenTape can
reuse. Current OpenTape archive commands still use their existing backend;
the native-query frontend adapter has not yet been wired into those commands.

Exit 0 means the query completed. Exit 1 is usage, DOS, API validation or
console failure. Exit 2 reports PARTIAL/BUSY or a retained write failure.
This does not qualify a backup or guarantee media readiness. The CLI uses
the shared English diagnostic convention of the other small DOS utilities.

Tests cover the public C validator and real 16-bit ABI layout, plus installed
DOS provider/client negotiation, unchanged rejected buffers, tail guards,
invalid pointers, no-I/O snapshots/BUSY, short/legacy replies, malformed
residuals/mode data, optional unsupported pages, shifted page locations,
record-size granularity and unspecified maximum. Test-only manager counters
assert submitted command counts and absence of unexpected media commands;
additional buffered-write fixtures retain a real saved write failure across
snapshot and rejected refresh queries, comparing every legacy status byte.
Both historical status layouts and existing transfer/buffering paths retain
their separate regression coverage. All fixtures use memory and disposable
QEMU images, not physical tape media.

Native writer session bits are active=`0010h`, dirty=`0020h` and failed or
abandoned=`0040h`. Snapshot queries report these without hardware activity.
An active or uncertain writer blocks REFRESH. Recovery uses an explicit native
REWIND after releasing the claim; READY does not clear the native flags.
