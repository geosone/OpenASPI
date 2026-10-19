# TAPECTL

`TAPECTL.COM` is the small, non-destructive DOS tape diagnostic. It opens
`NRMT0` (the non-rewinding name), enables DOS raw mode and reports:

- the ASPI host-adapter, target and LUN address;
- state flags and, when available, the driver error code;
- SCSI status, sense key and operation code;
- the residual byte count.

Values are printed in hexadecimal. The tool first requests OpenASPI's explicit
sixteen-byte status (`0705h`), so it works with either driver status-layout
option. If that query is unsupported, it falls back to the manual's fourteen-
byte `0702h` layout. That fallback cannot autodetect third-party drivers using
the different sixteen-byte layout at the same function number. See the
[ABI comparison](../../docs/aspitape-compat.md#two-historical-status-layouts).

## Status and readiness

Running without arguments only retrieves status; it sends no SCSI command:

```dos
TAPECTL
```

`TAPECTL /READY` additionally sends non-destructive `TEST UNIT READY` and
retrieves status again. An empty/not-ready drive can return an error.
Neither mode reads or writes tape data, changes tape position or attempts
media recovery.

## Device selection

The default is `NRMT0`. Use `/DEVICE:name` for a different non-rewinding alias,
for example after configuring the driver with `-tS -$`:

```dos
TAPECTL /DEVICE:NRST0$
TAPECTL /READY /DEVICE:NRST0$
TAPECTL /DEVICE:NST0$
```

The last example selects the optional buffered alias and requires driver
option `-b`. Device selection and `/READY` may appear in either order and are
case-insensitive. A `-` option prefix is also accepted. Specify the device
once, without quotes, paths or a trailing DOS colon.

Accepted names are `NR` + letter + `T` + unit (raw), or `N` + letter + `T` +
unit (buffered), optionally followed by `$`. Letters are A through Z and
units are 0 through 3; accepting a name does not create additional drives
(the current driver exposes only unit 0). Displayed names retain the dollar
suffix. `/READY` must be a complete token; `/ALREADY` does not request I/O.

Rewind-on-close names such as `RMT0` and `MT0`, other DOS devices, wildcards
and file paths are rejected before opening. After a valid name is opened,
TAPECTL verifies that DOS reports a character device before setting raw mode
or issuing tape queries. An ordinary file with that name is closed without
modification. The selected non-rewinding name is shown in status and open-error
messages. An unavailable but valid unit name returns an open error.

## Saved write warnings

OpenASPI state bit `0200h` identifies a saved write/finalization diagnostic.
When it is present, TAPECTL prints an explicit warning. The numeric diagnostic
fields describe that saved failure, not necessarily the latest readiness
command. This includes raw or buffered data writes, short writes and failed
final-close filemarks/positioning.

A successful readiness check does not prove that an earlier write or backup
succeeded and does not suppress the warning. If a readiness check fails while
a write diagnostic is saved, its DOS error is reported separately; the status
line still describes the saved write cause. The tool never clears the snapshot.
Its lifetime and application recovery rules are described in the
[driver documentation](../../drivers/aspitap/README.md#write-and-finalization-failures).

## Exit status

| Code | Meaning |
|------|---------|
| 0 | Status retrieved (and readiness successful when requested), with no saved-write flag observed. |
| 1 | Invalid device selection, a non-device file, or an open/query/readiness failure. This takes priority over code 2. |
| 2 | Queries succeeded, but a saved write/finalization failure was observed. |

Code 0 confirms the diagnostic operation, not backup integrity or media
qualification. In particular, the fourteen-byte fallback has no saved-write
state bit and cannot provide that warning classification.

DOS `IF ERRORLEVEL` tests mean "at least", so test the higher code first:

```dos
TAPECTL /READY
IF ERRORLEVEL 2 GOTO WRITEFAIL
IF ERRORLEVEL 1 GOTO PROBEFAIL
```
