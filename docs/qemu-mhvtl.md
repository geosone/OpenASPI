# QEMU test environment with mhVTL

The confirmed hardware path for testing the DOS driver is:

```text
mhVTL -> Linux /dev/sgN -> QEMU scsi-generic -> AMD 53C974/DC-390
      -> Tekram DOS ASPI manager -> OpenASPI ASPITAP.SYS
```

QEMU 10.2 provides the `dc390` controller and `scsi-generic` device. Tekram's
historical `ASPI.SYS` 1.60 has been confirmed to expose a passed-through mhVTL
tape through the DOS ASPI interface. The manager is a local black-box
compatibility fixture and is not redistributed with OpenASPI.

The tested Tekram fixture identifies itself as version 1.60 (1996-08-07) and
has SHA-256
`efd4ef4fb09bf7527eab4911b00a605277f037d54a9f89bc5a7cb43825a11b5a`.

The Symbios `ASPI8XX.SYS` manager does bind to QEMU's emulated LSI controller,
but QEMU 10.2 hangs in re-entrant LSI I/O when a `scsi-generic` target is used.
That combination therefore is not the default real-tape test path. The tested
Symbios 4.08.00 fixture has SHA-256
`a1f78db0204100848fea4ef83424112b0896a0ab03ab19c9f5e4d236a856e75b`.

## Host setup

Start mhVTL, then obtain the current generic SCSI nodes:

```sh
systemctl start mhvtl.target
lsscsi -g
```

One tested configuration exposed an IBM ULT3580-TD8 drive as `/dev/sg6`.
Device-node numbers are not stable; always verify them with `lsscsi -g`. The
QEMU process needs read/write access to the selected node, normally through the
host's `tape` group.

Only one sequential-access drive is required for the current OpenASPI stage:

```text
target 1, LUN 0  /dev/sg6   tape drive
```

Medium-changer/library robotics are not exercised by OpenASPI at this stage.

## Automated DOS smoke test

Supply the independently obtained Tekram manager and the verified mhVTL nodes:

```sh
ASPI_MANAGER=/path/to/ASPI.SYS \
MHVTL_TAPE=/dev/sg6 \
make dos-mhvtl-smoke
```

If the manager requires command-line switches, provide its complete
`CONFIG.SYS` line separately:

```sh
ASPI_MANAGER=/path/to/ASPI.SYS \
ASPI_MANAGER_LINE='DEVICE=ASPI.SYS' \
MHVTL_CHANGER=/dev/sg13 \
MHVTL_TAPE=/dev/sg6 \
make dos-mhvtl-smoke
```

The default `QEMU_SCSI_CONTROLLER=dc390` matches Tekram `ASPI.SYS`. Other
controllers can be selected only with their matching DOS ASPI manager. The
DC-390 is a narrow SCSI controller, so host target IDs are mapped modulo eight.
`QEMU_TAPE_TARGET`, `QEMU_TAPE_LUN`, `QEMU_CHANGER_TARGET` and
`QEMU_CHANGER_LUN` can override the guest addresses.

The test validates that `ASPISCAN` sees a sequential-access device, that
`ASPITAP.SYS` installs `RMT0`, and that `TAPECTL` reads the compatibility
status block. It performs no tape-data or positioning operation. Set
`CHECK_READY=1` to additionally issue the non-destructive `TEST UNIT READY`
command. That mode intentionally fails if no cartridge is loaded; `TAPECTL`
prints the resulting SCSI status and sense key for diagnosis.

The script verifies through sysfs that the tape node has SCSI peripheral type
`01h`; this prevents accidentally passing an unrelated `/dev/sgN` device to
the test.

## Destructive scratch-cartridge roundtrip

This test overwrites a **virtual scratch cartridge** from the beginning.
Never select media containing wanted data. It refuses physical SCSI nodes.
Load the scratch cartridge manually first; library robotics are not part of
the DOS test. Do not change the loaded cartridge or access the same drive
from another process during the run.

