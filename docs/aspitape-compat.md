# ASPITAPE compatibility target

The compatibility target is the public interface recorded in Ralf Brown's
Interrupt List for Greg Shenaut's `ASPITAPE.SYS`.

## Device names

- `RMT0` through `RMT3`: rewind on final close;
- `NRMT0` through `NRMT3`: no rewind on close;
- optional `MT0`/`NMT0` forms: historical 1024-byte defaults;
- optional `$` suffix variants for name disambiguation.

Only names backed by detected devices should be exposed.  Programs must put an
opened device into DOS raw mode before transferring tape data.

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
Ready. OpenASPI implements all of them. `MTWEOF` is never implicit: a zero-byte
DOS write is a no-op, and only an explicit `MTWEOF` writes filemarks.

Compatibility behavior still requiring verification against the historical
binary includes exact DOS error mapping, buffering, partial-transfer corner
cases, raw-mode enforcement, and exact close/rewind timing.

## Current transfer subset

One DOS character-device read maps to one variable-block SCSI `READ(6)`.
Managers advertising ASPI extension flag `0002h` return a residual count, so
short records produce the correct DOS byte count. With older managers, such as
the tested Tekram 1.60 manager, an exact-size record works directly and a valid
fixed-format ILI information field supplies the length of a short record.

A filemark with no data completes as one zero-byte read; a filemark delivered
with data defers that zero-byte result until the next read. EOM is an error by
default and becomes a zero/partial successful result only after IOCTL function
`03h` selects the historical ignore-EOT policy. Negative ILI (record larger
than the caller's buffer) remains an error.

One non-empty DOS write maps to one variable-block SCSI `WRITE(6)`. A complete
write returns the input byte count. ASPI residuals are validated when the
manager supports them; write protection and other CHECK CONDITION results stay
failed DOS requests and remain visible through `mtget`. Fixed-block mode
remains unavailable.

The current implementation discovers and exposes only the first tape drive.
Medium changers and tape-library robotics are outside this stage.

Both device headers advertise DOS open/close notifications. OpenASPI counts
`RMT0` opens and issues synchronous SCSI REWIND only when its final tracked
handle closes. Closing `NRMT0` never changes position. OpenASPI's own scan and
status tools therefore use `NRMT0`.
