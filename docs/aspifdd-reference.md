# ASPIFDD: ZIP and LS-120 reference investigation

Static investigation of the local vendor packages, 2026-10-23. This records
compatibility observations, not copied vendor implementations or a claim of
complete compatibility. No original utility was run against a drive, and no
media were written. See [reference material](reference-material.md) for the
original archive locations and redistribution restrictions.

## Inputs and method

| Input | Examination |
|---|---|
| `zip100.rar` | Extracted GUEST, help, INI, ASPI managers and ILM files; resident GUEST code examined with Ghidra and ndisasm |
| `zipdrivers.rar` | Listed bundled packages; extracted `iodrv-dos-x86-10.exe` and its DOS payload |
| `LS-120_IDE_KIT.zip` | Extracted all 21 files; SYS command handlers, documentation, format profiles, boot sectors and Windows DLL exports examined |
| `zipdrivers100-250-95-98-parallel.zip` | Listed nested Windows driver payload; not a completed disassembly of those drivers |
| `Zip_100_Parallel_Port-xp-2k.zip` | Extracted Windows installer wrappers; internal Iomega Tools functionality not established |
| `iomega_usb_firewire_dos_driver_boot_disk.zip` | Truncated archive; recovered selected complete entries with 7-Zip, including GUEST 8.5 and boot configuration |
| `Ghost 2003/guest.exe` | Independent local copy, byte-identical to recovered GUEST 8.5 |

The two DOS packages contain an identical `GUEST.EXE` 6.0:

```text
GUEST.EXE
8ca1ca07ceb37372b23175e934d6a95d30814b322ba2510ef552090320e8228e
MKELS120.SYS
487e5391a945ad92f4366e9283f2607b79dfd8e18a70c18fc20a047e56215141
GUEST.EXE 8.5 (both local copies)
8634b6ffccb098fd124c7d7c4e1c5a94df8c2c4c10f0fc50b7cbec1e03e71646
```

Ghidra 12.1.4 DEV was used locally with `x86:LE:16:Real Mode`.
MKELS120 was imported as a raw binary at `0000:0000`; GUEST used the MZ
loader at `1000:0000`. SYS offsets below are file offsets. GUEST offsets are
load-image offsets: add `0200h` to find the corresponding file position in
this particular EXE. Windows DLL addresses below are RVAs, not file offsets.
Selected control flow was checked with ndisasm/objdump; decompiler types,
segment assumptions and reconstructed register arguments are not an ABI.

The installed IDA Free refused `-B` with "does not support the batch mode".
No IDA analysis or cloud decompilation was completed.

## LS-120 DOS interface

MKELS120's strategy/interrupt entries are `07D0h`/`07DDh`. Its DOS command
table starts at `1929h`; the first word is **2817h**, the INIT handler.
`1728h` is not that entry point (little-endian decoding matters).

Generic IOCTL command `13h`, category `08h`, dispatches at `1B96h`:

| Minor | Handler | Observed purpose |
|---|---|---|
| `40h` / `60h` | `1C2Dh` / `1CE9h` | Set / get device parameters |
| `41h` / `61h` | `1DA8h` | Write / read track; selects WRITE(10) / READ(10) |
| `42h` | `1E93h` | Format-related processing, including media-dependent paths and a query branch |
| `62h` | `1FEDh` | Verify track |
| `46h` / `66h` | `20A6h` / `2139h` | Set / get media ID |
| `67h` | `217Dh` | Get access flag |
| `68h` | `21D2h` | Sense media type |

Request `19h` reaches `2219h`, but its advertised support is not identical
to dispatch: it accepts `40h,42h,46h,60h,62h,66h,67h,68h` and rejects
`41h/61h`, even though those have executable handlers. OpenASPI should test
and report its own real capabilities consistently, not reproduce that
inconsistency without a demonstrated compatibility need.

The supplied `README.TXT` explicitly says MKELS120.SYS does **not** support
DOS `DISKCOPY`, and describes it for DOS/Windows 3.1/WFW 3.11, not the native
Windows 95 path. Later Windows VxD changelog entries discuss DOS-box FORMAT/
DISKCOPY fixes; they do not establish SYS support for those operations.

