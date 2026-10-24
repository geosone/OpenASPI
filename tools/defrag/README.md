# DEFRAG

Defragments a FAT12, FAT16 or FAT32 drive: any DOS drive, and the media of
ASPIDSK/ASPIFDD (the same sector access as [ASPICHK](../aspichk/README.md)).

```dos
DEFRAG D:          full optimization
DEFRAG D: /U       only join fragmented files
DEFRAG D: /A       analysis only
DEFRAG D: /B       without the screen (lines, for batch files)
```

The drive is checked first with the check of ASPICHK; with errors nothing
is moved (run `ASPICHK D: /F`).

- Full optimization: fragmented files are joined first (moved to the end
  of the free space), then the directories and after them the files, in
  the order of the directory tree, are placed one after the other from the
  first cluster on; a file in the way is moved to the highest free run
  first.  The free space ends up at the end.
- `/U`: every fragmented file goes to the lowest free run that holds it.
- Clusters of no movable file stay where they are: bad clusters, the FAT32
  root directory, files for which there is no free run large enough.

Safe against power loss: files are moved whole, in this order of writes:

1. the data is copied to free clusters (the `.` entry of a directory
   corrected in the copy),
2. the new chain is written to all FATs,
3. the directory entry is switched to the new chain (one sector),
4. the `..` entries of a moved directory's subdirectories,
5. the old chain is freed.

An interruption at any sector leaves at most lost clusters, FAT copies
that differ in them and stale `..` entries; `ASPICHK /F` repairs them, no
file data is lost.  FAT entry 1 marks the volume dirty (FAT16/32) while
DEFRAG runs.  Esc stops between two moves.

The screen shows a cluster map (used, in place, free, reading, writing).
Memory: one bit per cluster and 16 bytes per file in up to 448 KB of
conventional memory, at most 32000 files and directories.

Exit codes: 0 done, 1 the drive has errors, 2 wrong use, no FAT drive or
too little memory, 3 read or write error (run ASPICHK /F), 4 stopped with
Esc.

Tests: `tests/defrag_host.sh` (the core `common/fat/fat_defrag.c` on
fragmented FAT12/16/32 images of `tests/defrag_image.sh`: no fragmented
file and no gap afterwards, files unchanged, `fsck.fat` clean; power loss
after every N-th sector written, `defrag_host.sh DIR 100000` after every
single one, then ASPICHK's repair), `tests/dos_defrag.sh` (MS-DOS 7.1: FAT16
with the screen, FAT32 with `/U`; `ASPI=1`: a FAT12 stick through ASPIDSK;
`CUT=0.3`: QEMU stopped in the middle).
