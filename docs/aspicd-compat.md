# ASPICD.SYS compatibility notes

Black-box and disassembly notes on Adaptec `ASPICD.SYS` 4.01 (EZ-SCSI 5.0,
SHA-256 `72b7166f457751e0461f6b3a99ce0dd0b19fd8396def9b196eb00467428c78fb`),
the driver `ASPICDA.SYS` replaces.  They record its interface and behavior
(command coverage, options, status bits) as a checklist for ASPICDA.  No
Adaptec code is used; the binary is not part of OpenASPI (see
[reference material](reference-material.md)).  It was examined with Ghidra
12.1 (raw real-mode load at 0000:0000, the jump tables of the interrupt
routine as function entries).

The original was re-imported and re-analyzed on 2026-10-23 with Ghidra
12.1.4 DEV. The hash-pinned [analysis script](../tools/reference/InspectAspiDriver.java)
read both DOS command tables and both IOCTL tables, then exported 94
discovered functions. See [reproduction instructions](reference-analysis.md).
This is actual static analysis, not proof that every legacy/vendor path is
understood or that ASPICDA already implements the corresponding function.

## Device header

Character device, attribute `C800h` (IOCTL, open/close/removable), default
name `MSCD000` style set by `/D:`, the unit count in the CD-ROM header
extension.  The interrupt routine switches to a private stack.

## Device commands

| Command | ASPICD 4.01 | ASPICDA 0.1 |
|---|---|---|
| 00h INIT | yes | yes |
| 03h IOCTL input | yes (below) | partly (below) |
| 07h input flush | yes | checks active audio and busy status |
| 0Bh output flush | no | yes (no-op) |
| 0Ch IOCTL output | yes (below) | partly (below) |
| 0Dh/0Eh open/close | checks unit and audio busy status | per-unit audio poll and busy status |
| 80h READ LONG | yes | yes |
| 82h READ LONG PREFETCH | yes (with seek) | SEEK(10), current-capacity check |
| 83h SEEK | yes | SEEK(10), current-capacity check |
| 84h PLAY AUDIO | yes | yes (PLAY AUDIO MSF) |
| 85h STOP AUDIO | yes | yes (PAUSE) |
| 86h/87h WRITE LONG | no | no |
| 88h RESUME AUDIO | yes | yes |

### IOCTL input (03h)

| Code | Function | ASPICD | ASPICDA |
|---|---|---|---|
| 0 | device header address | yes | yes |
| 1 | location of head | yes | READ SUB-CHANNEL, HSG/MSF |
| 4 | audio channel info | yes | current Audio Control mode page |
| 6 | device status | yes | baseline flags plus current audio-playing bit |
| 7 | sector size | yes | yes |
| 8 | volume size | yes | yes |
| 9 | media changed | yes | yes |
| 10 | audio disk info | yes | yes |
| 11 | audio track info | yes | yes |
| 12 | audio Q-channel info | yes | READ SUB-CHANNEL, checked conversion |
| 14 | UPC/EAN code | yes | checked MCN ASCII-to-BCD conversion |
| 15 | audio status info | yes | pause flag and committed MSF range per unit |
| 2, 3, 5, 13, 16 | - | no | no |

### IOCTL output (0Ch)

| Code | Function | ASPICD | ASPICDA |
|---|---|---|---|
| 0 | eject disk | yes | yes |
| 1 | lock/unlock door | yes | yes |
| 2 | reset drive | yes | yes (no-op) |
| 3 | audio channel control | yes | checked MODE SELECT(10) |
| 5 | close tray | yes | yes |
| 4, 6 | - | no | no |

## Device status (IOCTL input 6)

ASPICD always sets bits 7 (prefetching), 8 (audio channel manipulation) and
10, and per drive:

- bit 1 (door unlocked) unless the door is locked;
- bits 2 and 9 (raw reads, Red Book addressing) when the drive type supports
  raw reads;
- bit 4 (audio play) when the drive plays audio;
- bits 0 and 11 (door open, no disk) when TEST UNIT READY reports no disk.