`/Q` suppresses the initialization Abort/Retry interaction. `/F:IOS.INI`
records a driver name for Windows 95/98 handover; this is not a native
Windows storage driver. The historical readme mentions `LSFMT.EXE`, but
that program is **absent** from this kit.

## GUEST: actual services versus loading

`GUESTHLP.TXT` documents loading at a DOS prompt or through `AUTOEXEC.BAT`,
loading before Windows 3.1 starts, `LETTER=`, `LASTDRIVE`, and manager
selection through `GUEST.INI`. The INI enables scanning for an existing
manager and lists IDE/ATAPI, parallel and SCSI managers. These are transport
backends, not separate copies of ZIP media handling.

The resident generic IOCTL handler at image `08A5h` accepts category `08h`:

| Minor | Observed behavior |
|---|---|
| `41h` / `61h` | Track write / read via `0C3Dh` |
| `46h` / `66h` | Media-ID processing via `16F4h` |
| `60h` | Device parameters with media/BPB refresh |
| `48h` | Lock/unlock/status subfunctions, with an internal lock count and device-policy checks |
| `49h` | Calls START STOP UNIT helper with control byte zero; this alone does **not** prove mechanical eject |
| `40h`, `42h`, `62h` | Success paths without physical set-parameters/format/verify work in this handler; `42h` changes cached media state |

Helper `1510h` constructs PREVENT/ALLOW (`1Eh`); `0BD0h` constructs START
STOP UNIT (`1Bh`). The latter's CDB byte 4 comes from its caller: distinguish
stop, start and eject rather than assuming every call means eject.
Sense processing at `11E6h` distinguishes media-change/reset unit attention
and write-protection-related errors. The normal write path at `055Dh`
contains a WRITE AND VERIFY fallback; both the fallback and transferred
sector/address accounting need explicit regression coverage in OpenASPI.

There is also a private control handler at `215Bh`: it checks a 24-byte
request payload and a leading word `494Dh` (bytes `4Dh,49h`). Subcommand zero
calls a CDB-forwarding helper at `0D5Dh`, which constructs 6/10/12-byte
commands according to opcode group and has special transfer-length handling.
Other branches handle locks and expose/copy internal state. The DOS route
and observed fields are recorded below; full error semantics and the safe
public subset still need tracing before claiming Iomega Tools binary
compatibility. Do not turn internal pointers/state-copy branches into an
OpenASPI public API.

### Private packet route and observed layout

The resident dispatcher at image `25BCh` reads the DOS request command at
`+02h` and calls the near-function table at `41D9h` (`26A2h`). Table entries
for **both `03h` (IOCTL input) and `0Ch` (IOCTL output)** point to `215Bh`;
the `13h` generic-IOCTL entry instead points to `08A5h`. Thus the private
packet is not a category/minor combination in the generic-IOCTL path.

Handler `215Bh` requires DOS request count `+12h = 0018h`, then takes the
far pointer at request `+0Eh` as the private packet. Wrong count/signature
returns `8003h` before subcommand dispatch. Observed packet fields:

| Packet offset | Size | Observed use |
|---|---|---|
| `00h` | word | Required `494Dh`, bytes `4Dh 49h` (`MI`) |
| `02h` | word | Meaning not established |
| `04h` | byte | Private subcommand |
| `05h` | byte | Transfer flags for subcommand zero; nested selector for `0Ah` |
| `06h` | far pointer | CDB address for subcommand zero |
| `0Ah` | far pointer | Data buffer / state-copy destination or source, depending on subcommand |
| `0Eh` | word | Separate returned internal/transport status, initially cleared |
| `10h..17h` | eight bytes | Meaning not established; do not invent public fields |

Subcommand `00h` forwards a CDB; `01h` copies two internal 14-byte header
prefixes to the buffer (28 bytes total); `06h/07h` manipulate a persistent
lock policy separately from the generic-IOCTL lock counter. `04h/05h` and
`0Dh/0Eh` copy whole internal structures out/in. These are observations of
this binary, not stable structures OpenASPI should expose or blindly accept.
Subcommand `0Ah` has another selector and changes lock/status state; its
complete contract is still unverified.

