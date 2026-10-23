; Block device driver core shared by ASPIDSK.SYS and ASPIFDD.SYS.
;
; The including driver defines before it:
;   DRIVER_NAME     macro text of the banner
;   FDD_DRIVER      (ASPIFDD only) removable-media policy
; and includes dos_aspi.inc and devreq.inc.
;
; One DOS unit per device: the first supported FAT partition of a partitioned
; medium, or the whole medium of a superfloppy (no partition table, as on
; LS-120 disks).  512-byte sectors only.  WRITE uses WRITE(10), WRITE WITH
; VERIFY uses WRITE AND VERIFY(10) (WRITE(10) + VERIFY(10) without it); a
; write-protected medium reports DOS error 00h.
;
; ASPIFDD takes the type-00 devices with the removable bit whose INQUIRY
; names a known removable-media drive (fdd_models), ASPIDSK all other type-00
; devices, so the two drivers never claim the same device.

MAX_UNITS       equ     8
CHUNK_SECTORS   equ     64              ; 32 KB per READ(10)

; unit table entry
U_HA            equ     0
U_TARGET        equ     1
U_LUN           equ     2
U_FLAGS         equ     3
U_START         equ     4               ; dword: first sector of the volume
U_BPB           equ     8               ; 53-byte store, extended BPB for FAT32
U_DEFAULT_BPB   equ     61              ; installation-time extended BPB
U_LOCKS         equ     114
U_CAPACITY      equ     115
U_RAW_TOKEN     equ     119
UNIT_SIZE       equ     121

UF_REMOVABLE    equ     01h
UF_MEDIA        equ     02h
UF_RAW_ACTIVE   equ     04h
UF_RAW_WRITE    equ     08h
UF_FAT32        equ     10h

; BPB offsets (from the boot sector offset 0Bh)
BPB_BYTES       equ     0
BPB_SPC         equ     2
BPB_RESERVED    equ     3
BPB_FATS        equ     5
BPB_ROOT        equ     6
BPB_TOTAL16     equ     8
BPB_MEDIA       equ     10
BPB_FATSIZE     equ     11
BPB_SPT         equ     13
BPB_HEADS       equ     15
BPB_HIDDEN      equ     17
BPB_TOTAL32     equ     21
BPB_SIZE        equ     25
BPB_STORE_SIZE  equ     53

DEV_ATTR        equ     08C2h           ; block, generic IOCTL/query, open/close,
                                       ; 32-bit sectors; no legacy IOCTL

driver_start:
        dd      0FFFFFFFFh
        dw      DEV_ATTR
        dw      strategy
        dw      interrupt
unit_count      db      0
        db      7 dup (0)

request_ptr     dd      0
bpb_pointers    dw      MAX_UNITS dup (0)
unit_table      db      MAX_UNITS * UNIT_SIZE dup (0)
unit_ptr        dw      0               ; entry of the current request
sector_buf      db      512 dup (0)
fat32_enabled   db      0
ioctl_bpb_size  dw      BPB_SIZE

strategy proc far
        mov     word ptr cs:[request_ptr], bx
        mov     word ptr cs:[request_ptr+2], es
        ret
strategy endp

interrupt proc far
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        push    cs
        pop     ds
        cld
        ; DOS calls block drivers with a small stack, and the ASPI manager
        ; needs more: a stack of our own
        mov     word ptr [caller_ss], ss
        mov     word ptr [caller_sp], sp
        cli
        push    cs
        pop     ss
        mov     sp, offset driver_stack_top
        sti
        les     bx, [request_ptr]
        mov     al, byte ptr es:[bx+RH_COMMAND]
        cmp     al, CMD_INIT
        jne     not_init
        jmp     init_request
not_init:
        mov     si, offset command_table
next_command:
        cmp     byte ptr [si], 0FFh
        je      unknown_command
        cmp     al, byte ptr [si]
        je      found_command
        add     si, 3
        jmp     next_command
found_command:
        call    select_unit
        jc      request_failed
        les     bx, [request_ptr]
ifdef FDD_DRIVER
        mov     di, word ptr [unit_ptr]
        test    byte ptr [di+U_FLAGS], UF_RAW_ACTIVE
        jz      raw_normal_request
        cmp     byte ptr es:[bx+RH_COMMAND], CMD_IOCTL_QUERY
        je      raw_normal_request
        cmp     byte ptr es:[bx+RH_COMMAND], CMD_GEN_IOCTL
        jne     raw_request_busy
        cmp     byte ptr es:[bx+RH_IOCTL_CATEGORY], 80h
        je      raw_normal_request
raw_request_busy:
        mov     al, ERR_NOT_READY
        jmp     request_failed
raw_normal_request:
endif
        call    word ptr [si+1]
        jc      request_failed
        les     bx, [request_ptr]
        mov     word ptr es:[bx+RH_STATUS], ST_DONE
        jmp     short request_done
unknown_command:
        mov     al, ERR_UNKNOWN_CMD
request_failed:
        les     bx, [request_ptr]
        xor     ah, ah
        or      ax, ST_ERROR or ST_DONE
        mov     word ptr es:[bx+RH_STATUS], ax
request_done::
        cli
        mov     ss, word ptr cs:[caller_ss]
        mov     sp, word ptr cs:[caller_sp]
        sti
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
interrupt endp

command_table:
        db      CMD_MEDIA_CHECK
        dw      media_check
        db      CMD_BUILD_BPB
        dw      build_bpb
        db      CMD_READ
        dw      read_request
        db      CMD_WRITE
        dw      write_request
        db      CMD_WRITE_VERIFY
        dw      write_verify_request
        db      CMD_OPEN
        dw      do_nothing
        db      CMD_CLOSE
        dw      do_nothing
        db      CMD_REMOVABLE
        dw      removable_request
        db      CMD_GEN_IOCTL
        dw      generic_ioctl
        db      CMD_IOCTL_QUERY
        dw      ioctl_query
        db      0FFh

do_nothing proc near
        clc
        ret
do_nothing endp

; unit of the request -> unit_ptr, unit_ha/target/lun
select_unit proc near
        mov     al, byte ptr es:[bx+RH_UNIT]
        cmp     al, byte ptr [unit_count]
        jb      select_ok
        mov     al, ERR_UNKNOWN_UNIT
        stc
        ret
