# Media controls in block and CD drivers

`common/aspi/media_control.inc` builds the shared six-byte, no-data
PREVENT/ALLOW MEDIUM REMOVAL (`1Eh`) and START STOP UNIT (`1Bh`) commands.
Block and CD drivers retain their own DOS packet validation, error mapping
and state policy. `ASPICTL` calls these installed driver interfaces.

## Removable block devices

Category `08h`, minor `48h` uses the DOS two-byte media-lock packet:
operation 0 locks, 1 unlocks, 2 queries; byte one receives the accepted lock
count. The layout is [RBIL table 01567](https://fd.lod.bz/rbil/interrup/dos_kernel/21440d.html).
Minor `49h` ejects and requires no parameter block. These operations and
their query results are available only for removable units, including the
ZIP/LS-120 units owned by ASPIFDD. The common implementation also serves
ASPIDSK's other removable direct-access devices.

The first lock sends PREVENT; additional locks increment the unit's count.
Only the last unlock sends ALLOW. Counts are committed after hardware
success. Zero-count unlock and overflow at 255 fail with general failure,
without sending ALLOW or changing output. Unsupported PREVENT/ALLOW returns
unknown command; it is never converted into a software-only successful lock.
Other sense errors are propagated using the existing DOS mappings.

Eject refuses any nonzero count without an ASPI call. Otherwise it sends
START STOP with LoEj=1, Start=0. Only success invalidates the cached volume;
the next current-BPB request must read the device again. This does not add
low-level formatting, ZIP password protection, or a block-device close/load
extension. Query means the handler exists, not that every attached mechanism
implements hardware prevention/eject.

## CD/DVD

MSCDEX output controls 0 (eject), 1 (lock/unlock) and 5 (close tray) use the
same transport helper. Lock input is checked for a complete, nonwrapping
two-byte buffer and an exact value of zero or one. The driver records
successful lock/tray commands per unit. A locked eject fails before ASPI;
a failed hardware operation does not commit the requested state. Successful
eject/close clears only that unit's audio range/state.

Device-status bits 0/1 reflect those committed open/locked commands using
the [Microsoft CD-ROM driver specification](https://gist.github.com/abrasive/7a615e6dde0c1da962f9930cc63ee43d):
bit 0 denotes open; bit 1 denotes unlocked. This records driver commands,
not sensor polling of manual tray movement or externally issued resets.
The CD interface uses a boolean hardware lock, whereas DOS block media
locking is reference-counted.

## Verification

- `tests/media_control.asm` executes the actual resident strategy/interrupt
  paths against memory ASPI: exact no-data CDBs, nested locks, counter bounds,
  unsupported/failed prevention, failed final unlock, selected-unit isolation,
  invalid/null/wrapping packets, locked eject, cache invalidation, CD status
  bits, audio-state isolation and standard/EDR-DOS query layouts.
- `bash tests/dos_media_control.sh` runs both resident fixtures and the real
  CD stack in QEMU: filename aliases, blocked eject, forced unlock/eject,
  close/reopen, invalid FORCE combinations and file reading after close.
- `bash tests/dos_disk.sh` exercises actual EUSBASPI/ASPIFDD with a disposable
  QEMU USB/SCSI ZIP: two locks, partial unlock, blocked eject, forced eject,
  count zero, rejected non-CD CLOSE and a fresh current-BPB failure with
  unchanged output after removal. Existing file comparisons and FAT checks
  still run on all three scratch images.

The current local 86Box development CD model incorrectly readiness-checks
START STOP before its close/reload path, so close after eject can return
NOT READY. Its removable-disk model also has LoEj eject disabled. Those
emulator limits are not worked around with incorrect device commands;
the positive eject/close qualification above uses QEMU. Real mechanisms,
external/manual state changes and Windows storage handover remain unqualified.

## Removable-media tools

The agreed DOS 8.3 names are `ASPIFMT` for floppy/removable FAT formatting
and `ASPIDD` for sector-image read/write. Both are implemented:
[ASPIFMT](../tools/aspifmt/README.md) scans data sectors and marks bad
clusters; [ASPIDD/ASPIDDG](../tools/aspidd/README.md) supplies copying,
single-drive exchange, Rescue and a QUILIB progress UI.
`ASPICTL`, aliases for every registered command and `ASPIMGR` inventory
are available.
FAT filesystem creation and physical, device-specific formatting are distinct
operations and must not be advertised as completed by accepting an IOCTL.
