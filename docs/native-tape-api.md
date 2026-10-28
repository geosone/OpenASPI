# Native tape API for OpenTape

Decision: OpenTape's common tape interface is our own API. Its first platform
targets are DOS, Windows 3.x and Windows 9x/ME; NT and later Windows are a
long-term target. The historical ASPITAPE interface is a separate compatibility
case. Its operation numbers, small status buffers and device-name conventions
do not define the native API's scope or future layout.

The first [native DOS query binding](native-tape-query.md) is implemented:
category `80h`, function `00h`, version `0100h`, with a separate 128-byte
request/response. It supplies snapshots and explicit read-only capability
probes. The separate [native DOS control binding](native-tape-control.md)
adds READY and synchronous REWIND with explicit completion/position results.
OpenTape has a common adapter and localized DOS commands for these operations;
a [native variable-record reader](native-tape-read.md) now retains byte counts
and stream conditions in an open session. The [native writer binding](native-tape-write.md)
adds an explicit claim, variable records, flush, filemark, end and abort; close
never adds implicit marks. OpenTape archive commands can select these adapters
explicitly with `--native`. The broader operation set and Windows bindings
below remain the architecture contract and implementation backlog; no Windows VxD ID or DLL
contract is allocated here.

## Layering

```text
OpenTape archive engine, CLI and localized user interfaces
                         |
           Common native tape API and result model
                         |
        Platform/backend adapters and ownership management
                         |
    Device operations, capability parsing and qualified quirks
                         |
         Existing controller/transport or OS storage driver
```

The application requests an operation and inspects a common result. It does
not choose different CDBs for HP, Sony, Exabyte or QIC and does not interpret
DOS error numbers or NT status codes in its archive engine. Device-specific
handling lives below the common interface. Controller ownership remains
with one transport/OS driver at a time.

| Platform/backend | Role |
|---|---|
| DOS native OpenASPI/ASPITAP service | Provide the native operations over a separately versioned DOS binding, using the existing ASPI manager for hardware access. Legacy ASPITAPE requests remain a separate supported entry point. |
| Direct ASPI | An adapter for systems without our native service. Reuse common SCSI command/result logic; do not access a controller concurrently through another owner. |
| Legacy ASPITAPE | Optional adapter exposing its actual subset through the common API. Unsupported native features remain unsupported or unknown. |
| Windows 3.x | A Win16 application binding plus a mediator for protected/V86 access, shared buffers and ownership as needed. The Colorado VxD is a resource/buffer mediation reference, not the definition of our tape API. |
| Windows 9x/ME | A Windows binding using the selected ASPI/IOS integration and the controller's existing storage owner. Share tape semantics and device handling, not DOS pointer layouts. |
| Future NT+ | A later backend using the native Windows tape/storage interfaces where appropriate. The common API does not require replacing working NT tape drivers. |

Bindings may use different binaries, calling conventions and request layouts.
A common logical contract does not imply that a DOS far pointer can be sent
unchanged to Win16, Win32 or NT. Keep transport buffers and their ownership
inside the binding.

## Common operations

| Group | Logical operations and rules |
|---|---|
| Discovery and ownership | Enumerate, identify, open/claim, close/release. Selection and capability inspection must not prepare media, rewind or change compression implicitly. |
| Device/media information | Identity, transport, readiness, write protection, record-size range/mode, readable/writable formats, optional compression, locking and partition capabilities. Distinguish unknown, unsupported and supported. |
| Record I/O | Read/write records with requested and actual byte counts. Expose short records, filemarks, setmarks and EOM distinctly from transport failure. Preserve tape record boundaries across platforms. |
| Movement | Rewind, space records/filemarks, EOD positioning, optional READ POSITION/LOCATE, load/unload and retension. Distinguish logical record positions from byte offsets; report unknown position after ambiguous failure. |
| Commit and marks | Flush buffered writes separately from writing filemarks/setmarks. Define native close/finalization explicitly; a native client must not inherit extra implicit legacy marks through a second backend layer. |
| Configuration | Query mode/density/compression; explicitly set supported options only after validating the request and capability. Read and write support are independent. |
| Media preparation | Explicit erase/format/partition operations with identified media and separately qualified semantics. Capability detection never invokes these operations. QFA and archive framing are separate from physical preparation. |

