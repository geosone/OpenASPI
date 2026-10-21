# ASPITAP.SYS

`ASPITAP.SYS` is an ASPITAPE-compatible DOS character-device driver under
development. It locates the active `SCSIMGR$`, enumerates ASPI addresses, and
installs linked `RMT0` and `NRMT0` headers for the first sequential-access
device it finds.  It exits without remaining resident when no ASPI tape is
available.

Only the first tape drive is currently exposed. Medium changers and
tape-library robotics are intentionally deferred. OpenASPI provides the
transport driver; backup formats and the application UI belong to OpenTape.

## Transfers and controls

The category `07h` controls support `mtget`, enable/ignore EOT policy, `MTNOP`
(TEST UNIT READY), forward/backward file and record spacing, rewind,
rewind/unload and explicit filemark writing. Variable-block reads use the ASPI
manager's residual count to return short record lengths to DOS when available;
exact-length reads also work with older managers without that extension.
`RMT0` rewinds only when its final tracked handle closes; `NRMT0` never rewinds
on close. Variable-block writes and explicit `MTWEOF` filemarks are emulator-
tested, including a failed write-protected request. Fixed-block transfers are
selected automatically for drives whose SCSI `READ BLOCK LIMITS` response
requires one block size; nonintegral raw DOS requests are rejected. The historical
optional `MT0`/`NMT0` 1024-byte software-buffering layer is enabled by `-b`.
The write path is not yet qualified for production backups
on real media.

Short-record lengths use ASPI residual counts when available and fixed- or
descriptor-format ILI information otherwise. A filemark returns one zero-byte
read; EOM remains an error unless the application selects the ignore-EOT
policy. Write-protection errors remain failed DOS writes and are visible
through `mtget`. CHECK CONDITION decoding accepts both fixed and descriptor
sense; descriptor information and stream-command descriptors supply residual
ILI lengths, FILEMARK and EOM without requiring ASPI residual support.
An advertised ASPI residual larger than the request or wider than 16 bits is
always an error, even with FILEMARK, ILI or ignored EOM. Such a read reports
zero accepted bytes and cannot manufacture a successful EOF.
FILEMARK, ILI and ignored EOM are accepted as normal stream conditions only
with sense key NO SENSE or RECOVERED ERROR. Other sense keys remain failed
reads or writes even if the same response carries a stream flag. In
particular, ignore-EOT does not hide a media error on a full-length write.

The final close of a written session emits two filemarks. `RMT0` then rewinds;
`NRMT0` backspaces one filemark to preserve the historical append position.
Reads after a write in the same session are rejected.

Forward file/record spacing accepts counts up to `7FFFFFh`; backward spacing
accepts a magnitude up to `800000h`. Larger counts fail before any readiness
poll or tape command, so forward requests cannot wrap into backward movement.
`MTWEOF` uses an unsigned field and still accepts up to `FFFFFFh` filemarks.

## Buffered aliases

With `-b`, `MT0` rewinds and `NMT0` preserves the append position. Their
software cache splits and combines 1024-byte physical transfers, even when
the caller requests another byte count. Final close pads a partial written
record with zeros before the two-filemark terminator. Filemarks are delivered
after all preceding cached data. Status, EOT policy and `MTNOP` preserve the
cache; tape-moving `mtop` calls discard it, including pending write bytes, as
documented for historical ASPITAPE. Switching from read to write also discards
unread cached data. A session's first open selects raw or buffered transfers;
opens using other names remain counted, but their data transfers are refused,
even with `-m`. DOS does not reliably enforce device-open errors.

## Write and finalization failures

Physical buffered writes must complete the full 1024 bytes. An error or
partial write latches failure until the session ends: subsequent data writes
and finalization fail without replaying an ambiguous record or adding a
misleading terminator. A diagnostic snapshot remains available through `mtget`,
including after readiness/control commands and reopen. The sixteen-byte status
format marks that snapshot with `OA_MT16_STATE_WRITE_ERROR` (`0200h`). Only a
complete successful physical data write in a new session clears it; accepting
bytes into the cache does not. Reopening does not recover tape position:
applications must choose their recovery procedure before writing again.
DOS may ignore a failed device-close request,
so delayed flush errors must also be checked through tape status. The extra
1024-byte cache is retained in DOS memory only with `-b`.

