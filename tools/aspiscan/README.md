# ASPISCAN

`ASPISCAN.COM` is the read-only DOS ASPI inventory/detection diagnostic.  It opens the active
`SCSIMGR$`, enumerates ASPI host adapters and all reported target/LUN devices,
and issues a read-only standard SCSI INQUIRY to obtain vendor and product
identification.

Sequential-access devices are marked `TAPE`. With no arguments, exit status
is zero when at least one tape device is found, one when ASPI works but no
tape is present, and two when no usable ASPI manager or host adapter exists.

The scanner is also a generic OpenASPI detector for installers:

```
ASPISCAN /Q /TAPE
ASPISCAN /Q /DISK
ASPISCAN /Q /FDD
ASPISCAN /Q /CDA
ASPISCAN /Q /ANY
```

`/Q` suppresses output. The selected command returns zero when the requested
class exists, one when it does not, and two when ASPI itself is unavailable.
`DISK` includes ordinary direct-access media, including generic removable USB
sticks/readers. `FDD` means recognized removable-media models such as LS-120 or
ZIP. The distinction uses the same checked INQUIRY removable bit and
vendor/product matching policy as ASPIDSK/ASPIFDD, implemented in
[`removable.inc`](../../common/aspi/removable.inc). The removable bit alone does
not place a device in `FDD`.

The adapter line includes the ASPI extension flags. Bit `0002h` reports the
residual-count facility used for short variable-block tape reads.

The final line also reports whether the `RMT0` character device is resident,
which verifies whether `ASPITAP.SYS` accepted or rejected installation.

The tool never reads tape data, changes position or writes media.
