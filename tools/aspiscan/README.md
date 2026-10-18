# ASPISCAN

`ASPISCAN.COM` is the first DOS integration diagnostic.  It opens the active
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
`DISK` means fixed direct-access media; `FDD` means removable direct-access
media such as LS-120 or ZIP. The distinction uses the SCSI INQUIRY removable
media bit rather than product-name tables.

The final line also reports whether the `RMT0` character device is resident,
which verifies whether `ASPITAP.SYS` accepted or rejected installation.

The tool never reads tape data, changes position or writes media.
