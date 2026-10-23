# Linux tape references: defects, capabilities and adaptations

Reviewed upstream Linux commit
`7a78f7ba9f24962c8033e0152bf34a7903ff61ba` on 2026-10-23.
[Pinned files and SHA-256 hashes](linux-tape-reference.json) make these findings
reproducible. Downloaded sources stay in ignored `build/reference/linux-tape/`;
this investigation enables no runtime workaround or device-specific operation.

## Tape command and mode-page handling

The Linux [tape driver](https://github.com/torvalds/linux/blob/7a78f7ba9f24962c8033e0152bf34a7903ff61ba/drivers/scsi/st.c)
contains useful device observations even though its broad command interface is
generic:

| Reference | Evidence in the source | Qualification work for OpenASPI |
|---|---|---|
| `st_compression` | Sony SDT-7000 needs block descriptors retained during compression-page updates. Linux uses a general read/modify/write path. | Preserve bounded mode headers/descriptors and unrelated fields; test descriptor counts and malformed lengths before adding compression writes. A generally valid fix need not be a vendor branch. |
| `partition_tape` | HP C1533A and Sony SDT-7000 expose different partition-size descriptor layouts. Linux chooses using page structure. | Distinguish a format/capability variation from a defect. Define preparation semantics and checked layouts before adding native partition operations. |
| `partition_tape` | The comments record Seagate DDS page-length constraints for partition configuration. | Treat as a qualification candidate; establish affected model/firmware and validate accepted/rejected page lengths. |
| `partition_tape` | IBM TS1140/50 partition configuration needs a supported unit scale rather than assuming MB. | Model supported units/ranges; test exact conversions. Do not label a supported alternate representation a firmware bug. |

These observations do not establish our own compatibility or a complete affected
firmware range. No partitioning or compression-setting command is introduced.

## Discovery and transport entries

Linux also has a [shared SCSI device table](https://github.com/torvalds/linux/blob/7a78f7ba9f24962c8033e0152bf34a7903ff61ba/drivers/scsi/scsi_devinfo.c),
with [flag definitions](https://github.com/torvalds/linux/blob/7a78f7ba9f24962c8033e0152bf34a7903ff61ba/include/scsi/scsi_devinfo.h):

| Entry / recorded revision | Linux treatment | OpenASPI qualification boundary |
|---|---|---|
| Sony SDT-5000 / `3.17` | `BLIST_SELECT_NO_ATN` | Bus-selection behavior belongs to the controller/ASPI manager; a tape CDB cannot by itself change ATN selection. |
| WangDAT Model 2600 / `01.7`, Model 3200 / `02.2`, Model 1300 / `02.4` | `BLIST_SELECT_NO_ATN` | Qualify actual model, firmware and controller before requesting a transport adaptation. |
| Tandberg TDC 3600 / `U07` | `BLIST_NOLUN`; scanning other LUNs is recorded as hanging. | Discovery needs its own guard and tests; do not probe an unsafe LUN merely to confirm a known failure. |
| HP C1557A; Sony TSL family | `BLIST_FORCELUN`; TSL comment identifies DDS3/4 autoloaders. | Discovery coverage differs from unsafe-LUN avoidance. Changer functionality remains deferred. |

The table's revision member is not used by its registration/matching path.
Those recorded revisions are evidence hints, not proof that other revisions
are unaffected. Broad model/prefix matches are not a firmware qualification
database to copy unchanged.

## Native optional functions and emulation

The [Linux tape documentation](https://github.com/torvalds/linux/blob/7a78f7ba9f24962c8033e0152bf34a7903ff61ba/Documentation/scsi/st.rst)
separates configurable positioning behavior: `MT_ST_CAN_BSR` controls use of
multi-record backspacing, and `MT_ST_SCSI2LOGICAL` selects a logical coordinate
instead of a device-dependent address. These are useful inputs to our future
capability model, not proof of firmware defects. Linux policy is not our API.

Our future native positioning contract can use direct positioning or a verified
REWIND-plus-forward emulation. It must define partition, records, filemarks,
boundary state and validity. Report direct/emulated/unsupported/unknown support;
never silently replay an ambiguous failed move. Native special functions found
through Ghidra or source investigation should be reusable on other devices when
their semantics can be implemented faithfully.

## Implementation order and evidence requirements

- Fix shared API, parser and state-machine bugs in the common path now.
- Add useful optional functions through a documented native contract and
  capability reporting; implement portable emulations when qualified.
- Add a device/firmware quirk only for an evidenced deviation, with its source,
  identity/firmware/transport scope, avoided behavior and positive/negative tests.
- Keep controller/discovery workarounds below the tape command/provider layer.
- Preserve unknown scope as unknown. A driver branch found in Ghidra or Linux
  is evidence to investigate, not automatic authorization for a broad match.

These cases join the [historical qualification ledger](tape-device-profiles.md)
for the later separate quirks implementation.
