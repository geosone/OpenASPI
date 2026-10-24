; exFAT media for EXFAT.SYS, included by blkdrv.inc (ASPIDSK and ASPIFDD).
;
; DOS cannot use an exFAT volume through a block driver, so a unit with
; exFAT gets the placeholder BPB and no DOS data access (UF_MEDIA stays
; clear); EXFAT.SYS takes its drive letter over as a redirector and reads
; the sectors through the far entry exfat_service.  EXFAT.SYS finds it from
; the device header: "EXF1" and the entry offset after the unit count.
;
; exfat_service: ES:BX -> 16-byte packet, all registers kept.
;   00h byte  function: 0 INFO, 1 READ, 2 CHECK, 3 CALLBACK, 4 WRITE (EXCHK /F),
;             for EXFMT: 5 PREAD, 6 PWRITE (sectors of the medium, not of
;             the volume), 7 CAPACITY, 8 RELOAD (reads the medium again,
;             the next MEDIA CHECK reports "changed", EXFAT.SYS is told
;             when it is exFAT now)
;   01h byte  unit
;   02h word  out: 0 done, else 8000h | DOS driver error
;   04h dword READ/WRITE: sector, relative to the exFAT volume; PREAD/PWRITE:
;             sector of the medium, below its capacity of the last CAPACITY
;             INFO out: first sector of the volume (U_START)
;             CAPACITY out: sectors of the medium
;   08h word  READ/WRITE/PREAD/PWRITE: count, 1-64
;             INFO, RELOAD out: U_FLAGS (UF_EXFAT: exFAT volume)
;   0Ah dword READ/WRITE: far buffer; INFO out: sectors of the exFAT volume;
;             CALLBACK: far procedure, called with AL = unit and DX = the
;             driver's segment when BUILD BPB or a READ after a media
;             change finds a new exFAT medium (inside DOS: it must not
;             call DOS or this service)
;   0Eh word  INFO out: unit count; CHECK out: 1 the medium was changed
;             (and has been read again), 0 the same
;
; CHECK keeps the change for DOS: the next MEDIA CHECK reports "changed".

PK_FUNC         equ     0
PK_UNIT         equ     1
PK_STATUS       equ     2
PK_LBA          equ     4
PK_COUNT        equ     8
PK_BUFFER       equ     0Ah
PK_RESULT       equ     0Eh

exfat_packet    dd      0
exfat_callback  dd      0
exfat_starts    dd      4 dup (0)

; DI's unit: load_volume, else an exFAT volume (superfloppy, or a primary
; MBR partition of type 07h): placeholder BPB, UF_EXFAT, U_START, U_XLEN.
; CF and AL as load_volume when neither is there.
load_volume_x proc near
        and     byte ptr [di+U_FLAGS], not UF_EXFAT
        call    load_volume
        jnc     load_x_done
        cmp     al, ERR_UNKNOWN_MEDIA
        je      load_x_exfat
        test    byte ptr [di+U_FLAGS], UF_REMOVABLE
        jz      load_x_failed
        ; a changed medium answers NOT READY / UNIT ATTENTION once each
        mov     cx, 3
load_x_tur:
        push    cx
        call    test_unit_ready
        pop     cx
        jnc     load_x_again
        loop    load_x_tur
load_x_again:
        call    load_volume
        jnc     load_x_done
        cmp     al, ERR_UNKNOWN_MEDIA
        jne     load_x_failed
load_x_exfat:
        call    exfat_detect
        jc      load_x_unknown
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
        or      byte ptr [di+U_FLAGS], UF_EXFAT
        clc
load_x_done:
        ret
load_x_unknown:
        mov     al, ERR_UNKNOWN_MEDIA
load_x_failed:
        stc
        ret
load_volume_x endp

; sector_buf is an exFAT boot sector with 512-byte sectors? ZF set if so.
is_exfat_boot proc near
        cmp     word ptr [sector_buf+3], 'XE'
        jne     is_exfat_done
        cmp     word ptr [sector_buf+5], 'AF'
        jne     is_exfat_done
        cmp     word ptr [sector_buf+7], ' T'
        jne     is_exfat_done
        cmp     word ptr [sector_buf+9], '  '
        jne     is_exfat_done
        cmp     word ptr [sector_buf+510], 0AA55h
        jne     is_exfat_done
        cmp     byte ptr [sector_buf+108], 9