```sh
ASPI_MANAGER=/path/to/ASPI.SYS \
QEMU_BIN=/path/to/patched/qemu-system-i386 \
MHVTL_TAPE=/dev/sg6 \
MHVTL_VERIFY_CHANGER=/dev/sg13 \
MHVTL_VERIFY_DRIVE=0 \
MHVTL_SCRATCH_BARCODE=OA2101L8 \
make dos-mhvtl-roundtrip
```

The verification changer is queried read-only on the host; it need not be
passed to DOS. The gate checks both nodes under `mhvtl_pseudo`, peripheral
types, common adapter, `/etc/mhvtl/device.conf` library/slot mapping, and the
exact barcode in the selected zero-based changer drive. The checks run before
preparation and again immediately before QEMU starts. An alternate config
path can be selected with `MHVTL_DEVICE_CONF`.

The default test uses `ASPITAP.SYS -w` and starts with raw `NRMT0`. It writes
four differently sized records, finalizes that file, reopens without rewind,
appends two records, then rewinds and checks all 8,254 bytes and the three
filemarks. A second pass uses 4096-byte requests and verifies short-record
lengths, residuals, unchanged buffer tails and trailing guards. Filemark reads
must not modify the buffer. A 256-byte request for a 4096-byte record
must fail without corrupting its buffer tail or queuing EOF; the following
63-byte record must still be readable by the next explicit request.

Forward/backward record and filemark spacing is then verified against known
payloads and EOF positions. A record-space request exceeding the first file
must fail at its filemark, not silently continue across files; the next read
must start file two. On success, the test rewinds to BOT. The exact sequence
is described in [ASPITAP testing](../drivers/aspitap/TESTING.md).

The close/reopen phase verifies that `NRMT0` retains position, opening `RMT0`
does not move the tape, and its last close rewinds, including an untouched
handle. Reopening `NRMT0` must then read the first record.
The test also keeps an `NRMT0` handle open while opening and closing `RMT0`;
that nonfinal close must preserve the original session's read position.

Run the same command with `MHVTL_CLOSE_REWIND=immediate` to omit `-w` and
exercise default IMMED close. Pending rewind must survive reopen/status queries and clear before
the successful read at BOT. `MHVTL_CLOSE_REWIND=sync` is the default; other
values are rejected. These mode choices affect only the write-test roundtrip.

Success requires the roundtrip, short-record, oversized-record rejection,
positioning and mode-specific close-rewind markers plus the checked exit
status; any `FAILED` marker rejects the run. Logs and the temporary
boot floppy are under `build/dos-mhvtl/`, which is recreated each run.
Do not run multiple integration scripts against this output directory at once.

The original exact-read roundtrip passed three times with the local QEMU
10.2.3 patch, the Tekram 1.60
manager identified above, and mhVTL's IBM ULT3580-TD8 scratch `OA2101L8`.
The expanded short-record, oversized-record rejection, positioning and
synchronous/immediate close-rewind checks passed with that legacy manager,
which advertises no ASPI residual extension. This exercises the driver's
sense-information fallback through a real DOS manager.
The non-writing `/READY` smoke also passed with the installed, unmodified
QEMU. The LTO profile has variable block limits, so this qualifies the
variable-record scenarios, not physical hardware,
fixed-block media, media replacement or production backups. The separate
virtual-drive write-protection result is described below.

## Write-protection probe

The separate `make dos-mhvtl-write-protect` target requires the same
`ASPI_MANAGER`, `MHVTL_TAPE`, `MHVTL_VERIFY_CHANGER`, `MHVTL_VERIFY_DRIVE` and
`MHVTL_SCRATCH_BARCODE` variables. It adds a read-only `sg_modes` MODE SENSE(6)
check before preparation and again before QEMU starts. The device WP bit must
be set; otherwise no DOS WRITE is attempted. `sg_modes` and `od` are required.
The DOS program tests one rejected WRITE and retention of its DATA PROTECT
diagnostics across TUR and close/reopen, not the writable roundtrip.

