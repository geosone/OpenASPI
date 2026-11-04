# BIOS/DOS ownership during block-driver installation

ASPIDSK and ASPIFDD issue ASPI `SC_GET_DISK_INFO` (`06h`) for each matching
device, after INQUIRY/model selection and before TEST UNIT READY, volume
reads or unit allocation. The request carries the actual adapter, target
and LUN. No media command is sent to a rejected candidate.

The returned drive-ownership byte is an enumeration, not a bitmask:

| Completed result | Installation behavior |
| --- | --- |
| `00h`, no INT 13h mapping | Continue normal device installation |
| `01h`, INT 13h and claimed by DOS | ASPIDSK: skip; report the adapter:target:LUN. ASPIFDD: take the DOS letter over, see below |
| `02h`, INT 13h accessible but not claimed by DOS | Continue normal installation |
| Other value or success without writing the output | Skip; report a failed ownership query |

An explicit `SS_INVALID_CMD` (`80h`) permits the legacy scan to continue,
with one warning per driver load that BIOS ownership is unknown. The query
is still issued for subsequent candidates; an unsupported reply on one
adapter must not disable valid ownership reports from another adapter.
Other completion errors, including invalid adapter and missing device, skip
that candidate. There is no fallback based on matching capacity or geometry.
Requests and unused fields are cleared, with a sentinel in the ownership
output to catch incomplete manager implementations. Pending requests retain
the shared ASPI completion/wait behavior.

The field layout agrees with the DOS managers in the sibling AHCIASPI and
EUSBASPI trees (`src/aspi.inc`, command-06h handlers). The ownership enum is
also documented by Adaptec in [ASPI for Win32 Technical Reference,
SC_GET_DISK_INFO, pp. 22–23](https://www.zianet.com/jgray/dat/files/aspi32.pdf).
This implementation uses the DOS ASPI entry point and DOS SRB layout; it
does not import a Windows transport or vendor code.

## ASPIFDD: taking over the BIOS drive's letter

A BIOS may map a removable drive itself: ReBIOS's SeaBIOS boots an ATAPI
LS-120 as floppy A: or a ZIP as hard disk 80h. AHCIASPI finds that mapping
through EDD and reports `01h` with the BIOS drive in `SRB_Int13DriveInfo`.
ASPIFDD then takes over the letter DOS already has, so there is one letter
and it goes through ASPI (ASPIFMT, ASPICTL, raw sessions, the faster
transfer):

- DOS 4 or later only (the DPB layout).
- Floppy drive 00h/01h: the letter of the built-in driver's unit 00h/01h.
- Hard disk 80h+: the built-in driver's drive data tables (INT 2Fh
  AX=0800h/0803h, MS-DOS 4+) name the letter. The volume ASPIFDD loads must
  start where the table's hidden-sector count says.
- The unit is kept at the top of ASPIFDD's unit table and not reported to
  DOS. Its DPB is pointed at a second header of ASPIFDD (same strategy and
  interrupt) with the access flag set, so DOS rebuilds it on the next access;
  the first MEDIA CHECK reports a change.
- If every unit was taken over, ASPIFDD stays resident with its header
  turned into a character device, since DOS drops a block driver without
  units.

INIT prints `X: (BIOS drive taken over)`. If no such letter exists (another
DOS, no drive data tables, a volume start that does not match), the device
is skipped as before.

A kernel that sends generic IOCTL category `80h` of a block device to no
driver (MS-DOS 7.1 fails it with error 1) cannot carry the raw-media
requests. The DOS tools (`common/dos/raw_client.c`) then pass the same request
to the drive's driver directly, through the DPB's header and unit.

## Limits of the manager report

This avoids duplicate letters only when the manager reports DOS ownership
accurately. AHCIASPI identifies BIOS mappings through EDD (device path or
IDE parameter table, for ATA hard disks also size or geometry); EUSBASPI
returns `00h` and does not identify USB-boot BIOS mappings, so such a
mapping can still coexist with an OpenASPI letter. Unsupported
managers likewise cannot establish exclusive ownership. SUBST aliases,
later DOS drivers and Windows native-storage handover remain separate work.
Raw-copy sessions do not become universal physical-device locks through
this installation-time check.

## Verification

`bash tests/dos_block_ownership.sh` runs both drivers' real strategy,
interrupt, INIT and enumeration code with a memory-only ASPI manager.
Eleven scenarios cover all defined ownership results, explicit unsupported
commands, general errors, invalid adapters, missing devices, malformed
output, mixed claimed/unclaimed units and mixed supporting/unsupported
manager replies. Adapter 12, target 31 and
LUN 1 exercise address propagation and decimal diagnostics. Excluded units
must receive neither TEST UNIT READY nor volume reads; accepted units must
have the expected independent addresses, BPBs and DOS unit count. The
unsupported-command warning must appear once per driver, not per device.

The fixture does not load or contact a real manager and has no host disk
backend. `make dos-disk-smoke` includes it alongside the existing disposable
EUSBASPI image tests. Native LS-120/AHCIASPI testing remains separate.
