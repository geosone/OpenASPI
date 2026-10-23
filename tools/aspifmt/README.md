# ASPIFMT

Filesystem formatter for ASPIFDD-managed, 512-byte-sector removable media
such as ZIP and LS-120. It also works on a medium without an existing FAT
filesystem. It uses the driver's checked raw-media service; it is not a
replacement for physical FORMAT UNIT or vendor-specific media formatting.

```dos
ASPIFMT D:
ASPIFMT D: /YES
ASPIFMT D: /YES /FAT:32
ASPIFMT D: /YES /WHOLE
```

Without `/YES`, only the selected layout is displayed. `/YES` creates FAT12
or FAT16 according to size. `/FAT:32` explicitly selects FAT32 when the DOS
kernel supports its extended interfaces; this is qualified with FreeDOS 1.4.
Small media with fewer than the required FAT32 clusters are rejected.

By default an existing first FAT partition is reformatted without changing
the MBR or preceding sectors. A blank medium becomes a superfloppy. Unknown
partitioned layouts are rejected; `/WHOLE` explicitly replaces the entire
medium, including its partition table. Media size/layout is checked again
after acquiring the driver's session, before any format writes.

Formatting writes and reads back both FATs, reserved metadata and the root
directory. All usable data sectors are then read; failed chunks are retried
sector by sector. Repeatedly unreadable data clusters are marked with the
FAT12 `FF7h`, FAT16 `FFF7h` or FAT32 `0FFFFFF7h` bad-cluster value in **both**
FAT copies. FAT32 free-space summaries are adjusted, including the backup.
Duplicate failures within a cluster do not count it twice. The boot sector
is committed last. Error-free reading is not a destructive write-pattern
test or proof that a reported error originated in the magnetic surface.

Unreadable required metadata, an unusable FAT32 root cluster, failed FAT
updates, transport failure, media change or cancellation fail the operation;
they cannot be hidden by marking a data cluster. A failed format may have
modified metadata and must not be treated as a usable filesystem.

The generated filesystem is not bootable as a DOS system disk. Long file
names can be stored on every FAT variant when the OS provides VFAT/LFN;
FAT32 alone does not add a long-filename API to DOS. See the
[Microsoft FAT specification, section 7](https://www.scs.stanford.edu/~zyedidia/docs/_other/fat.pdf).

Exit codes: 0 preview or completed format, 1 incomplete/failed format,
2 invalid options or unavailable FAT32 support. This version supports media
up to just under 2 GiB and does not implement physical format profiles.
Ordinary BIOS/FDC floppy drives without ASPIFDD's service are unsupported.

Tests: `tests/dos_removable_tools.sh`, `tests/dos_format_partition.sh`,
`tests/dos_format_bad.sh` and `tests/dos_fat32.sh`. They check fresh blank
media, MBR preservation, FAT12 entries spanning sector boundaries, both FAT
copies, metadata-error rejection, FAT32 mounting and DOS file read/write.
`BAD_LBA=3105 OUT="$PWD/build/fat32-bad" bash tests/dos_fat32.sh` qualifies
bad-cluster avoidance by the FAT32 DOS filesystem itself.
