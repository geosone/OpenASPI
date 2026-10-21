# ASPITAPE compatibility target

The compatibility target is the public interface recorded in Ralf Brown's
Interrupt List for Greg Shenaut's `ASPITAPE.SYS`.

## Device names

- `RMT0` through `RMT3`: rewind on final close;
- `NRMT0` through `NRMT3`: no rewind on close;
- optional `MT0`/`NMT0` forms: historical 1024-byte defaults;
- optional `-$` suffix variants for name disambiguation;
- optional `-tX` replacement of the `M` in every device name.

Only names backed by detected devices should be exposed.  Programs must put an
opened device into DOS raw mode before transferring tape data.
OpenASPI implements `-tX` and `-$`; for example, `-tS -$` exposes `RST0$`
and `NRST0$` for the currently supported first drive.

## Generic IOCTL

The historical control call is `INT 21h`, `AX=440Ch`, with the device handle in
`BX`, category `CH=07h`, and one of these functions in `CL`:

| CL | Operation |
|----|-----------|
| 01h | `mtop`: execute a tape operation |
| 02h | `mtget`: return tape/driver status |
| 03h | ignore end-of-tape errors |
| 04h | enable end-of-tape errors |
| 05h | OpenASPI extension: explicitly request sixteen-byte status |

The byte-exact structures and flags are declared in
`include/openaspi/aspitape.h`.  Host tests assert the documented six-byte
`mtop`, fourteen-byte `mtget` and sixteen-byte `mtget16` sizes and field offsets.

### Two historical status layouts

The original archive is internally inconsistent: `ASPITAPE.4` describes a
14-byte status structure, but the distributed `ALGO_MAS.ZIP` headers
`IOCTL.H` and `MTIO.H` define a 16-byte structure. OpenASPI defaults to the
manual's 14-byte layout at function `02h`. Its new `-2` installation option
selects the 16-byte header layout at that entry point. **Do not use `-2`
with applications that allocate only 14 bytes.** DOS provides no parameter
buffer length with this request, so detecting the application's layout is
not possible. This switch is an OpenASPI addition, not an original option.

New OpenASPI clients should use function `05h`: it always returns exactly
16 bytes regardless of `-2`. `TAPECTL` uses that entry point and falls back
to the 14-byte `02h` layout only when it is unsupported. Its fallback does
not autodetect an original third-party driver's 16-byte ABI.

| Field | Manual ABI offset | Header ABI offset |
|-------|-------------------|-------------------|
| HA / target / LUN / parameters | 0 / 1 / 2 / 3 | 0 / 1 / 2 / 3 |
| state | 4 (byte) | 4 (word) |
| unit | 5 | 6 |
| driver error | absent | 7 |
| fixed block size | 6 | 8 |
| SCSI status / sense key | 8 / 9 | 10 / 11 |
| opcode / residual bytes | 10 / 12 | 12 / 14 |

Both state layouts share bits `01h` buffered, `02h` raw, `04h` rewind on
close, `08h` written and `10h` read. The header ABI additionally reports
`20h` after a successful explicit movement/filemark operation (not `MTNOP`),
uses `40h` for pending EOF, `80h` for ignored EOT, and `0100h` for a pending
rewind. The manual ABI retains `20h`, `40h`, `80h` for those last three states.

The header ABI's error byte reports a sense key on failed SCSI requests,
or driver errors 16 (rewind timeout), 17 (access/exclusivity), 18 (single-byte
guard), 19 (read after write), 20 (unsupported IOCTL), 21 (unknown tape
operation), 22 (SCSI BUSY), and 23 (interrupted rewind wait). OpenASPI reserves
31 for failures without a more specific code. Status queries do not clear
the error. A subsequent media request can replace it unless the saved buffered
write-failure rule below applies; this is not an error history. Unit zero is
the single supported physical drive. Emulator tests
compare both layouts throughout reads, writes, EOF/EOT and rewind waits,
including guard bytes after each destination buffer.

## Initial `mtop` operations

The baseline operations are write filemark, forward/backward space file,
forward/backward space record, rewind, rewind-and-unload, and no-op/Test Unit
Ready. OpenASPI implements all of them. Explicit `MTWEOF` writes filemarks
immediately. A zero-byte DOS write issues no immediate SCSI command. As in the
historical driver, the final close of a session which has written data
terminates it with two filemarks.

Compatibility behavior still requiring verification against the historical
binary includes exact DOS error mapping, buffering, partial-transfer corner
cases, and exact close/rewind timing.

## Current transfer subset

One DOS character-device read maps to one variable-block SCSI `READ(6)`.
Managers advertising ASPI extension flag `0002h` return a residual count, so
short records produce the correct DOS byte count. With older managers, such as
the tested Tekram 1.60 manager, an exact-size record works directly and a valid
fixed- or descriptor-format ILI information field supplies the length of a
short record. Descriptor stream-command flags also carry FILEMARK and EOM.

