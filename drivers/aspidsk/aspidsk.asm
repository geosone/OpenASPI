; ASPIDSK.SYS: OpenASPI disk driver.
;
; A DOS block device driver for SCSI direct-access devices (peripheral type
; 00h) behind an installed ASPI manager: hard disks, SSDs, USB sticks and
; card readers, used with partitions and drive letters like a hard disk.
; LS-120, ZIP and similar removable-media drives are left to ASPIFDD.SYS.
;
;   DEVICE=EUSBASPI.SYS
;   DEVICE=ASPIDSK.SYS
;
; The shared block core exposes the first supported FAT volume, including
; FAT32 only on a qualified DOS kernel. Normal requests are volume-relative;
; shared IOCTL helpers implement checked access, media control and parameters.
; Code and state live in common/dos/blkdrv.inc; changes there affect both
; ASPIDSK and ASPIFDD, so device classification remains a separate policy.

        .8086
        option casemap:none

        .model tiny
        .code
        org     0

        include common/aspi/dos_aspi.inc
        include common/dos/devreq.inc
        include common/dos/blkdrv.inc

msg_banner      db      'ASPIDSK 0.1 - OpenASPI disk driver', 13, 10, '$'
msg_no_device   db      'No disks with a FAT12/FAT16 volume - ASPIDSK not installed', 13, 10, '$'

        end     driver_start