**Verified on 2026-10-22:** the DOS mock passed and the host gate correctly
refused `OA2101L8` while it was unprotected. After manual unload, protection
and reload, the protected-media DOS probe passed twice through Tekram 1.60,
installed unmodified QEMU 10.2.3 and mhVTL's IBM ULT3580-TD8. Each run verified
the failed WRITE, DATA PROTECT, full residual and preserved diagnostics across
TUR and close/reopen. This probe does not read filemarks and needs no local
QEMU filemark patch. Physical-drive write protection remains unqualified.
After protection was manually removed by unload/edit/reload, the full
writable roundtrip passed again in both close-rewind modes using the local
QEMU filemark patch. These separate DOS boots do not qualify live media
replacement or clearing saved errors within an existing session.

mhVTL's `edit_tape -w on` changes cartridge MAM; the drive reads that flag on
load. The cartridge therefore must be unloaded first and reloaded afterward.
`vtlcmd` does not provide a live write-protect toggle. Preparing the current
root-owned scratch cartridge requires host-administrator action. Do not edit
the MAM while the cartridge is loaded, use WORM as a substitute, or change
media during a test.

For the verified current setup, drive 0 contains `OA2101L8`, library ID is 10,
and storage slot 21 is empty. After rechecking that identity and slot, run
manually as root, with no guest accessing the drive:

```sh
bash /home/mario/mars/OpenAspi/tests/mhvtl_write_guard.sh /dev/sg6 /dev/sg13 0 OA2101L8 &&
mtx -f /dev/sg13 unload 21 0 &&
edit_tape -l 10 -m OA2101L8 -w on &&
mtx -f /dev/sg13 load 21 0
```

Only that disposable cartridge is in scope. Node, library and slot numbers
are examples of the checked local setup, not portable constants. The script
does not move media or modify write protection automatically. After completing
the protected test, use the same manual unload/edit/reload procedure with
`-w off` to restore writable scratch media.

### QEMU 10.2.3 filemark workaround

Unmodified QEMU 10.2.3 stalls at an empty filemark on the tested
`dc390`/`scsi-generic` path: fixed sense's FILEMARK bit survives in
`scsi_parse_sense_buf().key`, so the sense branch bypasses the normal empty
transfer completion and calls `scsi_req_data(req, 0)`.
[The local test patch](../tests/qemu/scsi-generic-empty-sense.patch) preserves
partial data but routes zero-byte results to status completion. It does not
change the installed system QEMU and is not claimed as an upstream fix.

Apply it to a separate QEMU 10.2.3 source checkout with `patch -p1`, build
`qemu-system-i386` there, and select that binary through `QEMU_BIN`. The local
acceptance build used `--target-list=i386-softmmu --without-default-features
--enable-tcg --disable-docs --disable-werror --disable-download
--disable-guest-agent`; normal QEMU build dependencies are required.

### mhVTL media-name workaround

Some mhVTL revisions create `data.0` but `vtlcmd load map` still checks for
`data`. For the verified new-format scratch cartridge only, a `data` symlink
to `data.0` permits the host-side import. Do not rename or replace cartridge
data files. This compatibility symlink is not created by the DOS test.

## Equivalent QEMU devices

SeaBIOS hangs when the emulated DC-390 already has targets during boot. The
test therefore starts the controller without targets, waits until DOS is
loading, and sends these commands to the QEMU monitor while `DELAY.SYS` holds
the Tekram manager back briefly:

```sh
drive_add 0 if=none,id=mhvtl_tape,format=raw,file=/dev/sg6
device_add scsi-generic,drive=mhvtl_tape,bus=scsi0.0,scsi-id=1,lun=0
```

The controller itself is created with `-device dc390,id=scsi0`.

Do not access the same virtual tape concurrently through the host `/dev/stN`
interface and the DOS guest.
