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
Ready.

Compatibility behavior still requiring verification against the historical
binary includes DOS error mapping, EOF/EOM read semantics, buffering, partial
transfer reporting, raw-mode enforcement, and exact close/rewind timing.