ASPICDA uses baseline `0216h` and sets bit 10 only while its selected unit
is playing. Bit 8 is set only after a per-unit probe confirms a valid current
Audio Control page and a matching changeable page with routing/volume bits,
or after successful MODE SELECT using such a mask. Active audio is polled
before device-status output; paused or completed audio does not set bit 10.
The other per-drive bits and "no disk"
are still to do. It reads page 2Ah at INIT (Audio Play, CD-DA commands, CD-DA
accurate) and lists it with `/V`; bit 4 stays set on all drives, because
SHSUCDX with `/A:ON` plays CD audio digitally also where the drive has no
analog output.

## READ LONG

- Up to 255 sectors per request (0 means 256); HSG and Red Book addresses.
- The range is checked against the volume size: error 08h (sector not
  found) beyond it.
- Raw reads (2352 bytes) only on drive types with raw support.  Older drives
  switch the block size with MODE SELECT before reading and back after it.
- Transfers in chunks of 32 sectors.
- **XA emulation** (`/XAEMUL`, default per drive type): CD-ROM XA Mode 2
  Form 1 sectors read raw one at a time, the 2048 data bytes copied out, for
  drives that cannot read XA discs cooked.

ASPICDA uses READ(10) (cooked) and READ CD (BEh, raw; user data only when the
drive rejects the full sector of an audio track) in chunks of 16 sectors.
MMC drives (all ATAPI and USB drives) need neither MODE SELECT nor XA
emulation; those paths address pre-MMC SCSI drives. This distinction does
not remove legacy-device behavior from the goal of full ASPICD coverage.

## Positioning and address validation

ASPICDA now implements commands 82h and 83h as positioning hints using
SCSI SEEK(10), not successful no-ops. Both read the start DWORD at request
offset 14h (the buffer and count fields are ignored). A request shorter than
18h bytes fails with DOS error 05h. Each operation first obtains the current
last LBA with READ CAPACITY(10); the last sector is valid, a larger address
fails with error 08h without issuing SEEK. Drive errors propagate; unsupported
SEEK is not silently accepted. Prefetch positions the drive but does not promise
that any particular number of sectors has been cached.

READ LONG, SEEK/PREFETCH and PLAY share a checked HSG/MSF decoder: only
address modes 0 and 1 are accepted. MSF requires a zero reserved byte,
minutes 0..98 (matching the reference decoder), seconds 0..59 and frames
0..74, and cannot precede 00:02:00 (LBA zero). Invalid addresses return 08h.
This does not yet add explicit READ LONG capacity/range checking.

PLAY reads its start at **0Eh**, not the READ LONG start at 14h. Its packet
must contain at least 16h bytes. Nonempty play ranges reject DWORD addition
overflow and endpoints beyond 99:59:74 before conversion to PLAY AUDIO MSF;
they do not yet validate the audio-track layout. Per-unit state and busy
semantics are described below.

Volume-size IOCTL and positioning share READ CAPACITY decoding. A last LBA
of FFFFFFFFh is rejected (08h): it requires a larger-capacity command and
must not wrap to a zero volume size. Short/malformed ASPI responses and
audio-only or legacy drives rejecting READ CAPACITY still need dedicated
qualification; there is no untested TOC fallback hiding such errors.

`tests/cda_commands.asm` includes the actual driver, invokes its far
strategy/interrupt entry points and uses a memory-only ASPI callback. It
checks HSG/MSF decoding, packet layouts, boundaries, overflow, CDB bytes,
no-data positioning and capacity/seek errors. Through installed SHSUCDX it
also tests sector zero, the last sector and one past the end for both
positioning commands on the QEMU CD image. `make dos-cda-smoke` runs these
checks on both AHCI and IDE, alongside the existing multichunk file reads.

## Head position and Q channel

IOCTL input 1 and 12 now use MMC READ SUB-CHANNEL (42h), SUBQ=1,
format 1, allocation length 16. Head position requests use the caller's
HSG/MSF mode; Q-channel requests use MSF. Each call asks the drive again,
not an assumed position derived from the last read or SEEK.

