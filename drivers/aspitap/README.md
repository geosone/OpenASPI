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

By default, a final `RMT0` close sends REWIND with IMMED set. Reopening and
querying status remain possible while `mtget` reports `REWINDING`. The next
read, write, tape operation or additional rewind waits for readiness, polling
at most once per BIOS tick for about three minutes. BUSY and recognized
rewind/becoming-ready sense are retried; other errors fail immediately and
keep the pending flag so a later request cannot bypass the wait. The BIOS
tick calculation handles midnight rollover without consuming DOS' midnight
flag. `-w` selects synchronous rewind on close; explicit `MTREW` is always
synchronous. Command execution timeouts remain the ASPI manager's responsibility.

`-i` enables Ctrl-Break detection during this deferred readiness wait. The
driver temporarily hooks BIOS INT 1Bh and chains the previous handler, then
restores it on success, error, timeout or interruption. If another resident
component chains above this hook during the wait, its chain remains intact.
A handled Ctrl-Break fails the current request without canceling the drive's
physical rewind; `REWINDING` stays set and a later request can retry. Ctrl-C
and interruption inside a blocking ASPI manager call are not implemented by
this option. DOS/application Ctrl-Break handlers retain their normal behavior.

Data transfers require exactly one open tape handle and reject one-byte
requests by default. The latter is the historical cooked-mode safeguard:
applications are expected to put the character device into raw mode. The
historical `-m` and `-s` `CONFIG.SYS` overrides enable multiple-open and
single-byte transfers respectively. `-tX` replaces the `M` in all device
names with letter `X`, while `-$` appends a dollar sign to reduce DOS filename
collisions. Options may be clustered. For example:

```text
DEVICE=ASPITAP.SYS -ms$tS
```

This example installs `RST0$` and `NRST0$`.
The name letter must follow `-t` immediately and be in `A` through `Z` (case
insensitive). An incomplete `-t`, an invalid letter, an empty option prefix,
or an unsupported switch aborts installation with an error message. In
particular, `-b` is not implemented and must not
be supplied. The driver pathname is skipped as a whole token, so hyphens in
directory names do not enable options.

`-v` and the equivalent `-d` enable verbose initialization. They show adapter
count, manager/adapter identities and extension flags, the selected tape's
address and block mode (fixed sizes are hexadecimal), and both actual device
names. Failed discovery distinguishes an unavailable manager, a failed host
inquiry, an empty adapter list and the absence of a tape. Diagnostics reuse
discovery results without issuing additional ASPI commands.

CHECK CONDITION decoding accepts both fixed and descriptor sense. Descriptor
information and stream-command descriptors provide residual ILI lengths,
FILEMARK and EOM without requiring the ASPI residual extension.

Implementation order:

1. [done] locate the DOS ASPI manager and call its entry point safely;
2. [done] enumerate sequential-access devices (SCSI peripheral type `01h`);
3. [partial] create the compatible `RMTx`/`NRMTx` device-header set (`RMT0`
   and `NRMT0` are present; units 1 through 3 follow multi-device discovery);
4. [partial] implement open, close, raw mode, read and write request handling
   (variable-block reads and rewind/no-rewind close semantics are present;
   variable-block writes and mandatory fixed-block transfers are present;
   default cooked-mode and multiple-open safeguards and their `-s`/`-m`
   overrides are present; historical optional buffering remains);
5. [done] implement category `07h` generic IOCTL functions, including explicit
   `MTWEOF` filemark writing;
6. [done] translate CHECK CONDITION fixed/descriptor sense data needed for
   FILEMARK, EOM, ILI and the reported sense key;
7. [partial] add fixed- and variable-block tests (emulator coverage is present;
   real-drive fixed-block qualification remains).

The device uses attributes `8840h`, advertising the implemented open/close and
generic IOCTL handlers but not legacy IOCTL support. Non-destructive diagnostic
tools open `NRMT0`, so merely scanning or displaying status never rewinds tape.
