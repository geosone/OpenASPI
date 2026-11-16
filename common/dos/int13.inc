; ASPIDSK /I13: the disks as BIOS hard disks (INT 13h), included by
; blkdrv.inc for ASPIDSK only.
;
; Programs that read disks through the BIOS (NTFSDOS, NTFS4DOS, EXFAT.SYS's
; BIOS back end, disk editors) find no ASPI disk there.  With /I13 every
; disk ASPIDSK takes (also one without a FAT volume) gets a drive number
; after the BIOS hard disks: 80h + the count at 0040:0075, which grows by
; the disks added.  Functions:
;   00h 0Dh reset, 01h status, 02h 03h 04h CHS read/write/verify,
;   08h parameters, 0Ch 47h seek, 10h ready (TEST UNIT READY), 11h
;   recalibrate, 14h diagnostics, 15h type, 41h-44h, 48h extensions
;   (EDD 1.1, packet access); others: 01h, invalid function.
; Disks with 512-byte sectors only, and below 2 TB (READ CAPACITY(10)).
; CHS: 255 heads and 63 sectors (16 heads below 8 MB), at most 1024
; cylinders; LBA reaches the whole disk.  A removable device's capacity is
; read again by 08h, 15h and 48h (a new medium).
; Reads and writes go through xfer_sectors with a unit record of their own
; (i13_unit), at most 64 sectors per command.  A UNIT ATTENTION seen here
; marks the device's DOS units changed, and the command is tried again.
; Not reentrant: a call while a DOS request or another call of this driver
; runs (SS = CS) fails with AAh.

I13_MAX         equ     8
I13_HA          equ     0
I13_TARGET      equ     1
I13_LUN         equ     2
I13_FLAGS       equ     3               ; UF_REMOVABLE
I13_CAP         equ     4               ; dword: sectors
I13_CYLS        equ     8               ; word: CHS cylinders (<= 1024)
I13_HEADS       equ     10
I13_SPT         equ     11
I13_SIZE        equ     12

i13_old         dd      0
i13_base        db      0FFh            ; first drive number
i13_count       db      0
i13_status      db      0               ; of the last call (01h)
i13_table       db      I13_MAX * I13_SIZE dup (0)
i13_unit        db      UNIT_SIZE dup (0)       ; for xfer_sectors
i13_entry_ptr   dw      0
i13_ss          dw      0
i13_sp          dw      0
i13_cf          db      0
r_ax            dw      0
r_bx            dw      0
r_cx            dw      0
r_dx            dw      0
r_si            dw      0
r_di            dw      0
r_ds            dw      0
r_es            dw      0
i13_lba         dd      0
i13_done        dw      0               ; sectors transferred
i13_left        dw      0
i13_buf         dd      0

i13_handler proc far
        cmp     dl, byte ptr cs:[i13_base]
        jb      i13_chain
        push    ax
        mov     al, dl
        sub     al, byte ptr cs:[i13_base]
        cmp     al, byte ptr cs:[i13_count]
        pop     ax
        jb      i13_ours
i13_chain:
        jmp     dword ptr cs:[i13_old]
i13_ours:
        mov     word ptr cs:[r_ax], ax
        mov     word ptr cs:[r_bx], bx
        mov     word ptr cs:[r_cx], cx
        mov     word ptr cs:[r_dx], dx
        mov     word ptr cs:[r_si], si
        mov     word ptr cs:[r_di], di
        mov     word ptr cs:[r_ds], ds
        mov     word ptr cs:[r_es], es
        mov     ax, ss
        mov     bx, cs
        cmp     ax, bx
        jne     i13_switch
        ; inside our own request: the SRB and the stack are in use
        mov     byte ptr cs:[r_ax+1], 0AAh
        mov     byte ptr cs:[i13_cf], 1
        jmp     short i13_return
i13_switch:
        mov     word ptr cs:[i13_ss], ss
        mov     word ptr cs:[i13_sp], sp
        cli
        mov     ss, bx
        mov     sp, offset driver_stack_top
        sti
        push    bp
        mov     ds, bx
        cld
        push    word ptr [unit_ptr]
        push    word ptr [unit_ha]
        push    word ptr [unit_lun]             ; and the byte after it
        mov     al, byte ptr [capacity_fresh]
        mov     ah, byte ptr [aspi_attention]
        push    ax
        mov     byte ptr [aspi_attention], 0
        call    i13_dispatch
        mov     al, 0
        adc     al, 0
        mov     byte ptr [i13_cf], al
        call    i13_latch
        pop     ax
        mov     byte ptr [capacity_fresh], al
        or      byte ptr [aspi_attention], ah
        pop     word ptr [unit_lun]
        pop     word ptr [unit_ha]
        pop     word ptr [unit_ptr]
        pop     bp
        cli
        mov     ss, word ptr [i13_ss]
        mov     sp, word ptr [i13_sp]
        sti