The same diagnostic snapshot also records failed final-close filemarks,
backspacing and written-session rewind commands for raw and buffered names.
Finalization stops on the first error and does not retry on a duplicate close.
It remains visible across reopening and successful readiness checks, because
DOS may otherwise discard the close failure.

Failed explicit `MTWEOF` commands save the same diagnostic snapshot. Invalid
counts and failures in the preceding rewind-readiness wait do not replace it.
A successful filemark command does not clear a saved write failure; only a
complete physical data write can do that. This does not add retries or change
the existing control/close positioning policy after an error.

Raw physical write failures and short raw writes save the same diagnostic
snapshot. A short raw write returns an error instead of successful partial
completion: DOS can otherwise resubmit the remainder as another tape record.
The residual byte count remains available in status, including with the
ignore-EOT policy selected. Invalid block sizes and access guards do not
replace an earlier saved physical-write failure.

Unlike a failed buffered session, a raw session is not locked against explicit
later writes. A complete successful physical write clears its saved error,
including within the same raw session; choosing safe positioning/recovery is
the caller's responsibility. Existing raw control/final-close behavior is
unchanged, so a successful close or readiness check is not proof that earlier
data writes completed.

## Rewind and interruption

By default, a final `RMT0` close sends REWIND with IMMED set. Reopening and
querying status remain possible while `mtget` reports `REWINDING`. The next
read, write, valid tape operation or additional rewind waits for readiness,
polling at most once per BIOS tick for about three minutes. Invalid operation
numbers and out-of-range counts fail without polling or consuming pending
rewind state. BUSY and recognized
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

## Configuration

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
or an unsupported switch aborts installation with an error message.
The driver pathname is skipped as a whole token, so hyphens in
directory names do not enable options.

### Status layout

`-2` selects the original C headers' sixteen-byte status layout for IOCTL
`0702h`; the default remains the manual's fourteen-byte layout. Applications
must allocate the matching structure. New clients can use `0705h` to request
sixteen bytes explicitly in either mode. `TAPECTL` supports both installation
modes. See [the ABI comparison](../../docs/aspitape-compat.md#two-historical-status-layouts).

### Startup diagnostics

`-v` and the equivalent `-d` enable verbose initialization. They show adapter
count, manager/adapter identities and extension flags, the selected tape's
address and block mode (fixed sizes are hexadecimal), and all active device
names. Failed discovery distinguishes an unavailable manager, a failed host
inquiry, an empty adapter list and the absence of a tape. Diagnostics reuse
discovery results without issuing additional ASPI commands.

## Development status

Implementation order:

1. [done] locate the DOS ASPI manager and call its entry point safely;
2. [done] enumerate sequential-access devices (SCSI peripheral type `01h`);
3. [partial] create the compatible `RMTx`/`NRMTx` device-header set (`RMT0`
   and `NRMT0` are present; units 1 through 3 follow multi-device discovery);
4. [partial] implement open, close, raw mode, read and write request handling
   (variable-block reads and rewind/no-rewind close semantics are present;
   variable-block writes and mandatory fixed-block transfers are present;
   default cooked-mode and multiple-open safeguards and their `-s`/`-m`
   overrides and optional `-b` software buffering are present; exact historical
   error mapping and partial-transfer qualification remain);
5. [done] implement category `07h` generic IOCTL functions, including explicit
   `MTWEOF` filemark writing;
6. [done] translate CHECK CONDITION fixed/descriptor sense data needed for
   FILEMARK, EOM, ILI and the reported sense key;
7. [partial] add fixed- and variable-block tests (emulator coverage is present;
   real-drive fixed-block qualification remains).

The device uses attributes `8840h`, advertising the implemented open/close and
generic IOCTL handlers but not legacy IOCTL support. Non-destructive diagnostic
tools open `NRMT0`, so merely scanning or displaying status never rewinds tape.

## Testing and application interface

- [Testing](TESTING.md): emulator scenarios, focused runs and virtual-drive integration.
- [ASPITAPE compatibility](../../docs/aspitape-compat.md): ABI, IOCTLs and detailed semantics.
- [TAPECTL](../../tools/tapectl/README.md): status/readiness diagnostic.
- [Installation](../../installer/README.md) and [build guide](../../docs/building.md).
