; ASPIFDD.SYS: OpenASPI removable-media driver.
;
; A DOS block device driver for LS-120/240, ZIP, Clik!, Jaz and similar
; removable-media drives (peripheral type 00h with the removable bit and a
; known INQUIRY name) behind an installed ASPI manager.  A drive without a
; disk gets its drive letter; the disk is read when DOS asks for it (media
; change, BUILD BPB).  Partitioned disks (ZIP) and superfloppies (LS-120).
;
;   DEVICE=AHCIASPI.SYS
;   DEVICE=ASPIFDD.SYS
;
; Shared block IOCTLs provide media lock/eject and exclusive raw sessions.
; ASPIFMT/ASPIDD perform filesystem formatting/copying through that service;
; the driver itself does not invent a vendor-specific low-level format.
; FDD_DRIVER selects ownership policy in the common block implementation,
; keeping ZIP and LS-120 handling consistent with ASPIDSK and ASPISCAN.

        .8086
        option casemap:none

        .model tiny
        .code
        org     0

FDD_DRIVER      equ     1

        include common/aspi/dos_aspi.inc
        include common/dos/devreq.inc
        include common/dos/blkdrv.inc

msg_banner      db      'ASPIFDD 0.1 - OpenASPI removable-media driver', 13, 10, '$'
msg_no_device   db      'No LS-120, ZIP or similar drives - ASPIFDD not installed', 13, 10, '$'

        end     driver_start