The DOS packets follow RBIL table 01449. Head position has a 6-byte control
block (mode at 1, DWORD location at 2). Q-channel has an 11-byte block:
CONTROL/ADR at 1, BCD track at 2, binary index at 3, binary relative M/S/F
at 4..6, zero at 7 and binary absolute M/S/F at 8..10. Relative time is
copied without the 150-frame bias used for absolute MSF/LBA conversion.
Track AAh is retained as the lead-out marker.

The original's SCSI-2 path at `1D90h` calls the packet mapper at `1A18h`:
that mapper swaps CONTROL/ADR via `23F8h`, converts the binary track to BCD
via `2405h`, copies the index unchanged and copies the two time triples
without BCD conversion. These selected instructions were checked alongside
the Ghidra export. The MMC request and response offsets were cross-checked
against the primary [Linux cdrom implementation](https://github.com/torvalds/linux/blob/master/drivers/cdrom/cdrom.c)
(`cdrom_read_subchannel`); the implementation here is OpenASPI's own.

New handlers check the request header, control-block length, null pointer
and far-offset wrap before accessing their output fields. Invalid head modes
return 03h; short/wrapping buffers return 05h. A malformed format-1 response
(wrong declared length/format, invalid track/index or MSF fields) returns
0Ch. SCSI/ASPI failures retain the normal sense-to-DOS mapping, including
unsupported command and no medium. On failure, caller output is unchanged.
The response scratch buffer is poisoned before each command to detect absent
or incomplete MSF replies rather than reusing stale data. This does not
provide a transport-independent actual-byte-count guarantee for an ASPI
manager claiming success after a truncated binary-LBA response.

No capability is inferred from the analog-play bit in MODE page 2Ah:
data discs and digitally played discs can also have useful Q information.
Drives rejecting READ SUB-CHANNEL fail honestly; pre-MMC vendor alternatives
are not implemented. UPC uses the separate format-2 path described below.

`tests/cda_subchannel.asm` exercises the actual far strategy/interrupt entry
points with a memory-only manager, non-CS aliased output buffers and guards.
It checks binary/BCD/nibble layout, HSG and MSF positions, relative-time
semantics, lead-out, short/null/wrapping buffers, missing/malformed/partial
MSF responses, and unsupported/no-medium errors. It runs in both AHCI and
IDE smoke boots, alongside the installed driver's read/seek tests. These are
deterministic protocol tests, not physical audio-disc qualification.

## Audio state, pause and busy status

Each unit now owns an idle/playing/paused state and the committed start/end
range of its last successful PLAY. A rejected PLAY never overwrites that
range. The DOS IOCTL input 15 block is 11 bytes: pause WORD at 1, packed
binary MSF start DWORD at 3 and exclusive end DWORD at 7. Initial/cleared
ranges are zero. The reference at `0747h` copies those fields from the unit;
the selected PLAY/STOP instructions at `1636h`/`172Ah` confirm MSF endpoints
and a saved resume position after pause. The original's three-frame PLAY
adjustment is not emulated; OpenASPI uses the requested exclusive endpoint.

For an active driver-issued PLAY, audio-status and device-status IOCTLs,
OPEN, CLOSE and INPUT FLUSH query READ SUB-CHANNEL before returning status.
The [MMC/SCSI audio-status values](https://github.com/torvalds/linux/blob/master/include/uapi/linux/cdrom.h)
11h/12h mean playing/paused; 13h/14h/15h terminate active playback. A terminal
response needs a valid status header but need not contain current-Q position
data. Playing/paused responses require the validated format-1 MSF response.
Unsupported status 00h fails with 03h; malformed headers/status/position
fail with 0Ch. Outputs are unchanged on failure. Idle units are not polled:
external players that bypass this driver are not independently discovered.

Successful IOCTL input/output, OPEN/CLOSE and INPUT FLUSH responses include
the DOS busy bit (0300h instead of 0100h) when the unit is known to be playing.
Paused audio is not busy. A new PLAY while playback is still active is
rejected with 8302h after polling, rather than replacing it unnoticed.
Other IOCTLs use the latest committed state; they do not all poll the drive.
PLAY, STOP and RESUME themselves return ordinary completion on success.

STOP during active playback sends PAUSE/RESUME(0); only successful pause
commits paused state and the polled MSF resume position. RESUME requires a
paused, valid range, polls it, and commits playing only after successful
PAUSE/RESUME(1). A second STOP while paused clears the resume range without
sending another PAUSE. STOP while idle clears the old range. Natural
completion clears busy/pause but retains the last range for status reporting.
Successful eject/close-tray clears only the selected unit's audio range;
failed tray operations retain it unless the failure itself indicates a lost
medium. NOT READY or UNIT ATTENTION in the common SCSI result handler
invalidates that unit's resume data, including when a non-audio query consumes
the notification. The MEDIA CHANGED query uses the same raw-result helper,
even though it returns a media-change byte rather than a DOS error.
A missing/replaced medium cannot reuse the old range.
Other failed commands preserve the committed state/range and return their
DOS error. Error-stopped playback is reported as not busy, not successful
audio playback; the DOS audio-status packet has no separate error-status field.

`tests/cda_audio_state.asm` includes the real driver and far entry points.
Its two-unit memory manager checks play/pause/resume, saved positions,
natural/error/no-status completion, exact busy/error flags, malformed and
unsupported replies, unchanged guarded outputs, failed state transitions,
media loss/replacement, short packets and cross-unit isolation. It runs in
both AHCI/IDE smoke boots. These state-machine tests do not qualify physical
audio hardware, analog output or a full CD-player application yet.

## Volume and channel routing

IOCTL input 4 and output 3 use nine-byte DOS control blocks: the code byte,
then four `(input channel, volume)` byte pairs for output ports 0..3.
Input channel indexes are 0..3 and volume is 0..255. GET reads the actual
current drive settings, not the last requested software values. SET first
validates all caller fields, reads the current hardware page, then reads its
changeable-bit mask and submits MODE SELECT only if every requested change
is supported. The input/output envelopes share length/null-pointer checks;
these handlers also check control-block length and segment-offset wrap.

The MMC path uses MODE SENSE(10), page 0Eh, PC=0/1, DBD=1, allocation 64.
An eight-byte mode header and a returned block-descriptor length are parsed
with bounds checks even when the drive ignores DBD. The requested page must
be an ordinary page 0Eh with at least 14 payload bytes, fully contained in
the declared response and scratch buffer. Unexpected pages, subpages,
oversized/truncated declarations and current/mask page-size mismatches
fail with 0Ch. This strict implementation does not emulate bridges with
inconsistent mode-data lengths or provide a MODE SENSE(6) fallback.

DOS channel indexes map to one-hot SCSI selectors `1,2,4,8`. A mixed selector
such as 3 cannot be represented as one DOS input channel; GET returns 03h
without partially overwriting the caller's output. Selector zero is muted:
GET reports that port's own index and volume zero. Writing that semantic
zero-volume result back to an already muted port preserves its original
selector/volume pair, including a nonzero fixed volume, so it stays silent
and does not fail unnecessarily on fixed bits. A non-muted channel with
volume zero remains a normal routed channel at zero amplitude.

SET preserves selector reserved bits and all non-routing page fields,
including a bounded opaque page extension. It sends only a zeroed eight-byte
mode header plus the complete Audio Control page, strips PS, omits block
descriptors/unrelated pages, sets PF=1 and SP=0, and uses the exact payload
length. Requested differences in unchangeable bits return 03h; volume is not
silently clamped. A failed read, mask query or SELECT propagates its DOS
error and never becomes a successful cached setting. Playback state and
other units' settings are not modified by these handlers.

The baseline command/header/page offsets and mask use were cross-checked
against the primary [Linux MMC volume implementation](https://github.com/torvalds/linux/blob/master/drivers/cdrom/cdrom.c)
(`mmc_ioctl_cdrom_volume`). Unlike its volume-only API, the DOS interface also
requires explicit input-channel/selector translation. The original `0B46h`
handler caches only the first two caller pairs and dispatches a vendor-specific
control path; `0519h` reports those cached pairs plus fixed third/fourth input
indexes. OpenASPI's MMC implementation addresses all four hardware ports and
does not copy proprietary code or claim the legacy paths are implemented.

Device-status capability probing is optional: an unsupported Audio Control
page does not break the basic status query. Explicit ILLEGAL REQUEST or an
entirely fixed page is cached as unavailable per unit; transient/malformed
probe responses remain unknown and can be retried. A no-change SELECT on an
entirely fixed page does not falsely enable bit 8. That bit does not promise
audible output: physical analog wiring and digitally played VSBHDA volume
are separate from the drive's Audio Control page.

`tests/cda_audio_channels.asm` uses the real far strategy/interrupt handlers
and a two-unit memory-only manager. It checks all four ports, non-CS buffers,
guards, mute/mixed/index cases, two descriptor layouts, variable page tails,
PS/header/reserved-field preservation, current/mask/SELECT failures, fixed
bits, hardware readback after failure and success, capability reporting,
busy state, unit isolation and short/null/wrapping packets. Both AHCI/IDE
smoke boots run it; physical volume, wiring and diverse drive/bridge behavior
remain unqualified.

## UPC/EAN media catalog number

IOCTL input 14 accepts an 11-byte control block. It obtains the MCN with
READ SUB-CHANNEL format 2 (SUBQ, 24-byte allocation), then obtains CONTROL
from a separate format-1 query. Position and MCN requests share the same
ASPI transport; there is no separate duplicate submission/wait path.

The DOS result contains CONTROL/ADR at 1, seven packed-BCD bytes at 2..8,
zero at 9 and AFRAME at 10. Thirteen ASCII digits from the drive become
thirteen nibbles, preserving leading zeros; the final low nibble is explicitly
zero. ADR is 2 and CONTROL comes from the current-position response, not
format 2's reserved byte. MMC's binary frame number is converted to the raw
mode-2 Q packet's BCD representation. See the primary
[X3T10 MMC draft, section 5.1.12.3, tables 62/63](https://13thmonkey.org/documentation/SCSI/mmc-r10a.pdf#page=65)
for the transport format; DOS packet fields follow RBIL table 01449.

Instruction inspection of the original's `0857h` path and `0941h` helper
confirms the ASCII packing, MCVAL failure (8108h), and follow-up format-1
CONTROL query. That original path leaves its zeroed AFRAME field at zero;
OpenASPI returns the available frame instead. Its `072Eh` capability gate
and vendor-specific alternatives are not implemented as legacy profiles here.

Missing MCVAL or an all-ASCII-zero catalog number returns DOS error 08h,
not a fabricated valid zero code. Header/format/length, reserved fields,
decimal digit bytes and frame range are checked; malformed data returns
0Ch. All results are staged until both queries succeed: errors leave the
caller block unchanged. No EAN check-digit policy is imposed on stored
catalog data beyond decimal format/nonempty checks. Fresh queries and
poisoned scratch buffers prevent reuse of an earlier disc's code. Common
NOT READY/UNIT ATTENTION handling clears only the selected unit's saved
audio state/range while preserving the original DOS error.

SHSUCDX needs no change for UPC: `CD_Request` forwards ordinary IOCTL input
through `DDCall`; digital mode intercepts PLAY/STOP/RESUME, not UPC. The test
`tests/cda_upc.asm` verifies valid codes, leading zeros, BCD/frame packing,
CONTROL/ADR, absent/malformed/partial replies, second-query failures,
busy/unit isolation and guarded short/null/wrapping buffers against the real
driver with memory ASPI. It additionally calls the installed driver through
SHSUCDX in OFF and ON modes on the QEMU image without a usable catalog,
checks unchanged error output and restores the prior mode. Both AHCI/IDE
boots pass. Positive catalog data is memory-tested, not yet qualified with
a catalog-bearing physical disc or VSBHDA playback. Digital-player volume
and status integration are separate from this unchanged UPC forwarding path.
The generated [CUE/ISO catalog fixture](qemu-cd-catalog.md) is ready for a
catalog-capable backend. Native QEMU 10.2.3 lacks READ SUB-CHANNEL, so the
installed-driver negative test proves unsupported-command propagation;
it does not distinguish an absent catalog on a capable drive.
Positive image-backed tests now also pass using the separate patched 86Box
variant in that guide, including AHCIASPI/ASPICDA resident in UMBs. This
does not replace physical-disc/drive qualification or extend the current
DEVICEHIGH result to the other OpenASPI drivers.

## Options

`/D:name`, `/MB` (?), `/TYPE:n`, `/PAUSE`, `/NORST`, `/DIAG`, `/XAEMUL`,
`/NOXAEMUL`, `/ID=n` (target), `/L` (LUN), `/NOLUN`.

## Drive types

ASPICD knows command sets for pre-SCSI-2 drives and picks one by the INQUIRY
vendor (or `/TYPE:`): Toshiba, Texel, Hitachi, Chinon, Denon, SCSI-2,
Pioneer, Generic.  Its vendor table names PLASMON, YAMAHA, KODAK, HP
C4324/C4325, PLEXTOR, ShinaKen, MATSHITA, DEC, IBM CDRM00103, TEAC CD-40S,
IBM, COMPAQ CR-503, COMPAQ, CHINON, DENON, HITACHI, LMS, NEC, PANASONIC,
SONY, TOSHIBA, TEXEL, JVC, IMS, PIONEER, HITACHI CDR-3750, MATSHITA PD-1,
NRC.  These are vendor-specific audio and block-size commands of SCSI-1
drives; ASPICDA targets MMC drives only (ATAPI on AHCIASPI, USB on EUSBASPI,
SCSI-2/MMC on SCSI adapters).

Full compatibility with the original still requires validated support for
those older command sets; today's MMC baseline must not be labelled complete
ASPICD compatibility merely because contemporary ATAPI/USB reads pass.

## Re-analysis: dispatch and behavioral evidence

All offsets below refer to the hashed original SYS loaded at `0000:0000`.
The exported C contains real-mode stack/register/flag reconstruction caveats;
the tables and selected paths were also inspected as instructions.

| Dispatch table | File/image offset | Bounds read from image |
|---|---|---|
| DOS low commands | `001Ch` | 17 entries, commands 00h..10h |
| CD-ROM commands | `0040h` | 10 entries, commands 80h..89h |
| IOCTL input | `03FCh` | 17 entries, codes 00h..10h |
| IOCTL output | `097Fh` | 7 entries, codes 00h..06h |

The original unsupported-operation target is `256Fh`, returning `8103h`.
Do not count table slots pointing there as supported. The analysis script
exports every slot, including unsupported ones, so coverage is auditable.

| Original handler | Observed behavior | ASPICDA gap / acceptance requirement |
|---|---|---|
| `025Eh` / `0269h` | Strategy / interrupt, private stack and low/high table dispatch | Current stack/dispatch exists; preserve registers and exact success/busy/error behavior in tests |
| `0438h` / `09DBh` | IOCTL input/output dispatch with per-unit setup and status postprocessing | Existing partial IOCTL tables are not full functional coverage |
| `0538h`, input 6 | Starts with bits `0580h`, adds device/audio/raw/lock/media state | Playing bit is dynamic; lock/media/raw baseline still needs per-unit capability/state handling |
| `0519h` / `0B46h`, input 4 / output 3 | Cached audio routing/volume result and channel-control path | Four-port MMC hardware readback/set, masks and failure tests implemented; qualify physical/legacy behavior |
| `04BAh` / `0715h` | Head-position and Q-channel paths | MMC queries/conversion/error tests implemented; qualify real audio/data discs and legacy alternatives |
| `072Eh` | UPC path gated by per-drive capability | MMC MCN/CONTROL queries, packed BCD and failure tests implemented; qualify physical/legacy behavior |
| `0747h` | Audio-status response uses tracked state and play-range values | Per-unit MSF range/pause status and failure tests implemented; qualify physical media/player behavior |
| `0AF2h`, output 2 | Executes drive/state reset-related operations and lock/state handling | Current success-only no-op is incomplete; a failed operation must not look like a successful reset |
| `0CD2h` / `15D1h` | Open/close / input flush validate unit and report audio busy state | Active-audio polling and busy/error semantics implemented/tested |
| `0CEDh`, READ LONG | Checks address/read modes, capacity range and raw support; count zero means 256, values above 255 rejected | Current zero-count no-op and missing explicit capacity check differ; add bounds/overflow/residual tests |
| `14D9h`, 82h/83h | Shared prefetch/seek handler validates mode/range and issues drive operations | MMC SEEK(10) and fresh-capacity validation implemented/tested; legacy command sets remain |
| `1636h` / `172Ah` / `179Eh` | Play, stop/pause and resume control paths | Committed per-unit state/range and busy/failure tests implemented; disc/track validation and legacy behavior remain |
| `2830h` | Delegates operations through command-set-specific dispatch | SCSI-1/vendor compatibility requires additional command-table and hardware validation |

### Completion ledger

| Area | Current ASPICDA | Before claiming full ASPICD compatibility |
|---|---|---|
| MMC cooked/raw reads | Implemented and QEMU tested | Count-zero behavior, bounds, overflow, residual/error cases and diverse disc layouts |
| TOC / media-change / capacity | Basic implementation | Per-unit caches, replacement media, malformed/short responses, empty-drive behavior |
| Play / pause / resume / audio status | MMC paths, per-unit state/MSF range, polling, busy/error tests | Disc/track ranges, physical/player qualification and legacy command sets |
| Head/Q | MMC queries and packet/error/guard tests implemented | Physical audio/data-disc and legacy-command-set qualification |
| UPC | MMC MCN/CONTROL queries, BCD, error/guard tests and SHSUCDX negative forwarding checks | Catalog-bearing physical discs, diverse drives and legacy paths |
| Channel routing/volume | Four-port MMC page read/set, change masks, readback and preservation tests | Physical/bridge/player qualification, legacy MODE(6)/vendor paths |
| Device status and lock state | Dynamic playing/channel-control bits; per-unit committed lock/tray state and tested control/error transitions | Live manual/media/capability status and hardware qualification |
| Seek/prefetch | Real MMC SEEK(10), current bounds and error propagation | Audio-only/legacy media qualification, alternate command sets |
| Reset | Success-only no-op | Real operations and error propagation; no false capability claims |
| Legacy command sets / XA | Not implemented | Reference-verified profiles; vendor commands must not be sent based on broad vendor-name guesses |
| Selection and compatibility options | /D and /V baseline | /ID, LUN selection/limits and remaining reference options, with defined supported behavior |

The general completion rule is functional coverage, not reusing proprietary
code. Every missing area needs an implementation plus actual OpenASPI tests.
Static decompilation, compile success and happy-path MSCDEX/SHSUCDX reads are
necessary inputs but not substitutes for these checks.

## To do in ASPICDA

1. Physical/player qualification for audio state/status and head/Q; disc/track
   range validation and remaining legacy PLAY semantics.
2. Physical/bridge/player qualification for channel controls; legacy MODE(6)
   and vendor-specific Audio Control paths.
3. Physical catalog-bearing-disc qualification for UPC; legacy alternatives.
4. Device status per drive: live/manual door state, "no disk", raw capability
   (page 2Ah is read already). Driver-issued lock/eject/close state and
   error tests are described in [media controls](media-control.md).
5. READ LONG: count-zero behavior and range check against the volume size;
   qualify positioning on audio-only/legacy media.
6. Optional `/ID=`, `/L` and a unit limit to pick drives.
