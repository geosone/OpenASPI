# Static NT tape-driver investigation

Six x86 NT tape drivers from the [historical tape archives](tape-device-profiles.md)
were imported as PE files into local Ghidra on 2026-10-23. The analysis exports
functions, string references, decompilation and disassembly; vendor drivers
were not executed. This is evidence for targeted ASPITAP work, not hardware
qualification or a port of the NT storage stack.

## Reproduction and pinned inputs

`tools/reference/InspectNtTapeDriver.java` accepts only the six binary hashes
below and an x86 PE import. Addresses in this document are virtual addresses
with image base `00010000h`, not file offsets or real-mode addresses.

| Archive / member | SHA-256 | Exported functions |
|---|---|---:|
| `OTHER/4MMS2.ZIP` / `4MMDDS2.SYS` | `4b7c638087f6c8c953ab76951c55af31f50d05ea98c9cd3d587e4391b3702052` | 83 |
| `OTHER/IBM4MM.ZIP` / `4MMIBM.SYS` | `8e65c16cad4810316641156e23619af201941878d5f260d88f7fa253e63d97cc` | 84 |
| `OTHER/EX2501.ZIP` / `MINIQIC.SYS` | `aa8165e8801590c05b129d7de9f912d30c75d3f93367f3cbeed31c51f3ca08b6` | 83 |
| `OTHER/CNR35FLC.ZIP` / `I386/CONRMQIC.SYS` | `3eca6c45bd1a6ac2d3da06677483494193b71c18f6e27de3f20db2ed145f2c24` | 43 |
| `SONY/S4MM.ZIP` / `4MMSONY.SYS` | `39fc1be3c537b6e4206183b9b75a64f4d43fb45fb52dcfc2c45540afcbfa23da` | 84 |
| `SANKYO/SANKYO.ZIP` / `SANKQIC.SYS` | `af9381c9746f5f18f322c1abe89900187976f2059c2207085a6d9739ff6e4681` | 78 |

The [archive manifest](tape-reference-archives.json) also records binary sizes,
archive hashes, member paths and local report names. Function counts include
shared NT class code and import thunks; they do not measure recovered device
features. Some files retain COFF function names, while others use inferred
`FUN_...` names. In particular, Sankyo's decompilation loses some stack-built
SRB fields; check disassembly before interpreting such fields.

Example, after obtaining and extracting the pinned input:

```sh
mkdir -p build/reference-ghidra/nt-tape
bash /usr/share/ghidra/support/analyzeHeadless \
  "$PWD/build/reference-ghidra/nt-tape" tape-4mmdds2 \
  -import "$PWD/build/reference/tape-other/4MMS2/4MMDDS2.SYS" \
  -analysisTimeoutPerFile 120 -max-cpu 2 \
  -scriptPath "$PWD/tools/reference" \
  -postScript InspectNtTapeDriver.java \
  "$PWD/build/reference-ghidra/nt-tape/4mmdds2.txt"
```

Use distinct project/report names for the other inputs. Existing projects
can be revisited with Ghidra's `-process`. Generated reports/projects stay in
ignored `build/`; they contain vendor code. Only these behavioral notes and
our analysis tooling belong in the source tree.

## Findings relevant to ASPITAP

