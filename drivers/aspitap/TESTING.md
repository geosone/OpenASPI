# ASPITAP testing

For setup, options and behavior, see the [driver documentation](README.md).
For build requirements and other test targets, see the
[build guide](../../docs/building.md).

## Local checks

`make check` runs host-side ASPI/SCSI tests, validates the DOS device-header
layout and compiles byte-exact tape ABI checks with the 16-bit DOS compiler.

## Emulated tape

```sh
make dos-tape-smoke
```

The test boots the local SvarDOS fixture in QEMU with a test-only ASPI manager.
It does not access real tape media. Required local test media are catalogued
in [reference material](../../docs/reference-material.md).

The manager checks ordered SCSI command sequences and record contents.
Unexpected media commands cause a persistent fixture failure, so unwanted
record retries or finalization commands cannot pass unnoticed. Scanner
INQUIRY probes are separate from the ordered media scenario.

### Transfers and tape operations

Fixtures cover raw-mode setup, full and residual variable-block reads,
fixed- and descriptor-sense ILI short records, filemarks, both EOM policies,
variable-block writes, write protection and explicit `MTWEOF`. They validate
readiness, spacing, rewind and unload commands. Mandatory fixed-block fixtures
check block-limit detection, integral-request enforcement and fixed read/write
CDBs. Transfer scenarios also cover managers without ASPI residual support.

Nested opens check exclusive transfers and final-handle close processing.
Single-byte cooked-mode requests are rejected unless explicitly permitted.
Written-session cases check read-after-write rejection, the two-filemark
terminator and append positioning. Both status layouts are compared with
guard bytes after their destination buffers.

### Configuration and diagnostics

Clustered, slash-prefixed and mixed-case options are tested, including the
renamed `RST0$`/`NRST0$` aliases and transfer-guard overrides. Invalid names,
incomplete options, unsupported switches and bare prefixes must reject
installation. Boot-screen capture checks verbose output, fixed-block sizes,
renamed devices and discovery failure reasons; normal startup stays concise.

### Rewind and interruption

Rewind fixtures check default IMMED, synchronous `-w`, pending status and
read/write/control readiness barriers. They emulate fixed/descriptor progress
sense, SCSI BUSY and immediate media errors. An accelerated guest BIOS clock
tests timeout and midnight rollover. Ctrl-Break cases verify opt-in
interruption, retry, chaining of the previous BIOS handler and restoration of
the interrupt vector. Other transfer fixtures use `-w` for deterministic
synchronous-close command sequences.

### Buffering and failure handling

Buffered cases validate record contents, zero padding, deferred filemarks,
cache invalidation, mixed-mode guards and 64K far-pointer crossings with
variable/fixed-block drives, residual/legacy managers and renamed aliases.
Failed and short writes retain their diagnostic snapshot across readiness
checks, rejected operations, close and reopen. Recovery requires a complete
successful physical write, not merely accepting bytes into the cache.

Finalization cases inject errors in filemarks, append backspacing and close
rewind through raw and buffered names, including immediate rewind and the
16-byte status ABI. The sequence must stop at the failed step and the status
must retain the original cause after reopen and successful readiness checks.
Empty-write cases check the tested SvarDOS kernel's suppression of zero-byte
DOS writes: an otherwise unwritten, non-rewinding session must issue neither
data writes nor filemarks. See the
[compatibility notes](../../docs/aspitape-compat.md) for this DOS API distinction.

## Focused runs

Pass fixture names to the script to run a subset:

```sh
bash tests/dos_tape_ioctl.sh buffered-recovery final-marks-raw final-empty
```

The available names are listed in [dos_tape_ioctl.sh](../../tests/dos_tape_ioctl.sh).
Each invocation recreates `build/dos-tape-ioctl/`; do not run multiple copies
against that output directory concurrently.

## Virtual-drive integration

`make dos-mhvtl-smoke` exercises the driver through an external DOS ASPI
manager and QEMU passthrough to mhVTL. Setup, device selection and safety
requirements are in [qemu-mhvtl.md](../../docs/qemu-mhvtl.md).

Emulator coverage does not qualify the write path for production backups on
real drives and media. Real-drive fixed-block and broader error/partial-
transfer qualification remain outstanding.
