# Native tape LOAD/UNLOAD/RETENSION

The native DOS CONTROL binding adds synchronous sequential-access media
commands. These operate one selected tape drive; library/changer support
remains separate. LOAD cannot insert a physically absent cartridge.

## Wire contract

The existing packed 64-byte CONTROL packet/version `0100h` is unchanged.
Flags, block size, count and reserved bytes must be zero. Invalid requests
are rejected before submission without overwriting the caller's packet.

| Operation | Number | Provider bit | CDB byte 4 |
| --- | --- | --- | --- |
| LOAD | 10 | `4000h` | `01h` |
| UNLOAD | 11 | `8000h` | `00h` |
| RETENSION | 18 | `20000000h` | `03h` (LOAD with RETEN) |

The complete current operation mask, including [removal controls](native-tape-removal.md),
is `3FFFFFFFh`. Capability bits describe
provider entry points, not confirmed support by the attached drive. Each
accepted operation issues exactly one six-byte `1Bh` CDB with no data buffer.
IMMED and remaining CDB fields are zero; RETEN is set only by RETENSION.
RETENSION has its own capability bit: LOAD support does not imply it, and RETEN
without LOAD is never sent. Tape byte 4 uses LOAD, not
CD START STOP's LoEj semantics. There is no implicit readiness probe, rewind,
flush, filemark, retry or software fallback.

## Ownership, completion and recovery

Active native writers, legacy buffered/written/error state, pending rewind,
multiple open handles, buffered aliases and cached data reject the command as
BUSY without a CDB. Successful commands return completion `0003h`
(SUBMITTED|DONE), opcode `1Bh` and clean command diagnostics. They make no BOT
or READY claim; subsequent explicit READY/data commands establish whether
media is available. No cached loaded-state capability is invented.

A submitted failure returns completion `0005h` (SUBMITTED|POSITION_UNKNOWN),
qualified host/target/sense diagnostics and retained native FAILED (`40h`).
Deferred sense, contradictory completion, target BUSY and FILEMARK sense are
failures rather than successful media actions. No failed command is replayed.

Unlike relative SPACE, explicit LOAD/UNLOAD/RETENSION remain available when FAILED or
DIRTY|FAILED (`60h`) survives a closed/aborted session. They preserve that
state even on success: loading a tape does not finalize abandoned output or
establish its position. Native data I/O and SPACE remain blocked until an
explicit successful native REWIND confirms BOT and clears native uncertainty.
READY can inspect the drive but cannot clear that uncertainty. Applications
must distinguish completed media action from a recovered data session.

## Consumer and qualification

OpenTape's `ot_native_execute` / `ot_dos_native_execute` accept operations
10/11/18, check the individual capability bit and validate the returned packet.
The DOS UI's tape controls offer RETENSION on key N.

```text
OPENTAPE --native-unload --device NRMT0
OPENTAPE --native-load --device NRMT0
OPENTAPE --native-retension --device NRMT0
OPENTAPE --native-ready --device NRMT0
OPENTAPE --native-rewind --device NRMT0
```

There are no count, refresh or immediate-mode options. A successful
media command returns CLI status 0 even if earlier native uncertainty remains;
the localized warning remains visible. Command failure returns 2, malformed
arguments 1. Snapshot status still reports an uncertain native session as 2.

Host validation/SDK tests and OpenTape's `dos-native-media-smoke` exercise the
installed production provider in disposable QEMU DOS images with the
memory-only `tests/mockmedia.inc` manager. Coverage includes exact CDBs and
counts, invalid packet preservation, multiple handles, active/abandoned clean
and dirty writer claims, empty-drive READY/REWIND/READ, legacy residual support,
host/unsupported/deferred/contradictory/target/BUSY/FILEMARK failures, explicit
recovery and both CLI languages. Counters reject hidden marks/flushes. These
tests do not qualify physical-drive behavior or Windows bindings.
