# OTAPINFO

Read-only inspection of ASPITAP's native OTAP interface. It is separate from
[TAPECTL](../tapectl/README.md), which uses the historical ASPITAPE status ABI.

```dos
OTAPINFO
OTAPINFO NRMT0
OTAPINFO NRMT0 /REFRESH
OTAPINFO NRST0$ /REFRESH
```

The default alias is `NRMT0`. Accepted names are `NR` + letter A..Z + `T` + unit
0..3, optionally followed by `$`. Only units actually exposed by the installed
driver can be opened; accepting a unit name does not add multi-drive support.
Use the alias matching ASPITAP's configured letter/suffix. Buffered and
rewind-on-close aliases are not accepted by this tool.

Without `/REFRESH`, QUERY returns the current session snapshot without SCSI
probing. `/REFRESH` requests bounded read-only identity/limits/mode probes when
the provider permits them. Busy or unsafe sessions can return BUSY without
probing. Neither form reads/writes tape records, rewinds or changes compression.

The output includes API result, valid-group mask and session state. Identity,
block limits and current block size are printed only when their groups are
valid. Compression is reported as unknown, unsupported or supported; absent
probe data must not be interpreted as unsupported. An unverified-length notice
means the legacy manager could not establish exact probe byte counts.

## Results

- Exit 0: a valid QUERY reply with result OK and no saved legacy write-error bit.
  A snapshot can succeed while capabilities remain unknown; this is not proof
  that the drive is ready or a backup succeeded.
- Exit 2: a valid PARTIAL/BUSY query, or the saved legacy write-error session bit.
- Exit 1: invalid arguments, open/delivery/validation/close or output failure.

The tool verifies a character-device handle, validates the returned packet,
closes the handle and restores its temporary critical-error handler. Diagnostics
remain observations; no automatic media recovery is attempted.

Build with `make check` or `make`; the executable is `build/dos/OTAPINFO.EXE`.
See [native QUERY](../../docs/native-tape-query.md) for packet semantics and
[ASPITAP testing](../../drivers/aspitap/TESTING.md) for provider/client scenarios.
