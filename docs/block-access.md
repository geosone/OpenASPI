# DOS access policy and logical-drive mapping

ASPIDSK and ASPIFDD implement generic IOCTL `47h` (set access flag) and
`67h` (get access flag), through category `08h` and, with FAT32-capable DOS,
category `48h`. Capability queries advertise exactly the implemented calls,
including EDR-DOS's alternate query-packet layout for `0847h`/`0867h`.

The parameter block is two bytes: a reserved byte that must be zero and an
access byte. SET accepts zero to disable ordinary DOS block I/O and any
nonzero value to enable it. GET writes only the second byte, normalized to
zero or one. NULL pointers, offset wrap, short request packets, unsupported
categories and unknown units fail without changing the policy. The state
belongs to each DOS unit and starts enabled; another unit is unaffected.
Queries and changes require no medium and issue no device command.

While disabled, normal READ, WRITE and WRITE WITH VERIFY fail with the DOS
driver's general-failure status and transfer count zero, before reaching
ASPI. A malformed request too short to contain a transfer count is rejected
without writing beyond its declared length. Re-enabling does not fabricate
media, suppress a hardware error or clear a write-protection condition.
The policy persists through BPB refresh and media replacement until explicitly
changed or the driver is reloaded.

This is software control of the driver's normal block-data path. It does
not describe hardware write protection, PREVENT/ALLOW locks or password
protection, and is not a universal security lock. Metadata queries and
media controls remain separate administrative operations. ASPIFDD raw-media
sessions remain available to a formatter/imager while ordinary DOS access
is disabled. An active raw session already blocks competing generic calls,
including changes to this policy; capability queries remain available.
Ending a session preserves the prior access flag. Other BIOS/Windows views
and data already cached by DOS are outside this mechanism. Callers must
flush DOS buffers before changing policy and restore it when finished.

## Mapping requests

DOS device requests `17h` and `18h` implement the no-alternate-mapping case:
the selected valid unit returns zero in the request's unit byte. The DOS
API exposes these requests as INT 21h `440Eh`/`440Fh`. Each OpenASPI unit
has its own device; none is a shared A:/B: view of a single physical floppy.
The calls do not remap other units or issue ASPI commands. An unknown unit
still fails before the handler can change the packet.

Interface references: [RBIL generic block IOCTL, table 01566](https://fd.lod.bz/rbil/interrup/dos_kernel/21440d.html)
and the [FreeDOS kernel's Getlogdev/Setlogdev implementation](https://github.com/FDOS/kernel/blob/master/kernel/dsk.c).
These are ABI/behavior references; no kernel implementation was imported.

## Verification

`tests/block_access.asm` exercises the real resident entry points, compiled
for both block-driver variants with memory-only ASPI. It checks per-unit
isolation, read/write/write-with-verify denial before transport, re-enable,
hardware write-protection independence, empty media, guarded/non-CS
parameter buffers, malformed requests, both query layouts, FAT32 gating
and independent logical mappings. `tests/raw_media.asm` verifies raw sessions
while normal access is disabled, rejects competing policy changes and
checks that session cleanup does not reset the policy.

`tests/block_ioctl_dos.asm` uses actual DOS `440Dh`, `4411h`, `440Eh` and
`440Fh` calls on disposable EUSBASPI disk, ZIP and LS-120 images. Both resident
tests and the live DOS test run through `make dos-disk-smoke`; raw-session
integration runs through `make dos-media-smoke`. This does not complete
track-format/parameter-setting or Windows volume-lock compatibility.
