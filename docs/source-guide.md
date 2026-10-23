# Source guide

This guide follows the DOS implementation from a caller's request to a checked
ASPI completion. It describes code paths and ownership; command/packet details
remain in the linked interface documents. The Windows storage design is separate
and does not imply that Windows drivers are implemented by these DOS files.

## Source boundaries

| Layer | Source | Owns |
| --- | --- | --- |
| Public contracts | [`include/openaspi`](../include/openaspi/) | Scalar widths, packed packets, enums and mask definitions. |
| Portable SCSI helpers | [`common/scsi`](../common/scsi/README.md) | CDB encoding and bounded sense decoding, without transport. |
| Portable native packets | [`tape_api.c`](../common/tape/tape_api.c) | Request construction and reply consistency checks, without I/O. |
| DOS transport | [`common/aspi`](../common/aspi/README.md) | Manager discovery, SRBs and checked completion. |
| DOS block support | [`common/dos`](../common/dos/README.md) | Units, BPBs, block requests, raw sessions and tool helpers. |
| Drivers | [`drivers`](../drivers/) | Their respective DOS device contracts and state. |
| Tools | [`tools`](../tools/) | User intent, file/UI lifetime and operation policy. |

A packed wire structure is not a driver unit record. Its field offsets and
widths are public ABI; internal state can have a different representation.
Likewise, an enum selects one operation whereas a mask combines facts. Numeric
equality between two namespaces does not make their meanings interchangeable.

## Common request and transport lifecycle

For the block/CD drivers, strategy records ES:BX; interrupt saves caller state,
sets DS=CS and switches to a resident stack. INIT follows its discovery path;
runtime requests select a unit and dispatch a handler. The handler returns
carry and AL's driver error, and the outer boundary stores DOS DONE/ERROR.
ASPITAP has its own dispatcher and character-device rules.

The shared ASPI client prepares one resident SRB for the selected address. The
handler fills the CDB, direction and optional transfer buffer before submission.
The SRB and buffer remain live until the manager completes; polling must not
abandon a pending command. Manager timeouts differ from a driver's deadline for
polling readiness between completed commands.

Completion has several meanings:

| Observation | What it establishes |
| --- | --- |
| DOS accepted/delivered a request | The driver was reached; packet operation status may still report failure. |
| ASPI manager completed | The SRB is no longer pending; host/target status still need checking. |
| Manager/host/target report clean execution | The command completed cleanly; reply length/content may still need validation. |
| A packet or sense parser succeeds | Recognized, bounded data; callers must inspect result and validity. |
| Buffered tape bytes were accepted | Bytes entered driver memory; physical record/finalization can still fail. |

DOS autosense follows the actual CDB length. Sense flags/keys are not trustworthy
without the matching completion envelope; a host error cannot be hidden by
plausible stale sense. See [aspi-sense.md](aspi-sense.md).

## Disk and floppy requests

[`ASPIDSK`](../drivers/aspidsk/aspidsk.asm) and
[`ASPIFDD`](../drivers/aspifdd/aspifdd.asm) include the same
[`blkdrv.inc`](../common/dos/blkdrv.inc). Their main difference is device
ownership: known removable INQUIRY identities go to ASPIFDD. Classification is
shared with detection so a device is not claimed twice by these drivers.
Manager/BIOS ownership is checked separately; see
[block-ownership.md](block-ownership.md).

### Ordinary block I/O

1. `select_unit` chooses the unit record and transport address.
2. `rw_request` checks request length, media/access state and the complete
   volume-relative range.
3. It adds `U_START` once to obtain a physical LBA and splits into chunks.
4. `xfer_sectors` constructs READ/WRITE/WRITE AND VERIFY/VERIFY CDBs.
5. Successful chunks advance the buffer/LBA; errors retain partial-progress
   accounting and stop the request.