select_ok:
        mov     ah, UNIT_SIZE
        mul     ah
        add     ax, offset unit_table
        mov     di, ax
        mov     word ptr [unit_ptr], di
        mov     al, byte ptr [di+U_HA]
        mov     byte ptr [unit_ha], al
        mov     al, byte ptr [di+U_TARGET]
        mov     byte ptr [unit_target], al
        mov     al, byte ptr [di+U_LUN]
        mov     byte ptr [unit_lun], al
        clc
        ret
select_unit endp

;-----------------------------------------------------------------------------
; SCSI helpers
;-----------------------------------------------------------------------------

; READ(10) / WRITE(10) / WRITE AND VERIFY(10) / VERIFY(10): CX sectors at
; LBA DX:AX from or to the far buffer [xfer_buffer].  CF and AL = DOS error.
xfer_buffer     dw      0, 0
xfer_opcode     db      28h

read_sectors proc near
        mov     byte ptr [xfer_opcode], 28h
read_sectors endp

xfer_sectors proc near
        push    ax
        push    cx
        mov     al, SRB_DIR_NONE
        cmp     byte ptr [xfer_opcode], 2Fh
        je      xfer_direction
        mov     al, SRB_DIR_IN
        cmp     byte ptr [xfer_opcode], 28h
        je      xfer_direction
        mov     al, SRB_DIR_OUT
xfer_direction:
        mov     cl, 10
        call    aspi_prepare
        pop     cx
        pop     ax
        push    ax
        mov     al, byte ptr [xfer_opcode]
        mov     byte ptr [srb+SRB_CDB], al
        pop     ax
        xchg    dl, dh
        mov     word ptr [srb+SRB_CDB+2], dx
        xchg    dl, dh
        xchg    al, ah
        mov     word ptr [srb+SRB_CDB+4], ax
        xchg    al, ah
        mov     byte ptr [srb+SRB_CDB+7], ch
        mov     byte ptr [srb+SRB_CDB+8], cl
        push    ax
        push    dx
        cmp     byte ptr [xfer_opcode], 2Fh
        je      xfer_submit                     ; VERIFY: no payload or pointer
        mov     ax, 512
        mul     cx
        mov     word ptr [srb+SRB_BufLen], ax
        mov     word ptr [srb+SRB_BufLen+2], dx
        mov     ax, word ptr [xfer_buffer]
        mov     word ptr [srb+SRB_BufPointer], ax
        mov     ax, word ptr [xfer_buffer+2]
        mov     word ptr [srb+SRB_BufPointer+2], ax
xfer_submit:
        call    call_aspi
        pop     dx
        pop     ax
        push    ax
        call    aspi_result
        jnc     read_sectors_ok
        call    sense_to_doserr
        pop     dx                              ; drop saved AX, keep error
        stc
        ret
read_sectors_ok:
        pop     ax
        ret
xfer_sectors endp

; TEST UNIT READY: CF and AL = sense key on failure
test_unit_ready proc near
        mov     al, SRB_DIR_NONE
        mov     cl, 6
        call    aspi_prepare
        call    call_aspi
        jmp     aspi_result
test_unit_ready endp

; Read the volume of the unit at DI: its BPB and first sector.  CF if the
; medium has no usable FAT12/FAT16 volume.
load_volume proc near
        and     byte ptr [di+U_FLAGS], not (UF_MEDIA or UF_FAT32)
        mov     word ptr [xfer_buffer], offset sector_buf
        mov     word ptr [xfer_buffer+2], cs
        xor     ax, ax
        xor     dx, dx
        mov     cx, 1
        call    read_sectors
        jc      load_failed
        cmp     word ptr [sector_buf+510], 0AA55h
        jne     load_bad
        ; a boot sector (superfloppy): jump and 512 bytes per sector
        call    check_boot_sector
        jnc     load_boot_ok
        ; a partition table: the first FAT12/FAT16 partition
        mov     si, offset sector_buf+1BEh
        mov     cx, 4
load_find_partition:
        mov     al, byte ptr [si+4]
        cmp     al, 01h                         ; FAT12
        je      load_partition
        cmp     al, 04h                         ; FAT16 < 32 MB
        je      load_partition
        cmp     al, 06h                         ; FAT16
        je      load_partition
        cmp     al, 0Eh                         ; FAT16 LBA
        je      load_partition
        cmp     byte ptr [fat32_enabled], 0
        je      load_partition_next
        cmp     al, 0Bh
        je      load_partition
        cmp     al, 0Ch
        je      load_partition
load_partition_next:
        add     si, 16
        loop    load_find_partition
load_bad:
        mov     al, ERR_UNKNOWN_MEDIA
load_failed:
        stc
        ret
load_partition:
        mov     ax, word ptr [si+8]
        mov     dx, word ptr [si+10]
        mov     word ptr [di+U_START], ax
        mov     word ptr [di+U_START+2], dx
        mov     cx, 1
        call    read_sectors
        jc      load_failed
        cmp     word ptr [sector_buf+510], 0AA55h
        jne     load_bad
        call    check_boot_sector
        jc      load_bad
        jmp     short load_copy
load_boot_ok:
        mov     word ptr [di+U_START], 0
        mov     word ptr [di+U_START+2], 0
load_copy:
        push    di
        push    es
        push    cs
        pop     es
        lea     di, [di+U_BPB]
        mov     si, offset sector_buf+0Bh
        mov     cx, BPB_STORE_SIZE
        rep     movsb
        pop     es
        pop     di
        cmp     word ptr [di+U_BPB+BPB_FATSIZE], 0
        jne     load_fat16
        or      byte ptr [di+U_FLAGS], UF_FAT32
        jmp     short load_hidden
load_fat16:
        ; FAT12/16 has no FAT32 extension; never expose boot-code bytes as BPB.
        push    di
        push    es
        push    cs
        pop     es
        lea     di, [di+U_BPB+BPB_SIZE]
        xor     ax, ax
        mov     cx, BPB_STORE_SIZE-BPB_SIZE
        rep     stosb
        pop     es
        pop     di