is_exfat_done:
        ret
is_exfat_boot endp

; Finds an exFAT volume on DI's unit: CF clear, U_START and U_XLEN set.
exfat_detect proc near
        mov     word ptr [xfer_buffer], offset sector_buf
        mov     word ptr [xfer_buffer+2], cs
        xor     ax, ax
        xor     dx, dx
        mov     cx, 1
        call    read_sectors
        jnc     exfat_sector0
        jmp     exfat_none
exfat_sector0:
        xor     ax, ax
        xor     dx, dx
        call    is_exfat_boot
        je      exfat_found
        cmp     word ptr [sector_buf+510], 0AA55h
        jne     exfat_none
        ; the starts of the partitions of type 07h
        push    di
        push    es
        push    cs
        pop     es
        mov     si, offset sector_buf+1BEh
        mov     di, offset exfat_starts
        mov     cx, 4
exfat_entries:
        xor     ax, ax
        xor     dx, dx
        cmp     byte ptr [si+4], 07h
        jne     exfat_entry
        mov     ax, word ptr [si+8]
        mov     dx, word ptr [si+10]
exfat_entry:
        stosw
        xchg    ax, dx
        stosw
        add     si, 16
        loop    exfat_entries
        pop     es
        pop     di
        mov     si, offset exfat_starts
exfat_next_part:
        cmp     si, offset exfat_starts+16
        jae     exfat_none
        mov     ax, word ptr [si]
        mov     dx, word ptr [si+2]
        add     si, 4
        mov     bx, ax
        or      bx, dx
        jz      exfat_next_part
        push    ax
        push    dx
        push    si
        mov     cx, 1
        call    read_sectors
        pop     si
        pop     dx
        pop     ax
        jc      exfat_next_part
        call    is_exfat_boot
        jne     exfat_next_part
exfat_found:
        mov     word ptr [di+U_START], ax
        mov     word ptr [di+U_START+2], dx
        mov     ax, word ptr [sector_buf+72]
        mov     dx, word ptr [sector_buf+74]
        mov     bx, word ptr [sector_buf+76]
        or      bx, word ptr [sector_buf+78]
        jz      exfat_length
        mov     ax, 0FFFFh
        mov     dx, ax
exfat_length:
        mov     word ptr [di+U_XLEN], ax
        mov     word ptr [di+U_XLEN+2], dx
        clc
        ret
exfat_none:
        stc
        ret
exfat_detect endp

; READ, WRITE on an exFAT unit (DI): without EXFAT.SYS unknown media; with
; it, DOS sees the placeholder disk empty (zeros) and write-protected until
; EXFAT.SYS has the letter.  ES:BX request.
exfat_rw proc near
        mov     ax, word ptr [exfat_callback]
        or      ax, word ptr [exfat_callback+2]
        jnz     exfat_rw_placeholder
        mov     al, ERR_UNKNOWN_MEDIA
        jmp     short exfat_rw_error
exfat_rw_placeholder:
        mov     al, ERR_WRITE_PROTECT
        cmp     byte ptr [rw_opcode], 28h
        jne     exfat_rw_error
        push    es
        push    di
        mov     dx, word ptr es:[bx+RH_COUNT]
        les     di, dword ptr es:[bx+RH_BUFFER]
        xor     ax, ax
exfat_rw_sector:
        or      dx, dx
        jz      exfat_rw_zeroed
        mov     cx, 256
        rep     stosw
        mov     cx, es                          ; next sector: 32 paragraphs on
        add     cx, 32
        mov     es, cx
        sub     di, 512
        dec     dx
        jmp     exfat_rw_sector
exfat_rw_zeroed:
        pop     di
        pop     es
        clc
        ret
exfat_rw_error:
        mov     word ptr es:[bx+RH_COUNT], 0
        stc
        ret
exfat_rw endp