Every advertised capability needs backend/device evidence. Capabilities can
change with inserted media, mode, firmware or ownership. A successful INQUIRY
is not proof that a particular optional operation works. A missing compression
page does not disqualify a drive from basic streaming I/O.

## Results, state and versioning

The common result needs an operation result, actual transfer count and count
validity, stream conditions, position validity, and retained diagnostic
details. The latter may include SCSI response/key/ASC/ASCQ, host/target status
and a platform-native error for diagnosis; archive logic uses common semantics.
Host failure, unavailable media, incompatible format, write protection,
unsupported operation and a filemark must not collapse into one success/error
flag. Partial data and an accompanying condition must both be representable.

Versioned bindings must declare request/response size and version and check
them before reading or writing fields. Do not extend an old ASPITAPE caller's
14/16-byte buffer. New operations use a native contract; legacy adapters
translate the subset they can establish. Raw CDB pass-through, if provided
for diagnostics, is separate from ordinary archive operations.

Pending operations retain their buffers and ownership until the provider
reports a terminal state. Timeouts/cancellation do not imply that a device
stopped, a write did not happen or a buffer is free. Never automatically replay
writes, movement or marks after an ambiguous error. Read-only discovery retry
policy must be bounded and qualified independently.

## Evidence and implementation order

The [NT-driver investigation](nt-tape-analysis.md) supplies mode-page and
device-specific cases. The [DOS/Win3.x investigation](dos-tape-api-analysis.md)
supplies ASPI, private module and resource-mediation examples. They inform the
operation model and adapters; we are not cloning every historical API.

- [ ] Define a platform-neutral operation/capability/result model and tests
  for unknown capabilities, unsupported operations, short records, partial
  writes, media change and ambiguous position.
- [x] Implement native DOS query size/version negotiation independently of
  ASPITAPE, plus bounded inquiry/limits/mode-page queries and a DOS client.
- [x] Add native READY and synchronous REWIND, with busy-session checks,
  retained diagnostics and unknown position after a failed rewind.
- [x] Add native variable-record reads with byte-count validity, stream
  conditions, partial error results and no automatic replay.
- [x] Add native variable writes and explicit claim/flush/filemark/end/abort
  ownership, retained uncertainty and no legacy close-time marks.
- [x] Add explicit native fixed-block READ/WRITE and fixed writer claims,
  byte/block residual validation and SDK mode negotiation.
- [x] Add explicit fixed-block archive framing/reassembly in OpenTape, with
  checked length/CRCs/zero padding, DOS command selection and UI mode display.
- [x] Add signed SPACE records/filemarks and EOD, guarded state, retained
  movement uncertainty and explicit rewind recovery. See [positioning](native-tape-space.md).
- [x] Add synchronous [LOAD/UNLOAD](native-tape-media.md), including recovery
  while preserving earlier uncertainty; no inferred BOT/readiness or retries.
- [x] Add native [LOCK/UNLOCK](native-tape-removal.md), with non-moving
  failure semantics and preservation of native uncertainty and legacy EOF.
- [x] Add non-moving [short logical READ POSITION](native-tape-position.md),
  with address validity, transfer provenance and preserved session state.
- [x] Add synchronous [LOCATE(10)](native-tape-locate.md) with current/explicit
  partition selection, full-width addresses and retained failure state.
- [x] Add [64-bit long READ POSITION and LOCATE(16)](native-tape-wide.md),
  independent object/file validity, checked decimal conversion and old bindings.
- [x] Add read-only [reported partition layout](native-tape-partitions.md),
  with bounded page parsing, transfer proof and pending/stale provenance.
- [x] Complete the [SPACE family](native-tape-space.md) with consecutive
  filemarks, setmarks and consecutive setmarks; keep device mode unchanged.
- [x] Distinguish [setmarks during native READ](native-tape-setmarks.md) from
  filemarks using current sense and checked counts; reject them as OTB1 EOF.
