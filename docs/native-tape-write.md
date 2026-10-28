# Native OpenTape API: DOS writer sessions v1

Native writing is separate from legacy ASPITAPE write/close semantics. It uses
an explicit claim and explicit flush/filemark/end operations. It never sets the
legacy WRITTEN bit, appends two implicit marks, backspaces or rewinds on close.
The binding submits variable-record WRITE(6) or an explicit
[fixed-block WRITE](native-tape-fixed.md). OpenTape archive commands can select this writer with `--native`,
using an explicit flush, one archive filemark, end and close.

## Calls and packets

Use one raw no-rewind handle (`NRMT0`) for the entire session. Native control
operations use category `80h`, function `01h`, the existing 64-byte
`ot_tape_control_v1` packet and version `0100h`:

| Operation | Number | Hardware command | Successful completion flags |
|---|---:|---|---:|
| BEGIN_WRITE | 2 | None: claim ownership | `0042h` (DONE, CLAIMED) |
| FLUSH | 3 | WRITE FILEMARKS(6), count 0, IMMED=0 | `0003h` |
| FILEMARK | 4 | WRITE FILEMARKS(6), count 1, IMMED=0 | `0003h` |
| END_WRITE | 5 | WRITE FILEMARKS(6), count 0, IMMED=0; then release | `0083h` (SUBMITTED, DONE, RELEASED) |
| ABORT_WRITE | 6 | None: release ownership | `0082h` (DONE, RELEASED) |
| SETMARK | 17 | WRITE FILEMARKS(6), WSMK=1, count 1, IMMED=0 | `0003h` |

FLUSH and END_WRITE append **zero** filemarks. Call FILEMARK explicitly for
each desired filemark; [SETMARK](native-tape-setmark-write.md) explicitly writes
a distinct setmark in the same claimed session. END_WRITE does not imply an archive delimiter or spacing.
Every hardware operation is synchronous and submitted once. BEGIN/ABORT do
not claim SUBMITTED. Failed flush/mark/end returns ERROR, completion `0005h`
(SUBMITTED, POSITION_UNKNOWN), and retains ownership in a failed state.

Data uses category `80h`, function `03h`, the same 64-byte record packet as
the [read binding](native-tape-read.md), with operation=1 (WRITE). Initialize
with `ot_tape_write_init`, set the DOS buffer words, and keep the data buffer
valid until synchronous completion. Capacity must be 1..65535; zero-length
writes do not claim a session or finalize anything. Header, range, segment-wrap
and physical-overlap rejection is shared with READ and changes no caller bytes.

QUERY advertises WRITE=`0010h`, BEGIN=`0020h`, FLUSH=`0040h`, FILEMARK=`0080h`,
END=`0100h` and ABORT=`0200h`; FIXED_IO adds `0400h`.
Optional [SETMARK](native-tape-setmark-write.md) adds `08000000h` independently
of read-side setmark classification. The complete current provider mask is
`1FFFFFFFh`; see [query negotiation](native-tape-query.md) for other operations.
These are entry points, not proof of current media/mode compatibility. The
command does not change block mode. Driver-detected fixed-only devices reject
a variable-mode BEGIN without a CDB; fixed-mode BEGIN specifies the block size
explicitly. The caller selects a drive configured for that mode.

## Ownership, unfinished sessions and recovery

Native session bits supplement the legacy query flags:

| Bit | Meaning |
|---:|---|
| `0010h` | Native writer claim active |
| `0020h` | A submitted write or filemark may have changed the medium |
| `0040h` | Native session failed or was abandoned; explicit recovery required |

BEGIN requires one handle, no pending rewind, saved legacy write error,
written/buffered session, buffered data, queued legacy EOF, or previous native
uncertainty. While claimed, native reads/rewind, discovery refresh and legacy
data/movement operations cannot access the stream. DOS may ignore driver OPEN
errors, so extra opens are counted and poison the claim rather than being
assumed impossible. Mutators remain blocked while multiple handles exist;
closing the extra handle does not repair the failed writer.

Any submitted write/flush/mark/end failure blocks subsequent write/flush/mark/end
commands. ABORT releases ownership without hardware activity. Dirty/failed state
survives ABORT and close/reopen, blocking a new writer or native reader. A
successful explicit native REWIND after release clears this native uncertainty
and confirms BOT; it does not erase the saved legacy write-error mechanism.
READY alone does not repair position or clear native uncertainty.

Closing an active claim without END/ABORT releases it, retains FAILED and any
DIRTY flag, and submits no command. The driver reports a close error, but DOS
may ignore that notification. Applications must use the explicit result/state
contract, not DOS CLOSE success, as proof that a backup was completed.

## Write results and data durability

Only a clean full write returns OK with completion `0023h`, actual=requested,
and active/dirty session `0030h`. This acknowledges the physical command's
accepted record; a subsequent successful synchronous FLUSH/END is required
to drain the device buffer. FLUSH does not release the session.

A short clean completion is ERROR with diagnostic INCOMPLETE (`5`), a valid
partial count and SHORT. It must never be resubmitted as the remainder of the
same logical record. Invalid/oversize residuals return MALFORMED with unknown
count. Host/contradictory completion and deferred sense do not establish this
record's count. Current target CHECK CONDITION may retain a negotiated bounded
ASPI residual; a WRITE failure without that extension leaves count unknown.
Unlike READ, this version does not infer failed WRITE counts from sense data.

EOM is retained from trustworthy current target sense, including a possible
full accepted count; the operation still fails and latches the writer. It does
not inherit the legacy ignore-EOT policy. Keep the original error packet even
when count=requested. No failed record, mark or flush is replayed automatically.
Snapshot queries expose retained session flags; the caller retains the original
write/control packet for the detailed failure through abort/cleanup.

## OpenTape consumer and validation

OpenTape provides a persistent native writer with an explicit write-open
callback and platform-owned handles. It checks device identity and operation
support before BEGIN, verifies packet guards/echoes, retains the first failure,
and rejects further mutations after that failure. `finish` submits END; `close`
only aborts an outstanding claim and closes once. An unfinished/aborted writer
returns `OT_NATIVE_UNFINISHED`, even when the underlying DOS close succeeds.
The common close path never flushes or creates filemarks.

Installed DOS provider and consumer fixtures check full/short writes, host and
contradictory errors, write protection, partial/full EOM, malformed residuals,
deferred sense, partial hard errors, old managers, each failed finalization
stage, poisoned ownership and abrupt DOS close. Exact CDB/flush/mark counters
prove that no close-time marks, replay or implicit spacing are introduced.
QEMU uses the memory-only ASPI manager and disposable images; no physical tape
is written and physical-device compatibility is not claimed by these tests.