The CDB helper accepts opcode groups 0, 1, 5 and 7, mapping them to 6, 10,
12 and 10 bytes respectively; other groups return `8003h`. Group 7 is a
particular vendor-command assumption, not general modern SCSI passthrough.
Transfer count comes from CDB byte 4 (6-byte commands), bytes 7/8 (10-byte)
or bytes 9/10 (12-byte), with additional opcode-specific cases. Do not treat
this as a universal CDB transfer-length decoder. The helper also overwrites
the upper three bits of CDB byte 1 with the selected LUN.

Flag `04h` selects no data; bit 1 selects the output rather than input
direction in the ASPI bridge. Exact flag values `01h` and `03h` additionally
use the device's block size as a transfer-count multiplier. This reinforces
the need to distinguish byte counts from block counts. Packet status `+0Eh`
is separate from the handler's AX/DOS result; a caller cannot inspect only
one and assume all failure information has been consumed.

Reproduce the version-pinned byte checks and selected disassembly without
executing the original program:

```sh
bash tools/reference/inspect_guest.sh /path/to/extracted/GUEST.EXE
```

The script requires `ndisasm` and common shell utilities, selects separate
checks for the two documented binary hashes, rejects other versions, and
writes only to stdout/stderr. Keep any captured vendor
disassembly outside source control. This is a static reference check, not
an ASPIFDD runtime or hardware compatibility test.

### GUEST 8.5 is not the same private ABI

The recovered bootdisk EXE identifies itself as version 8.5. Ghidra's MZ
loader and ndisasm show materially different DOS routing, not just relocated
6.0 functions. Both binaries have a `0200h`-byte MZ header, so the same
file-offset conversion applies, but their function/table offsets differ.

| Interface evidence | GUEST 6.0 | GUEST 8.5 |
|---|---|---|
| Near handler table, image offset | `41D9h` | `1286h` |
| DOS `03h` / `0Ch` handlers | `215Bh`: private MI packet | `319Fh`: returns `8003h` unconditionally |
| Generic IOCTL `13h` handler | `08A5h` | `1C8Ah` |
| CDB-forwarding helper present | `0D5Dh` | `21EFh` |

In 8.5, dispatcher `3280h` selects a DOS-command case via the table at
`3427h`; the normal case at `333Eh` calls `[1286h + command*2]` at `335Ch`.
The `03h` and `0Ch` entries both resolve to `319Fh`, a short function that
returns `8003h`. Therefore finding a similar CDB helper in 8.5 **does not**
establish that the old private packet is callable through DOS IOCTL there.
The generic handler's minor table at `2056h` lists
`40h,41h,42h,46h,48h,49h,60h,61h,62h,66h`. The common-operation comparison
below distinguishes physical work from success-only paths.

For ASPIFDD, preserve the validated common device operations in one driver,
but do not call the 6.0 private layout a universal GUEST API. Any legacy
Iomega Tools compatibility must identify which version/interface the caller
actually needs. Our own media/format utility API should have explicit
version, length and capability fields rather than vendor internal layouts.

The bootdisk archive itself remains damaged (`Unexpected end of archive`);
do not describe it as verified or boot it as a qualification environment.
The recovered GUEST file is corroborated by the byte-identical Ghost copy.
Its AUTOEXEC loads GUEST separately from its USB/FireWire ASPI-manager
configuration, further illustrating the transport/device-service boundary.
The included historical BOOTLOG reports several load failures; it is not
evidence of a successful OpenASPI test.

### Common operations: logical state is not a hardware guarantee

The 8.5 generic-IOCTL dispatch table resolves as follows. Compare with the
6.0 handler described above:

| Minor | 8.5 branch | Cross-version observation |
|---|---|---|
| `60h` | `1CCCh` | Refreshes device/media/BPB information |
| `41h` / `61h` | `1EF1h` / `1EE8h` | Track write/read through CHS-to-LBA helper `210Bh` |
| `46h` / `66h` | `1F15h` / `1F10h` | Media-ID processing through `2D2Fh` |
| `48h` | `1F20h` | Lock, unlock and count query |
| `49h` | `203Fh` | START STOP UNIT with control byte zero, not an observed eject sequence |
| `40h`, `42h`, `62h` | `1F1Eh` / `1F0Eh` / `1F1Eh` | Return success without physical parameter-setting/format/verify work in those branches |

