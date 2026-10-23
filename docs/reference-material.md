# Local reference and compatibility material

These paths are development inputs on the current machine.  They are not
dependencies of a source release and their binaries must not be copied into
OpenASPI packages unless redistribution rights are independently established.

## Published programming references

- [Brian Sawert: The Programmer's Guide to SCSI](https://vtda.org/books/Computing/Hardware/SCSI/The_Programmers_Guide_To_SCSI.pdf):
  ASPI and SCSI reference; see [Windows integration notes](windows9x-storage.md#additional-aspi-implementation-references).
- [IBM OS/2 ASPI specification, EDM2 reprint](https://www.edm2.com/index.php/Advanced_SCSI_Programming_Interface_%28ASPI%29_OS/2_Specification):
  compare platform contracts; OS/2 layouts and entry points are not DOS or Win32 ABIs.

These documents are linked, not redistributed with installation media.

Tape-relevant locations in Sawert (printed book page / PDF page):

- MODE SENSE/SELECT and parameter headers: 39–41 / 60–62.
- Fixed sense, FILEMARK/EOM/ILI and ASC/ASCQ: 49–52 / 70–73.
- Completion callbacks for streaming devices: 62–63 / 83–84.
- Immediate REWIND and later readiness checks: 156 / 177.
- Windows tape class versus SCSI-port responsibilities: 165 / 186.
- The SCSI Snooper example limits tape actions to common commands: 243 / 264.
  It is not a complete tape implementation. Appendix B identifies SSC as the
  command-set reference for sequential devices.

For the implemented native record-limit query, the
[IBM LTO SCSI reference](https://www.ibm.com/support/pages/system/files/inline-files/%5BAPPROVED%5D%20LTO%20SCSI%20Reference%20GA32-0928-07%20%28EXTERNAL%29.pdf)
documents READ BLOCK LIMITS granularity. Device-specific documentation and
SSC remain necessary alongside the general programming book.

## Free ASPI managers

- `/home/mario/mars/ahciaspi`: AHCI/IDE ATAPI ASPI manager, ASPI constants,
  `ASPITEST`, emulator tests, and the Adaptec ASPI for DOS specification.
- `/home/mario/mars/eusbaspi`: USB mass-storage ASPI manager, including
  manager chaining, hotplug behavior, `ASPITEST`, and `USBSYNC`.

OpenASPI must be tested as a normal client of both managers and of historical
Adaptec-compatible managers. Source reuse should retain the selected code's
license and provenance; sibling trees remain read-only references during
these compatibility investigations.

## Historical binaries and media

The DOS archive is mounted as `/home/mario/Iso/Dos` (capital `I` and `D`), not
`/iso/dos` in the current environment.  Relevant examples include:

- `ez-scsi/ASPIDISK.SYS` and `ez-scsi/ASPICD.SYS`;
- compressed Adaptec ASPI manager files in `ez-scsi/`;
- `LS-120_IDE_KIT.zip`;
- `Zip_100_Parallel_Port-xp-2k.zip`, `zip100.rar`, `zipdrivers.rar`, and
  `zipdrivers100-250-95-98-parallel.zip`;
- `USBASPI.sys`, `USBASPIS.zip`, and `usbaspi-v2.20.zip`.

These are black-box compatibility fixtures.  Record hashes, command-line
options and observed behavior in test logs; do not check the binaries into the
OpenASPI repository.

The [ZIP/LS-120 investigation](aspifdd-reference.md) records local static
analysis of GUEST/MKELS120, companion-file roles, hashes, handler offsets and
unverified functionality. Original binaries and decompiler output are not
included in that document or the source tree.

The [reproducible Adaptec analysis](reference-analysis.md) uses a hash-pinned
Ghidra script for the original ASPIDISK and ASPICD binaries. Their respective
compatibility documents track observed entry points, incomplete behavior and
the implementation/test work needed in ASPIDSK/ASPICDA.

The original 1992 `ASPITAPE.ZIP` distribution and its `ASPITAPE.4` manual are
available from the [Pier Shareware 1 archive](https://cdrom.classicistranieri.com/Pier%20Shareware%201/017A/ASPITAPE.ZIP).
They confirm that mandatory SCSI fixed-block operation is selected using
`READ BLOCK LIMITS`, whereas optional `MTx`/`NMTx` names implement a separate
1024-byte software buffer. The archive is reference material only and is not
redistributed by OpenASPI.

The same distribution's `ALGO_MAS.ZIP` contains `IOCTL.H` and `MTIO.H`.
Their `mtget` is **16 bytes**, with a word-sized state and driver error byte;
the manual instead describes **14 bytes**. Their `TPS_MTOP`, `TPS_ZERO`,
`TPS_IEOT`, and `TPS_WIND` values are 0020h, 0040h, 0080h, and 0100h.
These headers are the reference for OpenASPI's explicitly selected 16-byte
ABI, not evidence that all historical binaries use one layout.

Reference archive SHA-256:
`62f5d4a75e8fa6baefce5aaea5e62642b72bd1e10c12784cdaf0c497e1495917`.

The [mpoli.fi tape archive mirror](https://ftp.zx.net.nz/pub/mirror/files.mpoli.fi/files/hardware/TAPE/)
adds device/application references for DAT, QIC and DLT. The
[device-case ledger](tape-device-profiles.md) separates documented behavior,
qualification candidates, platform-specific drivers and source candidates.
The [27-archive manifest](tape-reference-archives.json) pins URLs, sizes,
hashes, documentation members and six analyzed NT PE inputs. Downloads and
extracted material remain under ignored `build/reference/tape-other/` and
`build/reference/tape-vendors/`. The [NT](nt-tape-analysis.md) and
[DOS/Win3.x](dos-tape-api-analysis.md) investigations record binary-level
findings for the [native OpenTape API](native-tape-api.md).

`ASPITAR.ZIP` is a GNU tar 1.10 ASPI port with C sources and a bundled GPLv1
`COPYING`; it is a source-reuse/test-client candidate, distinct from the
original ASPITAPE character driver. `ASPI505A.ZIP` contains Valitek backup
software, not a generic ASPI manager. Local copies of both under
`/home/mario/Iso/Dos` match the downloaded hashes. No archive binaries or source
were imported into OpenASPI packages by this investigation.

## Virtual tape integration

- mhVTL provides Linux virtual SCSI tape drives and media changers.
- QEMU `scsi-generic` passes their `/dev/sgN` interfaces to a guest.
- QEMU's `dc390` controller works with the locally tested historical Tekram
  DOS `ASPI.SYS` manager when the targets are hot-plugged after SeaBIOS.
- QEMU 10.2's LSI emulation hangs with Symbios `ASPI8XX.SYS` and a
  `scsi-generic` target, so it is not the mhVTL test default.

The historical manager remains an external black-box fixture. Its binary must
not be committed. The reproducible setup and required environment variables
are documented in `docs/qemu-mhvtl.md`.