A filemark with no data completes as one zero-byte read; a filemark delivered
with data defers that zero-byte result until the next read. EOM is an error by
default and becomes a zero/partial successful result only after IOCTL function
`03h` selects the historical ignore-EOT policy. Negative ILI (record larger
than the caller's buffer) remains an error.

When ASPI residual support is active, a returned residual above the requested
length or with a nonzero high word is rejected before classifying stream
sense. FILEMARK, positive ILI and ignored EOM cannot convert that malformed
result into success. The DOS transfer count is zero, status retains the SCSI
result and reports the full request as residual, and no deferred EOF is added.
The legacy sense-derived length path remains unchanged.

Normal stream completions (FILEMARK, positive ILI, or ignored EOM) require
NO SENSE (`00h`) or RECOVERED ERROR (`01h`). Other sense keys remain failed
read requests; stream flags cannot mask a media or hardware error and cannot
queue a deferred EOF after such an error. The same restriction applies to
ignore-EOT on writes, even if the manager reports zero residual. A failed
physical write retains its diagnostic snapshot rather than becoming an
apparently successful write solely because EOM is set.

One non-empty DOS write maps to one variable-block SCSI `WRITE(6)`. A complete
write returns the input byte count. ASPI residuals are validated when the
manager supports them; write protection and other CHECK CONDITION results stay
failed DOS requests and remain visible through `mtget`.

By default, data reads and writes are accepted only while exactly one tape
handle is open. Single-byte requests are rejected as likely DOS cooked-mode
traffic; applications must select raw mode before transferring data. This
matches the historical driver's default safeguards. Its `-m` override for
multiple-open transfers and `-s` override for single-byte transfers are
implemented as `CONFIG.SYS` arguments. Upper/lower case, `-`/`/` prefixes and
option clusters such as `-ms` are accepted. Open and close requests themselves
remain tracked so final-close processing occurs at the correct time.
Malformed or unsupported options abort installation before ASPI discovery;
they are not silently ignored. `-t` requires an immediate alphabetic name
letter. `-b` enables the historical buffered aliases. `-v` and its
historical alias `-d` enable
initialization diagnostics with adapter identities, extension flags, tape
address, selected block mode and actual device names. Discovery failures also
report the failing stage. The diagnostics add no ASPI commands.

At installation, `READ BLOCK LIMITS` detects a drive whose minimum and maximum
block sizes are the same. `mtget` then reports `FIXED_BLOCK` and that size.
Raw DOS reads and writes must contain an integral number of blocks; the driver sets
the SCSI fixed bit and converts the byte count to a block count. This mandatory
fixed-drive handling is distinct from the historical optional `MTx`/`NMTx`
1024-byte software-buffering mode, enabled with `-b`. Buffered transfers reuse
the same SCSI paths; on a mandatory fixed-block drive, 1024 must be an integral
multiple of its required physical block size.

`-b` links `MT0` and `NMT0` in addition to the raw aliases. `-tX` and `-$`
apply to all four names. Buffered `mtget` reports state bit `BUFFERED` (01h);
the fixed-block parameter and size still describe the drive, not the cache.
The optional 1024-byte cache is resident only when `-b` is enabled.

Buffered reads split or combine records and defer a zero-byte filemark result
until preceding cached data has been delivered. Buffered writes accumulate
1024-byte records; final close zero-pads any partial record before writing the
usual terminator. Status, EOT policy and `MTNOP` retain cache contents. Tape
movement through `mtop` discards cached reads and writes, matching the original
manual. A read-to-write transition discards unread cached bytes.

The first open determines the session's transfer mode. Mixed raw/buffered
opens are counted because DOS may disregard a driver's open error, but data
transfers through the other mode are rejected even with `-m`. Failed or short
physical buffered writes latch an error through final close, preventing
automatic record replay and terminating filemarks after a failed flush.
The SCSI status and sense remain inspectable after reopen. Applications must
check tape status for delayed write errors because DOS may disregard device
close errors.

A failed or short physical raw or buffered write saves its diagnostic tuple:
SCSI status, sense key, opcode, residual byte count and driver error.
If a buffered request's readiness barrier fails before the data CDB is sent,
the snapshot's opcode identifies that failing readiness command instead. Raw
access guards, invalid block sizes and pre-write readiness failures do not
replace an older saved physical-write diagnostic. Both
status layouts return this saved tuple even after successful `MTNOP`, other
controls, rejected retries, close or reopen. The 16-byte ABI marks this with
the OpenASPI-only state bit `0200h` (`OA_MT16_STATE_WRITE_ERROR`); its state
bits still describe the current session, but the diagnostic fields refer to
the failed write, not the latest readiness/control command. The 14-byte ABI
has no spare state bit and returns the same saved diagnostic fields.

Failed written-session finalization saves the same diagnostic tuple for both
raw and buffered aliases: writing the two filemarks, `NRMT0`/`NMT0` backspacing
over the last filemark, or `RMT0`/`MT0` submitting the close rewind. Finalization
stops at the first failed step. In particular, failed filemarks do not trigger
spacing or rewind afterwards. DOS may ignore the close error, but a new open
and successful `MTNOP` cannot hide it. Read-only close rewind failures retain
the ordinary live status; they are not classified as failed writes.

An explicitly requested `MTWEOF` that reaches the manager and fails also saves
the write diagnostic tuple. Count validation and a failed readiness barrier
before command submission do not replace an older saved write error. This
does not change the existing control or close policy, and does not latch the
buffered-data retry guard. A successful filemark command cannot acknowledge
an earlier write failure.

After a buffered data failure, the active session remains locked against data
retries and automatic finalization. Finalization failures occur on final close,
so the session has already ended; a duplicate close does not retry any steps.
A new session may write again. Raw sessions permit explicit subsequent write
requests; the driver does not replay a failed raw record itself. The diagnostic
snapshot is cleared only by a full physical data write completed with ASPI success and
zero residual, through either raw or buffered aliases. Merely opening a new
session, accepting bytes into the software cache, a zero-length write,
writing filemarks, moving tape, or a partial/ignored-EOT transfer does not
acknowledge the failure. A complete raw write may clear the snapshot in the
same raw session; a buffered failure requires a new session because its data
path is locked. Another failed/short data write or written-session
finalization or explicit filemark failure replaces the snapshot with its own
failure. This protects delayed errors without silently replaying potentially
consumed records. It
does not restore tape position or make appending after an error safe; the caller must choose the
appropriate media recovery and positioning before starting a new session.

Raw short writes are failed DOS requests even when ASPI reports command
success or the ignore-EOT policy is enabled. Returning a successful short
character-device write can make DOS resubmit the remaining bytes as another
physical record; the SvarDOS fixture detects this unwanted extra WRITE. The
driver preserves the residual count and original SCSI result in status, but
does not claim the entire requested record was written. Buffered short
physical writes retain their existing error-and-session-lock handling. Raw
control and final-close behavior is unchanged: applications must inspect the
saved write diagnostic rather than infer backup success from a later close,
filemark operation or `MTNOP` result.

`MTFSF` and `MTFSR` accept nonnegative counts up to `007FFFFFh`, since SCSI
SPACE encodes a signed 24-bit count. `MTBSF` and `MTBSR` accept magnitudes up
to `00800000h` and encode their negative. `MTWEOF` instead has an unsigned
24-bit field and accepts up to `00FFFFFFh`. Larger counts fail before any
pending-rewind readiness wait or command submission, without discarding the
software buffer or replacing a saved write diagnostic. In particular, a
forward count with bit 23 set must not silently become backward movement.

After any write, later reads in the same open session are rejected. On final
close, a written session receives two filemarks. `RMT0` then rewinds; `NRMT0`
spaces backward over one filemark and leaves the tape positioned between the
pair for a later append. A zero-byte write request delivered to the driver
marks the session as written for this close processing but does not create a
zero-length data record. This does not make a zero-byte DOS API write a portable
way to request filemarks: the tested SvarDOS kernel returns zero without
delivering that call to the character driver. Tests verify that such an empty
non-rewinding session issues no data or filemark commands. Applications should
use explicit `MTWEOF` when they need to write filemarks.

The current implementation discovers and exposes only the first tape drive.
Medium changers and tape-library robotics are outside this stage.

Both device headers advertise DOS open/close notifications. OpenASPI counts
all opens and performs finalization only when the last tracked handle closes.
An unwritten `NRMT0` session never changes position. OpenASPI's own scan and
status tools therefore use `NRMT0`.

Final `RMT0` close defaults to REWIND with IMMED=1; `-w` selects IMMED=0 and
waits for command completion. Explicit `MTREW` continues to use IMMED=0.
Following an immediate close, `mtget` reports `REWINDING` (80h) and reopening
does not wait. Before a subsequent nonempty read, write (including zero-byte
write), `mtop` or additional close rewind, the driver polls TEST UNIT READY
until ready or about three minutes have elapsed. BUSY, fixed/descriptor
NOT READY 04h/01h or 04h/07h, and NO SENSE 00h/1Ah indicate progress. Other
errors fail immediately, leaving rewind pending until a later readiness check
succeeds. Polling is paced by BIOS ticks and handles midnight rollover.
The wait bounds the retry loop; an individual SCSI command still depends on
the ASPI manager's own execution timeout.

`-i` adds Ctrl-Break detection to the deferred rewind wait. A temporary
INT 1Bh handler records the break and chains the previous handler. The old
vector is restored on every ordinary exit; if another resident handler
chains above OpenASPI during the wait, that chain is preserved. A handled
break returns a failed DOS request and retains `REWINDING`; a later request
can retry and complete. This does not cancel the physical rewind or interrupt
a blocking ASPI manager. OpenASPI does not currently wait for initial drive
readiness at open, so there is no corresponding open-time wait to interrupt.
BIOS INT 1Bh's role is documented in
[Ralf Brown's interrupt list](https://delorie.com/djgpp/doc/rbinter/id/52/24.html).

The REWIND IMMED semantics and BUSY readiness behavior are described in the
[StorageTek T10000 interface manual](https://docs.oracle.com/cd/E19957-01/MT9259H/MT9259H.pdf),
REWIND and TEST UNIT READY sections. Modern progress sense is described by
[T10 proposal 01-316r1](https://www.t10.org/ftp/t10/document.01/01-316r1.pdf).