load_hidden:
        ; hidden sectors: where the volume starts
        mov     ax, word ptr [di+U_START]
        mov     word ptr [di+U_BPB+BPB_HIDDEN], ax
        mov     ax, word ptr [di+U_START+2]
        mov     word ptr [di+U_BPB+BPB_HIDDEN+2], ax
        or      byte ptr [di+U_FLAGS], UF_MEDIA
        clc
        ret
load_volume endp

; sector_buf holds a FAT12/16 boot sector?  CF if not.
check_boot_sector proc near
        mov     al, byte ptr [sector_buf]
        cmp     al, 0EBh
        je      check_bpb
        cmp     al, 0E9h
        jne     check_no
check_bpb:
        cmp     word ptr [sector_buf+0Bh+BPB_BYTES], 512
        jne     check_no
        cmp     byte ptr [sector_buf+0Bh+BPB_SPC], 0
        je      check_no
        mov     al, byte ptr [sector_buf+0Bh+BPB_SPC]
        cmp     al, 128
        ja      check_no
        mov     ah, al
        dec     ah
        test    al, ah
        jnz     check_no
        cmp     byte ptr [sector_buf+0Bh+BPB_FATS], 0
        je      check_no
        cmp     word ptr [sector_buf+0Bh+BPB_FATSIZE], 0   ; 0: FAT32
        jne     check_yes
        cmp     byte ptr [fat32_enabled], 0
        je      check_no
        cmp     word ptr [sector_buf+17], 0       ; FAT32 has no fixed root
        jne     check_no
        cmp     word ptr [sector_buf+19], 0
        jne     check_no
        cmp     word ptr [sector_buf+42], 0       ; filesystem version 0
        jne     check_no
        mov     ax, word ptr [sector_buf+36]
        or      ax, word ptr [sector_buf+38]
        jz      check_no
        mov     ax, word ptr [sector_buf+32]
        or      ax, word ptr [sector_buf+34]
        jz      check_no
        cmp     word ptr [sector_buf+44], 2       ; root cluster >= 2
        jae     check_fat32_size
        cmp     word ptr [sector_buf+46], 0
        je      check_no
check_fat32_size:
        call    validate_fat32_aux
        jc      check_no
        call    validate_fat32_size
        ret
check_yes:
        clc
        ret
check_no:
        stc
        ret
check_boot_sector endp

; Validate FAT32 metadata/data arithmetic before handing the extended BPB
; to DOS. BX:DX and other scratch registers may change; DI/BP are retained.
validate_fat32_size proc near
        mov     ax, word ptr [sector_buf+14]
        or      ax, ax
        jnz     fat32_reserved_present
        stc
        ret
fat32_reserved_present:
        cmp     byte ptr [sector_buf+16], 2
        jbe     fat32_copies_valid
        stc
        ret
fat32_copies_valid:
        mov     bx, word ptr [sector_buf+32]
        mov     dx, word ptr [sector_buf+34]
        sub     bx, ax
        sbb     dx, 0
        jc      fat32_size_bad
        xor     ax, ax
        mov     al, byte ptr [sector_buf+16]
        mov     si, ax
fat32_subtract_fat:
        sub     bx, word ptr [sector_buf+36]
        sbb     dx, word ptr [sector_buf+38]
        jc      fat32_size_bad
        dec     si
        jnz     fat32_subtract_fat
        mov     cl, byte ptr [sector_buf+13]
fat32_clusters:
        cmp     cl, 1
        jbe     fat32_cluster_count
        shr     dx, 1
        rcr     bx, 1
        shr     cl, 1
        jmp     short fat32_clusters
fat32_cluster_count:
        cmp     dx, 1000h
        jae     fat32_size_bad
        cmp     dx, 0FFFh
        jne     fat32_min_clusters
        cmp     bx, 0FFF5h
        jae     fat32_size_bad
fat32_min_clusters:
        or      dx, dx
        jnz     fat32_check_root
        cmp     bx, 0FFF5h
        jb      fat32_size_bad
fat32_check_root:
        add     bx, 1
        adc     dx, 0
        cmp     word ptr [sector_buf+46], dx
        ja      fat32_size_bad
        jb      fat32_check_fat_entries
        cmp     word ptr [sector_buf+44], bx
        ja      fat32_size_bad
fat32_check_fat_entries:
        add     bx, 1
        adc     dx, 0
        mov     ax, word ptr [sector_buf+36]
        mov     cx, word ptr [sector_buf+38]
        cmp     cx, 20h                        ; already covers max FAT32 clusters
        jae     fat32_size_ok
        mov     si, 7
fat32_entry_count:
        shl     ax, 1
        rcl     cx, 1
        dec     si
        jnz     fat32_entry_count
        cmp     cx, dx
        jb      fat32_size_bad
        ja      fat32_size_ok
        cmp     ax, bx
        jb      fat32_size_bad
fat32_size_ok:
        clc
        ret
fat32_size_bad:
        stc
        ret
validate_fat32_size endp

validate_fat32_aux proc near
        mov     ax, word ptr [sector_buf+48]
        cmp     ax, 0FFFFh
        je      fat32_aux_backup
        or      ax, ax
        jz      fat32_aux_bad
        cmp     ax, word ptr [sector_buf+14]
        jae     fat32_aux_bad
fat32_aux_backup:
        mov     ax, word ptr [sector_buf+50]
        cmp     ax, 0FFFFh
        je      fat32_aux_flags
        or      ax, ax
        jz      fat32_aux_flags
        cmp     ax, word ptr [sector_buf+14]
        jae     fat32_aux_bad
fat32_aux_flags:
        mov     ax, word ptr [sector_buf+40]
        or      ah, ah
        jnz     fat32_aux_bad
        test    al, 70h
        jnz     fat32_aux_bad
        test    al, 80h
        jz      fat32_aux_ok
        and     al, 0Fh
        cmp     al, byte ptr [sector_buf+16]
        jae     fat32_aux_bad
fat32_aux_ok:
        clc
        ret
fat32_aux_bad:
        stc
        ret
validate_fat32_aux endp

;-----------------------------------------------------------------------------
; requests
;-----------------------------------------------------------------------------

