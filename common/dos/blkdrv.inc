; Block device driver core shared by ASPIDSK.SYS and ASPIFDD.SYS.
;
; The including driver defines before it:
;   DRIVER_NAME     macro text of the banner
;   FDD_DRIVER      (ASPIFDD only) removable-media policy
; and includes dos_aspi.inc and devreq.inc.
;
; One DOS unit per device: the first FAT12/FAT16 partition of a partitioned
; medium, or the whole medium of a superfloppy (no partition table, as on
; LS-120 disks).  512-byte sectors only.  WRITE uses WRITE(10), WRITE WITH
; VERIFY uses WRITE AND VERIFY(10) (WRITE(10) on devices without it); a
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
U_BPB           equ     8               ; 25-byte DOS BPB
UNIT_SIZE       equ     34

UF_REMOVABLE    equ     01h
UF_MEDIA        equ     02h

; BPB offsets (from the boot sector offset 0Bh)
BPB_BYTES       equ     0
BPB_SPC         equ     2
BPB_RESERVED    equ     3
BPB_FATS        equ     5
BPB_ROOT        equ     6
BPB_TOTAL16     equ     8
BPB_MEDIA       equ     10
BPB_FATSIZE     equ     11
BPB_HIDDEN      equ     17
BPB_TOTAL32     equ     21
BPB_SIZE        equ     25

ifdef FDD_DRIVER
DEV_ATTR        equ     0802h           ; block, open/close/removable, 32-bit sectors
else
DEV_ATTR        equ     0802h
endif

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

; READ(10) / WRITE(10) / WRITE AND VERIFY(10) (xfer_opcode): CX sectors at
; LBA DX:AX from or to the far buffer [xfer_buffer].  CF and AL = DOS error.
xfer_buffer     dw      0, 0
xfer_opcode     db      28h

read_sectors proc near
        mov     byte ptr [xfer_opcode], 28h
read_sectors endp

xfer_sectors proc near
        push    ax
        push    cx
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
        mov     ax, 512
        mul     cx
        mov     word ptr [srb+SRB_BufLen], ax
        mov     word ptr [srb+SRB_BufLen+2], dx
        mov     ax, word ptr [xfer_buffer]
        mov     word ptr [srb+SRB_BufPointer], ax
        mov     ax, word ptr [xfer_buffer+2]
        mov     word ptr [srb+SRB_BufPointer+2], ax
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
        and     byte ptr [di+U_FLAGS], not UF_MEDIA
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
        mov     cx, BPB_SIZE
        rep     movsb
        pop     es
        pop     di
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
        cmp     byte ptr [sector_buf+0Bh+BPB_FATS], 0
        je      check_no
        cmp     word ptr [sector_buf+0Bh+BPB_FATSIZE], 0   ; 0: FAT32
        je      check_no
        clc
        ret
check_no:
        stc
        ret
check_boot_sector endp

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
write_verify_request endp

rw_opcode       db      0

; READ, WRITE, WRITE WITH VERIFY: RH_COUNT sectors from RH_START
rw_request proc near
        mov     di, word ptr [unit_ptr]
        test    byte ptr [di+U_FLAGS], UF_MEDIA
        jnz     read_have_media
        mov     al, ERR_NOT_READY
        jmp     short read_error
read_have_media:
        mov     ax, word ptr es:[bx+RH_BUFFER]
        mov     word ptr [xfer_buffer], ax
        mov     ax, word ptr es:[bx+RH_BUFFER+2]
        mov     word ptr [xfer_buffer+2], ax
        mov     ax, word ptr es:[bx+RH_START]
        xor     dx, dx
        cmp     ax, 0FFFFh
        jne     read_start_ready
        mov     ax, word ptr es:[bx+RH_START32]
        mov     dx, word ptr es:[bx+RH_START32+2]
read_start_ready:
        add     ax, word ptr [di+U_START]
        adc     dx, word ptr [di+U_START+2]
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
        call    xfer_sectors
        jnc     read_chunk_ok
        cmp     al, 08h                                 ; ILLEGAL REQUEST:
        jne     read_chunk_failed                       ; no WRITE AND
        cmp     byte ptr [rw_opcode], 2Eh               ; VERIFY, write
        jne     read_chunk_failed
        mov     byte ptr [rw_opcode], 2Ah
        pop     bx
        pop     es
        jmp     read_chunk
read_chunk_failed:
        stc
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

        include common/aspi/aspi_client.inc

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
fdd_models:
        db      'ZIP', 0
        db      'LS-120', 0
        db      'LS-240', 0
        db      'CLIK', 0
        db      'SUPERDISK', 0
        db      'JAZ', 0
        db      0

; Is the scan_* device (type 00, inquiry_data read) one of fdd_models with
; the removable bit?  CF clear if it is.
is_fdd_model proc near
        test    byte ptr [inquiry_data+1], 80h
        jz      fdd_no
        mov     si, offset fdd_models
fdd_next_model:
        cmp     byte ptr [si], 0
        je      fdd_no
        mov     di, offset inquiry_data+8
        mov     cx, 24
fdd_try_at:
        push    si
        push    di
fdd_compare:
        lodsb
        or      al, al
        jz      fdd_match
        mov     ah, byte ptr [di]
        cmp     ah, 'a'
        jb      fdd_upper
        cmp     ah, 'z'
        ja      fdd_upper
        sub     ah, 20h
fdd_upper:
        inc     di
        cmp     al, ah
        je      fdd_compare
        pop     di
        pop     si
        inc     di
        loop    fdd_try_at
fdd_skip_model:
        lodsb
        or      al, al
        jnz     fdd_skip_model
        jmp     fdd_next_model
fdd_match:
        pop     di
        pop     si
        clc
        ret
fdd_no:
        stc
        ret
is_fdd_model endp

first_drive     db      0

init_request:
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
        mov     cx, BPB_SIZE
        rep     movsb
        pop     es
        pop     di
        jmp     short init_add_unit
else
        jmp     init_next_device                ; no FAT12/16 volume
endif
init_add_unit:
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
        cmp     al, 10
        jb      print_digit_one
        push    ax
        mov     dl, '1'
        mov     ah, 02h
        int     21h
        pop     ax
        sub     al, 10
print_digit_one:
        add     al, '0'
        mov     dl, al
        mov     ah, 02h
        int     21h
        ret
print_digit endp

ifdef FDD_DRIVER
; 1.44 MB until the first BUILD BPB of a drive without a disk
default_bpb     dw      512
                db      1
                dw      1
                db      2
                dw      224
                dw      2880
                db      0F0h
                dw      9
                dw      18
                dw      2
                dd      0
                dd      0
endif

msg_no_manager  db      'No ASPI manager (SCSIMGR$) - not installed', 13, 10, '$'
msg_no_media    db      ' (no disk)$'
msg_crlf        db      13, 10, '$'