; BUILD BPB found exFAT on DI's unit: tell EXFAT.SYS.
exfat_notify proc near
        mov     ax, word ptr [exfat_callback]
        or      ax, word ptr [exfat_callback+2]
        jz      exfat_notify_done
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        mov     ax, di
        sub     ax, offset unit_table
        mov     cl, UNIT_SIZE
        div     cl
        mov     dx, cs
        call    dword ptr [exfat_callback]
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
exfat_notify_done:
        ret
exfat_notify endp

exfat_service proc far
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
        mov     word ptr [exfat_packet], bx
        mov     word ptr [exfat_packet+2], es
        mov     word ptr [caller_ss], ss
        mov     word ptr [caller_sp], sp
        cli
        push    cs
        pop     ss
        mov     sp, offset driver_stack_top
        sti
        mov     word ptr es:[bx+PK_STATUS], 0
        cmp     byte ptr es:[bx+PK_FUNC], 3
        jne     svc_unit
        mov     ax, word ptr es:[bx+PK_BUFFER]
        mov     word ptr [exfat_callback], ax
        mov     ax, word ptr es:[bx+PK_BUFFER+2]
        mov     word ptr [exfat_callback+2], ax
        jmp     svc_done
svc_unit:
        mov     al, byte ptr es:[bx+PK_UNIT]
        cmp     al, byte ptr [unit_count]
        jb      svc_unit_ok
        mov     al, ERR_UNKNOWN_UNIT
        jmp     svc_error
svc_unit_ok:
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
        mov     al, byte ptr es:[bx+PK_FUNC]
        cmp     al, 8
        ja      svc_unknown
        xor     ah, ah
        mov     si, ax
        shl     si, 1
        or      al, al
        jz      svc_go
        test    byte ptr [di+U_FLAGS], UF_RAW_ACTIVE
        jz      svc_go
        mov     al, ERR_NOT_READY
        jmp     svc_error
svc_go:
        jmp     word ptr [svc_table+si]
svc_table       dw      svc_info, svc_read, svc_check, svc_unknown, svc_read
                dw      svc_phys, svc_phys, svc_capacity, svc_reload
svc_unknown:
        mov     al, ERR_UNKNOWN_CMD
        jmp     svc_error
svc_capacity:
        ; a changed medium answers NOT READY / UNIT ATTENTION once each
        mov     cx, 3
svc_capacity_tur:
        push    cx
        call    test_unit_ready
        pop     cx
        jnc     svc_capacity_read
        loop    svc_capacity_tur
svc_capacity_read:
        call    block_read_capacity
        jnc     svc_capacity_ok
        jmp     svc_error
svc_capacity_ok:
        les     bx, [exfat_packet]
        mov     ax, word ptr [di+U_CAPACITY]
        mov     word ptr es:[bx+PK_LBA], ax
        mov     ax, word ptr [di+U_CAPACITY+2]
        mov     word ptr es:[bx+PK_LBA+2], ax
        jmp     svc_done
svc_phys:
        mov     cx, word ptr es:[bx+PK_COUNT]
        jcxz    svc_phys_count
        cmp     cx, CHUNK_SECTORS
        ja      svc_phys_count
        mov     ax, word ptr es:[bx+PK_LBA]
        mov     dx, word ptr es:[bx+PK_LBA+2]
        add     ax, cx
        adc     dx, 0
        jc      svc_phys_range
        cmp     dx, word ptr [di+U_CAPACITY+2]
        ja      svc_phys_range
        jb      svc_phys_ok
        cmp     ax, word ptr [di+U_CAPACITY]
        ja      svc_phys_range
svc_phys_ok:
        mov     ax, word ptr es:[bx+PK_BUFFER]
        mov     word ptr [xfer_buffer], ax
        mov     ax, word ptr es:[bx+PK_BUFFER+2]
        mov     word ptr [xfer_buffer+2], ax
        mov     ax, word ptr es:[bx+PK_LBA]
        mov     dx, word ptr es:[bx+PK_LBA+2]
        jmp     svc_opcode
svc_phys_count:
        jmp     svc_bad_count
