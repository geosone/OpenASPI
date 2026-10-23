# Native OpenTape API: DOS record reads v1

Category `80h`, function `02h` reads one variable-length tape record. QUERY
advertises READ as operation bit `8`; the full current operation mask is
`0000FFFFh` (including the separate writer operations). This bit describes a provider entry
point. Variable-mode requests on driver-detected fixed-only devices return
UNSUPPORTED without submission; explicit [fixed-block requests](native-tape-fixed.md)
are now supported. [Native writes](native-tape-write.md)
use a separate explicit writer session.
The command does not change the drive's current block mode: the caller must
select a drive configured for variable records. The operation mask alone is
not proof of that mode; an explicit capability refresh can report its current
block descriptor.

## Wire packet and buffers

Use the raw no-rewind alias and `INT 21h AX=440Ch`, `CH=80h`, `CL=02h`,
`DS:DX` pointing at `struct ot_tape_record_v1`. Initialize with
`ot_tape_record_init`, set the separate DOS buffer offset/segment, and allocate
the entire requested capacity. The packet has magic `OTAP`, version `0100h`,
size at least 64, operation=0 (READ) and flags=0 for variable mode. The
fixed-block extension uses flag=1 and an explicit block-size field. Larger packet capacity is
accepted; output size is 64 and only those 64 bytes are written.

| Offset | Bytes | Meaning |
|---:|---:|---|
| `00h` | 28 | Same field layout as the control packet through completion flags |
| `1Ch` | 4 | Requested buffer capacity, 1..65535 bytes |
| `20h` | 4 | Actual bytes, meaningful only with COUNT_VALID |
| `24h` | 4 | Stream flags |
| `28h` | 2+2 | DOS buffer offset / segment |
| `2Ch` | 4 | Fixed block size; zero in variable mode |
| `30h` | 16 | Reserved, zero on output |

The command rejects invalid headers, operations, flags, zero/oversize counts,
null data pointers, segment wrap, ranges beyond 1 MiB, and physical overlap
between data and the 64-byte packet. Overlap is checked after linearizing far
pointers, including distinct pointers that alias the same physical bytes.
Rejected calls leave caller bytes and legacy diagnostics unchanged and submit
no SCSI command. Callers remain responsible for owning the memory they supply.
Other platforms pass ordinary buffers to their adapter; DOS far-pointer fields
are not a cross-platform pointer representation.

## Results and count validity

One accepted read submits exactly one READ(6), FIXED=0 and SILI=0, with no
readiness polling, mode changes, retry, synthetic EOF or fallback. Written,
buffered, pending-rewind or saved-write-error sessions, multiple handles,
buffered data, a legacy queued EOF and unsuitable aliases return BUSY first.
The provider does not discard those states to make a read possible.

| Result | Meaning |
|---|---|
| OK (`0`) | Completed read, including a possible empty record |
| BUSY (`2`) | No command submitted |
| ERROR (`3`) | Submitted failure; position is unknown |
| UNSUPPORTED (`4`) | Variable request on a fixed-only drive; no command submitted |
| STREAM (`5`) | Completed read with a qualified stream condition and valid count |

Completion flags reuse SUBMITTED=`1`, DONE=`2`, POSITION_UNKNOWN=`4` and add
COUNT_VALID=`20h`. A zero `actual` without COUNT_VALID does not mean an empty
record or filemark. A successful empty record has OK, DONE, COUNT_VALID and
SHORT, without FILEMARK. Errors may carry both a valid partial count and
diagnostics; applications must retain the error rather than consume the bytes
as an ordinary successful record.

Stream flags are FILEMARK=`1`, EOM=`2`, ILI=`4`, SHORT=`8`, TRUNCATED=`10h`
and EOD=`20h`. SHORT means the validated count is below requested capacity.
FILEMARK and data can coexist in the same response. No extra zero-byte read
is queued: the next native read submits the next command. EOM is reported
independently of the legacy ignore-EOT option. EOD requires current BLANK CHECK
sense, ASC/ASCQ `00/05` and a known zero transfer; it is distinct from FILEMARK.

Transport completion takes precedence over plausible sense or residual bytes.
Only current target CHECK CONDITION (70h/72h) can qualify a failed command's
count/stream flags. Deferred sense does not describe this read. Negotiated ASPI
residuals must fit the requested count. Without that extension, clean success
means the full request; bounded positive sense information can establish a
short count. Positive ILI must agree with a negotiated residual. Contradictory
or malformed lengths invalidate the count and return a malformed diagnostic.
Negative ILI reports an overlong record as ERROR with ILI/TRUNCATED and unknown
position; it does not become a successful short record. Hard target errors
remain errors even if stream flags or partial data are also present.

Explicit reads update live legacy diagnostics but do not set WRITTEN or add
close-time marks. They neither clear a retained write error nor finalize a
written session. A client must keep the no-rewind handle open for its stream
and close explicitly. The separate [writer contract](native-tape-write.md) defines
write/flush/mark/close ownership; a reader cannot claim it implicitly.

## Consumer and tests

OpenTape has a persistent native reader adapter with platform-owned handles.
It validates packet guards and echoed capacity, retains partial error results,
and blocks further reads after a failure until explicit close/reopen. It never
replays an ambiguous read. OpenTape archive commands can select that reader
with `--native`. The archive bridge consumes data before a co-returned filemark
and rejects EOM/EOD as proof of a completed archive.

`native-read-*` DOS fixtures test record content/guards, rejected pointers,
busy ownership, full/short/empty records, filemarks with/without data, EOM/EOD,
host errors, deferred sense, malformed/conflicting counts, truncation and
partial hard errors. Legacy-manager fixtures test sense-derived counts;
`native-read-fixed` checks rejection without a CDB. The sibling OpenTape tests
exercise the installed provider through its actual DOS adapter and verify
exact command counts. These use memory-only mocks and disposable QEMU images;
they do not qualify physical hardware.

The fixed-block extension changes CDB transfer units and sense-count conversion
explicitly; see [native-tape-fixed.md](native-tape-fixed.md). Variable requests
never infer that mode, and the archive bridge remains variable-only.
