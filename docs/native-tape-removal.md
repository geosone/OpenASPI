# Native tape medium removal control

LOCK/UNLOCK control cartridge removal through synchronous PREVENT/ALLOW MEDIUM
REMOVAL. They are independent of native writer claims, filesystem locks and
write protection. They neither move tape nor finalize output. Changer control
and automatic locking around archive jobs remain separate future work.

## Packet and command

The existing version `0100h`, packed 64-byte CONTROL envelope is unchanged.
Count, request flags and block size are zero. Constructors, response validation
and DOS assembly offsets retain the established ABI.

| Operation | Number | Provider capability | CDB byte 4 |
| --- | --- | --- | --- |
| LOCK | 12 | `00010000h` | `01h` (prevent removal) |
| UNLOCK | 13 | `00020000h` | `00h` (allow removal) |

The complete current provider operation mask, including
[position observation](native-tape-position.md), is `3FFFFFFFh`. These new bits
occupy the high WORD; consumers must retain all 32 bits. Each accepted operation
issues exactly one six-byte CDB with opcode `1Eh`, no data buffer and remaining
CDB bytes zero. Persistent-prevent variants are not requested. There is no
implicit LOAD, readiness probe, flush, mark, rewind, retry or fallback.
Provider capability advertises an entry point, not verified device support.

## State and errors

The ordinary single-owner/no-buffer/no-rewind/no-active-writer guards apply.
Legacy written/buffered/saved-error state rejects the command as BUSY before
submission. Released native FAILED (`40h`) and DIRTY|FAILED (`60h`) sessions
may explicitly LOCK/UNLOCK, but retain their previous state. Success cannot
repair an uncertain position or finalize abandoned data. Locking does not
prevent a later native write claim; unlocking does not release that claim.

Successful completion is exactly `0003h` (SUBMITTED|DONE), opcode `1Eh`, clean
command diagnostics and unchanged native state. It makes no BOT, READY or
write-protection claim. The provider does not invent a cached lock-state field.

A submitted failure returns ERROR, completion `0001h` (SUBMITTED only), command
diagnostics and unchanged native state. Unlike failed SPACE/LOAD/UNLOAD, failed
LOCK/UNLOCK does not set POSITION_UNKNOWN or latch native FAILED: it does not
move tape. An ambiguous command failure leaves removal policy unconfirmed;
there is no guessed successful lock state, retry or automatic opposite command.
Host, deferred, unsupported, target BUSY, FILEMARK and contradictory completion
failures remain failures. Earlier native uncertainty is never cleared.

A successful non-moving removal command preserves queued legacy filemark/EOF
and buffered stream state. Rewind must not silently issue UNLOCK. An explicitly
attempted UNLOAD while removal is prevented may fail; that remains a failed
media operation with the existing LOAD/UNLOAD uncertainty rules. The caller
must explicitly allow removal and establish position as needed afterward.

## OpenTape and qualification

```text
OPENTAPE --native-lock --device NRMT0
OPENTAPE --native-unlock --device NRMT0
```

The shared `ot_native_execute` and DOS wrapper check the individual capability
bit, validate the response and close once. CLI exit status is 0 for a completed
removal command, 2 for errors and 1 for malformed arguments. Prior native
uncertainty is still printed after an otherwise successful command. A build
against older native provider headers rejects the new CLI verbs without opening
a device or accidentally mapping them to READY.

Host and installed DOS tests cover the high-WORD capabilities, exact CDB and
submission counts, invalid request preservation, multiple handles, active and
abandoned clean/dirty writers, unchanged state on failure, prevented UNLOAD,
explicit recovery, preserved legacy queued EOF, old provider headers and both
CLI languages. OpenTape's `dos-native-lock-smoke` uses `tests/mocklock.inc` and
disposable QEMU DOS images. No physical drive or Windows binding is qualified.
