# Formatting and media type (ASPIFDD)

ASPIFDD implements generic IOCTL `42h` (format and verify track) and `68h`
(sense media type) in category `08h`; query `19h` reports both. ASPIDSK
reports them unsupported. Code: `common/dos/block_format.inc`; test:
`tests/block_format.asm` (memory-only ASPI manager, in `tests/dos_disk.sh`).

## 42h: format and verify track

Packet ([RBIL table 01563](https://fd.lod.bz/rbil/interrup/dos_kernel/21440d.html)):
byte flags, WORD head, WORD cylinder, and with flags bit 1 a WORD track count.
Other flag bits fail with "unknown command".

The geometry is the current BPB: the one set with `40h`, else the medium's
volume, else the installation default. Its sectors/track, heads and total
sectors give the size to format to. Track addresses are device-absolute, as
for `41h`/`61h`.

- **Status call (flags bit 0):** byte 0 returns whether the size can be
  formatted, from READ FORMAT CAPACITIES: 0 yes, 1 the drive has no
  READ FORMAT CAPACITIES, 2 the size is not offered, 3 no medium. Nothing is
  written.
- **Format:** a drive formats whole media, not tracks. The first track
  (cylinder 0, head 0) therefore sends FORMAT UNIT for the whole medium;
  every 42h then verifies its tracks with VERIFY(10). Formatting another
  track alone only verifies it.
- The size must be one READ FORMAT CAPACITIES offers; a write-protected
  medium fails with error 00h before any command is sent.
- After FORMAT UNIT the cached volume is gone (BUILD BPB reads the new
  one); a BPB set with `40h` stays for the formatter.

Two FORMAT UNIT forms, chosen at INIT by the INQUIRY name:

| Drive | CDB | Parameter list |
|---|---|---|
| LS-120, LS-240, SuperDisk (SFF-8070i) | 12 bytes `04 17 00 00 00 00 00 00 0C 00 00 00` | `00 A2 00 08` (FOV, DCRT, IMMED) + blocks, `00`, `00 02 00` (as Linux ide-floppy) |
| others: ZIP, Jaz, Clik, SyQuest, SyJet (SBC) | 6 bytes `04 10 00 00 00 00` | `00 02 00 00` (IMMED): the drive's own format of its current capacity, which must be the requested size |

With IMMED the drive returns at once. TEST UNIT READY is then asked once per
timer tick while the drive reports "not ready, operation in progress"
(02/04); UNIT ATTENTION is skipped; any other error ends the format with its
DOS error. The wait ends after about an hour. FORMAT UNIT is never repeated.

SyQuest ATA cartridges behind AHCIASPI's ATA translation have neither READ
FORMAT CAPACITIES nor FORMAT UNIT: the status call answers 1 and a format
fails with "unknown command" before anything is written.

Limits: the 86Box ZIP/LS-120 emulations accept FORMAT UNIT without changing
the image, so only the commands sent and the error paths are tested. Real
drives are unqualified; LS-120 formatting a 1.44 MB disk in particular.

## 68h: sense media type

Byte 1 returns the type by capacity: `02h` 720 KB, `07h` 1.44 MB, `09h`
2.88 MB. Byte 0 is 1 when that is the size of the installation-time
default BPB, else 0. Other sizes (ZIP, 120 MB) have no DOS media type: the
call fails with "unknown media" and leaves the packet unchanged. Without a
medium it fails with "not ready".
