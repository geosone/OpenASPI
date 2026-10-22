# ASPICD.SYS compatibility notes

Black-box and disassembly notes on Adaptec `ASPICD.SYS` 4.01 (EZ-SCSI 5.0,
SHA-256 `72b7166f457751e0461f6b3a99ce0dd0b19fd8396def9b196eb00467428c78fb`),
the driver `ASPICDA.SYS` replaces.  They record its interface and behavior
(command coverage, options, status bits) as a checklist for ASPICDA.  No
Adaptec code is used; the binary is not part of OpenASPI (see
[reference material](reference-material.md)).  It was examined with Ghidra
12.1 (raw real-mode load at 0000:0000, the jump tables of the interrupt
routine as function entries).

## Device header

Character device, attribute `C800h` (IOCTL, open/close/removable), default
name `MSCD000` style set by `/D:`, the unit count in the CD-ROM header
extension.  The interrupt routine switches to a private stack.

## Device commands

| Command | ASPICD 4.01 | ASPICDA 0.1 |
|---|---|---|
| 00h INIT | yes | yes |
| 03h IOCTL input | yes (below) | partly (below) |
| 07h input flush | yes | yes (no-op) |
| 0Bh output flush | no | yes (no-op) |
| 0Ch IOCTL output | yes (below) | partly (below) |
| 0Dh/0Eh open/close | yes | yes |
| 80h READ LONG | yes | yes |
| 82h READ LONG PREFETCH | yes (with seek) | no-op |
| 83h SEEK | yes | no-op |
| 84h PLAY AUDIO | yes | yes (PLAY AUDIO MSF) |
| 85h STOP AUDIO | yes | yes (PAUSE) |
| 86h/87h WRITE LONG | no | no |
| 88h RESUME AUDIO | yes | yes |

### IOCTL input (03h)

| Code | Function | ASPICD | ASPICDA |
|---|---|---|---|
| 0 | device header address | yes | yes |
| 1 | location of head | yes | **missing** |
| 4 | audio channel info | yes | **missing** |
| 6 | device status | yes | yes (fixed value) |
| 7 | sector size | yes | yes |
| 8 | volume size | yes | yes |
| 9 | media changed | yes | yes |
| 10 | audio disk info | yes | yes |
| 11 | audio track info | yes | yes |
| 12 | audio Q-channel info | yes | **missing** |
| 14 | UPC/EAN code | yes | **missing** |
| 15 | audio status info | yes | **missing** |
| 2, 3, 5, 13, 16 | - | no | no |

### IOCTL output (0Ch)

| Code | Function | ASPICD | ASPICDA |
|---|---|---|---|
| 0 | eject disk | yes | yes |
| 1 | lock/unlock door | yes | yes |
| 2 | reset drive | yes | yes (no-op) |
| 3 | audio channel control | yes | **missing** |
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

ASPICDA reports the fixed value `0216h`; the per-drive bits and "no disk"
are to do.

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
emulation; both are only for pre-MMC SCSI drives.

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

## To do in ASPICDA

1. IOCTL input 12 (Q channel, READ SUB-CHANNEL), 15 (audio status: paused,
   start/end of the last play) and 1 (location of head): CD players.
2. IOCTL input 4 / output 3 (audio channel volume and routing, MODE SENSE /
   MODE SELECT page 0Eh).
3. IOCTL input 14 (UPC/EAN, READ SUB-CHANNEL format 2).
4. Device status per drive: door lock state, "no disk", raw and audio
   capability (MODE SENSE page 2Ah).
5. READ LONG: range check against the volume size, real prefetch/seek.
6. Optional `/ID=`, `/L` and a unit limit to pick drives.
