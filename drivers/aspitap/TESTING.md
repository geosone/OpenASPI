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
readiness, spacing, rewind and unload commands. Raw fixtures compare the
exact six-byte CDBs for maximum forward spacing (`7FFFFFh`), maximum backward
magnitude (`800000h`) and unsigned filemarks (`FFFFFFh`). Out-of-range forward
counts must fail rather than encode a backward movement; the pending-rewind
cases verify rejection before polling. Host CDB tests cover the same signed
limits and leave the destination unchanged on rejected inputs. Buffered
fixtures retain and verify their pending write tail after these rejections.

Malformed-read cases combine oversized or nonzero-high-word manager residuals
with descriptor ILI, fixed-format FILEMARK and descriptor EOM under ignore-EOT.
All must fail with the full request remaining, preserve SCSI diagnostics and
avoid queuing a synthetic EOF. The following valid read must reach the manager.
Both status ABIs are exercised; legacy sense-based completions remain covered.

Stream-sense cases combine ILI, FILEMARK and ignored EOM with MEDIUM ERROR or
HARDWARE ERROR and require failed reads with the original sense key retained.
They cover legacy sense-derived lengths and both status ABIs. RECOVERED ERROR
is a positive control: valid short data, filemarks and ignored EOM still work.
Raw-write cases combine ignored EOM with MEDIUM ERROR and zero residual; they
must fail and retain the saved write error across readiness checks and reopen.

Completion-envelope cases retain plausible ILI/FILEMARK/EOM sense while
injecting host selection timeout, aborted ASPI status, SCSI GOOD instead of
CHECK CONDITION, or SCSI BUSY. Reads and ignore-EOT writes must remain errors.
Legacy reads and both status ABIs are covered, including BUSY's error `22`.
Write snapshots must survive readiness checks and reopen without driver replay.

Combined-flag fixtures exercise FILEMARK+EOM, ILI+EOM and all three flags.
Default EOT policy must reject them; ignore-EOT permits only valid lengths.
Negative ILI remains an error with FILEMARK and/or ignored EOM, without queuing
a synthetic EOF. A positive ILI+FILEMARK returns its short payload and exactly
one deferred zero-byte read. Residual/legacy managers and both ABIs are covered.

Mandatory fixed-block fixtures check block-limit detection, integral-request
enforcement and fixed read/write
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
sense, SCSI BUSY and immediate media errors. Invalid operation numbers and
out-of-range forward/backward counts are rejected before polling, preserving
pending rewind state and the preceding command diagnostics in both status
layouts. An accelerated guest BIOS clock
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

Raw-write cases exercise the same persistent diagnostics with variable/fixed
blocks, residual/legacy managers and both status layouts. Short writes,
EOT with and without error suppression, and invalid manager residuals must
remain failed DOS writes without an automatic remainder WRITE. The saved
tuple survives readiness checks, guard/IOCTL errors and reopen. Explicit
successful raw recovery is checked both in the same session and after reopen.

Finalization cases inject errors in filemarks, append backspacing and close
rewind through raw and buffered names, including immediate rewind and the
16-byte status ABI. The sequence must stop at the failed step and the status
must retain the original cause after reopen and successful readiness checks.
Explicit `MTWEOF` failure cases check the same persistence through raw and
buffered aliases, mandatory fixed blocks and both status layouts. An otherwise
unwritten non-rewinding session must not retry failed marks on close.
Empty-write cases check the tested SvarDOS kernel's suppression of zero-byte
DOS writes: an otherwise unwritten, non-rewinding session must issue neither
data writes nor filemarks. See the
[compatibility notes](../../docs/aspitape-compat.md) for this DOS API distinction.

### TAPECTL reporting

Post-scenario utility runs check explicit saved-write warnings and DOS exit
status 2 for buffered/raw-short/finalization failures and the 16-byte legacy
entry point. A successful `/READY` must retain that warning and exit status;
a failed readiness check must instead return operational-error status 1 while
still displaying the saved write cause. After successful physical recovery,
status-only queries return 0 without a stale warning. The mock rejects any
unexpected media command, including recovery or repositioning by the utility.

Device-selection fixtures cover renamed raw/buffered aliases, dollar suffixes,
mixed case, option order and `/READY` token boundaries. Invalid paths,
rewind-on-close names, missing values and repeated selections must fail before
opening; unavailable valid units must produce an open error. A normal file
whose name matches the device pattern must be rejected as a non-device, with
its contents unchanged. These checks require no driver-side name special cases.

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
