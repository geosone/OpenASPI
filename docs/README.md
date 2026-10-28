# Documentation index

Start with the driver/tool guide for use, the source guide for implementation,
and the status ledger for remaining work. Planned behavior is kept separate
from implemented DOS interfaces and qualification results.

## Build, installation and source

- [Build and checks](building.md), [installation](../installer/README.md) and
  [language/package generation](../tools/package/README.md).
- [Driver suite](driver-suite.md): device ownership and current feature split.
- [Architecture](architecture.md), [source guide](source-guide.md) and
  [public headers](../include/openaspi/README.md).
- Shared code: [ASPI](../common/aspi/README.md), [DOS/block](../common/dos/README.md),
  [SCSI](../common/scsi/README.md) and [native tape packets](../common/tape/README.md).
- [Implementation status and remaining work](driver-status.md),
  [future projects](future-plans.md) and [Windows storage plans](windows9x-storage.md).

## Drivers and application interfaces

| Driver | Use and configuration | Interface details |
| --- | --- | --- |
| ASPIDSK | [Driver guide](../drivers/aspidsk/README.md) | [ASPIDISK compatibility](aspidisk-compat.md) |
| ASPIFDD | [Driver guide](../drivers/aspifdd/README.md) | [Removable-device findings](aspifdd-reference.md) |
| ASPICDA | [Driver guide](../drivers/aspicda/README.md) | [ASPICD compatibility](aspicd-compat.md) |
| ASPITAP | [Driver guide](../drivers/aspitap/README.md) | [ASPITAPE compatibility](aspitape-compat.md), [testing](../drivers/aspitap/TESTING.md) |

Shared contracts:

- [Completion/autosense](aspi-sense.md) and [media controls](media-control.md).
- Block [ownership](block-ownership.md), [access](block-access.md),
  [generic IOCTLs](block-ioctl.md), [logical parameters](block-parameters.md),
  [track operations](block-track.md) and [raw-media sessions](raw-media.md).
- Native tape [architecture](native-tape-api.md), [query](native-tape-query.md),
  [control](native-tape-control.md), [relative positioning](native-tape-space.md),
  [logical position](native-tape-position.md), [LOCATE](native-tape-locate.md),
  [64-bit positioning](native-tape-wide.md), [media loading](native-tape-media.md),
  [removal control](native-tape-removal.md), [read](native-tape-read.md),
  [setmark classification](native-tape-setmarks.md),
  [explicit setmark writing](native-tape-setmark-write.md),
  [TapeAlert retrieval](native-tape-alerts.md),
  [write](native-tape-write.md) and [fixed-block extension](native-tape-fixed.md).
- [Tape device profiles](tape-device-profiles.md) and
  [Linux tape quirks/reference boundaries](linux-tape-quirks.md).

## Tools

- [ASPISCAN](../tools/aspiscan/README.md): ASPI inventory and installer detection.
- [ASPIMGR](../tools/aspimgr/README.md): DOS inventory UI.
- [ASPICTL](../tools/aspictl/README.md): drive-letter controls and executable aliases.
- [ASPIFMT](../tools/aspifmt/README.md): FAT formatting and bad-cluster marking.
- [ASPIDD/ASPIDDG](../tools/aspidd/README.md): copy/images, media exchange and rescue.
- [TAPECTL](../tools/tapectl/README.md): legacy status and explicit readiness probe.
- [OTAPINFO](../tools/otapinfo/README.md): native session/capability inspection.
- [WINCHECK](../tools/wincheck/README.md): DOS/Win16 environment detection.

## Test environments and reference research

- [QEMU/mhVTL](qemu-mhvtl.md), [CD fixture catalog](qemu-cd-catalog.md) and
  [86Box LS-120](86box-ls120.md).
- [Reference material](reference-material.md), [analysis ledger](reference-analysis.md)
  and [static inspection tools](../tools/reference/README.md).
- [Historical DOS/Win3.x tape APIs](dos-tape-api-analysis.md) and
  [NT tape-driver analysis](nt-tape-analysis.md).

Reference manifests record provenance, not executable requirements:
[`tape-reference-archives.json`](tape-reference-archives.json) and
[`linux-tape-reference.json`](linux-tape-reference.json). Device-specific
findings must be qualified before becoming capabilities, emulation or quirks.

See [reported partition layout](native-tape-partitions.md) for the read-only page `11h` binding, pending-layout limits and memory-only DOS qualification.
