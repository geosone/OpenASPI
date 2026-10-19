# OpenASPI installation

OpenASPI reuses the GeosOne DOS Installer (GDI) rather than implementing a
separate installer. Build a package with `make dist`; see the
[build guide](../docs/building.md). The packaged DOS instructions are in
[README.TXT](README.TXT).

Install an ASPI manager before the OpenASPI drivers in `CONFIG.SYS`.
Run `INSTALL.EXE` to install or update OpenASPI and `INSTALL /U` from the
installation directory to remove it. Drivers absent from the package are
unavailable for selection. Tape-driver configuration belongs in the
[ASPITAP documentation](../drivers/aspitap/README.md).

## Package-defined detection

The installer runs package-defined probes instead of containing OpenASPI
hardware rules. `ASPISCAN /Q /TAPE`, `/DISK`, `/FDD` and `/CDA` preselect the
matching DOS components. `WINCHECK.COM` distinguishes DOS, Windows 3.x and
Windows 9x/ME DOS boxes; the companion `WINCHECK.EXE` is a real Win16 probe
for Windows-specific setup decisions. All automatic selections remain editable.

See [ASPISCAN](../tools/aspiscan/README.md) and
[WINCHECK](../tools/wincheck/README.md) for the probe interfaces.

## Shared DOS and Windows frontend

GDI supplies one dual-mode `INSTALL.EXE`: DOS runs its MZ text installer,
while Windows 3.1/9x loads its native Win16 NE component-selection frontend.
Both use the same `INSTALL.INI`. The frontend preserves detector-controlled
choices as three-state automatic selections and starts the embedded
transactional DOS engine with explicit choices.

It waits for an explicit success, cancellation or failure result before later
native Windows stages can run. No MFC or other GUI framework is required.

## Registry integration

GDI's package-defined registry layer has a strict shared parser,
Windows-family capability checks, typed data conversion and a lossless
rollback/uninstall journal format. The native Windows 3.x backend is active
and VM-tested for transactional install and removal; the Windows 9x mutation
backend remains a later stage.

The implementation and registry syntax belong to GDI. See its
[registry documentation](../deps/gdi/docs/registry.md) in the initialized
submodule checkout.