| Driver / addresses | Observed behavior | Implementation consequence |
|---|---|---|
| DDS2 `WhichIsIt` at `000149B0h` | Compares the padded INQUIRY vendor and product prefixes and returns separate model IDs for Archive Python, Exabyte 4200/4200c, HP/IBM, WangDAT and other drives. | Keep exact identity evidence for narrow exceptions. Do not restrict general ASPITAP discovery to this old whitelist or treat a product prefix as firmware qualification. |
| DDS2 get/set drive parameters at `000116F0h` / `000136A0h` | MODE SENSE(6) requests device-configuration page `10h` and compression page `0Fh`, with DBD set. The query tolerates NT status `C0000010h` for IDs 2, 8 and 16; the setter's exception covers only IDs 2 and 8. These map to Archive Python, Exabyte EXB-4200 and, for the query only, WangDAT Model 1300. | Missing optional compression data must not prevent basic tape use. Preserve query/set distinctions; do not suppress transport errors or invent compression capability. Add exact-model and neighboring-model fault tests before introducing an exception. |
| DDS2 set media parameters at `00013BF0h` | Builds a 12-byte MODE SELECT(6) parameter buffer with an eight-byte block descriptor, density byte `7Fh` and a big-endian 24-bit requested block length. | Investigate density/block-setting behavior by device. The observed `7Fh` is not a universal safe density value for every tape. Validate current/changeable parameters and returned lengths before a future setter. |
| DDS2 error hook at `000112D0h`; IBM error hook at `00010899h` | Both inspect fixed-sense ASC/ASCQ and can clear the NT retry flag for `04h/01h`, but map to different NT status values. DDS2 also handles `3Ah/00h`. IBM identity at `0001285Ah` matches HP/IBM vendor/product aliases. | These are historical NT policy choices, not permission to replace our checked becoming-ready/rewind handling with a global no-media rule. Qualify command, device and firmware before any such mapping. |
| Exabyte identity/error at `00012950h` / `00010CD0h` | Matches `EXABYTE ` plus `EXB-2501`. The error hook recognizes key 3, ASC/ASCQ `31h/00h`, changes the reported NT error and disables retry. | Add an incompatible-media-format case. Retain key/ASC/ASCQ diagnostics and do not retry the failed media operation or silently erase/format the tape. |
| Exabyte prepare at `00011CE0h`; setters at `00012110h` / `000121A0h` | Prepare rejects immediate operation; supported paths construct LOAD/UNLOAD `1Bh`, retension with CDB byte 4=`03h`, and an ERASE `19h` path. Both parameter setters return unsupported. | Separate load, unload, retension and physical preparation capabilities. Do not advertise block/compression setters solely because the device is QIC or speaks SCSI. Destructive preparation needs a separate explicit operation and scratch-media tests. |
| Conner identity at `00011717h`, erase at `00010290h`, setter at `00010EB0h` | Matches `CONNER  ` / `CTMS  3200` with exact spacing. The erase path issues REWIND `01h` before ERASE `19h`. Another path reads/updates configuration page `10h` using MODE SENSE/SELECT. | Record preparation sequencing and configuration-page support for this model. Do not infer the same sequence for all Conner drives, nor trigger it during detection. |
| Sony identity at `00013E79h`, drive query at `00011384h`, read/write at `000127B7h` | Matches Sony SDT-2000/4000/5000. The query uses a 28-byte mode buffer including block-descriptor space, unlike DDS2's 20-byte DBD form. Its NT read/write path sets the fixed-block bit. | Parse the MODE SENSE header and block-descriptor length; do not hardcode a page at offset 4. A historical NT transfer policy is not proof that the hardware requires fixed blocks. |
| Sony error hook at `00010FCCh` | For one incoming NT error plus sense key `0Bh`, it changes status and enables the retry flag; it also handles `04h/01h` with retry disabled. | Do not import this as a blanket DOS retry rule. Tape writes, spacing and filemarks require explicit recovery semantics; any read-only retry policy needs command-specific tests. |
| Sankyo inquiry at `00011500h`, prepare at `00010DC0h`, media setter at `00011000h` | Inquiry checks only the padded vendor `SANKYO  `. Prepare constructs load/unload/retension and PREVENT/ALLOW `1Eh` paths. Disassembly confirms MODE SELECT `15h`, PF and a 12-byte parameter list in the media setter. | Vendor-only matching is too broad for a new quirk. Treat locking, preparation and parameter changes as separately qualified capabilities. Check stack-built CDBs in assembly rather than rely on the incomplete decompiler output. |

The imported class-layer sense handlers also distinguish setmarks, filemarks,
beginning/end of medium and blank check. These are useful additional test
targets; the NT structures, status numbers and older fixed-sense assumptions
are not the ASPITAPE ABI or a replacement for our checked sense decoder.

## Next implementation slices

- [ ] Add bounded MODE SENSE parsing for header, block descriptors, page code
  and page length. Test DBD/no-DBD forms, page order, truncated buffers,
  unsupported optional pages and transport errors. Query capability without
  silently changing density, compression, partitions or block mode.
- [ ] Extend read-only diagnostic reporting of media-format mismatch,
  setmarks/BOM and optional-page support while preserving both historical
  ASPITAPE status layouts. Design an explicit extension if more fields are
  needed; do not enlarge an old caller's status buffer.
- [ ] Add identified-device fixtures for the exact branch cases above.
  Parameter setters and erase/retension/partition operations follow only
  after their command encoding, state transitions and failure tests exist.
- [ ] Keep NT retry decisions separate from DOS error translation. Retain
  the current no-replay policy for media-changing operations.

No vendor decompiler output was compiled into OpenASPI and no new runtime
quirk is enabled by this investigation.
