# Driver implementation status and remaining work

Implemented in this checkpoint: ASPICTL filename aliases from one command
registry; block media locks/eject; CD lock/eject/close; checked raw sessions;
ASPIFMT FAT12/16 and conditional FAT32; bad-cluster marking; ASPIDD full-media
copy/image, one-drive exchange and Rescue; QUILIB copy UI; extended BPBs and
volume/LBA bounds. These are concrete tested paths, not full compatibility
with every reference-driver operation.

The [source guide](source-guide.md) maps these features to request paths,
state ownership and behavior tests. Source comments explain the implemented
checks; documentation coverage does not close any hardware qualification or
unimplemented-operation item below. In particular, READ BLOCK LIMITS is not
MODE SENSE, device presence is not mounted-media validity, and successful
buffer acceptance is not proof of tape finalization.

## Block/removable drivers

- BIOS ownership: [GET DISK INFO filtering](block-ownership.md) and an explicit
  unsupported-manager fallback are implemented and INIT-tested. Accurate
  motherboard/USB-boot BIOS mappings still depend on the manager; current
  tools cannot resolve every BIOS, SUBST or Windows alias.
- More than the first supported primary partition; checked extended-partition
  traversal, complete partition-bound validation and independent DOS units.
- [Software access flags and independent logical mappings](block-access.md)
  are implemented and DOS-tested. Verified [Media-ID writes](block-ioctl.md)
  include FAT32 backup boot sectors and selected-partition extent checks.
  [Checked parameter-setting](block-parameters.md) supports logical BPBs on
  mounted FAT media. [Track read/write/verify](block-track.md) is implemented
  with the tested FreeDOS addressing convention. Variable track tables and
  complete DOS FORMAT/category-48 compatibility remain open.
  The OpenASPI-specific formatter does not establish complete standard FORMAT
  or variable-track-table compatibility.
- Device-specific physical format/media profiles for LS-120/240 and ZIP,
  vendor protection/password operations, and non-512-byte sectors.
- Detailed capability/live protection sensing, failed/short transport replies,
  residual-count handling and real mechanism qualification.
- Runtime attachment like GUEST, original private caller ABIs, selection/
  spin-up options and Windows 9x storage ownership/handover.

FAT32 now has a tested FreeDOS path. Broad MS-DOS 7.1 and Windows 9x/me
compatibility still needs dedicated qualification. A read surface scan can
identify repeatedly unreadable clusters; it is not a physical low-level
format or a full-medium write-pattern test.

## CD/DVD

- Replace the reset success-only stub with defined real behavior and tests.
- READ LONG count-zero/reference behavior, complete range/overflow/residual
  coverage and raw/cooked handling across disc layouts.
- Live tray/media/capability state beyond committed driver commands, physical
  audio/player qualification, legacy/vendor command sets and track validation.
- Remaining selection options and actual Windows handover.

The separate [ASPICD ledger](aspicd-compat.md) records implementation details.
86Box's known eject/close emulation limitations remain documented separately;
the positive mechanical-command tests use QEMU, not guessed alternative CDBs.

## Tape

The existing protocol/mhVTL tests remain useful, but production hardware
write/recovery qualification and the limitations in the ASPITAP README and
TESTING document still apply. Completion/sense validation is hardened as
described below; physical tape write/recovery qualification remains open.

## Prioritized follow-up from the programming references

