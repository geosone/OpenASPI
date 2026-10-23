# ASPIDISK.SYS and MKELS120.SYS compatibility notes

Black-box and disassembly notes on the block drivers that `ASPIDSK.SYS` and
`ASPIFDD.SYS` replace, as a checklist.  No vendor code is used; the binaries
are not part of OpenASPI (see [reference material](reference-material.md)).
Both were examined with Ghidra 12.1 and ndisasm (raw load at 0000:0000, the
command table of the interrupt routine).

The 2026-10-23 ASPIDISK re-analysis imported the original into Ghidra
12.1.4 DEV and exported 94 discovered functions, including INIT and all
nonzero DOS dispatch entries. See [reproducing the analysis](reference-analysis.md).
An exported function is evidence to review, not a passed compatibility test.

- Adaptec `ASPIDISK.SYS` 4.01b (EZ-SCSI 5.0), SHA-256
  `3066b40ed15ae6ddc8211d9434eb3c2ff078f0170e7f527ead0daca08ae044ee`.
- MKE `MKELS120.SYS` (LS-120 IDE kit, 120Pack, 1998), SHA-256
  `487e5391a945ad92f4366e9283f2607b79dfd8e18a70c18fc20a047e56215141`.

## Device headers

| | ASPIDISK | MKELS120 |
|---|---|---|
| attribute | `68C0h` | `08C2h` |
| meaning | IOCTL, non-IBM format, open/close/removable, IOCTL query, generic IOCTL | 32-bit sectors, generic IOCTL, IOCTL query, open/close/removable |
| own stack | no | yes |

## Device commands

| Command | ASPIDISK | MKELS120 | ASPIDSK/ASPIFDD 0.1 |
|---|---|---|---|
| 00h INIT | yes | yes | yes |
| 01h MEDIA CHECK | yes | yes | yes |
| 02h BUILD BPB | yes | yes | yes |
| 03h/0Ch IOCTL input/output | yes | yes (no-op) | no |
| 04h READ | yes | yes | yes |
| 08h/09h WRITE (VERIFY) | yes | yes | yes |
| 0Dh/0Eh OPEN/CLOSE | yes | yes (no-op) | yes (no-op) |
| 0Fh REMOVABLE MEDIA | yes | yes (no-op) | yes |
| 13h GENERIC IOCTL | yes | yes | 08h/60h parameters, 08h/66h Media-ID (read only) |
| 17h/18h GET/SET LOGICAL DRIVE | yes | 17h only | **missing** |
| 19h IOCTL QUERY | yes | yes | yes, only advertises 08h/60h and 08h/66h |

### Generic IOCTL (13h)

Category 08h (disk); ASPIDISK also 48h (FAT32 disk, MS-DOS 7.1).
ASPIDISK's execution handler at `01BBh` accepts the minors below, but its
query handler at `0051h` **omits 67h**. Do not copy that inconsistent query
result into OpenASPI.

| Minor | Function | ASPIDISK | MKELS120 |
|---|---|---|---|
| 40h / 60h | set / get device parameters | yes | yes |
| 41h / 61h | write / read track | yes | yes |
| 42h / 62h | format / verify track | yes | yes |
| 46h / 66h | set / get media ID | yes | yes |
| 47h / 67h | set / get access flag | yes | 67h |
| 68h | sense media type | no | yes |

These are interfaces used by disk/format/label tools, but dispatch coverage
alone does not prove that a complete application works. The kit explicitly
excludes DOS `DISKCOPY` support in MKELS120.SYS; Windows VxD/formatter history
must not be attributed wholesale to the SYS. Its query handler also rejects
41h/61h despite having track handlers. See the newer
[ZIP/LS-120 investigation](aspifdd-reference.md) for exact offsets, limitations
and the distinction between an implemented handler and a success-only path.
ASPIDSK needs at least 60h, 66h, 46h, 47h/67h and 61h.

## ASPIDISK behavior