Minor `48h` reads a subfunction byte at parameter-block offset zero and
returns the count at offset one. Subfunctions 0/1/2 are lock/unlock/query.
The reference keeps a byte-sized count per device (`+47h` in 6.0's media
state, `+57h` in 8.5). Count zero on unlock may issue ALLOW; another internal
policy bit can suppress it. Both versions decrement then clamp using the
high bit, rather than providing a robust saturating counter for arbitrary
nesting. OpenASPI must not allow overflow/underflow to release an active lock.

More importantly, the hardware helper is best-effort:

- 6.0 helper `1510h` and 8.5 helper `2AF6h` attempt START STOP UNIT with
  start=1 (one retry if needed), then build PREVENT/ALLOW (`1Eh`).
- If PREVENT/ALLOW maps to `8003h` (unsupported), the helper changes the
  result to success and caches a per-device "do not try again" flag.
- Thus a successful GUEST lock/count operation does **not** establish that
  pressing the physical eject button is prevented. Software lock state and
  hardware-removal prevention need separate capabilities/status in our API.

The Media-ID handlers also expose a behavior not to reproduce. In 6.0,
`176Dh` calls the sector-write helper and `1773h` immediately clears AX. In
8.5, `2DB3h` calls the write helper, saves its return value, then `2DBBh`
clears AX; the alternate extended-BPB branch converges on the same success
path. Consequently write failure can be hidden from the caller. OpenASPI
must propagate that failure and must not update a successful-write cache
before the medium has accepted the write.

6.0's Media-ID handling recognizes the extended BPB signature `29h` at
boot-sector `26h` and copies 23 bytes starting at `27h` (serial, label,
filesystem-type text). 8.5 additionally checks the FAT32-style signature at
`42h` and copies from `43h`. This is a boot-sector metadata operation, not
proof of an entire format operation or directory-label synchronization.
FAT32 metadata recognition in the reference is not a claim of FAT32 support
in the current OpenASPI block core.

#### Required implementation tests

The combined ASPIFDD service can now use these concrete acceptance cases:

| Case | Required OpenASPI outcome |
|---|---|
| Two locks, one unlock | A lock remains; no physical ALLOW/eject |
| Last unlock succeeds/fails | Commit state only after the required operation succeeds; propagate failure |
| Unlock at zero / lock at counter limit | No wraparound, accidental ALLOW or silent loss of ownership |
| PREVENT unsupported | Report hardware prevention unavailable; do not label a software lock as hardware protection |
| Explicit eject while locked | Refuse; START/STOP support alone is insufficient evidence for eject capability |
| Media-ID write rejected / write-protected | Return the real error; never the reference's unconditional success |
| Media changes between metadata read and write | Reject stale operation; do not overwrite replacement media |
| Metadata write on partitioned ZIP | Preserve MBR, partition offset, unrelated BPB and filesystem structures |
| Physical format / verify absent | Capability query and execution both report unsupported, not a success-only shim |

These tests should first use the real OpenASPI resident code and a
memory-only ASPI callback, following `tests/block_fallback.asm`, before any
scratch-media tests. Vendor binaries/disassembly are compatibility evidence,
not source for an implementation.

Neither GUEST help nor these handlers establish complete ZIP password,
vendor write-protection, recovery or low-level-format semantics. Those remain
unverified, not implemented requirements checked off by finding a CDB path.

## LS-120 companion files and Windows boundary

`MKELSFMT.EXE` is a PE32 Windows GUI application, not a DOS formatter.
`MKEFMTEX.DLL` exports COM registration/class-factory functions and contains
context-menu/formatter-launch code and registry/ShellExecute imports. These
belong to the future Windows shell/utility frontend, not the DOS block core.
`MKELS120.VXD` is a separate LE Windows driver; its IOS integration has not
been fully reverse-engineered here.

`MKEDEVIO.DLL` has 24 named exports, but names overstate implemented behavior:
`EjectMedia` and `LoadMedia` share RVA `12F0h`, which only returns zero;
`GetDriveGeometry` and `ModeSelectScsi` share another such stub at `1300h`.
Their names are not evidence that those functions issue hardware commands.

