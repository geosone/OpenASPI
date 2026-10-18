# Windows 9x storage and ASPI architecture

This document records the planned Windows 95/98/98SE/ME architecture.  It is
separate from the DOS driver suite: the DOS drivers remain clients of a DOS
ASPI manager, while Windows uses IOS, the SCSI port manager, miniports and an
optional ASPI application interface.

## Adaptec reference model

Adaptec's Windows 95/98 drivers did not contain one hardware driver for every
disk, CD-ROM, removable drive or tape unit.  An AIC-78xx adapter used one
hardware-specific miniport, `AIC78XX.MPD`, below the Microsoft SCSI and IOS
layers.  Adaptec documented the same miniport for a family of AHA-29xx and
AIC-78xx adapters:

- <https://storage.microsemi.com/en-us/support/scsi/2930/aha-2930cu/install_sw/7800_fms_for_98.htm>
- <https://techshelps.github.io/MSDN/DNWIN95/HTML/S6564.HTM>

The native Windows path was conceptually:

```text
VFAT / CDFS / Windows shell
             |
   DISKTSD.VXD / CDTSD.VXD and other type-specific layers
             |
        SCSIPORT.PDR
             |
         AIC78XX.MPD
             |
       Adaptec controller
```

`SCSIPORT.PDR` supplied the common SCSI port services.  The miniport owned the
adapter and implemented adapter discovery, initialization, interrupt handling,
request start/completion and bus reset.  Windows supplied the upper disk and
CD-ROM behavior, filesystems, drive letters and shell operations.

## Open source implementation references

ReactOS contains an open `scsiport.sys`-compatible NT storage port in
`drivers/storage/port/scsiport`. Microsoft publishes the StorAHCI Storport
miniport in its Windows Driver Samples. Both are valuable implementation
references for SRB handling, DMA, interrupts, timeouts and AHCI recovery.

They are not drop-in Windows 9x components. ReactOS targets the NT kernel
driver contract, while Microsoft's sample targets the newer Storport API.
Windows 9x uses IOS, `SCSIPORT.PDR` and `.MPD` miniports with different loading
and service interfaces. OpenASPI may reuse algorithms and structure, but the
9x glue must be implemented against the 9x DDK contracts and tested with the
original vendor `.MPD` binaries.

References:

- <https://github.com/reactos/reactos/tree/master/drivers/storage/port/scsiport>
- <https://github.com/microsoft/Windows-driver-samples/tree/main/storage/miniports/storahci>

ASPI was a second client of the same storage stack, not a layer between the
miniport and the Windows filesystems:

```text
16-bit or 32-bit ASPI application
             |
 WINASPI.DLL / WNASPI32.DLL
             |
          APIX.VXD
             |
 SCSI port/miniport and IOS devices
```

Consequently, native filesystem requests and ASPI requests reached the same
controller owner.  No second driver accessed the adapter concurrently.

## Proposed OpenASPI model

The preferred AHCI experiment is a SCSI miniport named `OAHCI.MPD`, rather
than beginning with a monolithic clone of R. Loew's `AHCI.PDR`.

```text
Windows native storage                 ASPI applications / OpenTape
          |                                        |
   Windows IOS/TSDs                      WINASPI.DLL/WNASPI32.DLL
          |                                        |
   Windows SCSIPORT.PDR <--------- APIX.VXD or OASPI.VXD
          |
       OAHCI.MPD
          |
       AHCI hardware
```

`OAHCI.MPD` will map Windows SCSI request blocks to AHCI operations:

- SCSI disk CDBs are translated to ATA commands and AHCI FIS structures;
- ATAPI CDBs are transported as AHCI ATAPI packets;
- each AHCI port is exposed as a target visible to the standard Windows
  type-specific drivers;
- DMA, interrupts, timeouts, recovery and controller ownership stay in one
  miniport;
- unsupported commands complete with accurate SCSI status and sense data.

This design should let Windows handle normal disks, CD/DVD devices and common
removable media.  ASPI remains useful for tape software, burning software,
scanners, diagnostics and raw device commands.  Real floppy-controller
semantics and device-specific formatting may still require a special adapter;
they must not be promised merely because a device can be enumerated through
ASPI.

Existing SCSI miniports do not register with an OpenASPI-private HBA ABI.
OpenASPI must interoperate through the standard Windows SCSI/IOS path so that
an installed Adaptec or other vendor miniport can remain the sole owner of its
controller.

## Compatibility with official vendor drivers

Binary and behavioral compatibility with the official Windows 9x storage
drivers is a hard requirement.  Keeping every original Microsoft or Adaptec
binary active forever is not.  The first implementation preserves the
installed files to establish a known-good baseline; later free OpenASPI
components may replace them after they pass the same compatibility tests.

An unchanged Adaptec `AIC78XX.MPD`, BusLogic miniport or other official `.MPD`
must continue to bind to `SCSIPORT.PDR` or to a future compatible OpenASPI port
manager without being rebuilt.  OpenASPI's ASPI frontend likewise implements
the published `WINASPI.DLL` and `WNASPI32.DLL` application ABI so existing
ASPI programs do not need modification.

