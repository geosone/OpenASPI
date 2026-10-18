# ASPITAP.SYS

`ASPITAP.SYS` is planned as an ASPITAPE-compatible DOS character-device
driver.  The current assembly file is only a loadable bootstrap image.  It
must not be used with valuable media.

Implementation order:

1. locate the DOS ASPI manager and call its entry point safely;
2. enumerate sequential-access devices (SCSI peripheral type `01h`);
3. create the compatible `RMTx`/`NRMTx` device-header set;
4. implement open, close, raw mode, read and write request handling;
5. implement category `07h` generic IOCTL functions;
6. translate CHECK CONDITION and fixed/descriptor sense data;
7. add fixed- and variable-block tests using an emulator and real drives.

The device currently uses attributes `8000h`, intentionally advertising no
IOCTL or open/close support.  Those capability bits must only be enabled when
their request handlers exist.
