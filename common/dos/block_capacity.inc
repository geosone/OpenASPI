; DS=CS, DI selects the unit record; uses the shared execute-SCSI SRB.
; Accept only a checked eight-byte READ CAPACITY(10) reply with sectors of 512,
; 1024 or 2048 bytes (U_SHIFT), no larger than DOS's buffers (sec_shift_max).
; The returned last LBA must be converted to a sector count without wrapping;
; unsupported sizes/overflow fail rather than inventing a usable DOS geometry.

block_capacity_data db 8 dup (0)
block_read_capacity proc near
        mov     al, SRB_DIR_IN
        mov     cl, 10
        call    aspi_prepare
        mov     byte ptr [srb+SRB_CDB], 25h
        mov     word ptr [srb+SRB_BufLen], 8
        mov     word ptr [srb+SRB_BufPointer], offset block_capacity_data
        mov     word ptr [srb+SRB_BufPointer+2], cs
        ; Poison so a short or untouched response cannot look like capacity.
        mov     word ptr [block_capacity_data], 0FFFFh
        mov     word ptr [block_capacity_data+2], 0FFFFh
        mov     word ptr [block_capacity_data+4], 0FFFFh
        mov     word ptr [block_capacity_data+6], 0FFFFh
        call    call_aspi
        call    aspi_result
        jnc     block_capacity_validate
        call    sense_to_doserr
        stc
        ret
block_capacity_validate:
        cmp     word ptr [block_capacity_data+4], 0
        jne     block_capacity_bad
        cmp     byte ptr [block_capacity_data+7], 0
        jne     block_capacity_bad
        ; block length 0200h, 0400h or 0800h: U_SHIFT 0, 1 or 2
        xor     cl, cl
        mov     al, byte ptr [block_capacity_data+6]
block_capacity_shift:
        cmp     al, 2
        je      block_capacity_size
        cmp     cl, MAX_SHIFT
        jae     block_capacity_bad
        test    al, 1
        jnz     block_capacity_bad
        shr     al, 1
        jz      block_capacity_bad
        inc     cl
        jmp     short block_capacity_shift
block_capacity_size:
        ; DOS's buffers were sized at INIT; until then a medium raises it
        cmp     cl, byte ptr [sec_shift_max]
        jbe     block_capacity_fits
        cmp     byte ptr [sec_shift_grow], 0
        je      block_capacity_bad
        mov     byte ptr [sec_shift_max], cl
block_capacity_fits:
        mov     byte ptr [di+U_SHIFT], cl
        mov     ax, word ptr [block_capacity_data+2]
        xchg    al, ah
        mov     dx, word ptr [block_capacity_data]
        xchg    dl, dh
        add     ax, 1
        adc     dx, 0
        jc      block_capacity_bad
        mov     word ptr [di+U_CAPACITY], ax
        mov     word ptr [di+U_CAPACITY+2], dx
        mov     byte ptr [capacity_fresh], 1    ; a load right after: no repeat
        clc
        ret
block_capacity_bad:
        mov     al, ERR_UNKNOWN_MEDIA
        stc
        ret
block_read_capacity endp
