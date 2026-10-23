# ASPICTL

DOS drive-letter controls through the installed block driver or
MSCDEX/SHSUCDX, rather than a second direct-ASPI implementation.

```text
ASPICTL EJECT F:
ASPICTL CLOSE D:
ASPICTL LOCK F:
ASPICTL UNLOCK F:
ASPICTL STATUS F:
ASPICTL EJECT F: /FORCE
```

The same executable is distributed as `EJECT.EXE`, `CLOSE.EXE`, `LOCK.EXE`,
`UNLOCK.EXE` and `STATUS.EXE`. The command registry in `commands.def` drives
both dispatch and packaged aliases, including future registered commands.
It selects
the operation from its invoked filename:

```text
EJECT F:
EJECT F: /FORCE
CLOSE D:
LOCK F:
UNLOCK F:
STATUS F:
```

MSCDEX drive detection selects the CD packet interface. Other drives use
DOS generic block IOCTLs; the driver decides whether the medium and operation
are supported. CLOSE is restricted to CD drives. Unsupported operations
return an error rather than attempting transport-specific guesses. STATUS
reports the block driver's lock count or the CD device-status word.

Normal EJECT respects the driver's locks. `/FORCE` is accepted only for
EJECT: it releases all lock counts reported by the block driver, or sends
CD unlock, then attempts eject. An unlock failure stops the sequence. It
does not bypass hardware errors or Windows volume locks. The count API has
no process ownership, so this explicitly releases other callers' pending
media locks too. DOS filesystem buffers are flushed before block eject.

Exit codes: 0 success, 1 failed device operation, 2 invalid arguments or
CLOSE on a non-CD drive. Commands require an explicit drive letter plus
colon and do not assume the current drive.

Build with `make`. Binaries are under `build/dos/` and included in the
installer payload. See [media-control implementation and tests](../../docs/media-control.md).
