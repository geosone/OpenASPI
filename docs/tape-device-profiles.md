# Historical tape device cases and qualification backlog

The [mpoli.fi tape archive mirror](https://ftp.zx.net.nz/pub/mirror/files.mpoli.fi/files/hardware/TAPE/OTHER/)
contains useful device documentation, applications and some platform-specific
drivers. On 2026-10-23 all 17 ZIP files in `OTHER` were downloaded and their member lists
and the documentation identified below inspected. `ASPITAR`'s source and patch
tarballs were also unpacked for static inspection. No historical executable
was run, and no physical tape was accessed.

[Archive manifest](tape-reference-archives.json) records exact URLs, sizes,
SHA-256 hashes and documentation members. Local ZIPs, full member inventory
and extracted reference files are under `build/reference/tape-other/` and are
not release contents. Existing `/home/mario/Iso/Dos/ASPI505A.zip` and
`ASPITAR.zip` match the downloaded hashes.

## Device cases to qualify

Evidence below describes the particular historical product/software. The
OpenASPI actions and tests are proposed work, not implemented compatibility
or universal requirements for every tape in the same family.

| Device / case | Evidence in the archive | OpenASPI / OpenTape action and required test |
|---|---|---|
| Valitek DAT and PST2-2000 QFA directory | `ASPI505A.ZIP:STEST.HLP` describes partition preparation for those products; `README.NOW` describes `/C0` for non-QFA media and warns against mixing append modes. | Detect/report partition capabilities separately from archive layout. Keep partition creation explicit. Test QFA/non-QFA identification and incompatible append refusal. This is not an LTFS requirement or a rule that all DAT media need partitioning. |
| DLT record size and cache | `DLT.ZIP:DLT.FAQ`, Quantum firmware-development author, 3-Oct-1994: small records or disabled cache can limit DLT2000 throughput. | Report limits/cache state; qualify practical record sizes within DOS buffer limits. Do not disable cache for an unfamiliar INQUIRY string or impose one block size on all drives. |
| DLT flush versus filemark | Same FAQ distinguishes zero-count WRITE FILEMARKS cache flush from an actual filemark and discusses flush costs. | Test explicit `MTWEOF 0`, real marks and close separately, including deferred errors and unchanged logical mark count. Preserve the existing ASPITAPE close contract unless a separately defined interface changes it. |
| DLT position and compression | Same FAQ discusses LOCATE, READ POSITION, logical records, hardware compression controls and front-panel overrides. | Qualify optional position/seek and compression reporting. Never equate compressed bytes or arbitrary byte offsets with logical record positions; use sequential fallback when optional positioning is unavailable. |
| DLT startup/load readiness | Same FAQ documents transient startup selection failure/BUSY followed by normal command response; load/unload have distinct readiness states. | Add bounded readiness scenarios for startup/load independently of pending rewind. No automatic replay of WRITE, SPACE, FILEMARKS or other media-changing commands after a transport error. |
| DLT older-format access | Same FAQ lists model-specific read-only versus read/write format support. | Record readable and writable media/density capabilities independently. Test an older readable format with rejected writes rather than infer writability from successful reads. |
| Archive Viper reverse spacing | `ASPITAR.ZIP:aspisrc.tar.Z:aspi.c`, `aspilseek`, reports backward seeking on an Archive Viper 2150S and explicitly leaves other drives uncertain. | Qualify negative SPACE and failure position. Do not assume all QIC/DAT devices can backspace. A rewind/forward fallback needs independently verified semantics across records and filemarks. |
| Fixed/variable record limits | Same source, `aspiinit`, reads block limits but labels its variable-drive record-size choice unfinished. | Use this as a negative reference: test limits, unsupported/short READ BLOCK LIMITS replies and mandatory fixed-block drives; do not adopt its guessed 512-byte fallback. |
| Floppy-controller / dedicated-card QIC | `QICTEST.ZIP:README.DOC` probes QIC controller IRQ/DMA; `CONNER.ZIP:README.TXT` identifies an NT floppy-tape driver. | These require a separate transport/controller implementation before becoming ASPI targets. A matching tape capacity or QIC name is insufficient. Keep outside the current SCSI/ASPI driver scope. |
| Irwin/AccuTrak and controller compression | `IOMET250.ZIP:DISK1/README.TXT` says the described Iomega drive reads AccuTrak after catalog rebuilding, but cannot format/write it; Ditto Tools 5.0 lacks some controller compression support. | Record readable/writable formats and application limitations separately. Test read-only foreign media and catalog rebuilding; an application's missing feature is not proof the device lacks it. |
| Tape exposed as a drive letter | `LITE31.ZIP:readme.txt` describes a CD-ROM-style Windows presentation; `LITE95.ZIP:README95.TXT` documents competing backup software. | Treat a tape-filesystem frontend as an application/virtual-drive feature. Windows 3.11 native tape support is not established by this package. Qualify exclusive ownership and release before another ASPI client gains control. |

## Device identification fixtures, not established quirks

The NT installation documentation supplies useful exact product candidates:

| Archive | Documented models / role | What remains to establish |
|---|---|---|
| `4MMS2.ZIP` | Archive/Conner 4326NP, 4326RP, 4356XP; Compaq 4/16 Gigabyte TurboDAT; HP C1533a; WangDAT 3400DX. | Capture INQUIRY identity, firmware, block limits and sense behavior for each actual device. A shared NT driver does not prove identical quirks. |
| `IBM4MM.ZIP` | IBM option 55F9428 (`IBM HP35480A !C6`) and IBM DAT 3440 001 (`HP IBM35480A !C5`). | Preserve the documented identifiers as qualification inputs; establish actual byte fields before adding a runtime match. |
| `EX2501.ZIP` | Exabyte 2501, `MINIQIC.SYS`. | Qualify record mode, supported movement and media handling; no specific workaround follows from the README alone. |
| `CNR35FLC.ZIP` | INF selects Conner CTMS 3200 (Falcon), `CONRMQIC.SYS`, with I386/MIPS/ALPHA packages. | Device-specific NT implementation reference; binaries/INF are not Windows 9x or DOS driver source. |
| `4MMDRV.ZIP` | Sytos Plus IBM 4mm DAT DOS/OS2 components. | Investigate a separate application-private interface only if compatibility with Sytos is wanted. Its `.DRV` extension is not evidence of an ASPITAPE ABI. |

## Application references and scope

- `ASPITAR.ZIP` contains GNU tar 1.10 with ASPI C sources, patches and
  `ctctrl`, not Greg Shenaut's `ASPITAPE.SYS`. `ASPI.DOC` describes direct
  ASPI access and `/dev/ct` / `/dev/nrct`; this is a potential independent
  ASPI-manager client, not already an ASPITAP character-device test. Its
  fixed-sense assumptions and unfinished record-size policy are not templates
  for our decoder. Its `aspisrc.tar.Z:COPYING` is GNU GPL version 1,
  February 1989, and GNU tar's source headers refer to that file. It is
  recorded as a source-reuse/test-client candidate as well as a behavior
  reference. The ASPI additions have no separate per-file license/version
  notice in the inspected files; retain archive and package licensing
  provenance when selecting code. No source has been imported into OpenASPI
  by this investigation.
- `ASPI505A.ZIP` is Valitek backup software 5.05a, not a general ASPI manager.
  `VER19P` and `VER35C` are other Valitek application generations. Their
  documentation distinguishes long-filename/archive compatibility and QFA
  behavior; those belong to application/media-format qualification.
- `BETA905A.ZIP:READTHIS.NEW` distinguishes whole-disk image restore from
  file restore. Keep future OpenTape image and file archive types explicit;
  sharing a tape framing format must not make them interchangeable.
- `TD2040.ZIP` contains Tallgrass TD 2040 utilities. Its member list and
  package description establish provenance only; no controller protocol,
  recovery semantics or OpenASPI compatibility has been established.
- `LITE31`/`LITE95` and `IOMET250` remain UI/ownership/application references;
  their tape formats are not the selected OpenTape archive format.

The [pinned Linux tape/SCSI review](linux-tape-quirks.md) adds command-layout,
discovery and transport cases, including the caveat that recorded firmware
revisions in Linux's shared table are not used for matching there.

## Separate quirks implementation, later

The current work connects OpenTape archives to the generic native tape API.
Device special cases will be added afterward in a distinct provider/device
quirks layer. Keep vendor/firmware/transport matching and qualified command
adjustments below the native API; archive framing, restore and common
completion handling must not gain device-specific branches. This ledger is
input for that later work, not an instruction to enable guessed quirks now.

## Classify bugs, optional features and quirks separately

- A violation of the specified command/result/state contract in our code is a
  common implementation bug. Fix it in the shared path with a regression;
  do not postpone it or hide it behind a vendor match.
- A valid optional or uncommon device function is a capability, not a defect.
  Give useful functions a defined native API operation. Providers may implement
  the operation directly or emulate it where the advertised semantics hold.
- A demonstrated device/firmware deviation may require a narrowly matched
  quirk. Record the expected behavior, observed deviation, identity/firmware/
  transport scope and positive/negative tests before enabling the workaround.
- An unexplained failure remains unclassified until evidence distinguishes a
  caller/transport/driver defect, unsupported capability and device deviation.

Future optional-function reporting must distinguish direct support, emulated
support, unsupported and unknown. A working emulation is usable support, with
its provenance and any restrictions exposed. The common API defines behavior;
providers adapt device commands below it. Never treat a guessed command or an
unverified approximation as support. An emulation must preserve promised data,
position/filemark behavior, completion and error semantics, and required
persistence/interchange properties. Give a weaker logical feature its own
contract rather than labeling it equivalent to a stronger physical operation.
No new wire capability mask is allocated until a concrete function and its
qualification tests exist.

Example: positioning back to a known location can use a direct device command
or an emulation of REWIND plus forward traversal from BOT. Missing reverse
positioning is an optional capability gap, not itself a bug or a vendor quirk.
Track partition, record and filemark coordinates and test exact boundary
behavior. Select this path from known capabilities; an ambiguous failed move
must not trigger a blind replay. Only a demonstrated defect in a supported
command warrants a device-specific avoidance rule.

## Rules for future capability and quirk implementation

- [ ] Collect an identity/transport/media record: full INQUIRY fields and
  firmware, supported commands/pages, record limits, media type/density,
  write protection, partition count and compression state where available.
  Unknown capabilities stay unknown; a failed optional probe must not
  reconfigure media or change drive ownership.
- [ ] Prefer checked command/capability responses. Introduce an identity-based
  workaround only with a narrow model/firmware/transport match, evidence of
  the defect and a positive/negative regression pair.
- [ ] Separate readable/writable formats, physical preparation, optional QFA
  metadata and OpenTape archive framing. Validate append mode before writing.
  Existing single-stream operation remains the baseline; partitioning,
  vendor commands and changer automation are not added by this investigation.
- [ ] Qualify the cases above with memory-backed ASPI fixtures first, then
  identified scratch media. Assert command counts and position after failure;
  no guessed success or implicit destructive recovery.

This ledger adds qualification targets. It does not enable runtime quirks,
change tape contents, import third-party drivers or establish redistribution
rights for these historical packages.

## Parent-directory expansion

The [parent tape directory](https://ftp.zx.net.nz/pub/mirror/files.mpoli.fi/files/hardware/TAPE/)
also contains `COLORADO`, `MOUNTAIN`, `SANKYO` and `SONY`. Their ten ZIPs were
downloaded and inventoried, bringing the pinned manifest to 27 archives.
Selected READMEs/INF files were inspected; nested installers and every
application binary have not been exhaustively analyzed.

| Group / archive | Useful evidence and scope |
|---|---|
| `SONY/S4MM.ZIP` | NT driver for SDT-2000/4000/5000. README records tests with firmware 3.02 and controller/BIOS restrictions, including Future Domain TMC-1670 BIOS 3.0 versus 3.4. Keep firmware/transport qualification distinct from a device-code quirk. |
| `SANKYO/SANKYO.ZIP` | Additional SCSI tape NT driver. Its inquiry/capability/control paths were statically inspected alongside the other NT binaries. |
| `COLORADO/POWER401.ZIP` | Includes DOS ASPI managers, backup applications and the Win3.1 `CMSDTAPE.386` resource/buffer mediator. See the DOS/Win3.x API investigation below. |
| `COLORADO/JUMBOSYT.ZIP` | OS/2 Sytos Jumbo 120/250 drivers; README describes controller DMA/IRQ and TC-15 setup issues. These are transport/platform cases, not generic ASPI tape quirks. |
| `COLORADO/JUMBO403.ZIP`, `JUMBO405.ZIP` | DOS backup/installation packages. Member inventory alone does not establish a reusable tape driver API. |
| `COLORADO/QICBAT12.ZIP`, `TAPELIB3.ZIP` | Batch generation and tape cataloguing around CMS backup software; application workflow examples. |
| `COLORADO/TRAVAN1K.ZIP` | HP Travan T-1000 Win95 installer package. Nested `95CBW151.EXE` remains unexamined. |
| `MOUNTAIN/525TD.ZIP` | README describes on-demand physical formatting and CHKTAPE catalogue/media recovery. Treat those as explicit preparation/recovery features; do not introduce automatic formatting into ordinary native-API record writes. |

The [six NT-driver analyses](nt-tape-analysis.md) and
[DOS/Win3.x API investigation](dos-tape-api-analysis.md) now add binary-backed
findings to the document-only evidence above. The
[native OpenTape API](native-tape-api.md) is our common interface, with
ASPITAPE retained as a separate compatibility provider.