i13_return:
        mov     ax, word ptr cs:[r_ax]
        mov     bx, word ptr cs:[r_bx]
        mov     cx, word ptr cs:[r_cx]
        mov     dx, word ptr cs:[r_dx]
        mov     si, word ptr cs:[r_si]
        mov     di, word ptr cs:[r_di]
        mov     es, word ptr cs:[r_es]
        mov     ds, word ptr cs:[r_ds]
        push    bp
        mov     bp, sp
        and     word ptr [bp+6], 0FFFEh         ; the caller's CF
        cmp     byte ptr cs:[i13_cf], 0
        je      i13_flags_done
        or      word ptr [bp+6], 1
i13_flags_done:
        pop     bp
        iret
i13_handler endp

; A UNIT ATTENTION seen by this call: the medium of a removable device may
; have changed, so its DOS units read it again.
i13_latch proc near
        cmp     byte ptr [aspi_attention], 0
        je      i13_latch_done
        mov     byte ptr [aspi_attention], 0
        test    byte ptr [i13_unit+U_FLAGS], UF_REMOVABLE
        jz      i13_latch_done
        push    di
        mov     di, offset i13_unit
        call    siblings_changed
        pop     di
i13_latch_done:
        ret
i13_latch endp

; -> CF and r_ax+1 (AH) = status; the other result registers in r_*.
i13_dispatch proc near
        ; the device: i13_table entry SI, unit record DI
        mov     al, byte ptr [r_dx]
        sub     al, byte ptr [i13_base]
        mov     ah, I13_SIZE
        mul     ah
        add     ax, offset i13_table
        mov     si, ax
        mov     word ptr [i13_entry_ptr], si
        mov     di, offset i13_unit
        mov     word ptr [unit_ptr], di
        mov     al, byte ptr [si+I13_HA]
        mov     byte ptr [unit_ha], al
        mov     byte ptr [di+U_HA], al
        mov     al, byte ptr [si+I13_TARGET]
        mov     byte ptr [unit_target], al
        mov     byte ptr [di+U_TARGET], al
        mov     al, byte ptr [si+I13_LUN]
        mov     byte ptr [unit_lun], al
        mov     byte ptr [di+U_LUN], al
        mov     al, byte ptr [si+I13_FLAGS]
        mov     byte ptr [di+U_FLAGS], al
        mov     byte ptr [di+U_XFLAGS], 0
        mov     byte ptr [di+U_SHIFT], 0
        mov     al, byte ptr [r_ax+1]
        mov     bx, offset i13_functions
i13_find:
        cmp     byte ptr [bx], 0FFh
        je      i13_bad_function
        cmp     al, byte ptr [bx]
        je      i13_found
        add     bx, 3
        jmp     short i13_find
i13_found:
        call    word ptr [bx+1]
        jmp     short i13_result
i13_bad_function:
        mov     al, 01h
        stc
i13_result:
        ; AL = status, CF
        mov     byte ptr [r_ax+1], al
        mov     byte ptr [i13_status], al
        ret
i13_dispatch endp

i13_functions   db      00h
                dw      i13_ok
                db      01h
                dw      i13_get_status
                db      02h
                dw      i13_chs
                db      03h
                dw      i13_chs
                db      04h
                dw      i13_chs
                db      08h
                dw      i13_params
                db      0Ch
                dw      i13_ok
                db      0Dh
                dw      i13_ok
                db      10h
                dw      i13_ready
                db      11h
                dw      i13_ok
                db      14h
                dw      i13_ok
                db      15h
                dw      i13_type
                db      41h
                dw      i13_check_ext
                db      42h
                dw      i13_ext
                db      43h
                dw      i13_ext
                db      44h
                dw      i13_ext
                db      47h
                dw      i13_ok
                db      48h
                dw      i13_ext_params
                db      0FFh

i13_ok proc near
        xor     al, al
        clc
        ret
i13_ok endp

i13_get_status proc near
        mov     al, byte ptr [i13_status]
        mov     byte ptr [r_ax], al
        xor     al, al
        clc
        ret
i13_get_status endp

i13_ready proc near
        call    i13_tur
        jnc     i13_ok
        mov     al, 0AAh
        ret
i13_ready endp

