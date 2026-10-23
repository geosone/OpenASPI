# Shared DOS driver support

ASPIDSK and ASPIFDD include [`blkdrv.inc`](blkdrv.inc), which contains their
resident block-request implementation and transient initialization. Their
small driver front ends select device ownership and provide diagnostic text.
ASPICDA and ASPITAP retain their own CD-ROM and character-device contracts.

| File | Responsibility |
| --- | --- |
| [`devreq.inc`](devreq.inc) | DOS request offsets, commands and status bits; extensions depend on the command. |
| [`blkdrv.inc`](blkdrv.inc) | Unit records, request dispatch, media/BPB discovery, ordinary block I/O and generic IOCTL dispatch. |
| [`block_capacity.inc`](block_capacity.inc) | Checked READ CAPACITY(10), 512-byte sector qualification and last-LBA conversion. |
| [`block_params.inc`](block_params.inc) | Logical current/default BPB updates with staged validation and media preflight. |
| [`block_track.inc`](block_track.inc) | CHS track READ/WRITE/VERIFY, address conversion and bounded transfers. |
| [`raw_media.inc`](raw_media.inc) | RAW1 exclusive physical-media sessions for tools. |
| [`raw_client.c`](raw_client.c) | DOS client wrappers, session cleanup and read-error classification. |
| [`fat_format.c`](fat_format.c) | I/O-independent FAT12/16/32 layout, metadata and bad-cluster encoding. |
| [`rescue_read.c`](rescue_read.c) | Bounded retries and zero-fill/reporting for classified sector read faults. |

## Follow a request

For ordinary block I/O, `strategy` saves the DOS request pointer, `interrupt`
dispatches it, and `select_unit` chooses the unit record and ASPI address.
`rw_request` validates the volume-relative range, adds the partition start and
splits it into `xfer_sectors` calls. A chunk advances only after successful
completion, including any requested verification.

Generic IOCTL dispatch selects a separate contract. Track READ/WRITE use
physical-device CHS; track VERIFY uses volume-relative CHS. RAW1 always uses
physical LBAs and a BEGIN-issued token. These address spaces must not be
interchanged. [`block-track.md`](../../docs/block-track.md) and
[`block-ioctl.md`](../../docs/block-ioctl.md) describe the packets.

## State and errors

Resident helpers use DS=CS and shared scratch buffers/SRBs. They assume
serialized driver requests. Code after `resident_end` is initialization-only
and cannot be called after DOS has reclaimed it.

Candidate BPBs are staged before publication. Malformed input does not install
a candidate; a failed media preflight deliberately invalidates cached media and
BPB override flags. Lock counts, raw ownership and normal DOS access permission
are separate state, described in [`block-access.md`](../../docs/block-access.md).

Assembly handlers generally return carry plus AL's DOS driver error; C clients
return 0/-1 and retain diagnostics in their client state. RAW1 includes original
driver/sense diagnostics because DOS kernels can map the same driver error to
different application-visible codes. Rescue policy uses that classification;
it must not treat every controller or media-change error as a bad sector.
