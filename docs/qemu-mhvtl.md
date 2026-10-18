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

One tested configuration exposed the STK L700 changer as `/dev/sg13` and its
first IBM ULT3580-TD8 drive as `/dev/sg6`. Device-node numbers are not stable;
always verify them with `lsscsi -g`. The QEMU process needs read/write access
to the selected nodes, normally through the host's `tape` group.

The L700 example can preserve the mhVTL target IDs on one emulated SCSI bus:

```text
target 0, LUN 0  /dev/sg13  medium changer
target 1, LUN 0  /dev/sg6   tape drive
```

## Automated DOS smoke test

Supply the independently obtained Tekram manager and the verified mhVTL nodes:

```sh
ASPI_MANAGER=/path/to/ASPI.SYS \
MHVTL_CHANGER=/dev/sg13 \
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
`01h` and an optional changer has type `08h`; this prevents accidentally
passing an unrelated `/dev/sgN` device to the test.

## Equivalent QEMU devices

SeaBIOS hangs when the emulated DC-390 already has targets during boot. The
test therefore starts the controller without targets, waits until DOS is
loading, and sends these commands to the QEMU monitor while `DELAY.SYS` holds
the Tekram manager back briefly:

```sh
drive_add 0 if=none,id=mhvtl_changer,format=raw,file=/dev/sg13
device_add scsi-generic,drive=mhvtl_changer,bus=scsi0.0,scsi-id=0,lun=0
drive_add 0 if=none,id=mhvtl_tape,format=raw,file=/dev/sg6
device_add scsi-generic,drive=mhvtl_tape,bus=scsi0.0,scsi-id=1,lun=0
```

The controller itself is created with `-device dc390,id=scsi0`.

Do not access the same virtual tape concurrently through the host `/dev/stN`
interface and the DOS guest.
