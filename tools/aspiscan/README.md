# ASPISCAN

`ASPISCAN.COM` is the first DOS integration diagnostic.  It opens the active
`SCSIMGR$`, enumerates ASPI host adapters and all reported target/LUN devices,
and issues a read-only standard SCSI INQUIRY to obtain vendor and product
identification.

Sequential-access devices are marked `TAPE`.  Exit status is zero when at
least one tape device is found, one when ASPI works but no tape is present,
and two when no usable ASPI manager or host adapter exists.

The final line also reports whether the `RMT0` character device is resident,
which verifies whether `ASPITAP.SYS` accepted or rejected installation.

The tool never reads tape data, changes position or writes media.
