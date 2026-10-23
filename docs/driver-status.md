# Remaining driver work after the removable-media tools

Implemented in this checkpoint: ASPICTL filename aliases from one command
registry; block media locks/eject; CD lock/eject/close; checked raw sessions;
ASPIFMT FAT12/16 and conditional FAT32; bad-cluster marking; ASPIDD full-media
copy/image, one-drive exchange and Rescue; QUILIB copy UI; extended BPBs and
volume/LBA bounds. These are concrete tested paths, not full compatibility
with every reference-driver operation.

## Block/removable drivers

- BIOS ownership: [GET DISK INFO filtering](block-ownership.md) and an explicit
  unsupported-manager fallback are implemented and INIT-tested. Accurate
  motherboard/USB-boot BIOS mappings still depend on the manager; current
  tools cannot resolve every BIOS, SUBST or Windows alias.
- More than the first supported primary partition; checked extended-partition
  traversal, complete partition-bound validation and independent DOS units.
- Standard parameter-setting, Media-ID writes, logical access flags,
  track read/write/verify and complete DOS FORMAT/category-48 compatibility.
  The OpenASPI-specific formatter is not evidence these IOCTLs are done.
- Device-specific physical format/media profiles for LS-120/240 and ZIP,
  vendor protection/password operations, and non-512-byte sectors.
- Detailed capability/live protection sensing, failed/short transport replies,
  residual-count handling and real mechanism qualification.
- Runtime attachment like GUEST, original private caller ABIs, selection/
  spin-up options and Windows 9x storage ownership/handover.

FAT32 now has a tested FreeDOS path. Broad MS-DOS 7.1 and Windows 9x/me
compatibility still needs dedicated qualification. A read surface scan can
identify repeatedly unreadable clusters; it is not a physical low-level
format or a full-medium write-pattern test.

## CD/DVD

- Replace the reset success-only stub with defined real behavior and tests.
- READ LONG count-zero/reference behavior, complete range/overflow/residual
  coverage and raw/cooked handling across disc layouts.
- Live tray/media/capability state beyond committed driver commands, physical
  audio/player qualification, legacy/vendor command sets and track validation.
- Remaining selection options and actual Windows handover.

The separate [ASPICD ledger](aspicd-compat.md) records implementation details.
86Box's known eject/close emulation limitations remain documented separately;
the positive mechanical-command tests use QEMU, not guessed alternative CDBs.

## Tape

The existing protocol/mhVTL tests remain useful, but production hardware
write/recovery qualification and the limitations in the ASPITAP README and
TESTING document still apply. This checkpoint does not alter tape behavior.

## Filesystem checking

No ASPIFSCK is planned here. Use an appropriate DOS checker already available
for the filesystem. FreeDOS documents [DOSFSCK](https://help.fdos.org/en/hhstndrd/base/dosfsck.htm)
for FAT16/FAT32 and DOSLFN; its [CHKDSK](https://help.fdos.org/en/hhstndrd/base/chkdsk.htm)
does not support FAT32. For a non-repairing check, DOSFSCK provides `-n`.
These external programs are not silently bundled or invoked to modify media.