The [published references](reference-material.md#published-programming-references)
and [platform differences](windows9x-storage.md#additional-aspi-implementation-references)
inform this implementation backlog. These are proposed OpenASPI work items,
not capabilities established merely by reading a specification.

### Shared ASPI core: next priority

- [ ] Validate autosense consistently before translating errors: completed SRB
  status, host status, CHECK CONDITION, actual CDB/sense offsets, response type
  and available length. Test truncated, untouched and stale sense buffers on
  all four driver families; keep host/transport failures distinct from media
  errors. [Shared block/CD completion and sense checks](aspi-sense.md) are
  implemented and DOS-tested, including the raw and track-VERIFY consumers.
  The tape decoder now checks status/host/target, six-byte CDB, allocation and
  descriptor bounds, and uses checked ASC/ASCQ for rewind readiness. Resident
  parser and installed-driver fault tests cover these paths. Actual short-
  transfer qualification remains open; allocation length alone cannot prove
  the returned byte count.
- [x] ASPITAP: [Unit Attention latch](aspi-sense.md#tape-unit-attention-latch).
  A current key 6 on any tape command blocks data, filemarks and motion other
  than REWIND until a successful REWIND; no command is retried. Emulator-tested
  for reset and medium-change sense on legacy and native paths.
- [x] ASPIDSK/ASPIFDD/ASPICDA: [Unit Attention latch](aspi-sense.md#block-and-cd-unit-attention-latch).
  A current key 6 consumed by any request drops a removable unit's BPB and is
  reported once by the next MEDIA CHECK/MEDIA CHANGED; no command is retried.
  Emulator-tested with memory-only ASPI; real insertion, power-up and reset
  notifications on hardware remain to be checked.
- [x] Short INQUIRY replies: `common/aspi/inquiry.inc`, shared by ASPIDSK,
  ASPIFDD, ASPICDA and ASPISCAN, poisons the buffer, uses the DOS ASPI
  residual count (`SRB_RESIDUAL`, `HA_EXT_RESIDUAL`) when the adapter has it,
  cuts the reply to its additional length and rejects untouched, too short,
  qualified or type-mismatched replies; missing identification reads as
  blanks. `tests/aspi_inquiry.asm`. READ CAPACITY already poisons its reply.
- [x] ASPICDA short replies: READ TOC, READ CAPACITY and the INIT
  capabilities page poison their buffers; the TOC header must describe whole
  descriptors within the buffer, at least the lead-out and tracks 1..99 with
  first <= last. Sub-channel and the audio mode page were already poisoned and
  length-checked. `tests/cda_toc.asm`.
- [ ] Residual counts for the CD replies where the manager supports them.
  Without them a truncated transfer whose own header claims full length is
  only caught by the poisoned bytes it leaves.
- [ ] Add pending-completion/abort/reset fault tests around the shared client.
  IRQ-driven completion must remain possible; SRBs and buffers cannot be
  reused or released while a manager still owns them. Driver/app cancellation
  and hardware recovery must have explicit completion states.

### Device drivers

- [x] ASPIDSK/ASPIFDD: basic `41h`/`61h`/`62h` track-I/O milestone, including
  addressing, transfer bounds, partial failure and live DOS tests.
- [ ] Qualify MS-DOS track/verify conventions and standard formatting/track
  tables and media profiles independently. Probe
  live capacity/protection and unsupported commands without inferring complete
  device behavior from a name or a successful INQUIRY alone.
- [x] ASPICDA: reset drive sends ASPI Reset Device once; rejected requests keep
  state, accepted ones invalidate audio/lock state and latch a disc change on
  every unit of the target. The TOC is never cached. Resident tests, and
  `tests/cda_reset.asm` through AHCIASPI in QEMU on AHCI (COMRESET) and IDE
  (ATAPI DEVICE RESET).
- [ ] ASPICDA: extend physical media and optional-command qualification after
  emulator coverage, including reset on other managers and real drives.
- [ ] ASPITAP: extend real-device qualification of pending rewind, recovery,
  residuals, short records, filemarks and EOM. Use the tape command standards
  and ASPITAPE ABI for tape-specific decisions; the general ASPI book is not
  a complete tape specification. Changers remain deferred.
- [ ] Qualify the [historical tape device cases](tape-device-profiles.md):
  QFA versus non-QFA append, optional DAT partition preparation, DLT flush
  versus filemark and startup readiness, record limits, reverse SPACE,
  optional positioning/compression and readable versus writable formats.
  Use capability probes and narrowly evidenced quirks; FDC QIC controllers
  need a separate transport. Evaluate the GPLv1 ASPITAR source for the direct
  ASPI provider of our native API; ASPITAPE compatibility is a separate case.
- [ ] Build the [native OpenTape API](native-tape-api.md) as our own common
  operation/capability/result contract for DOS, Win3.x and Win9x; keep NT+
  as a later provider. ASPITAPE is a separate compatibility case. Use the
  [six hash-pinned NT-driver analyses](nt-tape-analysis.md) and
  [DOS/Win3.x API findings](dos-tape-api-analysis.md) for capability handling,
  MODE SENSE layouts, ownership and buffer lifetime, not vendor-API clones.
  The [native DOS query binding](native-tape-query.md), public C validation
  helpers and `OTAPINFO.EXE` client are implemented and emulator-tested.
  The [native control binding](native-tape-control.md) adds READY and
  synchronous REWIND; OpenTape has shared adapter tests and English/German
  DOS integration tests. The [native read binding](native-tape-read.md) and
  persistent OpenTape reader expose variable records and explicit stream/count
  validity. The [native writer](native-tape-write.md) adds variable writes,
  explicit ownership/flush/marks/end/abort and retained failed-session state.
  OpenTape archive commands can now select the native bridge with `--native`;
  DOS tests cover backup/verify/list/preview/restore/compare and exact command
  counts on a memory-only medium. `--native --ui` now selects the same native
  snapshot/rewind/archive path in QUILIB, including failed-position display.
  The [fixed-block extension](native-tape-fixed.md) supports explicit aligned
  READ/WRITE, fixed writer claims and checked byte/block residuals in the SDK.
  OpenTape now adapts fixed-block archives with explicit sizing, checked zero
  padding/reassembly and DOS CLI/UI integration. Remaining controls, Windows
  providers and physical fixed-device qualification remain open. Native
  [SPACE positioning](native-tape-space.md) now covers records/filemarks/EOD
  with retained failure state and explicit rewind recovery. Device special cases
  are reserved for a later separate quirks layer.

### Windows frontend and storage integration

- [ ] Define separate DOS, Win16 and Win32 wire headers and ABI tests, including
  CDB lengths 6/10/12/16 and sense placement. Never cast a DOS SRB into a Win32
  request, or import OS/2-specific header/posting fields into either one.
- [ ] Implement paired application-DLL/VxD completion and buffer ownership:
  Win32 events/callback lifetime, Win16 locking/thunking and pending shutdown
  or cancellation. Qualify against native ASPI clients before replacement.
- [ ] Continue the existing IOS/SCSI-port miniport plan while preserving
  official vendor miniports and a single controller owner. NT pass-through
  examples are references, not a Windows 9x implementation.

OS/2 AttachDD/DevHelp, DMD allocation switches and an OS/2 driver port are not
current implementation tasks. Its specification is useful for identifying
shared concepts and incompatible ABI details.

## Filesystem checking

No ASPIFSCK is planned here. Use an appropriate DOS checker already available
for the filesystem. FreeDOS documents [DOSFSCK](https://help.fdos.org/en/hhstndrd/base/dosfsck.htm)
for FAT16/FAT32 and DOSLFN; its [CHKDSK](https://help.fdos.org/en/hhstndrd/base/chkdsk.htm)
does not support FAT32. For a non-repairing check, DOSFSCK provides `-n`.
These external programs are not silently bundled or invoked to modify media.
