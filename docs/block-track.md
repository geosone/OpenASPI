# Logical track I/O

ASPIDSK and ASPIFDD implement `41h` write, `61h` read and `62h` verify in
category `08h` and, with a FAT32-capable DOS kernel, `48h`. Query `19h`
advertises them without accessing media. Standard and EDR-DOS query packets
use one shared minor-code registry.

## Addressing contract

| Operation | CHS origin | Sector field | Buffer |
| --- | --- | --- | --- |
| `41h` / `61h` | Physical device LBA zero | Zero-based first sector | Contiguous real-mode buffer |
| `62h` | Selected volume start | Starts at the beginning of the track | None; real VERIFY(10), BYTCHK=0 |

This follows the [FreeDOS generic block implementation](https://github.com/FDOS/kernel/blob/master/kernel/dsk.c):
read/write use its absolute CHS conversion, while verification uses its
volume-relative conversion. In particular, adding the partition start to
`41h`/`61h` would read or overwrite the wrong sector. VERIFY adds that start
exactly once and cannot cross the selected volume boundary. This convention
is explicitly tested; broad MS-DOS/Windows compatibility remains unqualified.

CHS uses the current BPB, including a checked `40h` override. Heads and
cylinders start at zero; sectors/track must be 1–63 and heads 1–256. The
conversion uses checked 32-bit arithmetic. Every nonempty operation reads
current capacity; removable-media geometry is refreshed unless a valid
current override is active. An existing recognized FAT volume/current BPB
is required, as for the current standard parameter-setting path. Blank or
non-FAT raw media remain the responsibility of the private raw service.

## Parameter blocks and transfers

The `41h`/`61h` block is 13 bytes: reserved byte zero, WORD head, WORD cylinder,
WORD first sector, WORD sector count and a far buffer pointer. Counts may
cross track boundaries. Zero sectors are a validated no-op with no device
command or data-buffer access. The entire buffer must fit below/equal the
exclusive 1-MiB boundary; NULL data pointers and address overflow fail.
Far pointers are normalized, allowing contiguous data across 64-KiB offsets.
Requests are split into at most 64 sectors/32 KiB per SCSI command.

The `62h` block is five bytes in single-track mode: flags zero, WORD head and
WORD cylinder. Multiple-track mode sets flags bit 0 and adds a WORD track
count. Other flags fail. The resulting count must be at most 255 sectors;
zero tracks are a no-op. No buffer pointer or data payload is submitted.
Successful verification returns flags byte zero. Known failures report byte
1 for unsupported VERIFY opcode, 2 for invalid geometry/range, or 3 for not
ready; other transport errors retain the input byte. Callers must always
check the DOS error/CF result. No opcode fallback or success-only stub is used.

Packet layout and result fields follow [RBIL tables 01562/01564](https://fd.lod.bz/rbil/interrup/dos_kernel/21440d.html).
Pointer bounds are checked for the actual five-, seven- or thirteen-byte
packet; malformed requests do not partially overwrite it. Read/write input
packets remain unchanged. VERIFY changes only its defined result byte.

All transfer ranges must fit the fresh physical capacity. VERIFY must also
fit the current volume before physical translation. All failures propagate;
writes are never automatically retried, and an interrupted multi-command
write may already have changed earlier sectors. A transport failure discards
the current BPB/override. Successful writes invalidate an ordinary cached
volume, but retain an explicit formatting BPB until a real rediscovery or
media-change operation replaces it.

These are administrative operations: software access flag `47h` controls
normal filesystem block traffic, not track I/O. An active ASPIFDD raw session
blocks competing track calls; capability queries still work. Callers must
flush DOS caches and coordinate other BIOS/Windows views. These operations
do not implement physical formatting, arbitrary sector-ID tables or Windows
volume locks, and do not establish full DOS DISKCOPY/FORMAT compatibility.

## Verification

`tests/block_track.asm` runs the real resident entry points for both driver
variants with memory-only ASPI. It checks physical versus volume-relative
addressing, 32-bit LBA carries, maximum CHS values, normalized/cross-segment
buffers, a buffer ending exactly at 1 MiB, multi-command transfers, zero
counts, the 255-sector verify limit, no-data VERIFY SRBs, partial failures,
unsupported commands, result bytes, invalid capacities, bounds and headers.
Numeric data pointers in this fixture are checked but never dereferenced.

`tests/track_dos.inc` uses actual DOS calls on disposable images: physical
sector zero must contain the expected MBR or superfloppy BPB, the identical
sector is written back, another read is compared and the first logical
track is verified. `tests/dos_disk.sh` covers disk, ZIP and LS-120;
`tests/dos_fat32.sh` covers extended calls through both ASPIFDD and ASPIDSK.
The raw-session suite checks exclusion while a lease is active.