- Options `/pause`, `/nospinup`, `/id=` (targets to use).
- Devices handled by the host adapter BIOS (INT 13h) are skipped ("Handled
  by Host Adapter BIOS"); ASPIDSK must do the same to avoid two drive
  letters for one disk with Adaptec BIOS adapters.  AHCIASPI and EUSBASPI do
  not present disks through their BIOS, the board BIOS may (USB boot
  emulation: the test stick appears as C: through SeaBIOS as well).
- Spin-up of stopped drives (START STOP UNIT), unless `/nospinup`.
- Removable media get reserved drive letters ("x: to x: reserved") for the
  partitions of disks inserted later.
- Floptical disks are recognized (INQUIRY "FLOPTICAL").
- Several partitions per disk ("logical drives"), translation for disks
  over 1 GB, a capacity limit message.
- Requires an ASPI manager with the current ASPI interface (rejects
  "old-style" managers).

## Re-analysis: behavior behind the entry points

Offsets below are file/image offsets for the hashed 4.01b SYS, not addresses
in OpenASPI. They were checked against the disassembly as well as Ghidra's
output; reconstructed C types and register arguments alone are not an ABI.

| Reference entry | Observation | OpenASPI consequence |
|---|---|---|
| `0012h` / `001Dh`, table `13B7h` | Strategy / interrupt; DOS commands 00h..1Ah are table-dispatched | Keep an explicit supported-command matrix; slot 1Ah is zero, not a supported operation |
| `0117h`, DOS 03h/0Ch | Seven-byte private packet, signature word `4131h` (bytes `31h 41h`), copying five per-unit state bytes from/to offset `+5Ch` | This is not general SCSI passthrough; validate its semantics/target ownership before considering legacy binary compatibility |
| `0194h` | OPEN/CLOSE return success without device I/O | Existing no-op is not proof of locking support |
| `01B3h` | GET/SET LOGICAL DRIVE both return unit byte zero | Single-logical-drive mapping behavior still needs implementing/testing in OpenASPI |
| `02D5h` / `02E6h` | Get/set access flag reads/writes the global byte `135Ah` | Software access status, **not** MODE SENSE write-protection detection; enforcement is not demonstrated by these handlers |
| `0322h` / `0407h` | Get/set parameter paths distinguish 25-byte and extended BPBs and category 08h/48h | 60h supports legacy/extended BPBs; 40h remains open |
| `0460h` / `0473h` | Track read/write select a shared CHS-to-LBA path | Requires tested geometry, partition offsets, bounds and error handling, not just generic block I/O |
| `0556h` | 42h/62h share a handler; ordinary path constructs VERIFY(10), with a separate format branch for recognized floptical media and a query-only branch | Do not implement a universal physical FORMAT UNIT just because 42h exists |
| `1A19h` | Floptical format helper builds FORMAT UNIT plus a small media/track-specific parameter list | Needs a separately validated device profile and scratch-media tests |
| `018Dh` -> `0699h` | DOS WRITE WITH VERIFY uses a WRITE followed by VERIFY path | OpenASPI fallback now uses WRITE + separate VERIFY instead of silently dropping verification |
| `1604h` / `164Ch` | Media-ID helpers handle FAT12/16 and extended-BPB metadata layouts | 66h covers FAT12/16 and conditional FAT32 reads; 46h remains open |
| `31D4h` | Uses ASPI command 06h (GET DISK INFO) to check BIOS handling | INIT now skips DOS-owned units; explicit unsupported fallback and malformed/error replies are tested |
| `3483h` / `36DEh` / `3586h` | Partition discovery, extended-BPB units and reserved removable-volume entries | Multi-partition/removable-letter coverage is larger than today's first-volume-only model |

### Completion ledger

The target is functional coverage of the original, not merely a successful
load or a list of accepted IOCTL numbers. No row below is implicitly done
because Ghidra found a function.

| Area | Current ASPIDSK | Required evidence before full compatibility |
|---|---|---|
| FAT12/FAT16 data I/O | Implemented for one selected volume, 512-byte sectors | Retain success/error, large-LBA, buffer/chunk and image-consistency tests |
| WRITE WITH VERIFY | Combined command, with WRITE+VERIFY fallback | Memory tests check both chunks, no-data VERIFY and failures of WRITE/VERIFY; device qualification remains |
| Parameters / Media-ID | Read-only 60h/66h with matching queries | Add 40h/46h and their error/media-change tests; no success-only shims |
| Software access flag / logical mapping | Not implemented | Distinguish logical policy from hardware write protection and lock state |
| Track read/write/verify/format | Not implemented | Exact packet/bounds behavior plus validated device-specific destructive paths |
| FAT32/category 48h | Extended BPB, parameter/Media-ID reads, DOS filesystem read/write tested on FreeDOS 1.4 | Standard setting/track operations and MS-DOS 7.1/Windows 9x qualification remain open |
| Multiple primary/extended partitions | First supported primary partition only | EBR traversal, overflow/loop guards, independent units and partition isolation |
| Removable reserved letters / identity | Limited | Empty-media boot, replacement media with changed partitioning, stable letters and stale-cache rejection |
| BIOS-owned devices | GET DISK INFO filtering and unsupported-manager fallback, tested through INIT | Actual Adaptec hardware and accurate motherboard/USB BIOS mappings in managers remain unqualified; see [ownership details](block-ownership.md) |
| Spin-up and options | No /ID=, /NOSPINUP or /PAUSE compatibility yet | Manager/target selection, retry/error behavior and deterministic option tests |
| Floptical and other sector sizes | Generic 512-byte path only | Device profiles, logical/physical sector translation and separately qualified formatting |
| Private 7-byte ABI | Not implemented | Exact fields and behavior verified with callers; never expose unchecked internal state |

The two core drivers intentionally share implementation and tests. ZIP and
LS-120 ownership stays in ASPIFDD; implementing ASPIDISK-compatible disk
services must not make ASPIDSK claim those same targets.

## MKELS120 behavior

- Talks to `SCSIMGR$`, `ATAPIMGR`, `ATAPIMGR98` or `ASPIMGR98`: the MKE
  ATAPI manager or any ASPI manager (AHCIASPI works the same way).
- One unit per LS-120 drive; the media type (120 MB UHD, 1.44 MB HD, 720 KB
  DD, 1.25 MB NEC, 640 KB) is sensed and the BPB built from it.
- Media-dependent formatting paths through generic IOCTL 42h. The kit's
  `UHDDATA.BIN`, `HDDATA.BIN` and `DDDATA.BIN` are boot-sector/BPB templates,
  **not** hardware FORMAT UNIT parameter descriptors. The separate Windows
  formatter and its INI profiles are not proof of DOS formatting coverage.

## To do in ASPIDSK and ASPIFDD

1. Hardware write-protection sensing (MODE SENSE) separately from DOS
   software access flags 47h/67h. The original ASPIDISK getter does not itself
   probe hardware write protection.
2. Extend generic IOCTL beyond implemented 60h/66h: 40h, 46h, 67h/47h,
   61h/41h, 62h; extend the matching query only as operations are implemented;
   17h/18h. See [current block IOCTL behavior](block-ioctl.md).
3. ASPIFDD: 42h format with FORMAT UNIT, 68h media type, eject/lock, the
   LS-120 media types (sensed with READ FORMAT CAPACITIES).
4. ASPIDSK: all partitions (extended partitions), remaining FAT32/category-48
   compatibility and MS-DOS 7.1 qualification, reserved letters for removable disks, skip
   disks handled by INT 13h, spin-up, `/ID=`.
5. Sector sizes other than 512 (MO media with 2048-byte sectors).

## Iomega GUEST.EXE

The compatibility goal is to implement GUEST's ZIP-specific device functions
**inside ASPIFDD**, alongside the MKELS120/LS-120 functions. This is not a
separate GUEST clone or second ZIP block driver. The runtime loader discussed
below is only an optional loading mechanism; it does not replace media,
eject/lock, formatting or reference-verified ZIP-specific device behavior in
ASPIFDD itself. Version 0.1 does not yet claim that functional coverage.

Iomega `GUEST.EXE` 6.0 (zip100 / Iomega DOS driver package, SHA-256
`8ca1ca07ceb37372b23175e934d6a95d30814b322ba2510ef552090320e8228e`) is the
"portable" Zip/Jaz driver: a program started at the DOS prompt or from
`AUTOEXEC.BAT`, not a `CONFIG.SYS` driver.

- It stays resident (INT 21h AX=3100h) and adds drive letters while DOS is
  running: it takes the List of Lists (INT 21h AH=52h), builds Drive
  Parameter Blocks from the BPB of the disk (INT 21h AH=53h) and links them
  and the Current Directory Structures of free letters up to `LASTDRIVE`.
  Option `LETTER=x` picks the first letter, `QUIET` hides the messages.
- Without an ASPI manager it loads one itself: `GUEST.INI` lists the
  Iomega managers to try in turn (`ASPIIDE.SYS`, `ASPIATAP.SYS`,
  `ASPIPPM1/2.SYS` for the parallel port Zip with `NIBBLE.ILM`,
  `ASPI8DOS.SYS`, `ADVASPI.SYS`, `ASPIPC16.SYS`, `ASPI1616.SYS`);
  `SCAN=ON` first looks for a manager already loaded (`SCSIMGR$`).
- It takes only Iomega drives (INQUIRY vendor `IOMEGA`: Zip, Jaz,
  Bernoulli), in SCSI ID order, and refuses to run under Windows and twice
  (`SCSI_TSR` signature).
- A drive already served by a BIOS (adapter or board) gets two letters;
  the help tells the user to reboot.  Removability is then lost.

For OpenASPI this suggests a later **runtime mode for ASPIFDD**: load the
driver from the command line (a small loader that runs the INIT of
`ASPIFDD.SYS` and links its units into the DPB and CDS chains), for a USB or
parallel Zip attached after boot, as EUSBASPI already handles hot plugging.
The managers stay separate programs; OpenASPI does not load them itself.

The detailed [ZIP/LS-120 reference investigation](aspifdd-reference.md)
separates GUEST's resident device operations, private control path and no-op
handlers from the loader, and inventories the kit's companion Windows files.