; TEST UNIT READY, up to three times (a UNIT ATTENTION, a medium coming
; ready). CF on failure.
i13_tur proc near
        mov     cx, 3
i13_tur_next:
        push    cx
        call    test_unit_ready
        pop     cx
        jnc     i13_tur_done
        loop    i13_tur_next
        stc
i13_tur_done:
        ret
i13_tur endp

; A removable device: TEST UNIT READY and READ CAPACITY again.  CF and
; AL = status when there is no usable medium.
i13_refresh proc near
        test    byte ptr [si+I13_FLAGS], UF_REMOVABLE
        jz      i13_refresh_done
        call    i13_tur
        call    i13_capacity
        jnc     i13_refresh_done
        mov     al, 0AAh
        ret
i13_refresh_done:
        clc
        ret
i13_refresh endp

; READ CAPACITY of the device of DI/SI into the i13_table entry, and its
; CHS geometry.  CF when it fails or the sectors are not 512 bytes.
i13_capacity proc near
        mov     word ptr [si+I13_CAP], 0
        mov     word ptr [si+I13_CAP+2], 0
        mov     word ptr [si+I13_CYLS], 0
        mov     byte ptr [si+I13_HEADS], 16
        mov     byte ptr [si+I13_SPT], 63
        mov     al, byte ptr [sec_shift_grow]
        push    ax
        mov     byte ptr [sec_shift_grow], 0
        call    block_read_capacity
        pop     ax
        mov     byte ptr [sec_shift_grow], al
        jc      i13_capacity_failed
        cmp     byte ptr [di+U_SHIFT], 0
        jne     i13_capacity_failed
        mov     ax, word ptr [di+U_CAPACITY]
        mov     dx, word ptr [di+U_CAPACITY+2]
        mov     word ptr [si+I13_CAP], ax
        mov     word ptr [si+I13_CAP+2], dx
        ; 255 heads x 63 sectors = 16065 per cylinder from 8 MB on
        mov     bx, 16 * 63
        or      dx, dx
        jnz     i13_capacity_big
        cmp     ax, 16065
        jb      i13_capacity_cyls
i13_capacity_big:
        mov     byte ptr [si+I13_HEADS], 255
        mov     bx, 16065
i13_capacity_cyls:
        mov     cx, 1024
        cmp     dx, bx                          ; quotient above 65535
        jae     i13_capacity_store
        div     bx
        cmp     ax, cx
        jae     i13_capacity_store
        mov     cx, ax
        or      cx, cx
        jnz     i13_capacity_store
        inc     cx
i13_capacity_store:
        mov     word ptr [si+I13_CYLS], cx
        mov     byte ptr [di+U_SHIFT], 0
        clc
        ret
i13_capacity_failed:
        mov     byte ptr [di+U_SHIFT], 0
        stc
        ret
i13_capacity endp

; 08h: CH/CL cylinders and sectors, DH last head, DL hard disk count
i13_params proc near
        call    i13_refresh
        jc      i13_params_done
        mov     cx, word ptr [si+I13_CYLS]
        dec     cx                              ; the last cylinder
        xchg    cl, ch
        ror     cl, 1
        ror     cl, 1
        and     cl, 0C0h
        or      cl, byte ptr [si+I13_SPT]
        mov     word ptr [r_cx], cx
        mov     al, byte ptr [si+I13_HEADS]
        dec     al
        mov     byte ptr [r_dx+1], al
        push    es
        mov     ax, 40h
        mov     es, ax
        mov     al, byte ptr es:[75h]
        pop     es
        mov     byte ptr [r_dx], al
        xor     al, al
        mov     byte ptr [r_ax], al
        clc
i13_params_done:
        ret
i13_params endp

; 15h: AH = 03h (hard disk), CX:DX sectors
i13_type proc near
        call    i13_refresh
        jc      i13_type_done
        mov     ax, word ptr [si+I13_CAP+2]
        mov     word ptr [r_cx], ax
        mov     ax, word ptr [si+I13_CAP]
        mov     word ptr [r_dx], ax
        mov     al, 03h
        clc
i13_type_done:
        ret
i13_type endp

; 41h: BX = 55AAh -> AA55h, AH = 21h (EDD 1.1), CX = 1 (packet access)
i13_check_ext proc near
        cmp     word ptr [r_bx], 55AAh
        jne     i13_check_bad
        mov     word ptr [r_bx], 0AA55h
        mov     word ptr [r_cx], 1
        mov     al, 21h
        clc
        ret
i13_check_bad:
        mov     al, 01h
        stc
        ret
i13_check_ext endp

