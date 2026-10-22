# Shared ASPI layer

`dos_aspi.inc` defines the ASPI for DOS SRB offsets and constants used by the
8086 assembly clients.  `include/openaspi/aspi.h` is the matching packed C
contract, with host tests asserting every important size and offset.

DOS autosense follows the **actual** CDB length: its offset is
`64 + SRB_CDBLen`, not always 80. The C structure reserves maximum storage;
`OA_ASPI_SENSE_OFFSET(cdb_length)` locates returned sense bytes from the SRB
base. Its `sense_tail` member is extra storage, not a universal sense pointer.

`ASPISCAN.COM` and `ASPITAP.SYS` now implement manager discovery through
`SCSIMGR$`, synchronous submission, host/target/LUN enumeration and device-type
selection.  Manager chaining remains the manager's responsibility: a client
sees the combined adapter numbers advertised by the active `SCSIMGR$`.

ASPITAP enables hardware IRQs during submission/completion waiting, restores
the caller's flags and never reuses an `SS_PENDING` SRB after a CPU poll limit.
Command timeouts remain the manager's responsibility. A future client-side
deadline would also need confirmed cancellation before releasing buffers.
Reusable execute-SCSI helpers, scanner completion-policy alignment and posting
where asynchronous client I/O is useful remain pending work.

AHCIASPI and EUSBASPI provide the first free manager implementations used for
integration tests.  The layer must also remain compatible with historical
Adaptec managers.
