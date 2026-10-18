# ASPITAP.SYS

`ASPITAP.SYS` is planned as an ASPITAPE-compatible DOS character-device
driver.  It locates the active `SCSIMGR$`, enumerates ASPI addresses, and
installs linked `RMT0` and `NRMT0` headers for the first sequential-access
device it finds.  It exits without remaining resident when no ASPI tape is
available.

The non-writing category `07h` control subset supports `mtget`, enable/ignore
EOT policy, `MTNOP` (TEST UNIT READY), forward/backward file and record spacing,
rewind, and rewind/unload. Variable-block reads use the ASPI manager's residual
count to return short record lengths to DOS when available; exact-length reads
also work with older managers without that extension. Fixed-block reads, data
writes, `MTWEOF`, and rewind-on-close are still rejected, so the driver must
not yet be used for backup or restore.

Implementation order:

1. [done] locate the DOS ASPI manager and call its entry point safely;
2. [done] enumerate sequential-access devices (SCSI peripheral type `01h`);
3. [partial] create the compatible `RMTx`/`NRMTx` device-header set (`RMT0`
   and `NRMT0` are present; units 1 through 3 follow multi-device discovery);
4. [partial] implement open, close, raw mode, read and write request handling
   (variable-block reads are present; fixed-block reads, close semantics and
   writes remain);
5. [partial] implement category `07h` generic IOCTL functions (all documented
   non-writing operations are present; `MTWEOF` remains safety-gated);
6. translate CHECK CONDITION and fixed/descriptor sense data;
7. add fixed- and variable-block tests using an emulator and real drives.

The device uses attributes `8040h`, advertising the implemented generic IOCTL
handler but not open/close or legacy IOCTL support.
