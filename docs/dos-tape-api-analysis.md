# DOS and Win3.x tape-interface investigation

This investigation supplies input to the [native OpenTape API](native-tape-api.md).
The goal is a common operation/capability model, not binary clones of each
vendor API. All work was static; the historical modules were not executed.
Downloads remain under ignored `build/reference/`.

## DOS interfaces

| Input | Observed interface | Useful native-API lesson |
|---|---|---|
| `COLORADO/POWER401.ZIP`: `ASPI2DOS.SYS`, `ASPI4DOS.SYS`, `ASPIEDOS.SYS` | Raw DOS character-device headers name `SCSIMGR$`. The inspected `ASPI4DOS` strategy/interrupt entries are at `0014h`/`001Fh`. Request command `03h` reaches `00BEh`, which returns a far entry pointer `CS:04D4h` in the caller's IOCTL buffer. | A direct-ASPI backend uses a manager and SRBs; it is not a tape-specific application API. Reuse existing ASPI discovery rather than invent another controller-access mechanism. |
| `OTHER/ASPITAR.ZIP` | GNU tar ASPI source uses direct manager calls, `/dev/ct` and `/dev/nrct`, record I/O and tape-control operations. Bundled `COPYING` is GPLv1. | Source-reuse candidate for the direct-ASPI adapter; keep the common native interface above it. Its private tar device names and record-size assumptions do not become our API. |
| `OTHER/4MMDRV.ZIP`: `IBG_DATI.DRV` | A raw Sytos module, not a DOS `CONFIG.SYS` character-device image. A 42-entry word-offset table occupies file `0100h..0153h`. Entry `0158h` stores a supplied far pointer at `0154h`. Other functions make indirect far calls through that host callback structure. | Separating operations from host allocation/progress/I/O services is useful. The old callback layout is private; do not advertise direct OpenTape compatibility without a loader and a verified record contract. |
| Same Sytos module, hardware path | Initialization at `0892h` probes BIOS `INT 15h` with `C000h`/`C400h`. Helpers at `10B8h`, `10C1h`, `115Bh` and `1168h` use `INT 4Bh`, AH=`80h`, subfunctions 0..3, with adapter/device fields. | A private module need not use ASPI. Its transport must be identified separately; a common API cannot make this an ASPI target merely by translating a function number. |
| `COLORADO/JUMBOSYT.ZIP` | `.SYS` files have NE executable headers, and the documentation describes OS/2 Sytos drivers for Jumbo controllers. | A `.SYS` suffix does not prove a DOS character-device ABI. Keep OS/2 module services separate from DOS bindings. |
| `MOUNTAIN/525TD.ZIP`, Colorado Jumbo utilities | Backup programs, format/configuration data, schedulers and catalogue tools are present, but no universal DOS tape API was established from the package lists. | Reuse workflow/capability ideas where useful; do not label command-line backup programs as resident device APIs. |

Hash-pinned DOS Ghidra inputs:

| File | SHA-256 | Exported functions |
|---|---|---:|
| `IBG_DATI.DRV` | `5ca618abec3e714971a4c6677c1041586bbee355c3a3860a934e3827f491afbf` | 99 |
| `ASPI4DOS.SYS` | `161de4d65082e4a5c8dc8f7b2ba75463c4e36d9f61739b3c715ac05bdd05fde9` | 72 |

`tools/reference/InspectDosTapeApi.java` validates these hashes, seeds the
Sytos callback table or DOS strategy/interrupt entries and exports both
decompilation and assembly. Import using `BinaryLoader`, processor
`x86:LE:16:Real Mode`, base `0000:0000`, and a report path under `build/`.
The local reports are `build/reference-ghidra/nt-tape/sytos-dos.txt` and
`aspi4dos.txt`. Counts include helpers; inferred register arguments and far
pointer types need assembly review. The Sytos callback names/parameter records
have not been fully recovered, and no claim is made about its complete
underlying BIOS/controller protocol.

## Colorado CMSDTAPE.386

`POWER401.ZIP:CMSDTAPE.386` is an LE Windows 3.10 VxD, 5,302 bytes, SHA-256:
`c3752c69d7c97094ce2ec39cf3aa56f148723f1756695f3782a9d03decd6bd92`.
It contains the Win386 CMSDTAPE identification string. Its LE objects and
x86 instructions were inspected separately from the DOS/NT Ghidra imports.

The first object has virtual base 0, size `02D6h`, file data at `0400h`;
the second has base `1000h`, virtual size `0080h`, data at `1400h`. The DDB
at first-object offset `01F0h` contains device ID `299Bh`, SDK `030Ah`,
control entry `0036h`, and the same V86 and protected-mode API entry `0049h`.
Offsets below are relative to that loaded image, not file offsets.

The API dispatches on the client AX saved in the VMM client register frame:

| AX | Observed action | Qualification |
|---:|---|---|
| `0000h` | Returns signature/version-like `0905h`, feature bits and a VM ownership indicator. | The meaning of each returned bit must be established with the caller; do not equate this literal with a public tape API version. |
| `0100h` | Claims an unowned VM-associated resource; reports failure through the client's carry flag if already owned. | Ownership mediation, not a tape READ/WRITE command. |
| `0200h` | Clears the stored owner. | Do not copy unchecked release behavior into the native API. |
| `0300h` | Calls the PIT-based delay routine at `0150h`, using client DX. | Timing support; units and caller expectations remain to qualify. |
| `0400h` | Maps client ES:EDI using VMM Map_Flat, reserves a free slot, and copies a four-dword buffer descriptor to the client. | Buffer pooling/mapping; not four dwords of tape record payload. |
| `0500h` | Maps the client descriptor and releases its referenced slot. | A candidate ownership/buffer-lifetime pattern, requiring pointer validation in our implementation. |

Other code forwards interrupt activity and filters direct I/O against the
stored VM owner. Initialization at `1000h` invokes VMM/virtual-interrupt
services and allocates up to five buffers. These are resource-mediation
primitives, not an established generic tape-command/streaming interface.
The DDB and client-register interpretation is cross-checked against the
local Open386MAX `INC/VMM.INC`; inline VxD service operands must not be
mistaken for ordinary instructions after `INT 20h`.

For our Windows 3.x provider this is useful evidence for shared-buffer
allocation, protected/V86 mapping and exclusive resource ownership. The
OpenTape API still needs common record, movement, capability and result
semantics above that mediator. No historical binary has been connected to
OpenTape and no Win3.x native backend is claimed complete here.

## Follow-up

- [ ] Map the useful operation families into the native API without depending
  on a Sytos caller or Colorado's private VxD function numbers.
- [ ] Qualify buffer lifetime, ownership and completion across DOS/Win16
  boundaries; define explicit release on close/failure without abandoning
  hardware-owned transfers.
- [ ] Keep ASPI, private BIOS/controller transports and OS-specific mediators
  as backend concerns. The archive engine consumes common capabilities and
  results, not vendor parameter blocks or raw NT statuses.