WRITE AND VERIFY can use the checked unsupported-command fallback to WRITE plus
VERIFY. Both commands must use the original chunk LBA, and successful WRITE
alone must not produce verified success. An arbitrary transport error is not
permission to repeat a write.

### BPBs, media and address spaces

`load_volume` qualifies a superfloppy or supported partition and prepares its
BPB. `U_START` is physical; ordinary DOS sector numbers are volume-relative.
Track READ/WRITE instead use physical-device CHS, while track VERIFY uses
volume-relative CHS. RAW1 uses physical LBAs throughout. See
[block-track.md](block-track.md) and [raw-media.md](raw-media.md).

The current BPB, default BPB, cached-medium validity and an explicit BPB override
are separate state. SET PARAMETERS stages a candidate before checking layout,
descriptor geometry and physical bounds. Syntax rejection does not install it;
failed media preflight invalidates stale cache/override flags. It is a logical
parameter update, not a filesystem format. FAT32 additionally needs DOS-kernel
qualification; see [block-parameters.md](block-parameters.md).

Blank ASPIFDD media can retain a DOS unit with placeholder parameters so raw
tools can reach it. That placeholder does not make ordinary filesystem block
I/O valid.

### Raw ownership and tool cleanup

RAW1 BEGIN prevents removal and publishes a nonzero session token after success.
Normal ASPIFDD requests are gated while a raw session is active; READ/WRITE/END
check the token. A token associates calls with the session, not a security
identity. END retires software ownership even when hardware ALLOW fails, while
retaining the lock count/error rather than pretending the drive was unlocked.

[`raw_client.c`](../common/dos/raw_client.c) translates zero-based drive numbers
to DOS's one-based block IOCTL numbering and keeps original driver/sense
information alongside DOS errors. A successful open needs a close. Callers must
include close/flush errors in the overall result, not just data-transfer errors.

## CD requests and playback

[`aspicda.asm`](../drivers/aspicda/aspicda.asm) implements the DOS CD-ROM contract;
MSCDEX/SHSUCDX supply filesystem access and drive letters. `read_long` selects
2048-byte cooked or 2352-byte raw sectors. Address conversion separates LBA from
Red Book MSF, which includes the 150-frame lead-in offset.

Input/output IOCTL control blocks have individual minimum sizes. Subchannel and
mode-page parsing validate the expected format and bounded payload before
returning caller data. MODE SENSE descriptor length determines where audio
page 0Eh begins even if DBD requested no block descriptors.

Playback is per unit: idle, playing or paused, plus a separately valid resume
range. Successful PLAY publishes the range; polling reconciles cached state.
NOT READY/UNIT ATTENTION clears stale resume state even if encountered by an
informational query. STOP uses pause semantics for an active range; RESUME
requires a qualified paused state and valid range.

Audio routing translates DOS channel/volume pairs to MMC selectors. The desired
changes are compared with the drive's changeable-bit mask; changes to fixed
bits fail instead of being silently clamped. A muted pair may preserve its
hardware amplitude when writing back an equivalent semantic zero volume.
The reset IOCTL handler is currently a successful no-op, not a hardware reset.
See [aspicd-compat.md](aspicd-compat.md) for coverage and limits.

## Tape requests, buffers and finalization

[`aspitap.asm`](../drivers/aspitap/aspitap.asm) exposes multiple aliases for one
physical tape. Strategy captures raw/buffered and rewind/no-rewind policy.
Aliases do not provide independent streams or positions.

### Legacy character interface

Raw character I/O preserves physical record boundaries. Buffered I/O uses a
private resident request packet to reuse the raw handlers, but owns separate
logical-byte accounting. `buffer_count/cursor` describe the physical cache;
`buffer_done/left` describe the current DOS request. A filemark is delivered only
after bytes preceding it, including cached bytes.

