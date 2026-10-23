# ASPIFDD checked raw-media service

Category `80h` is an OpenASPI-specific generic block IOCTL interface for the
formatter and imager. It is available only on ASPIFDD removable units.
The shared C wrapper is `common/dos/raw_client.c`; programs do not duplicate
the ASPI transport or manipulate resident driver pointers.

The caller supplies a 32-byte packet at the standard generic-IOCTL pointer:

| Offset | Size | Meaning |
| --- | --- | --- |
| 00h | 4 | ASCII `RAW1` |
| 04h | 2 | Packet size, exactly 32 |
| 06h | 2 | Session token; returned by BEGIN |
| 08h | 4 | Physical LBA for READ/WRITE; INFO/BEGIN return HA, target, LUN and FAT32-kernel flag in these four bytes |
| 0Ch | 2 | Sector count, 1–32 for READ/WRITE |
| 0Eh | 2 | BEGIN mode: 0 read, 1 read/write |
| 10h | 4 | Far transfer-buffer pointer |
| 14h | 4 | INFO/BEGIN: physical sector count |
| 18h | 4 | INFO/BEGIN: selected FAT volume start, zero if absent |
| 1Ch | 4 | INFO/BEGIN: selected FAT volume length, zero if absent |

On a submitted transport operation's error, byte 0Dh returns the original
driver error; bytes 0Eh/0Fh return checked fixed-format sense key/ASC, or
zero when no valid sense reply exists. DOS AX alone is insufficient: the
tested kernels map these errors differently. A caller must reset the count
and clear its error fields before each new transfer, as the C wrapper does.

| Minor | Operation |
| --- | --- |
| 00h | INFO: READ CAPACITY(10), sector-size check and FAT-volume discovery |
| 01h | BEGIN: acquire one read/read-write session |
| 02h | READ physical sectors |
| 03h | WRITE physical sectors |
| 04h | END and release the session |

BEGIN requires no existing media locks/session and hardware PREVENT success.
A new nonzero token is assigned only after success. Standard DOS accesses
to this unit are blocked during the session, while the owner's raw requests
remain available. Each transfer checks token, access mode, count, physical
capacity, 32-bit arithmetic, NULL/segment wrap and the 1-MiB physical-address
boundary before ASPI. Buffers are caller-owned accessible memory, as with
the rest of the DOS driver interface. The manager owns command timeouts;
pending requests are not abandoned or freed early.

END invalidates the current volume and releases software ownership even if
ALLOW fails. A failed hardware unlock retains its real lock count so ASPICTL
can retry UNLOCK; it is not falsely reported as unlocked. The tools flush
DOS buffers around sessions, release them on ordinary errors/cancellation,
and never ignore write/verification errors. A crashed process can still
require recovery/reboot; this is a cooperative DOS service, not process-owned
Windows volume locking.

After exchanging a formatted disk for an unformatted one, BUILD BPB can
return a resident placeholder to keep its DOS letter addressable. This is
not a measured capacity or a usable filesystem: ordinary I/O/current BPB
still require a recognized volume; raw INFO uses READ CAPACITY instead.

FAT32 uses 53-byte per-unit current/default BPBs. It is enabled after an
extended-DOS API probe and accepts FAT32 partition types 0Bh/0Ch. Category
48h/60h returns the extended descriptor; 48h/66h returns the FAT32 Media-ID.
Legacy current-parameter requests cannot claim success with a truncated
FAT32 BPB. Cluster-size/count, FAT size, root cluster, reserved fields,
active-FAT selection and FSInfo/backup pointers are checked before DOS uses
the BPB. FreeDOS 1.4 file creation/readback and filesystem checking pass
through both ASPIFDD and ASPIDSK; MS-DOS 7.1/Windows handover remains unqualified.

Normal block READ/WRITE/WRITE WITH VERIFY also reject short packets,
volume crossings and 32-bit logical/physical LBA overflow before transport.
This is not yet a complete proof against malformed partition tables or
duplicate BIOS/Windows ownership. See [remaining driver work](driver-status.md).

Tests include real resident entry points in `tests/raw_media.asm` and
`tests/fat32_driver.asm`, plus the DOS integration suites documented with
[ASPIFMT](../tools/aspifmt/README.md) and [ASPIDD](../tools/aspidd/README.md).