`OAHCI.MPD` is an additional standard miniport and does not change the contract
used by official miniports.  A future free AIC-78xx miniport may optionally
replace `AIC78XX.MPD`, but only one of them may own a particular controller.
That optional hardware replacement is independent of the common OpenASPI
runtime.

The compatibility target is:

```text
                         Windows IOS / SCSI port
                            /              \
              official AIC78XX.MPD       OAHCI.MPD
                       |                      |
              Adaptec controller        AHCI controller
                            \              /
                     one ASPI-visible device set
```

The following are release acceptance criteria:

- original miniport packages remain usable and require no source changes;
- unchanged official `.MPD` binaries load through the selected compatible port
  manager;
- native disk and CD access behind an official miniport works before and after
  installing the OpenASPI frontend;
- ASPI clients can enumerate both official-miniport and OpenASPI-miniport
  devices;
- an AHCI controller and an Adaptec controller can coexist without duplicate
  claims or host-adapter-number collisions;
- the installer backs up displaced components and uninstall restores the
  previously selected stack without disturbing native Windows storage.

## Which ASPI files OpenASPI must provide

Windows 95 and Windows 98 installations commonly provide the classic ASPI
runtime (`WINASPI.DLL`, `WNASPI32.DLL` and `APIX.VXD`).  The local original
Windows 98 SE medium also contains these files together with `SCSIPORT.PDR`,
`DISKTSD.VXD`, `CDTSD.VXD` and `AIC78XX.MPD`.  Presence and version must still
be detected at installation time; the design must not assume that every 9x/ME
installation has an intact compatible ASPI runtime.

The implementation is therefore staged:

1. Bring up `OAHCI.MPD` with the Windows-supplied `SCSIPORT.PDR` and
   type-specific drivers.
2. Test ASPI access through an already installed compatible Windows ASPI
   runtime.  OpenASPI does not redistribute those Microsoft or Adaptec
   binaries.
3. Implement the free OpenASPI runtime for a complete, reproducible install:
   `OASPI.VXD`, `WINASPI.DLL` and `WNASPI32.DLL`.
4. Add enumeration support equivalent to `ASPIENUM.VXD` only if compatibility
   testing shows that clients require it.

The components have distinct purposes:

| Component | Purpose | Initial requirement |
| --- | --- | --- |
| `OAHCI.MPD` | AHCI hardware miniport for Windows SCSI port | Required |
| `SCSIPORT.PDR` and Windows TSDs | Native Windows storage stack | Use installed Windows files |
| `APIX.VXD` | Existing Windows kernel ASPI bridge | May be used for bring-up |
| `OASPI.VXD` | Free OpenASPI kernel bridge/replacement | Required for standalone release |
| `WINASPI.DLL` | 16-bit Windows ASPI API | Required for Win16 compatibility |
| `WNASPI32.DLL` | 32-bit Windows ASPI API | Required for Win32 clients/OpenTape |
| `ASPIENUM.VXD` equivalent | Optional ASPI/PnP enumeration compatibility | Defer until proven necessary |

Using the installed runtime is a compatibility mode, not the final ownership
model.  OpenASPI packages must not copy proprietary Windows or Adaptec files.
The installer will probe the installed components and versions, preserve a
recoverable copy of a working system stack, and install OpenASPI replacements
only when the user selects them or no suitable runtime exists.

The shared GDI package now uses one dual-mode `INSTALL.EXE`: its MZ part is the
DOS installer and its NE part is the native Win16 frontend, built directly on
the Windows 3.1 API without MFC. Both read the same `INSTALL.INI`, and the
Windows frontend distinguishes Windows 3.x from 9x/ME.

Registry changes will use GDI's package-defined `[Registry]` transaction
format. Its strict parser, family validation, typed-data conversion and
lossless old-value journal records are implemented and host-tested. GDI also
waits for an explicit result from the DOS file/configuration transaction,
which provides the required ordering. The remaining mutation stage will use
separate Windows 3.1 and Windows 9x backends and must flush each journal record
before changing a value; OpenASPI will add package entries only after those
backends can roll back failures and restore values during uninstall.

The first replacement milestone covers the paired ASPI bridge and DLLs.  A
compatible replacement for `SCSIPORT.PDR`, the Windows type-specific drivers
or an official hardware miniport is allowed as a later milestone; none is
required to deliver the OpenASPI frontend or `OAHCI.MPD`.  Until a replacement
passes the official-miniport and application compatibility tests, the
installer defaults to the working system component.

## One-owner rule

One controller has exactly one hardware owner:

- an AHCI controller supported by OpenASPI is owned by `OAHCI.MPD`;
- an Adaptec controller is owned by either its official miniport or one selected
  compatible replacement, never both;
- a USB mass-storage device remains owned by the installed USB storage stack.

Native Windows and ASPI frontends submit requests through that owner.  An ASPI
component must never bypass an active miniport and touch the same controller
directly.