Buffered WRITE acceptance is not physical completion. Full buffers are submitted
once; final partial buffers are zero-padded to the physical buffer size. Failed
or partial physical writes are latched and never replayed automatically.
Final close flushes and performs historical written-session filemark/position
policy. Saved failures remain reportable through status because DOS may ignore
a close error. See [aspitape-compat.md](aspitape-compat.md).

Residuals count bytes not transferred. Negotiated ASPI residuals need range and
alignment checks; sense information counts bytes in variable mode and blocks in
fixed mode. Checked multiplication converts blocks before subtraction. A plausible
sense key cannot repair a malformed residual or prove a count after host failure.

### Native OTAP interface

Native category 80h is separate from legacy category 07h. A delivered native
request can return a well-formed ERROR/BUSY packet with DOS success. Consumers
validate the packet and inspect result/completion/count/stream flags.

BEGIN claims writer ownership, WRITE submits records, FLUSH/FILEMARK/END perform
explicit finalization, and ABORT releases ownership without I/O or rollback.
Dirty/failed state is not cleared merely because ownership was released. Native
close must not add legacy marks or implicitly flush an abandoned claim. An extra
open during a claim poisons it because relying on DOS to honor OPEN errors would
not safely preserve exclusivity.

Native requests always express requested/actual in bytes. FIXED adds block size;
CDB construction converts to whole blocks. COUNT_VALID, not actual=0, establishes
whether the reported count can be used. See [native-tape-fixed.md](native-tape-fixed.md)
and [native-tape-write.md](native-tape-write.md).

## Tools and verification

ASPICTL routes drive-letter commands to the CD or block interface. Executable
aliases and subcommands share the command registry. Forced eject releases locks
through checked operations; it does not suppress a hardware failure.

ASPIDD captures/copies full physical images. Target chunks are read back;
same-drive copying stages a complete source image before replacement. Rescue
zero-fill requires a preserved gap map and has a distinct completion result.
ASPIFMT owns write policy, while portable FAT helpers only calculate layouts and
encode metadata. Both FAT copies and FAT12 sector-straddling entries matter when
marking bad clusters; required metadata cannot simply become a bad data cluster.

`make check` builds the relevant DOS/host artifacts, runs protocol/layout tests
and compiles the portable ABI for 16-bit DOS. Assembly fixtures and disposable
DOS-image tests cover behavior beyond those checks. Use the targeted procedures
in [building.md](building.md), [ASPITAP testing](../drivers/aspitap/TESTING.md) and
the interface documents when behavior changes. Comment-only edits can additionally
be checked by comparing code tokens before/after; no media I/O is needed for that.


### Locate behavior tests

These are test entry points to inspect when changing the corresponding behavior;
listing one here does not mean `make check` runs every DOS integration scenario.

| Change area | Fixtures / integration entry points |
| --- | --- |
| Ownership and duplicate exposure | [`block_ownership.asm`](../tests/block_ownership.asm), [`dos_block_ownership.sh`](../tests/dos_block_ownership.sh) |
| Logical BPBs and access state | [`block_params.asm`](../tests/block_params.asm), [`block_access.asm`](../tests/block_access.asm) |
| Track address/VERIFY behavior | [`block_track.asm`](../tests/block_track.asm) |
| CD playback and routing | [`cda_audio_state.asm`](../tests/cda_audio_state.asm), [`cda_audio_channels.asm`](../tests/cda_audio_channels.asm) |
| Native packet consistency and driver behavior | [`native_tape_api_test.c`](../tests/native_tape_api_test.c), [`tape_native_api.asm`](../tests/tape_native_api.asm) |
| Portable FAT layout and rescue | [`fat_format_test.c`](../tests/fat_format_test.c), [`rescue_test.c`](../tests/rescue_test.c) |
| Tools, medium swap and rescue in DOS | [`dos_removable_tools.sh`](../tests/dos_removable_tools.sh), [`dos_diskcopy_swap.sh`](../tests/dos_diskcopy_swap.sh), [`dos_rescue.sh`](../tests/dos_rescue.sh) |