`FMTDATA.INI` supplies these profiles:

| Profile | MediaType | Cylinders / heads / sectors | Bytes/sector | FAT sectors / root entries |
|---|---|---|---|---|
| DD, 720 KB | `11h` | 80 / 2 / 9 | 512 | 3 / 112 |
| HD, 1.44 MB | `24h` | 80 / 2 / 18 | 512 | 9 / 224 |
| UHD, 120 MB | `31h` | 963 / 8 / 32 | 512 | 241 / 512 |

`DDDATA.BIN`, `HDDATA.BIN` and `UHDDATA.BIN` are each 512-byte **boot-sector
templates with BPBs**, not physical FORMAT UNIT parameter descriptors. The
UHD template describes FAT16, 246528 sectors and four sectors per cluster;
DD/HD describe FAT12. Generate our own boot/FAT metadata; do not copy vendor
boot code or confuse writing a filesystem with physically formatting media.
Additional 640 KB/NEC compatibility mentioned in the readme is not completely
specified by these three default profiles.

The ZIP Windows package lists MPD/PDR/SYS/INF transport/storage components,
including PPA and USB paths. Merely listing these does not establish the
special operations of the separate Iomega Tools suite. The Windows installer
wrappers from the XP/2000 archive were not fully unpacked/analyzed.

The IomegaWare 4.02 wrapper identifies a VISE extraction layer (`ViseMain`,
`vise32ex.dll`, and an `ESIV` marker at file `11000h`). Its plaintext
installer metadata names `ToolApp.exe`, `IMGMENU.DLL`, `IMGPROP.DLL`,
`format.html`, `win_format.html` and `protect.html`. It also contains Drive
context-menu/property-sheet registration paths. These identify relevant
Windows utility/UI components for further extraction, **not** their actual
SCSI operations or proof of password support in DOS GUEST. Neither 7-Zip nor
cabextract unpacked the wrapper; the contained executables/help have not
yet been analyzed. Wrapper SHA-256:
`461d0104d503ce65a341cd97e2bfa3d8a8291602b86ed84de8d03435c1473cef`.

`PPA3.ZIP` from `zipdrivers.rar` contains just `ppa3.mpd` and `file_id.diz`;
it is not the missing DOS format/protection-tools package.

## Implementation consequences and remaining work

ASPIFDD remains **one combined ZIP/LS-120 device service**, sharing block
transport with ASPIDSK. No second GUEST block implementation is needed.
Runtime attachment is separate from device functions. Dedicated format and
media utilities should consume ASPIFDD's checked capabilities and controls;
Windows context-menu integration is a separate frontend to those services.

Next implementation work should start with tested device-parameter/media-ID
IOCTLs and accurate query reporting, then media sensing/protection and
reference-counted locking. Physical format and vendor-specific destructive
operations require separately verified device sequences and scratch-media
tests. Mechanical eject must not bypass locks or be inferred from a stub.

The implementation now provides read-only `08h/60h`, `08h/66h` and matching
query handlers in `common/dos/blkdrv.inc`, with separate installation-time
and current BPBs and a fresh boot-sector read for Media-ID. See [current behavior and tests](block-ioctl.md). The other
operations are tracked separately. Reference-counted `08h/48h` locking and
locked-aware `08h/49h` eject now have resident-code and QEMU integration
tests; see [media controls](media-control.md). [ASPIFMT](../tools/aspifmt/README.md)
now creates FAT filesystems with bad-cluster marking through a checked raw
session; [ASPIDD](../tools/aspidd/README.md) supplies copying and Rescue.
Conditional FAT32 uses extended parameter/Media-ID reads, tested on FreeDOS.
Media-ID writes now preserve boot-sector contents, verify written data and
update a validated FAT32 backup; failures propagate. See [block IOCTLs](block-ioctl.md).
Basic track read/write/verify is now implemented and tested; see
[addressing and scope](block-track.md). Physical formatting, variable track
tables and vendor protection remain missing work.
Still open: complete private GUEST packet semantics/caller compatibility,
original Iomega Tools payloads, ZIP vendor commands, detailed VxD handover,
and hardware behavior. Static analysis cannot replace those compatibility
tests.