; 1 unchanged, 0 don't know, 0FFh changed
media_check proc near
        mov     di, word ptr [unit_ptr]
        mov     ah, 1
        test    byte ptr [di+U_FLAGS], UF_REMOVABLE
        jz      media_check_done
        push    es
        push    bx
        call    test_unit_ready
        pop     bx
        pop     es
ifdef FDD_DRIVER
        mov     ah, 0                           ; removable media: ask DOS
else
        mov     ah, 1
endif
        jnc     media_check_done
        mov     ah, 0FFh                        ; UNIT ATTENTION, no medium
media_check_done:
        mov     byte ptr es:[bx+RH_MEDIA_RET], ah
        clc
        ret
media_check endp

build_bpb proc near
        mov     di, word ptr [unit_ptr]
        test    byte ptr [di+U_FLAGS], UF_REMOVABLE
        jz      build_bpb_ready
        push    es
        push    bx
        call    load_volume
        pop     bx
        pop     es
        jnc     build_bpb_ready
ifdef FDD_DRIVER
        cmp     al, ERR_UNKNOWN_MEDIA
        jne     build_bpb_not_ready
        ; Keep the DOS unit addressable after exchanging a formatted disk for
        ; a blank one. Normal sector requests still require a valid volume;
        ; the placeholder enables checked raw IOCTL formatting/copying only.
        push    di
        push    es
        push    cs
        pop     es
        lea     di, [di+U_BPB]
        mov     si, offset default_bpb
        mov     cx, BPB_STORE_SIZE
        rep     movsb
        pop     es
        pop     di
        jmp     short build_bpb_ready
build_bpb_not_ready:
endif
        mov     al, ERR_NOT_READY
        ret
build_bpb_ready:
        lea     ax, [di+U_BPB]
        mov     word ptr es:[bx+RH_BPB_PTR], ax
        mov     word ptr es:[bx+RH_BPB_PTR+2], cs
        clc
        ret
build_bpb endp

read_request proc near
        mov     byte ptr [rw_opcode], 28h               ; READ(10)
        jmp     short rw_request
read_request endp

write_request proc near
        mov     byte ptr [rw_opcode], 2Ah               ; WRITE(10)
        jmp     short rw_request
write_request endp

write_verify_request proc near
        mov     byte ptr [rw_opcode], 2Eh               ; WRITE AND VERIFY(10)
        jmp     short rw_request
write_verify_request endp

rw_opcode       db      0
rw_verify_after_write db 0

; READ, WRITE, WRITE WITH VERIFY: RH_COUNT sectors from RH_START
rw_request proc near
        mov     byte ptr [rw_verify_after_write], 0
        mov     di, word ptr [unit_ptr]
        test    byte ptr [di+U_FLAGS], UF_MEDIA
        jnz     read_have_media
        mov     al, ERR_NOT_READY
        jmp     read_error
read_have_media:
        cmp     byte ptr es:[bx+RH_LENGTH], 16h
        jb      read_bad_packet
        cmp     word ptr es:[bx+RH_COUNT], 0
        jne     read_nonempty
        clc
        ret
read_nonempty:
        mov     ax, word ptr es:[bx+RH_BUFFER]
        mov     word ptr [xfer_buffer], ax
        mov     ax, word ptr es:[bx+RH_BUFFER+2]
        mov     word ptr [xfer_buffer+2], ax
        mov     ax, word ptr es:[bx+RH_START]
        xor     dx, dx
        cmp     ax, 0FFFFh
        jne     read_start_ready
        cmp     byte ptr es:[bx+RH_LENGTH], 1Eh
        jb      read_bad_packet
        mov     ax, word ptr es:[bx+RH_START32]
        mov     dx, word ptr es:[bx+RH_START32+2]
read_start_ready:
        ; Validate the complete volume-relative request before any transfer.
        ; Reject 32-bit carry and crossings into another partition.
        mov     cx, word ptr [di+U_BPB+BPB_TOTAL16]
        xor     bp, bp
        or      cx, cx
        jnz     read_volume_limit
        mov     cx, word ptr [di+U_BPB+BPB_TOTAL32]
        mov     bp, word ptr [di+U_BPB+BPB_TOTAL32+2]
read_volume_limit:
        push    ax
        push    dx
        add     ax, word ptr es:[bx+RH_COUNT]
        adc     dx, 0
        jc      read_range_stack
        cmp     dx, bp
        ja      read_range_stack
        jb      read_range_ok
        cmp     ax, cx
        ja      read_range_stack
read_range_ok:
        pop     dx
        pop     ax
        add     ax, word ptr [di+U_START]
        adc     dx, word ptr [di+U_START+2]
        jc      read_range_error
        push    ax
        push    dx
        mov     si, word ptr es:[bx+RH_COUNT]
        dec     si
        add     ax, si
        adc     dx, 0
        pop     dx
        pop     ax
        jc      read_range_error
        jmp     short read_validated
read_range_stack:
        pop     dx
        pop     ax
read_range_error:
        mov     al, ERR_NOT_FOUND
        jmp     read_error
read_bad_packet:
        mov     al, 5
        jmp     read_error
read_validated:
        mov     si, word ptr es:[bx+RH_COUNT]   ; sectors left
read_loop:
        or      si, si
        jz      read_done
        mov     cx, si
        cmp     cx, CHUNK_SECTORS
        jbe     read_chunk
        mov     cx, CHUNK_SECTORS
read_chunk:
        push    es
        push    bx
        push    ax
        mov     al, byte ptr [rw_opcode]
        mov     byte ptr [xfer_opcode], al
        pop     ax
        ; xfer_sectors returns errors in AL and may clobber DX. A rejected
        ; WRITE AND VERIFY must retry the exact original LBA, not those
        ; error registers. Keep it independently until the chunk succeeds.
        push    ax
        push    dx
        call    xfer_sectors
        jnc     read_chunk_completed
        cmp     al, 08h                                 ; ILLEGAL REQUEST:
        jne     read_chunk_failed                       ; no WRITE AND
        cmp     byte ptr [rw_opcode], 2Eh               ; VERIFY, write
        jne     read_chunk_failed
        mov     byte ptr [rw_opcode], 2Ah
        mov     byte ptr [rw_verify_after_write], 1
        pop     dx
        pop     ax
        pop     bx
        pop     es
        jmp     read_chunk
