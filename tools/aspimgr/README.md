# ASPIMGR

`ASPIMGR.EXE` is the common DOS text interface for OpenASPI. Its seven-letter
base name fits DOS 8.3; a future settings file can use `ASPIMGR.CFG`.
There is currently no settings file and no CONFIG.SYS editor.

The interface links Open386MAX's QUILIB directly, sharing its colors,
screen layout and keyboard input with OpenTape. The dependency is a pinned
Git submodule; no UI source is copied into this tool.

## Available now

Start `ASPIMGR` for the interface, or `ASPIMGR /TEXT` for redirected diagnostic
output. Up/Down selects an adapter or device, R scans again, and Esc returns
to DOS. The current inventory shows:

- ASPI manager and adapter names, initiator ID and extension flags;
- host:target:LUN addresses, device classes and removable-media bit;
- INQUIRY vendor, product and firmware revision, plus SRB status.

Disks, removable media, tape, CD/DVD and medium changers appear in the same
inventory. `FDD/RM` means removable direct-access media, including ZIP and
LS-120, rather than a guarantee that the device is a conventional floppy.
Information queries use HA INQUIRY, GET DEVICE TYPE and standard INQUIRY.
The inventory performs no media writes, formatting, resets or tape movement.

Up to 256 adapter/device rows are retained. A full list or failed adapter
query is reported rather than silently presented as complete. LUNs 0–7 and
the adapter-reported target range (up to 32, otherwise the legacy default
of eight) are scanned. Command timeout handling belongs to the ASPI manager;
a pending SRB is not reused while the manager still owns it.

The return code is zero for a complete inventory, including an empty bus,
and two for unavailable ASPI, failed adapter queries, a full list or invalid
arguments. A device whose INQUIRY fails remains visible with an error label.
For installer class detection retain `ASPISCAN` and its existing exit codes.

## Build and test

```sh
git submodule update --init --recursive
make MAXLANG=US
make MAXLANG=GR
bash tests/dos_aspimgr.sh
MAXLANG=GR bash tests/dos_aspimgr.sh
NOASPI=1 bash tests/dos_aspimgr.sh
```

Binaries are `build/US/dos/ASPIMGR.EXE` and `build/GR/dos/ASPIMGR.EXE`.
The selected language is included by `make dist`. QUILIB and its compatible
JWasm are built under OpenASPI's `build/tools/`, leaving their source
checkouts unchanged. The GUI test uses the local automation-enabled 86Box
build, private Xvfb and existing ROMs described in
[LS-120 testing](../../docs/86box-ls120.md). It verifies real ASPI inventory,
selects the LS-120, checks its vendor/firmware details, rescans and exits.
The no-manager variant checks both text and GUI failure reporting.

## Next functions

Filesystem creation and copying are available through
[ASPIFMT](../aspifmt/README.md) and [ASPIDD/ASPIDDG](../aspidd/README.md).
Integration into this inventory interface, device-specific physical
ZIP/LS-120 formatting and detailed live protection reporting remain open.
Eject, lock/unlock
and CD close are now implemented in the drivers and available through
[ASPICTL](../aspictl/README.md); GUI integration remains to be done.
These actions are not exposed as working menu entries yet.