svc_phys_range:
        jmp     svc_range
svc_info:
        mov     ax, word ptr [di+U_START]
        mov     word ptr es:[bx+PK_LBA], ax
        mov     ax, word ptr [di+U_START+2]
        mov     word ptr es:[bx+PK_LBA+2], ax
        mov     al, byte ptr [di+U_FLAGS]
        xor     ah, ah
        mov     word ptr es:[bx+PK_COUNT], ax
        mov     ax, word ptr [di+U_XLEN]
        mov     word ptr es:[bx+PK_BUFFER], ax
        mov     ax, word ptr [di+U_XLEN+2]
        mov     word ptr es:[bx+PK_BUFFER+2], ax
        mov     al, byte ptr [unit_count]
        xor     ah, ah
        mov     word ptr es:[bx+PK_RESULT], ax
        jmp     svc_done
svc_check:
        mov     word ptr es:[bx+PK_RESULT], 0
        test    byte ptr [di+U_FLAGS], UF_REMOVABLE
        jz      svc_check_done
        call    test_unit_ready
        jnc     svc_check_done
        ; changed or gone: read it again, and tell DOS at its next MEDIA CHECK
        or      byte ptr [di+U_XFLAGS], XF_CHANGED
        call    load_volume_x
        les     bx, [exfat_packet]
        mov     word ptr es:[bx+PK_RESULT], 1
svc_check_done:
        jmp     svc_done
svc_read:
        test    byte ptr [di+U_FLAGS], UF_EXFAT
        jnz     svc_read_unit
        mov     al, ERR_UNKNOWN_MEDIA
        jmp     svc_error
svc_read_unit:
        mov     cx, word ptr es:[bx+PK_COUNT]
        jcxz    svc_bad_count
        cmp     cx, CHUNK_SECTORS
        ja      svc_bad_count
        ; the whole range inside the exFAT volume
        mov     ax, word ptr es:[bx+PK_LBA]
        mov     dx, word ptr es:[bx+PK_LBA+2]
        add     ax, cx
        adc     dx, 0
        jc      svc_range
        cmp     dx, word ptr [di+U_XLEN+2]
        ja      svc_range
        jb      svc_in_range
        cmp     ax, word ptr [di+U_XLEN]
        ja      svc_range
svc_in_range:
        mov     ax, word ptr es:[bx+PK_BUFFER]
        mov     word ptr [xfer_buffer], ax
        mov     ax, word ptr es:[bx+PK_BUFFER+2]
        mov     word ptr [xfer_buffer+2], ax
        mov     ax, word ptr es:[bx+PK_LBA]
        mov     dx, word ptr es:[bx+PK_LBA+2]
        add     ax, word ptr [di+U_START]
        adc     dx, word ptr [di+U_START+2]
        jc      svc_range
svc_opcode:
        mov     byte ptr [xfer_opcode], 28h     ; READ(10)
        cmp     byte ptr es:[bx+PK_FUNC], 4
        je      svc_write
        cmp     byte ptr es:[bx+PK_FUNC], 6
        jne     svc_xfer
svc_write:
        mov     byte ptr [xfer_opcode], 2Ah     ; WRITE(10)
svc_xfer:
        call    xfer_sectors
        jnc     svc_done
        jmp     short svc_error
svc_reload:
        or      byte ptr [di+U_XFLAGS], XF_CHANGED
        call    load_volume_x
        test    byte ptr [di+U_FLAGS], UF_EXFAT
        jz      svc_reloaded
        call    exfat_notify
svc_reloaded:
        les     bx, [exfat_packet]
        mov     al, byte ptr [di+U_FLAGS]
        xor     ah, ah
        mov     word ptr es:[bx+PK_COUNT], ax
        jmp     svc_done
svc_bad_count:
        mov     al, ERR_GENERAL
        jmp     short svc_error
svc_range:
        mov     al, ERR_NOT_FOUND
svc_error:
        les     bx, [exfat_packet]
        xor     ah, ah
        or      ah, 80h
        mov     word ptr es:[bx+PK_STATUS], ax
svc_done:
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
exfat_service endp