read_chunk_failed:
        add     sp, 4                           ; discard LBA; preserve AL error
        stc
        jmp     short read_chunk_ok
read_chunk_completed:
        cmp     byte ptr [rw_verify_after_write], 0
        je      read_chunk_verified
        ; Restore the original chunk LBA for separate VERIFY. Do not advance
        ; the data buffer or report successful WRITE WITH VERIFY before it.
        pop     dx
        pop     ax
        push    ax
        push    dx
        mov     byte ptr [xfer_opcode], 2Fh
        call    xfer_sectors
        jc      read_chunk_failed
read_chunk_verified:
        pop     dx
        pop     ax
read_chunk_ok:
        pop     bx
        pop     es
        jc      read_error
        sub     si, cx
        add     ax, cx
        adc     dx, 0
        push    ax
        push    cx
        mov     ax, cx
        mov     cl, 5                           ; 512 bytes = 32 paragraphs
        shl     ax, cl
        add     word ptr [xfer_buffer+2], ax
        pop     cx
        pop     ax
        jmp     read_loop
read_done:
        clc
        ret
read_error:
        mov     word ptr es:[bx+RH_COUNT], 0
        stc
        ret
rw_request endp

; busy bit: not removable
removable_request proc near
        mov     di, word ptr [unit_ptr]
        test    byte ptr [di+U_FLAGS], UF_REMOVABLE
        jnz     removable_yes
        mov     word ptr es:[bx+RH_STATUS], ST_BUSY or ST_DONE
        pop     ax                              ; return address
        jmp     request_done
removable_yes:
        clc
        ret
removable_request endp

; Only advertise executable operations, independent of media presence.
; Category 48h/FAT32 and write/format minors remain unsupported. Media
; control (08h/48h,49h) is available only for removable units.
ioctl_query proc near
        cmp     byte ptr es:[bx+RH_LENGTH], 0Fh
        jae     ioctl_query_length_ok
        jmp     ioctl_unsupported
ioctl_query_length_ok:
ifdef FDD_DRIVER
        cmp     byte ptr es:[bx+RH_IOCTL_CATEGORY], 80h
        jne     ioctl_query_standard
        cmp     byte ptr es:[bx+RH_IOCTL_MINOR], 4
        jbe     ioctl_query_raw_known
        jmp     ioctl_unsupported
ioctl_query_raw_known:
        jmp     ioctl_query_removable
ioctl_query_standard:
endif
        cmp     byte ptr es:[bx+RH_IOCTL_CATEGORY], 48h
        jne     ioctl_query_legacy
        cmp     byte ptr [fat32_enabled], 0
        jne     ioctl_query_fat32
        jmp     ioctl_unsupported
ioctl_query_fat32:
        cmp     byte ptr es:[bx+RH_IOCTL_MINOR], 60h
        je      ioctl_query_yes
        cmp     byte ptr es:[bx+RH_IOCTL_MINOR], 66h
        je      ioctl_query_yes
        jmp     ioctl_unsupported
ioctl_query_legacy:
        cmp     byte ptr es:[bx+RH_IOCTL_CATEGORY], 08h
        jne     ioctl_query_edr
        cmp     byte ptr es:[bx+RH_IOCTL_MINOR], 60h
        je      ioctl_query_yes
        cmp     byte ptr es:[bx+RH_IOCTL_MINOR], 66h
        je      ioctl_query_yes
        cmp     byte ptr es:[bx+RH_IOCTL_MINOR], 48h
        je      ioctl_query_removable
        cmp     byte ptr es:[bx+RH_IOCTL_MINOR], 49h
        jne     ioctl_unsupported
ioctl_query_removable:
        mov     di, word ptr [unit_ptr]
        test    byte ptr [di+U_FLAGS], UF_REMOVABLE
        jz      ioctl_unsupported
ioctl_query_yes:
        clc
        ret
ioctl_query_edr:
        ; EDR-DOS INT 21h/4411h uses the 22-byte legacy IOCTL layout:
        ; CX=category:minor at RH_COUNT; AX is returned from that count.
        ; Restrict this alternate layout to QUERY, never generic execution.
        cmp     byte ptr es:[bx+RH_COMMAND], CMD_IOCTL_QUERY
        jne     ioctl_unsupported
        cmp     byte ptr es:[bx+RH_LENGTH], 16h
        jne     ioctl_unsupported
        cmp     byte ptr es:[bx+RH_MEDIA], 0
        jne     ioctl_unsupported
        cmp     word ptr es:[bx+RH_COUNT], 0860h
        je      ioctl_query_edr_yes
        cmp     word ptr es:[bx+RH_COUNT], 0866h
        je      ioctl_query_edr_yes
        cmp     word ptr es:[bx+RH_COUNT], 0848h
        je      ioctl_query_edr_removable
        cmp     word ptr es:[bx+RH_COUNT], 0849h
        jne     ioctl_unsupported
ioctl_query_edr_removable:
        mov     di, word ptr [unit_ptr]
        test    byte ptr [di+U_FLAGS], UF_REMOVABLE
        jz      ioctl_unsupported
ioctl_query_edr_yes:
        mov     word ptr es:[bx+RH_COUNT], 0
        clc
        ret
ioctl_query endp

ioctl_unsupported:
        mov     al, ERR_UNKNOWN_CMD
        stc
        ret

; Category 08h, minor 60h: seven descriptor bytes + the 25-byte DOS BPB.
; Bit 0 selects current media instead of installation-time defaults. Bit 2
; (uniform sector sizes) is accepted; reserved/track-layout-only bits fail.
; Never modify the output until all input/media/geometry checks succeed.
generic_ioctl proc near
        call    ioctl_query
        jc      ioctl_unsupported
        cmp     byte ptr es:[bx+RH_LENGTH], 17h
        jb      ioctl_unsupported
ifdef FDD_DRIVER
        cmp     byte ptr es:[bx+RH_IOCTL_CATEGORY], 80h
        jne     ioctl_standard
        jmp     raw_ioctl
ioctl_standard:
endif
        cmp     byte ptr es:[bx+RH_IOCTL_MINOR], 48h
        jne     ioctl_not_lock
        jmp     ioctl_media_lock