; 48h: the result buffer at DS:SI
i13_ext_params proc near
        call    i13_refresh
        jc      i13_ext_params_done
        push    es
        mov     es, word ptr [r_ds]
        mov     bx, word ptr [r_si]
        cmp     word ptr es:[bx], 1Ah
        jb      i13_ext_params_bad
        mov     ax, 1Ah
        cmp     word ptr es:[bx], 1Eh
        jb      i13_ext_params_size
        mov     word ptr es:[bx+1Ah], 0FFFFh    ; no device parameter table
        mov     word ptr es:[bx+1Ch], 0FFFFh
        mov     ax, 1Eh
i13_ext_params_size:
        mov     word ptr es:[bx], ax
        mov     word ptr es:[bx+2], 0002h       ; the CHS values are valid
        mov     ax, word ptr [si+I13_CYLS]
        mov     word ptr es:[bx+4], ax
        xor     ax, ax
        mov     word ptr es:[bx+6], ax
        mov     word ptr es:[bx+0Ah], ax
        mov     word ptr es:[bx+0Eh], ax
        mov     word ptr es:[bx+14h], ax
        mov     word ptr es:[bx+16h], ax
        mov     al, byte ptr [si+I13_HEADS]
        mov     word ptr es:[bx+8], ax
        mov     al, byte ptr [si+I13_SPT]
        mov     word ptr es:[bx+0Ch], ax
        mov     ax, word ptr [si+I13_CAP]
        mov     word ptr es:[bx+10h], ax
        mov     ax, word ptr [si+I13_CAP+2]
        mov     word ptr es:[bx+12h], ax
        mov     word ptr es:[bx+18h], 512
        pop     es
        xor     al, al
        clc
        ret
i13_ext_params_bad:
        pop     es
        mov     al, 01h
        stc
i13_ext_params_done:
        ret
i13_ext_params endp

; 02h 03h 04h: AL sectors, CH/CL cylinder and sector, DH head, ES:BX buffer
i13_chs proc near
        mov     al, byte ptr [r_ax]
        xor     ah, ah
        or      ax, ax
        jz      i13_chs_bad
        mov     word ptr [i13_left], ax
        mov     cl, byte ptr [r_cx]
        and     cl, 3Fh
        jz      i13_chs_bad
        cmp     cl, byte ptr [si+I13_SPT]
        ja      i13_chs_bad
        mov     al, byte ptr [r_dx+1]
        cmp     al, byte ptr [si+I13_HEADS]
        jae     i13_chs_bad
        ; LBA = (cylinder * heads + head) * spt + sector - 1
        mov     al, byte ptr [r_cx]
        xor     ah, ah
        shl     ax, 1
        shl     ax, 1
        mov     al, byte ptr [r_cx+1]           ; AX = 10-bit cylinder
        mov     bl, byte ptr [si+I13_HEADS]
        xor     bh, bh
        mul     bx                              ; DX:AX
        mov     bl, byte ptr [r_dx+1]
        add     ax, bx
        adc     dx, 0
        mov     bl, byte ptr [si+I13_SPT]
        push    ax
        mov     ax, dx
        mul     bx
        mov     cx, ax                          ; high part
        pop     ax
        mul     bx
        add     dx, cx
        mov     cl, byte ptr [r_cx]
        and     cx, 3Fh
        dec     cx
        add     ax, cx
        adc     dx, 0
        mov     word ptr [i13_lba], ax
        mov     word ptr [i13_lba+2], dx
        mov     ax, word ptr [r_bx]
        mov     word ptr [i13_buf], ax
        mov     ax, word ptr [r_es]
        mov     word ptr [i13_buf+2], ax
        mov     al, byte ptr [r_ax+1]
        sub     al, 02h                         ; 0 read, 1 write, 2 verify
        call    i13_transfer
        pushf
        push    ax
        mov     al, byte ptr [i13_done]
        mov     byte ptr [r_ax], al
        pop     ax
        popf
        ret
i13_chs_bad:
        mov     byte ptr [r_ax], 0
        mov     al, 01h
        stc
        ret
i13_chs endp

