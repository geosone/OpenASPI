# Native READ: distinguish setmarks from filemarks

Native READ classifies a current target mark with ASC/ASCQ `00/03` as a
**setmark**, separately from FILEMARK. SCSI's raw FM bit can represent either
kind. Treating a positively identified setmark as FILEMARK could allow an
unexpected tape boundary to end archive verification successfully.

The [Exabyte VXA-2 SCSI reference, READ section](https://www.bitsavers.org/pdf/exabyte/VXA/1009566-001_VXA-2_SCSI_Reference_200605.pdf)
documents the shared mark bit and distinct additional sense codes, including
a count of data transferred before the mark. The
[HP 35470A OEM manual, REQUEST SENSE section](https://bitsavers.trailing-edge.com/pdf/hp/tape/dat/C1503A/C1503-90900_35470A_DDS-1_OEM_Product_Manual_Jun91.pdf)
also associates `00/03` with a reported setmark and setmark-reporting mode.
These references establish a common classification, not a vendor quirk.

## Wire contract and provenance

The existing category `80h`, function `02h`, version `0100h`, packed 64-byte
READ packet and byte-count fields are unchanged. `OT_TAPE_STREAM_SETMARK=40h`
is a returned stream flag; it is not a request flag or operation number.
The provider advertises `OT_TAPE_OP_READ_SETMARK=04000000h`; the complete
current operation mask is `1FFFFFFFh`. This means the provider can classify
the event, not that a drive supports or currently reports setmarks.

Classification requires checked current target CHECK CONDITION, usable fixed
or descriptor sense (`70h`/`72h`), bounded ASC/ASCQ `00/03` and the raw FM bit.
A missing FM bit contradicts this identified event and returns MALFORMED.
Host errors, contradictory completion or deferred sense cannot acquire a
SETMARK flag from stale sense. Other mark reports retain their existing
compatibility interpretation; unavailable or vendor-specific identification
still needs separate device qualification. No mode is changed automatically.

When both sense information and ASPI residual counts are available they must
agree. Sense information uses bytes for variable reads and blocks for fixed
reads; the public actual count always uses bytes. Invalid, out-of-range or
conflicting counts produce MALFORMED with count/boundary validity removed.
A manager without residual support can still supply a qualified count through
bounded current sense information. If neither source establishes a count,
the event can remain visible in a validated ERROR packet, without COUNT_VALID.
Zero actual bytes alone never grants permission to assume a boundary.

A benign NO SENSE/RECOVERED event with a known count returns STREAM,
SUBMITTED|DONE|COUNT_VALID and SETMARK, with SHORT if appropriate. Data and a
setmark can coexist. A hard sense key remains ERROR, even with a classified
mark and a valid partial count. SETMARK cannot coexist with FILEMARK or EOD.
It is invalid on WRITE and requires matching current target diagnostics.
A native read never queues a synthetic EOF after this event; a subsequent
accepted raw read submits its own CDB.

## SDK and archive behavior

The shared packet validator rejects FILEMARK paired with current `00/03`,
including responses from an older provider with that misclassification.
The native SDK then reports a malformed response and blocks further reads in
that reader session. It never silently relabels or retries a delivered packet.
Conversely an older SDK that does not understand flag `40h` rejects the new
packet safely instead of accepting archive EOF.

A current raw SDK reader returns the validated stream event and actual bytes;
its caller decides how to handle it. OpenTape's OTB1 archive transport rejects
SETMARK as an I/O boundary error for both variable records and fixed-block
reassembly. It accepts no bytes from that archive read, marks the reader
failed, queues no FILEMARK, and does not read again or retry implicitly.
A completed archive session followed by a setmark therefore cannot pass as
one terminated by its required filemark. Cleanup preserves the first failure
and does not reposition tape.

This binding supplies classified reading. [Explicit setmark writing](native-tape-setmark-write.md)
now has a separate owned writer operation. Media preparation and archive
formats that deliberately use setmarks remain separate work. Legacy
ASPITAPE applications keep their existing compatibility interface.

## Qualification

`tests/mocksetmark.inc` validates exact READ CDBs, flags, sizes and byte/block
units using memory only. The sibling OpenTape `tests/dos_native_setmark.sh`
boots installed drivers and SDK consumers in disposable QEMU DOS images.
It covers fixed/descriptor sense, data plus mark, fixed/variable blocks,
legacy residual reporting, missing/conflicting count evidence, host/deferred/
contradictory/hard errors and ordinary filemark regression. Exact counters
verify no hidden retries, queued EOF or write commands.

OpenTape's archive harness also tests `setmark`, `combined-setmark`,
`fixed-setmark` and `fixed-combined-setmark`: backup to its virtual medium
succeeds, then CLI verification rejects the substituted terminal mark.
Host packet, SDK and archive tests include older-provider misclassification
and combined final-data/mark responses. No physical tape is attached; hardware
qualification remains open.
