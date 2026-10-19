# OpenASPI

OpenASPI is a free DOS driver suite for storage devices reached through an
ASPI manager.  The planned suite consists of `ASPIDSK.SYS`, `ASPIFDD.SYS`,
`ASPICDA.SYS`, and `ASPITAP.SYS`.  The first component under development is
`ASPITAP.SYS`, a SCSI tape driver intended to be compatible with the
documented interface of Greg Shenaut's historical `ASPITAPE.SYS`.

This repository is at the bootstrap stage.  It currently contains:

- byte-exact ASPI for DOS SRB definitions shared by C and assembly code;
- `ASPISCAN.COM`, a read-only host/target/LUN and SCSI-INQUIRY diagnostic;
- `TAPECTL.COM`, a non-destructive ASPITAPE status/readiness diagnostic;
- generic installer probes for ASPI device classes and the running DOS/Windows environment;
- `ASPITAP.SYS` initialization-time ASPI discovery for the first tape device;
- linked `RMT0`/`NRMT0` device names with variable-block reads and writes,
  explicit filemark writing, `mtget`, EOT policy, final-close rewind semantics
  and tape positioning through the generic IOCTL interface;
- the documented ASPITAPE compatibility ABI;
- portable builders for the initial SCSI sequential-access commands;
- fixed-format SCSI sense decoding;
- host-side unit tests for those protocol helpers;
- 8086 DOS binaries built with JWasm.

The generated `ASPITAP.SYS` installs `RMT0` and `NRMT0` only when it finds an
ASPI sequential-access device. Variable-block reads and writes, explicit
filemark writing, status, readiness, forward/backward spacing, rewind and
unload are implemented. Short-record lengths use the ASPI residual extension
when available and fixed-format ILI sense with older managers. A filemark
returns one zero-byte read; EOM remains an error unless the application selects
the documented ignore-EOT policy. Write-protection errors remain failed DOS
writes and are visible through `mtget`. `READ BLOCK LIMITS` detects drives
which require fixed-size blocks; their byte requests must be integral block
multiples and are translated to fixed-block SCSI transfers. Broader sense/error
translation remains a later stage. The write path is emulator-tested but not
yet qualified for production backups on real media.
`RMT0` rewinds when its last tracked handle closes; `NRMT0`, `ASPISCAN` and
`TAPECTL` leave an unwritten tape position unchanged. A written final close
adds the historical two-filemark terminator; `NRMT0` then backspaces one mark,
whereas `RMT0` rewinds.

The installer runs package-defined probes rather than containing OpenASPI
hardware rules. `ASPISCAN /Q /TAPE`, `/DISK`, `/FDD` and `/CDA` preselect the
matching DOS components. `WINCHECK.COM` distinguishes DOS, Windows 3.x and
Windows 9x/ME DOS boxes; the companion `WINCHECK.EXE` is a real Win16 probe
for Windows-specific setup decisions. All automatic selections remain editable.

GDI supplies one dual-mode `INSTALL.EXE`: DOS runs its MZ text installer while
Windows 3.1/9x loads its native Win16 NE component-selection frontend. It reads
the same `INSTALL.INI`, preserves detector-controlled choices as three-state
automatic selections, and starts its embedded transactional DOS engine with
the explicit choices. The frontend waits for an explicit success, cancellation
or failure result before later native Windows stages can run. No MFC or other
GUI framework is required. Its package-defined registry layer now has a
strict shared parser, Windows-family capability checks, typed data conversion
and a lossless rollback/uninstall journal format. The native Windows 3.x
backend is active and VM-tested for transactional install and removal; the
Windows 9x mutation backend remains the next stage.

## Build

JWasm and JWlink are pinned Git submodules and are built locally without
writing generated files into their checkouts:

```text
build/tools/jwasm/jwasm
build/tools/jwlink/jwlink
```

Build the DOS loader skeleton and run the protocol tests:

```sh
make
make test
```

`make dos-smoke` boots the local SvarDOS fixture in QEMU, loads the sibling
AHCIASPI manager, verifies the no-tape driver path and runs `ASPISCAN` against
an emulated ATAPI CD-ROM.  It requires the private test media described in
`docs/reference-material.md` and is therefore not part of `make check`.

`make dos-tape-smoke` boots a test-only ASPI manager that exposes an emulated
tape. It verifies both device names, DOS raw-mode setup, full and residual
variable-block reads, fixed-sense ILI short records, filemarks, both EOM
policies, variable-block writes, write protection, `MTWEOF`, `mtget`, and the
exact CDBs for readiness, spacing, rewind and unload without touching real tape
media. Separate fixtures emulate a fixed 1024-byte drive and verify block-limit
detection, integral-request enforcement, and fixed read/write CDBs. Every
transfer fixture runs both with and without ASPI residual support. Nested
`RMT0` opens verify that rewind occurs only on final close, while `NRMT0` never
rewinds. Written-session tests verify read-after-write rejection and the final
two-filemark/append positioning sequence. All variants use the same SvarDOS
fixture.

`make dos-mhvtl-smoke` uses QEMU's emulated Tekram-compatible DC-390 controller
and `scsi-generic` passthrough to exercise `ASPITAP.SYS` against an mhVTL tape.
The external DOS ASPI manager and the selected `/dev/sgN` nodes are provided
through environment variables. See
[docs/qemu-mhvtl.md](docs/qemu-mhvtl.md).

`make check` also compiles the portable C modules as 16-bit DOS objects with
OpenWatcom from `/opt/watcom`.

Clone with `git clone --recursive`, or initialize an existing checkout with
`git submodule update --init --recursive`. Override `JWASM`, `JWLINK`, or `CC`
on the make command line when required. Build products are written below
`build/`.

`make dist` creates an installable directory with the existing GeosOne DOS
Installer. Its component choices cover all four OpenASPI drivers; drivers not
yet present in the distribution remain unavailable to the installer.

## Planned projects

OpenASPI owns the DOS drivers and low-level ASPI/SCSI support.  OpenTape is a
separate sibling project and consumes the ASPITAPE-compatible character-device
interface; it must work with both OpenASPI's `ASPITAP.SYS` and the historical
`ASPITAPE.SYS`. The current tape scope is one sequential-access drive; medium
changer and tape-library control is intentionally deferred.

See [docs/architecture.md](docs/architecture.md) and
[docs/aspitape-compat.md](docs/aspitape-compat.md).  The complete driver split
is defined in [docs/driver-suite.md](docs/driver-suite.md), and local reference
material is catalogued in [docs/reference-material.md](docs/reference-material.md).
The planned Windows 95/98/98SE/ME miniport and ASPI-runtime architecture is
documented in [docs/windows9x-storage.md](docs/windows9x-storage.md).

OpenASPI command-line tools follow the shared Open386MAX UI language described
by OpenTape. Installation and removal are delegated to GDI rather than being
implemented again here.

## License

OpenASPI is licensed under the GNU General Public License version 3. See
`LICENSE`.