- [x] Add owned [explicit SETMARK writing](native-tape-setmark-write.md),
  independent provider capability, dirty/failure state and no automatic marks.
- [x] Add explicit acknowledged [TapeAlert retrieval](native-tape-alerts.md),
  with reported/active masks, bounded parsing and no implicit health polling.
- [x] Add synchronous [RETENSION](native-tape-media.md) (LOAD with RETEN) with
  its own capability bit, LOAD's recovery rules and no BOT claim.
- [ ] Add remaining common controls and qualify physical fixed-block devices.
- [x] Define native close/flush/mark behavior without duplicating legacy
  finalization; keep explicit writer results through abort and close.
- [x] Add bounded read-only mode-page/capability queries with unknown support,
  independent record limits/granularity and retained diagnostic results.
- [ ] Add separately qualified configuration and preparation operations.
- [x] Connect OpenTape query/READY/REWIND through a shared adapter with
  platform-owned handles, packet validation and one close per successful open.
- [x] Add a persistent OpenTape native reader with validated packets and
  a failed-session gate; retain the handle through successive records.
- [x] Add a persistent OpenTape writer with a write-open callback and no
  implicit finalization/replay in cleanup.
- [x] Connect archive backup/read/verify/list/restore/compare through the native
  adapters with explicit backend selection and stream/finalization policy.
  Keep the legacy backend independently available.
- [x] Connect the existing QUILIB DOS UI to native snapshots, enumeration,
  confirmed synchronous rewind, verification and catalog export.
- [ ] Implement Win3.x and Win9x bindings against the same logical tests.
  Keep an NT+ backend boundary available without beginning that port now.

Device-specific special cases are deferred to a separate quirks layer below
this API. Archive integration uses the common semantics and must not accumulate
vendor/firmware checks. Qualification targets remain in
[tape-device-profiles.md](tape-device-profiles.md); no runtime quirks are enabled.

Optional and uncommon device functions can extend this native API with a common
logical contract. Providers report direct support, verified software emulation,
unsupported or unknown. Emulation is encouraged where it preserves the promised
data, position, mark, completion/error and persistence semantics. A shared
implementation defect remains a bug to fix now; only an evidenced device
deviation belongs in a later narrowly matched quirk. See the classification
and qualification rules in [tape-device-profiles.md](tape-device-profiles.md).

Example for a future native positioning operation: return to a known logical
tape position. A provider may use qualified direct positioning/reverse spacing,
or emulate it with REWIND followed by forward traversal from BOT. The fallback
is general capability adaptation when reverse positioning is absent; avoiding
a falsely implemented device command may additionally require a narrow quirk.
The coordinate must define partition, records, filemarks and boundary state;
byte offsets alone are insufficient. Select the fallback from established
capabilities before movement. An ambiguous failed movement does not authorize
automatic replay: report unknown position and require explicitly defined
recovery/repositioning semantics. Qualification and implementation remain later
work; this example allocates no wire opcode or capability bit.

Analysis-to-API rule: useful functions identified in the Ghidra/source/reference
investigations should become documented native operations where justified,
then be made available on other devices through direct support or a verified
shared emulation when feasible. Preserve useful semantics rather than cloning
a vendor's binary interface. Match a device only for the actual device-specific
adaptation; the reusable operation and emulation belong to the common provider
layer. Keep provenance/evidence, capability discovery and positive/negative
tests with each concrete function.

Linux-derived candidates and their qualification boundaries are recorded in
[linux-tape-quirks.md](linux-tape-quirks.md), pinned to an upstream commit.

The [fixed-block binding](native-tape-fixed.md) extends the provider and SDK
without implicit mode changes; OpenTape now supplies explicit fixed archive
adaptation with checked padding/reassembly. Device qualification remains open.

OpenTape now also exposes the implemented native operations through its DOS
QUILIB tape-controls subview (T in native mode). Full-width position/LOCATE,
load/unload, removal policy and explicit rewind reuse the SDK contracts and
retained failure gates; the interface adds no wire operation or automatic probe.
