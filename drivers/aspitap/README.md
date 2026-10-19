# ASPITAP.SYS

`ASPITAP.SYS` is planned as an ASPITAPE-compatible DOS character-device
driver.  It locates the active `SCSIMGR$`, enumerates ASPI addresses, and
installs linked `RMT0` and `NRMT0` headers for the first sequential-access
device it finds.  It exits without remaining resident when no ASPI tape is
available.

The category `07h` controls support `mtget`, enable/ignore EOT policy, `MTNOP`
(TEST UNIT READY), forward/backward file and record spacing, rewind,
rewind/unload and explicit filemark writing. Variable-block reads use the ASPI
manager's residual count to return short record lengths to DOS when available;
exact-length reads also work with older managers without that extension.
`RMT0` rewinds only when its final tracked handle closes; `NRMT0` never rewinds
on close. Variable-block writes and explicit `MTWEOF` filemarks are emulator-
tested, including a failed write-protected request. Fixed-block transfers are
selected automatically for drives whose SCSI `READ BLOCK LIMITS` response
requires one block size; nonintegral DOS requests are rejected. The historical
optional `MT0`/`NMT0` 1024-byte buffering layer is a separate feature and is
not yet exposed. The write path is not yet qualified for production backups
on real media.

The final close of a written session emits two filemarks. `RMT0` then rewinds;
`NRMT0` backspaces one filemark to preserve the historical append position.
Reads after a write in the same session are rejected.

Implementation order:

1. [done] locate the DOS ASPI manager and call its entry point safely;
2. [done] enumerate sequential-access devices (SCSI peripheral type `01h`);
3. [partial] create the compatible `RMTx`/`NRMTx` device-header set (`RMT0`
   and `NRMT0` are present; units 1 through 3 follow multi-device discovery);
4. [partial] implement open, close, raw mode, read and write request handling
   (variable-block reads and rewind/no-rewind close semantics are present;
   variable-block writes and mandatory fixed-block transfers are present;
   historical optional buffering remains);
5. [done] implement category `07h` generic IOCTL functions, including explicit
   `MTWEOF` filemark writing;
6. translate CHECK CONDITION and fixed/descriptor sense data;
7. [partial] add fixed- and variable-block tests (emulator coverage is present;
   real-drive fixed-block qualification remains).

The device uses attributes `8840h`, advertising the implemented open/close and
generic IOCTL handlers but not legacy IOCTL support. Non-destructive diagnostic
tools open `NRMT0`, so merely scanning or displaying status never rewinds tape.