ioctl_not_lock:
        cmp     byte ptr es:[bx+RH_IOCTL_MINOR], 49h
        jne     ioctl_not_eject
        jmp     ioctl_media_eject
ioctl_not_eject:
        cmp     byte ptr es:[bx+RH_IOCTL_MINOR], 66h
        jne     ioctl_get_parameters
        jmp     get_media_id
ioctl_get_parameters:
        les     bp, dword ptr es:[bx+RH_IOCTL_PARAM]
        mov     word ptr [ioctl_bpb_size], BPB_SIZE
        mov     ax, 0FFE0h
        les     bx, [request_ptr]
        cmp     byte ptr es:[bx+RH_IOCTL_CATEGORY], 48h
        jne     ioctl_parameter_size
        mov     word ptr [ioctl_bpb_size], BPB_STORE_SIZE
        mov     ax, 0FFC4h
ioctl_parameter_size:
        les     bp, dword ptr es:[bx+RH_IOCTL_PARAM]
        cmp     bp, ax
        ja      ioctl_unsupported
        mov     ax, es
        or      ax, bp
        jz      ioctl_unsupported               ; never write through NULL
        mov     al, es:[bp]
        test    al, 0FAh
        jnz     ioctl_unsupported
        push    es
        push    bp
        mov     di, word ptr [unit_ptr]
        test    al, 1
        jnz     ioctl_current
        lea     si, [di+U_DEFAULT_BPB]
        jmp     short ioctl_bpb_ready
ioctl_current:
        test    byte ptr [di+U_FLAGS], UF_REMOVABLE
        jz      ioctl_current_cached
        call    load_volume                     ; read only, refresh partition/BPB
        jnc     ioctl_current_cached
        jmp     ioctl_media_failed
ioctl_current_cached:
        test    byte ptr [di+U_FLAGS], UF_MEDIA
        jnz     ioctl_current_present
        jmp     ioctl_no_medium
ioctl_current_present:
        lea     si, [di+U_BPB]
ioctl_bpb_ready:
        cmp     word ptr [si+BPB_FATSIZE], 0
        jne     ioctl_fat_size_ok
        cmp     word ptr [ioctl_bpb_size], BPB_STORE_SIZE
        jne     ioctl_no_medium
ioctl_fat_size_ok:
        pop     bp
        pop     es
        ; Logical geometry, rounded up; never divide by zero or overflow.
        mov     ax, word ptr [si+BPB_HEADS]
        mul     word ptr [si+BPB_SPT]
        or      dx, dx
        jnz     ioctl_bad_geometry
        or      ax, ax
        jz      ioctl_bad_geometry
        mov     cx, ax
        xor     dx, dx
        mov     ax, word ptr [si+BPB_TOTAL16]
        or      ax, ax
        jnz     ioctl_total_ready
        mov     ax, word ptr [si+BPB_TOTAL32]
        mov     dx, word ptr [si+BPB_TOTAL32+2]
ioctl_total_ready:
        mov     bx, ax
        or      bx, dx
        jz      ioctl_bad_geometry
        add     ax, word ptr [si+BPB_HIDDEN]
        adc     dx, word ptr [si+BPB_HIDDEN+2]
        jc      ioctl_bad_geometry
        cmp     dx, cx
        jae     ioctl_bad_geometry
        div     cx
        or      dx, dx
        jz      ioctl_cylinders_ready
        inc     ax
        jz      ioctl_bad_geometry
ioctl_cylinders_ready:
        mov     word ptr es:[bp+4], ax
        mov     byte ptr es:[bp+1], 7            ; other removable block device
        mov     word ptr es:[bp+2], 0           ; no hardware lock claim
        test    byte ptr [di+U_FLAGS], UF_REMOVABLE
        jnz     ioctl_attributes_ready
        mov     byte ptr es:[bp+1], 5            ; fixed disk
        mov     word ptr es:[bp+2], 1
ioctl_attributes_ready:
        mov     byte ptr es:[bp+6], 0
        lea     di, [bp+7]
        mov     cx, word ptr [ioctl_bpb_size]
        rep     movsb
        clc
        ret
ioctl_no_medium:
        mov     al, ERR_NOT_READY
ioctl_media_failed:
        pop     bp
        pop     es
        stc
        ret
ioctl_bad_geometry:
        mov     al, ERR_UNKNOWN_MEDIA
        stc
        ret
generic_ioctl endp

; 08h/66h: info level 0, serial (4), volume label (11), filesystem text (8).
; Always load this unit's actual boot sector, including partition selection:
; sector_buf may belong to another unit or a previous medium. No writes.
get_media_id proc near
        les     bp, dword ptr es:[bx+RH_IOCTL_PARAM]
        cmp     bp, 0FFE7h                      ; 25-byte packet
        ja      media_id_invalid
        mov     ax, es
        or      ax, bp
        jz      media_id_invalid
        cmp     word ptr es:[bp], 0
        jne     media_id_invalid
        push    es
        push    bp
        mov     di, word ptr [unit_ptr]
        call    load_volume
        jc      media_id_failed
        mov     si, offset sector_buf+26h
        test    byte ptr [di+U_FLAGS], UF_FAT32
        jz      media_id_signature
        mov     si, offset sector_buf+42h
media_id_signature:
        cmp     byte ptr [si], 29h
        jne     media_id_unavailable
        pop     bp
        pop     es
        inc     si
        lea     di, [bp+2]
        mov     cx, 23
        rep     movsb
        clc
        ret
media_id_unavailable:
        mov     al, ERR_UNKNOWN_MEDIA
media_id_failed:
        pop     bp
        pop     es
        stc
        ret
media_id_invalid:
        jmp     ioctl_unsupported
get_media_id endp

; DOS 08h/48h: byte operation 0=lock, 1=unlock, 2=status; byte result count.
; Never mutate count/output on a rejected request or failed hardware command.
ioctl_media_lock proc near
        les     bp, dword ptr es:[bx+RH_IOCTL_PARAM]
        cmp     bp, 0FFFEh
        ja      media_lock_bad_packet
        mov     ax, es
        or      ax, bp
        jz      media_lock_bad_packet
        mov     al, byte ptr es:[bp]
        cmp     al, 2
        ja      media_lock_bad_packet
        mov     di, word ptr [unit_ptr]
        je      media_lock_result
        or      al, al
        jnz     media_unlock
        cmp     byte ptr [di+U_LOCKS], 0FFh
        je      media_lock_bad_count
        cmp     byte ptr [di+U_LOCKS], 0
        jne     media_lock_increment
        mov     ax, 011Eh                     ; PREVENT, first accepted lock
        call    medium_control_result
        jc      media_lock_done
