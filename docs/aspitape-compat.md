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

The byte-exact structures and flags are declared in
`include/openaspi/aspitape.h`.  Host tests assert the documented six-byte
`mtop` and fourteen-byte `mtget` sizes.

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

After any write, later reads in the same open session are rejected. On final
close, a written session receives two filemarks. `RMT0` then rewinds; `NRMT0`
spaces backward over one filemark and leaves the tape positioned between the
pair for a later append. A zero-byte DOS write marks the session as written for
this close processing but does not create a zero-length data record.

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
