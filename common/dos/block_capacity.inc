; DS=CS, DI selects the unit record; uses the shared execute-SCSI SRB.
; Accept only a checked eight-byte READ CAPACITY(10) reply with 512-byte sectors.
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
        cmp     word ptr [block_capacity_data+6], 2
        jne     block_capacity_bad
        mov     ax, word ptr [block_capacity_data+2]
        xchg    al, ah
        mov     dx, word ptr [block_capacity_data]
        xchg    dl, dh
        add     ax, 1
        adc     dx, 0
        jc      block_capacity_bad
        mov     word ptr [di+U_CAPACITY], ax
        mov     word ptr [di+U_CAPACITY+2], dx
        clc
        ret
block_capacity_bad:
        mov     al, ERR_UNKNOWN_MEDIA
        stc
        ret
block_read_capacity endp