media_lock_increment:
        inc     byte ptr [di+U_LOCKS]
        jmp     short media_lock_result
media_unlock:
        cmp     byte ptr [di+U_LOCKS], 0
        je      media_lock_bad_count
        cmp     byte ptr [di+U_LOCKS], 1
        jne     media_lock_decrement
        mov     ax, 001Eh                     ; ALLOW, final accepted unlock
        call    medium_control_result
        jc      media_lock_done
media_lock_decrement:
        dec     byte ptr [di+U_LOCKS]
media_lock_result:
        mov     al, byte ptr [di+U_LOCKS]
        mov     byte ptr es:[bp+1], al
        clc
media_lock_done:
        ret
media_lock_bad_count::
        mov     al, ERR_GENERAL
        stc
        ret
media_lock_bad_packet:
        jmp     ioctl_unsupported
ioctl_media_lock endp

; DOS 08h/49h: eject removable medium. No parameter block is required.
ioctl_media_eject proc near
        mov     di, word ptr [unit_ptr]
        cmp     byte ptr [di+U_LOCKS], 0
        jne     media_lock_bad_count
        mov     ax, 021Bh                     ; LoEj=1, Start=0
        call    medium_control_result
        jc      media_eject_done
        and     byte ptr [di+U_FLAGS], not UF_MEDIA
media_eject_done:
        ret
ioctl_media_eject endp

medium_control_result proc near
        call    aspi_media_control
        call    aspi_result
        jnc     medium_control_done
        cmp     al, 5                         ; unsupported PREVENT is not a lock
        jne     medium_control_error
        mov     al, ERR_UNKNOWN_CMD
        stc
        ret
medium_control_error:
        call    sense_to_doserr
        stc
medium_control_done:
        ret
medium_control_result endp

        include common/aspi/aspi_client.inc
        include common/aspi/media_control.inc
ifdef FDD_DRIVER
        include common/dos/raw_media.inc
; Resident placeholder: also needed after runtime blank-media exchanges.
default_bpb     dw      512
                db      1
                dw      1
                db      2
                dw      224
                dw      2880
                db      0F0h
                dw      9,18,2
                dd      0,0
                db      BPB_STORE_SIZE-BPB_SIZE dup (0)
endif

caller_ss       dw      0
caller_sp       dw      0
driver_stack    db      768 dup (0)
driver_stack_top label byte

resident_end label byte

;=============================================================================
; initialization (discarded after INIT)
;=============================================================================

        include common/aspi/aspi_init.inc

; INQUIRY vendor/product substrings of removable-media drives for ASPIFDD
        include common/aspi/removable.inc

first_drive     db      0

init_request:
        call    detect_fat32_kernel
        les     bx, [request_ptr]
        mov     al, byte ptr es:[bx+RH_INIT_DRIVE]
        mov     byte ptr [first_drive], al
        mov     dx, offset msg_banner
        mov     ah, 09h
        int     21h
        call    aspi_open
        jnc     init_scan
        mov     dx, offset msg_no_manager
        jmp     init_failed
init_scan:
        call    aspi_scan_first
init_next_device:
        call    aspi_scan_next
        jnc     init_device
        jmp     init_scan_done
init_device:
        cmp     byte ptr [scan_type], ASPI_DEV_DISK
        jne     init_next_device
        mov     al, byte ptr [unit_count]
        cmp     al, MAX_UNITS
        jb      init_inquiry
        jmp     init_scan_done
init_inquiry:
        call    aspi_inquiry                    ; sets unit_ha/target/lun
        jc      init_next_device
        call    is_fdd_model
ifdef FDD_DRIVER
        jc      init_next_device
else
        jnc     init_next_device
endif
        call    check_disk_ownership
        jc      init_next_device
        mov     al, byte ptr [unit_count]
        mov     ah, UNIT_SIZE
        mul     ah
        add     ax, offset unit_table
        mov     di, ax
        mov     al, byte ptr [scan_ha]
        mov     byte ptr [di+U_HA], al
        mov     al, byte ptr [scan_target]
        mov     byte ptr [di+U_TARGET], al
        mov     al, byte ptr [scan_lun]
        mov     byte ptr [di+U_LUN], al
        mov     byte ptr [di+U_FLAGS], 0
        mov     byte ptr [di+U_LOCKS], 0
        test    byte ptr [inquiry_data+1], 80h
        jz      init_flags_ready
        mov     byte ptr [di+U_FLAGS], UF_REMOVABLE
init_flags_ready:
        call    test_unit_ready                 ; clear UNIT ATTENTION
        call    load_volume
        jnc     init_add_unit
ifdef FDD_DRIVER
        ; no disk in the drive: a placeholder BPB until BUILD BPB
        push    di
        push    es
        push    cs
        pop     es
        lea     di, [di+U_BPB]
        mov     si, offset default_bpb
        mov     cx, BPB_STORE_SIZE
        rep     movsb
        pop     es
        pop     di
        jmp     short init_add_unit
else
        jmp     init_next_device                ; no FAT12/16 volume
endif
init_add_unit:
        ; Standard parameters remain stable when removable media change.
        push    di
        push    es
        push    cs
        pop     es
        lea     si, [di+U_BPB]
        lea     di, [di+U_DEFAULT_BPB]
        mov     cx, BPB_STORE_SIZE
        rep     movsb
        pop     es
        pop     di
        mov     bl, byte ptr [unit_count]
        xor     bh, bh
        shl     bx, 1
        lea     ax, [di+U_BPB]
        mov     word ptr [bpb_pointers+bx], ax
        call    print_unit
        inc     byte ptr [unit_count]
        jmp     init_next_device
init_scan_done:
        cmp     byte ptr [unit_count], 0
        jne     init_installed
        mov     dx, offset msg_no_device
