# ASPIDD and ASPIDDG

Sector copying for ASPIFDD-managed removable media. `ASPIDD.EXE` is the
command-line frontend; `ASPIDDG.EXE` uses the shared Open386MAX QUILIB UI.
The copy engine, driver interface and rescue logic are the same sources.

```dos
ASPIDD D: E:
ASPIDD D: E: /YES
ASPIDD D:
ASPIDD D: /YES /TEMP:C:\COPY.IMG
ASPIDD READ D: C:\DISK.IMG
ASPIDD WRITE E: C:\DISK.IMG /YES
ASPIDD D: E: /YES /RESCUE /MAP:C:\BAD.MAP
ASPIDDG
ASPIDDG D: E: /YES /RESCUE /MAP:C:\BAD.MAP
```

Two drive letters copy directly between distinct devices with exactly the
same physical sector count. One drive letter, or the same letter twice,
captures the entire source in a temporary file, releases its session and
asks for the target medium. Enter proceeds; Esc cancels. Size is checked
again before writing. A temporary file is removed only after a clean,
verified copy; cancellation, failure or rescued holes retain it for recovery.
Use `/TEMP:` or set TEMP/TMP to a sufficiently large, different drive.

Image files contain the **whole medium**, including any partition table,
filesystem metadata and VFAT long-name directory entries. No individual
filenames are interpreted during copying. New output images and rescue
maps must not already exist; they are never silently truncated. Image WRITE
requires `/YES` and an exact byte-size match. Every written chunk is read
back and compared; write/verification errors are never skipped.

## Rescue

`/RESCUE` applies to media reads: disk-to-disk, one-drive capture and image
READ. It does not excuse errors reading an image file for WRITE. A failed
read chunk is split into individual sectors with two read attempts per
sector. Unreadable sectors become 512 zero bytes, and copying continues.

The separate CSV map records zero-based physical LBA, DOS error, SCSI sense
key and ASC. `/MAP:` chooses a new file; image READ otherwise derives a
`.MAP` filename, and drive copies use a new map under TEMP/TMP or the current
directory. The map must be on a different drive from both source and target.
Map-write failures stop the copy. Device read failures are distinguished
from host/controller failures using the driver's checked sense result,
since EDR-DOS and FreeDOS do not return the same AX for generic-IOCTL errors.
Media changes and not-ready/protection errors abort; queued change reports
are handled only during deliberate one-drive target acquisition, before
writing. Data writes are never automatically replayed.

Exit codes: 0 clean completion, 1 failed/cancelled operation, 2 bad options
or rejected paths, **3 completed with rescued read gaps**. A progress display
of 100% means all sectors were processed, not that damaged contents were
recovered. A raw copy preserves existing names but cannot reconstruct data
from zero-filled unreadable sectors.

## DOS UI

With no arguments, ASPIDDG lets you choose source/target with A–Z and Tab;
Space selects the same drive, F2 toggles Rescue, and Enter continues to
overwrite confirmation. During copying it shows the operation, drive
letters, sector counts, percentage, unreadable-sector count, map and temporary
file paths. Esc cancels between completed driver calls. A blocking ASPI
manager call must return before cancellation is handled. The result stays
visible until Enter/Esc returns to DOS.

Build `MAXLANG=US` or `MAXLANG=GR` for the English/German GUI. It links QUILIB
from the pinned submodule, with no copied UI library. The GUI executable is
under `build/US/dos` or `build/GR/dos`; CLI tools are under `build/dos`.

## Scope and verification

Only ASPIFDD-provided drives and 512-byte sectors are supported; ordinary
BIOS/FDC floppy drives need a separate backend. Images are limited to under
2 GiB by the current DOS file-offset implementation. File paths use the DOS
runtime's filename services; long names **inside** a sector image are copied
unchanged even without a long-filename API in that DOS session.

Temporary files, image files and maps must be on physically different media.
The current path guard rejects matching drive letters; BIOS duplicate
mappings and SUBST aliases are not comprehensively resolved. Sessions block
other accesses through the same ASPIFDD unit, not every possible BIOS or
Windows alias. Windows native-storage handover is not qualified.

`tests/dos_removable_tools.sh` qualifies complete ZIP-100 drive/image copies
and long-name preservation. `tests/dos_diskcopy_swap.sh` exchanges actual
QEMU media at the prompt, verifies the full target, rejects a wrong size
without writing and checks retained images after cancellation.
`tests/dos_rescue.sh` injects a repeatable backend read error, checks that
only its sector is zero-filled, validates the CSV map and exercises GUI
progress, selection, confirmation and cancellation in both languages.