; 42h 43h 44h: the address packet at DS:SI
i13_ext proc near
        push    es
        mov     es, word ptr [r_ds]
        mov     bx, word ptr [r_si]
        cmp     byte ptr es:[bx], 10h
        jb      i13_ext_bad
        mov     ax, word ptr es:[bx+0Ch]        ; LBA above 32 bits
        or      ax, word ptr es:[bx+0Eh]
        jnz     i13_ext_bad
        mov     ax, word ptr es:[bx+4]
        mov     word ptr [i13_buf], ax
        mov     ax, word ptr es:[bx+6]
        mov     word ptr [i13_buf+2], ax
        and     ax, word ptr es:[bx+4]
        cmp     ax, 0FFFFh                      ; a 64-bit flat address
        je      i13_ext_bad
        mov     ax, word ptr es:[bx+8]
        mov     word ptr [i13_lba], ax
        mov     ax, word ptr es:[bx+0Ah]
        mov     word ptr [i13_lba+2], ax
        mov     ax, word ptr es:[bx+2]
        cmp     ax, 7Fh
        ja      i13_ext_bad
        mov     word ptr [i13_left], ax
        mov     word ptr es:[bx+2], 0
        pop     es
        or      ax, ax
        jz      i13_ok_near
        mov     al, byte ptr [r_ax+1]
        sub     al, 42h
        call    i13_transfer
        pushf
        push    ax
        push    es
        mov     es, word ptr [r_ds]
        mov     bx, word ptr [r_si]
        mov     ax, word ptr [i13_done]
        mov     word ptr es:[bx+2], ax
        pop     es
        pop     ax
        popf
        ret
i13_ok_near:
        jmp     i13_ok
i13_ext_bad:
        pop     es
        mov     al, 01h
        stc
        ret
i13_ext endp

; AL = 0 read, 1 write, 2 verify: [i13_left] sectors from [i13_lba] at
; [i13_buf]; [i13_done] counts them.  -> CF and AL = status.
i13_transfer proc near
        mov     word ptr [i13_done], 0
        mov     ah, 28h
        cmp     al, 1
        jb      i13_opcode
        mov     ah, 2Ah
        je      i13_opcode
        mov     ah, 2Fh
i13_opcode:
        mov     byte ptr [xfer_opcode], ah
i13_chunk:
        mov     cx, word ptr [i13_left]
        or      cx, cx
        jnz     i13_chunk_go
        xor     al, al
        clc
        ret
i13_chunk_go:
        cmp     cx, CHUNK_SECTORS
        jbe     i13_chunk_size
        mov     cx, CHUNK_SECTORS
i13_chunk_size:
        ; the buffer as segment:offset with an offset below 16
        mov     ax, word ptr [i13_buf]
        mov     dx, ax
        and     ax, 0Fh
        mov     word ptr [xfer_buffer], ax
        shr     dx, 1
        shr     dx, 1
        shr     dx, 1
        shr     dx, 1
        add     dx, word ptr [i13_buf+2]
        mov     word ptr [xfer_buffer+2], dx
        mov     word ptr [i13_buf], ax
        mov     word ptr [i13_buf+2], dx
        mov     bx, 3                           ; tries
i13_try:
        push    bx
        push    cx
        mov     ax, word ptr [i13_lba]
        mov     dx, word ptr [i13_lba+2]
        call    xfer_sectors
        pop     cx
        pop     bx
        jnc     i13_chunk_ok
        cmp     al, 0Fh                         ; UNIT ATTENTION
        je      i13_retry
        cmp     al, ERR_NOT_READY
        jne     i13_failed
i13_retry:
        dec     bx
        jz      i13_failed
        push    bx
        push    cx
        call    test_unit_ready
        pop     cx
        pop     bx
        jmp     short i13_try
i13_chunk_ok:
        add     word ptr [i13_done], cx
        sub     word ptr [i13_left], cx
        add     word ptr [i13_lba], cx
        adc     word ptr [i13_lba+2], 0
        cmp     byte ptr [xfer_opcode], 2Fh
        je      i13_chunk
        mov     ax, cx                          ; 512 bytes each
        mov     cl, 5
        shl     ax, cl                          ; paragraphs
        add     word ptr [i13_buf+2], ax
        jmp     i13_chunk
i13_failed:
        ; DOS driver error -> BIOS status
        mov     ah, 03h                         ; write protected
        cmp     al, ERR_WRITE_PROTECT
        je      i13_failed_status
        mov     ah, 0AAh                        ; not ready
        cmp     al, ERR_NOT_READY
        je      i13_failed_status
        mov     ah, 06h                         ; medium changed
        cmp     al, 0Fh
        je      i13_failed_status
        mov     ah, 04h                         ; sector not found
        cmp     al, ERR_NOT_FOUND
        je      i13_failed_status
        mov     ah, 10h                         ; read error
        cmp     byte ptr [xfer_opcode], 2Ah
        jne     i13_failed_status
        mov     ah, 0CCh                        ; write fault
i13_failed_status:
        mov     al, ah
        stc
        ret
i13_transfer endp

i13_end label byte