init_failed:
        mov     ah, 09h
        int     21h
        les     bx, [request_ptr]
        mov     byte ptr es:[bx+RH_INIT_UNITS], 0
        mov     word ptr es:[bx+RH_INIT_END], 0
        mov     word ptr es:[bx+RH_INIT_END+2], cs
        mov     word ptr es:[bx+RH_STATUS], ST_DONE
        jmp     request_done
init_installed:
        les     bx, [request_ptr]
        mov     al, byte ptr [unit_count]
        mov     byte ptr es:[bx+RH_INIT_UNITS], al
        mov     word ptr es:[bx+RH_INIT_END], offset resident_end
        mov     word ptr es:[bx+RH_INIT_END+2], cs
        mov     word ptr es:[bx+RH_INIT_ARGS], offset bpb_pointers
        mov     word ptr es:[bx+RH_INIT_ARGS+2], cs
        mov     word ptr es:[bx+RH_STATUS], ST_DONE
        jmp     request_done

; INIT-only ownership check before TUR, volume reads or DOS unit allocation.
; Int13 accessibility alone does not mean DOS has claimed the device.
; Only an explicit unsupported command permits the legacy fallback.
check_disk_ownership proc near
        call    clear_srb
        mov     byte ptr [srb+SRB_Cmd], SC_GET_DISK_INFO
        mov     al, byte ptr [scan_ha]
        mov     byte ptr [srb+SRB_HaId], al
        mov     al, byte ptr [scan_target]
        mov     byte ptr [srb+SRB_Target], al
        mov     al, byte ptr [scan_lun]
        mov     byte ptr [srb+SRB_Lun], al
        ; A broken manager returning success without output is not flag 0.
        mov     byte ptr [srb+SRB_DriveFlags], 0FFh
        call    call_aspi
        cmp     byte ptr [srb+SRB_Status], SS_INVALID_CMD
        je      ownership_unsupported
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        jne     ownership_failed
        mov     al, byte ptr [srb+SRB_DriveFlags]
        cmp     al, DISK_NOT_INT13
        je      ownership_available
        cmp     al, DISK_INT13
        je      ownership_available
        cmp     al, DISK_INT13_AND_DOS
        jne     ownership_failed
        mov     dx, offset msg_bios_owned
        call    print_ownership_device
        stc
        ret
ownership_failed:
        mov     dx, offset msg_ownership_failed
        call    print_ownership_device
        stc
        ret
ownership_unsupported:
        cmp     byte ptr [ownership_warned], 0
        jne     ownership_available
        mov     byte ptr [ownership_warned], 1
        mov     dx, offset msg_ownership_unknown
        mov     ah, 09h
        int     21h
ownership_available:
        clc
        ret
check_disk_ownership endp

; DX points to the diagnostic prefix. No device commands are issued here.
print_ownership_device proc near
        mov     ah, 09h
        int     21h
        mov     al, byte ptr [scan_ha]
        call    print_digit
        mov     dl, ':'
        mov     ah, 02h
        int     21h
        mov     al, byte ptr [scan_target]
        call    print_digit
        mov     dl, ':'
        mov     ah, 02h
        int     21h
        mov     al, byte ptr [scan_lun]
        call    print_digit
        mov     dx, offset msg_crlf
        mov     ah, 09h
        int     21h
        ret
print_ownership_device endp

ownership_warned db 0
msg_bios_owned db '  BIOS/DOS-owned device skipped: $'
msg_ownership_failed db '  Disk ownership query failed; device skipped: $'
msg_ownership_unknown db '  GET DISK INFO unsupported; BIOS ownership unknown.',13,10,'$'

; "  D: ha:target:lun VENDOR PRODUCT"
print_unit proc near
        push    di
        mov     dl, ' '
        mov     ah, 02h
        int     21h
        int     21h
        mov     dl, byte ptr [first_drive]
        add     dl, byte ptr [unit_count]
        add     dl, 'A'
        int     21h
        mov     dl, ':'
        int     21h
        mov     dl, ' '
        int     21h
        mov     al, byte ptr [scan_ha]
        call    print_digit
        mov     dl, ':'
        mov     ah, 02h
        int     21h
        mov     al, byte ptr [scan_target]
        call    print_digit
        mov     dl, ':'
        mov     ah, 02h
        int     21h
        mov     al, byte ptr [scan_lun]
        call    print_digit
        mov     dl, ' '
        mov     ah, 02h
        int     21h
        call    print_inquiry_name
        pop     di
        test    byte ptr [di+U_FLAGS], UF_MEDIA
        jnz     print_unit_end
        mov     dx, offset msg_no_media
        mov     ah, 09h
        int     21h
print_unit_end:
        mov     dx, offset msg_crlf
        mov     ah, 09h
        int     21h
        ret
print_unit endp

print_digit proc near
        push    bx
        push    cx
        xor     ah, ah
        mov     bx, 10
        xor     cx, cx
print_digit_divide:
        xor     dx, dx
        div     bx
        push    dx
        inc     cx
        or      ax, ax
        jnz     print_digit_divide
print_digit_one:
        pop     dx
        add     dl, '0'
        mov     ah, 02h
        int     21h
        loop    print_digit_one
        pop     cx
        pop     bx
        ret
print_digit endp

; Probe the extended DOS API with a deliberately invalid drive, so no disk
; access or recursion into an uninitialized unit is necessary. Older DOS
; returns AL=0 with no structure; a supported API reports invalid drive.
detect_fat32_kernel proc near
        push    es
        push    ds
        push    cs
        pop     es
        push    cs
        pop     ds
        mov     ax, 7303h
        mov     cx, 44
        mov     dx, offset fat32_probe_path
        mov     di, offset fat32_probe_buffer
        int     21h
        jnc     fat32_probe_done
        cmp     ax, 0Fh
        jne     fat32_probe_done
        mov     byte ptr [fat32_enabled], 1
fat32_probe_done:
        pop     ds
        pop     es
        ret
detect_fat32_kernel endp
fat32_probe_path db '[:\',0
fat32_probe_buffer db 44 dup (0)

msg_no_manager  db      'No ASPI manager (SCSIMGR$) - not installed', 13, 10, '$'
msg_no_media    db      ' (no disk)$'
msg_crlf        db      13, 10, '$'
