# ASPITAP.SYS

`ASPITAP.SYS` is planned as an ASPITAPE-compatible DOS character-device
driver.  It locates the active `SCSIMGR$`, enumerates ASPI addresses, and
installs linked `RMT0` and `NRMT0` headers for the first sequential-access
device it finds.  It exits without remaining resident when no ASPI tape is
available.

The read-only control subset supports category `07h` `mtget`, enable/ignore
EOT policy, and `MTNOP` (SCSI TEST UNIT READY). Data reads, writes, positioning,
and rewind-on-close are still rejected, so the driver must not yet be used for
backup or restore.

Implementation order:

1. [done] locate the DOS ASPI manager and call its entry point safely;
2. [done] enumerate sequential-access devices (SCSI peripheral type `01h`);
3. [partial] create the compatible `RMTx`/`NRMTx` device-header set (`RMT0`
   and `NRMT0` are present; units 1 through 3 follow multi-device discovery);
4. implement open, close, raw mode, read and write request handling;
5. [partial] implement category `07h` generic IOCTL functions (`mtget`, EOT
   policy, and `MTNOP` are present);
6. translate CHECK CONDITION and fixed/descriptor sense data;
7. add fixed- and variable-block tests using an emulator and real drives.

The device uses attributes `8040h`, advertising the implemented generic IOCTL
handler but not open/close or legacy IOCTL support.
