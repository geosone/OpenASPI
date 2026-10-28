# Native reported partition layout

The read-only PARTITIONS operation reports bounded MODE SENSE(6) medium
partition page `11h`. It does not create partitions, change mode, move tape,
select a partition or measure capacity. No command is retried implicitly.

This is a **reported layout**, not proof of the layout currently committed to
the loaded medium. Drives can report pending MODE SELECT changes; maximum
counts can depend on pending density or the previous medium. Keep the raw
maximum and defined **additional** partition counts separate. In particular,
zero is not proof of one usable partition, and defined greater than maximum
is not normalized or rejected. Do not turn these counts into a LOCATE target
whitelist or LTFS eligibility decision.

The [HPE MODE SENSE partition reference](https://support.hpe.com/hpesc/public/docDisplay?docId=sd00006916en_us&docLocale=en_US&page=GUID-D7147C7F-2016-0901-0922-00000000060A.html)
explains pending layout reporting. The
[IBM 3592 SCSI reference](https://www.ibm.com/support/pages/system/files/inline-files/3592%20SCSI%20Reference_GA32-0968-06%20%28EXTERNAL%29.pdf)
describes the page fields and maximum-count qualifications. Hardware support
and writable media preparation require separate qualification.

## Wire contract

Category `80h`, function `06h`, version `0100h`, packed size 64, format 0 and
flags 0. The provider capability is `00400000h`; the complete current mask is
`1FFFFFFFh`. This capability advertises the binding, not drive support.
Initialize with `ot_tape_partitions_init` and validate every response with
`ot_tape_partitions_validate` before inspecting its result.

| Offset | Bytes | Meaning |
| --- | --- | --- |
| `00h..1Bh` | 28 | Shared native envelope and read-only completion/diagnostic prefix |
| `1Ch` | 4 | Valid fields: bit 1 means reported layout present |
| `20h` | 4 | Maximum additional partitions, raw byte widened to DWORD |
| `24h` | 4 | Additional partitions defined, raw byte widened to DWORD |
| `28h` | 4 | Raw partition flags byte |
| `2Ch` | 4 | Raw medium format recognition byte |
| `30h` | 4 | Raw partition type/units byte; packed fields are not decoded |
| `34h` | 4 | Number of complete two-byte size descriptors, at most 26 |
| `38h` | 4 | Probe flags: UNVERIFIED_LENGTH bit 1 |
| `3Ch` | 4 | Reserved zero |

Flags, recognition and type/units are raw observations, not setter arguments.
Descriptor count supplies structural information only; individual sizes and
byte capacities are deliberately not exposed. All metadata is zero unless
layout validity is set. OK requires valid layout; PARTIAL, BUSY and ERROR
cannot carry layout metadata. Unknown reserved bits and contradictory result,
completion, diagnostic or provenance fields fail packet validation.

## Submission and bounds

One synchronous six-byte CDB `1A 00 11 00 40 00` uses a resident 64-byte buffer,
32 sense bytes, data-in and negotiated residual reporting. Length proof must
have a retained residual flag, zero high word and residual in `0..64`.
The parser checks the complete returned mode extent, eight-byte block
descriptor alignment, every page extent, duplicates, unsupported subpage
format, a minimum eight-byte target page, complete two-byte descriptors and
reserved target byte 7. PS is accepted as a page-header attribute.
Malformed trailing pages invalidate the whole observation. No partially parsed
metadata is published.

A complete reply returns OK, SUBMITTED|DONE and valid layout. A legacy manager
without residual proof returns PARTIAL/INCOMPLETE/UNVERIFIED_LENGTH with no
metadata, even if the buffer looks plausible. A malformed completed reply
returns ERROR/MALFORMED and SUBMITTED|DONE. Transport/target/unsupported
failures retain diagnostics and SUBMITTED without DONE. BUSY submits no CDB
and returns no opcode or completion bits.

Observation preserves legacy diagnostic fields, queued EOF and native session
state, including FAILED (`40h`) and DIRTY|FAILED (`60h`). Active writers, legacy
activity, pending rewind, buffered aliases/data and competing handles block
submission. A successful observation never recovers abandoned output.

## Consumer and qualification

OpenTape exposes `--native-partitions [--device NRMT0]` and key **I** in its
native DOS tape controls. Both use the checked SDK path, display the pending
layout caveat and preserve native uncertainty. Old provider headers reject
the operation without substituting a readiness command.

`tests/mockpartitions.inc` supplies memory-only MODE SENSE fixtures. The sibling
OpenTape `tests/dos_native_partitions.sh` runs an installed DOS driver, SDK and
localized CLI in disposable QEMU images, including exact CDB counters,
ownership, retained failure, queued EOF, malformed structures, length
provenance and command failures. These fixtures do not attach a host tape.
Real-drive qualification, committed-layout identification, configuration,
formatting and LTFS remain open work.
