# ASPIDISK.SYS and MKELS120.SYS compatibility notes

Black-box and disassembly notes on the block drivers that `ASPIDSK.SYS` and
`ASPIFDD.SYS` replace, as a checklist.  No vendor code is used; the binaries
are not part of OpenASPI (see [reference material](reference-material.md)).
Both were examined with Ghidra 12.1 and ndisasm (raw load at 0000:0000, the
command table of the interrupt routine).

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
| 13h GENERIC IOCTL | yes | yes | **missing** |
| 17h/18h GET/SET LOGICAL DRIVE | yes | 17h only | **missing** |
| 19h IOCTL QUERY | yes | yes | **missing** |

### Generic IOCTL (13h)

Category 08h (disk); ASPIDISK also 48h (FAT32 disk, MS-DOS 7.1).

| Minor | Function | ASPIDISK | MKELS120 |
|---|---|---|---|
| 40h / 60h | set / get device parameters | yes | yes |
| 41h / 61h | write / read track | yes | yes |
| 42h / 62h | format / verify track | yes | yes |
| 46h / 66h | set / get media ID | yes | yes |
| 47h / 67h | set / get access flag | yes | 67h |
| 68h | sense media type | no | yes |

These carry `FORMAT`, `DISKCOPY`, `SYS`, `CHKDSK`/`SCANDISK` and the label
and serial number tools.  ASPIFDD needs all of them for LS-120 (MKELS120
formats 120 MB, 1.44 MB, 1.25 MB NEC and 720 KB media through them, with
640 KB disks reformatted to 720 KB); ASPIDSK at least 60h, 66h, 46h, 47h/67h
and 61h.

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

## MKELS120 behavior

- Talks to `SCSIMGR$`, `ATAPIMGR`, `ATAPIMGR98` or `ASPIMGR98`: the MKE
  ATAPI manager or any ASPI manager (AHCIASPI works the same way).
- One unit per LS-120 drive; the media type (120 MB UHD, 1.44 MB HD, 720 KB
  DD, 1.25 MB NEC, 640 KB) is sensed and the BPB built from it.
- Formatting through generic IOCTL 42h and the drive's FORMAT UNIT, with the
  format descriptors of the kit (`UHDDATA.BIN`, `HDDATA.BIN`, `DDDATA.BIN`).

## To do in ASPIDSK and ASPIFDD

1. Write protection known before writing (MODE SENSE), for the access
   flag of generic IOCTL 67h.
2. Generic IOCTL 13h with 60h/40h, 66h/46h, 67h/47h, 61h/41h, 62h; IOCTL
   query 19h; 17h/18h.
3. ASPIFDD: 42h format with FORMAT UNIT, 68h media type, eject/lock, the
   LS-120 media types (sensed with READ FORMAT CAPACITIES).
4. ASPIDSK: all partitions (extended partitions), FAT32 (category 48h, the
   extended BPB of MS-DOS 7.1), reserved letters for removable disks, skip
   disks handled by INT 13h, spin-up, `/ID=`.
5. Sector sizes other than 512 (MO media with 2048-byte sectors).

## Iomega GUEST.EXE

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
