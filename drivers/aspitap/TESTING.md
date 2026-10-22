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

The `async` fixture completes tape requests only after three hardware timer
interrupts. It catches premature reuse of a pending SRB and requires IRQs
to remain enabled while the driver waits. All fixtures place DOS autosense
immediately after the actual six-byte CDB, including fixed/descriptor sense
and rewind-progress diagnostics.

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

ILI consistency cases use in-range manager residuals that disagree with
sense: a claimed full transfer, fewer bytes than sense indicates, or a zero
sense residual. Fixed/descriptor sense, a simultaneous FILEMARK and both ABIs
are covered. All contradictions must fail with error `31`, full residual and
no deferred EOF; subsequent reads must still reach the manager. Valid legacy
and combined short-record completions provide positive controls.

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

Deferred-sense cases use fixed `71h` and descriptor `73h` responses with ILI,
FILEMARK and ignored EOM. Reads must fail, including through a legacy manager
and both status ABIs. Full-length ignore-EOT writes also fail and retain their
saved diagnostics across readiness and reopen. Deferred rewind-progress sense
must stop the current wait without polling through to success; a later
explicit request can retry and clear pending rewind.

Combined-flag fixtures exercise FILEMARK+EOM, ILI+EOM and all three flags.
Default EOT policy must reject them; ignore-EOT permits only valid lengths.
Negative ILI remains an error with FILEMARK and/or ignored EOM, without queuing
a synthetic EOF. A positive ILI+FILEMARK returns its short payload and exactly
one deferred zero-byte read. Residual/legacy managers and both ABIs are covered.

Mandatory fixed-block fixtures check block-limit detection, integral-request
enforcement and fixed read/write
CDBs. Transfer scenarios also cover managers without ASPI residual support.

Fixed-block residual cases inject a half-block byte residual on read success,
fixed/descriptor FILEMARK and write success. All must fail with error `31`
and the full request remaining, without deferred EOF or implicit replay.
Write cases verify the saved failure and its clearing after a complete
explicit write. Whole-block EOF cases cover both ASPI byte residuals and
legacy block-count sense information, followed by another valid read.

Multi-block cases request two fixed blocks and return one block plus FILEMARK.
They verify the payload, untouched transfer-buffer tail, one deferred zero-byte
EOF and the following physical read. A rejected nonintegral read must preserve
that deferred EOF. Fixed/descriptor sense, residual/legacy managers and both
status ABIs are covered. A pending-rewind fixture also verifies that invalid
fixed-block read sizes fail without polling away the pending rewind state.

Raw write-size fixtures reject disallowed single-byte and nonintegral fixed
writes while rewind is pending, preserving state and opcode without setting
the saved physical-write-error flag. Both status ABIs are covered. `-s` is a
positive control on variable records and must not bypass fixed alignment.
After a failed readiness wait, invalid fixed reads/writes must still report
input error `31`, not inherit the old NOT READY sense key.

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

Buffered-boundary fixtures drain cached data and then encounter a filemark
with no additional bytes in the same DOS read. The data must be returned
first, with exactly one zero-byte EOF on a later valid read and no extra
physical READ. An intervening rejected single-byte read must preserve pending
EOF. Variable/fixed drives, residual/legacy managers and both ABIs are covered.
Additional descriptor ILI+FILEMARK cases verify short payload delivery without
losing or duplicating the file boundary.

Focused boundary runs use `bash tests/dos_tape_ioctl.sh buffered-boundary`
or the `-legacy`, `-fixed`, `-fixed-legacy`, `-status16`, `-ili`, `-ili-legacy`
and `-ili-status16` suffixes.

Buffered-refill error fixtures copy a known cached prefix, then fail the next
physical read. They inject an oversized residual, host error, NOT READY with
FILEMARK, deferred sense, contradictory ILI, or an unaligned fixed residual.
The DOS call must fail, the valid prefix remains intact and sentinel bytes in
the untransferred caller tail stay untouched. Status must report the read
failure without pending EOF or a saved-write flag. The next explicit read
must reach the manager, without implicit replay or a spurious zero-byte EOF.
Both status ABIs and a legacy sense-based failure are covered. A focused run
is `bash tests/dos_tape_ioctl.sh buffered-refill-residual`.

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

`make dos-mhvtl-roundtrip` is a separate, destructive virtual-scratch test.
It writes four variable records, closes and reopens `NRMT0`, appends two more
records, rewinds and compares every byte and all three filemarks. The total
is 8,254 bytes in six records and two files. Both status ABIs and destination
guards are checked throughout. Only initial UNIT ATTENTION readiness checks
are retried; data and finalization operations are never replayed by the test.
The host gate checks mhVTL sysfs identity, library-to-drive mapping and the
explicit scratch barcode before launch. Physical devices are refused.

Emulator coverage does not qualify the write path for production backups on
real drives and media. Real-drive fixed-block and broader error/partial-
transfer qualification remain outstanding.
