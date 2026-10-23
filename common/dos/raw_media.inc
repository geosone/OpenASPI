; OpenASPI removable-media session API, category 80h, minors 0..4.
; 32-byte versioned packet: "RAW1", size WORD=32, token WORD,
; physical LBA DWORD, count WORD, mode WORD (BEGIN: 0 read / 1 write),
; buffer FAR, capacity DWORD, selected FAT volume start/length DWORDs.
; INFO=0 BEGIN=1 READ=2 WRITE=3 END=4. No filesystem is required.
raw_sequence dw 0
raw_minor db 0
raw_capacity_data db 8 dup (0)

raw_ioctl proc near
        mov     al, byte ptr es:[bx+RH_IOCTL_MINOR]
        mov     byte ptr [raw_minor], al
        les     bp, dword ptr es:[bx+RH_IOCTL_PARAM]
        cmp     bp, 0FFE0h
        ja      raw_header_bad
        mov     ax, es
        or      ax, bp
        jz      raw_header_bad
        cmp     word ptr es:[bp], 4152h
        jne     raw_header_bad
        cmp     word ptr es:[bp+2], 3157h
        jne     raw_header_bad
        cmp     word ptr es:[bp+4], 32
        je      raw_header_ok
raw_header_bad:
        jmp     raw_bad_packet
raw_header_ok:
        mov     di, word ptr [unit_ptr]
        mov     al, byte ptr [raw_minor]
        cmp     al, 1
        jbe     raw_info_begin
        jmp     raw_session
raw_info_begin:
        test    byte ptr [di+U_FLAGS], UF_RAW_ACTIVE
        jz      raw_not_active
        jmp     raw_busy
raw_not_active:
        cmp     word ptr es:[bp+14], 1
        ja      raw_header_bad
        cmp     al, 0
        je      raw_info
        cmp     byte ptr [di+U_LOCKS], 0
        je      raw_info
        jmp     raw_busy
raw_info:
        call    raw_read_capacity
        jnc     raw_capacity_ready
        ret
raw_capacity_ready:
        call    load_volume
        jnc     raw_volume_ready
        cmp     al, ERR_UNKNOWN_MEDIA
        je      raw_volume_ready
        stc
        ret
raw_volume_ready:
        cmp     byte ptr [raw_minor], 0
        je      raw_info_output
        mov     ax, 011Eh
        call    medium_control_result
        jnc     raw_prevented
        ret
raw_prevented:
        mov     byte ptr [di+U_LOCKS], 1
        inc     word ptr [raw_sequence]
        jnz     raw_token_ready
        inc     word ptr [raw_sequence]
raw_token_ready:
        mov     ax, word ptr [raw_sequence]
        mov     word ptr [di+U_RAW_TOKEN], ax
        or      byte ptr [di+U_FLAGS], UF_RAW_ACTIVE
        test    word ptr es:[bp+14], 1
        jz      raw_info_output
        or      byte ptr [di+U_FLAGS], UF_RAW_WRITE
raw_info_output:
        mov     al, byte ptr [unit_ha]
        mov     byte ptr es:[bp+8], al
        mov     al, byte ptr [unit_target]
        mov     byte ptr es:[bp+9], al
        mov     al, byte ptr [unit_lun]
        mov     byte ptr es:[bp+10], al
        mov     al, byte ptr [fat32_enabled]
        mov     byte ptr es:[bp+11], al
        mov     ax, word ptr [di+U_RAW_TOKEN]
        mov     word ptr es:[bp+6], ax
        mov     ax, word ptr [di+U_CAPACITY]
        mov     word ptr es:[bp+20], ax
        mov     ax, word ptr [di+U_CAPACITY+2]
        mov     word ptr es:[bp+22], ax
        xor     ax, ax
        mov     word ptr es:[bp+24], ax
        mov     word ptr es:[bp+26], ax
        mov     word ptr es:[bp+28], ax
        mov     word ptr es:[bp+30], ax
        test    byte ptr [di+U_FLAGS], UF_MEDIA
        jz      raw_success
        mov     ax, word ptr [di+U_START]
        mov     word ptr es:[bp+24], ax
        mov     ax, word ptr [di+U_START+2]
        mov     word ptr es:[bp+26], ax
        mov     ax, word ptr [di+U_BPB+BPB_TOTAL16]
        xor     dx, dx
        or      ax, ax
        jnz     raw_volume_length
        mov     ax, word ptr [di+U_BPB+BPB_TOTAL32]
        mov     dx, word ptr [di+U_BPB+BPB_TOTAL32+2]
raw_volume_length:
        mov     word ptr es:[bp+28], ax
        mov     word ptr es:[bp+30], dx
raw_success:
        clc
raw_return:
        ret
raw_bad_packet:
        mov     al, ERR_UNKNOWN_CMD
raw_return_error:
        stc
        ret
raw_busy:
        mov     al, ERR_NOT_READY
        stc
        ret
raw_session:
        test    byte ptr [di+U_FLAGS], UF_RAW_ACTIVE
        jz      raw_busy
        mov     ax, word ptr es:[bp+6]
        cmp     ax, word ptr [di+U_RAW_TOKEN]
        jne     raw_busy
        cmp     byte ptr [raw_minor], 4
        jne     raw_data_request
        jmp     raw_end
raw_data_request:
        cmp     byte ptr [raw_minor], 3
        jne     raw_read
        test    byte ptr [di+U_FLAGS], UF_RAW_WRITE
        jz      raw_bad_packet
raw_read:
        mov     cx, word ptr es:[bp+12]
        jcxz    raw_bad_packet
        cmp     cx, 32
        ja      raw_bad_packet
        mov     ax, word ptr es:[bp+8]
        mov     dx, word ptr es:[bp+10]
        add     ax, cx
        adc     dx, 0
        jc      raw_bad_packet
        cmp     dx, word ptr [di+U_CAPACITY+2]
        ja      raw_bad_packet
        jb      raw_range_ok
        cmp     ax, word ptr [di+U_CAPACITY]
        ja      raw_bad_packet
raw_range_ok:
        mov     ax, word ptr es:[bp+16]
        mov     dx, word ptr es:[bp+18]
        or      dx, ax
        jz      raw_bad_packet
        push    cx
        mov     cl, 9
        mov     dx, word ptr es:[bp+12]
        shl     dx, cl
        dec     dx
        add     dx, ax
        pop     cx
        jc      raw_bad_packet
        push    ax
        push    cx
        mov     cl, 4
        shr     dx, cl
        add     dx, word ptr es:[bp+18]
        pop     cx
        pop     ax
        jc      raw_bad_packet                  ; physical address beyond 1 MB
        mov     word ptr [xfer_buffer], ax
        mov     ax, word ptr es:[bp+18]
        mov     word ptr [xfer_buffer+2], ax
        mov     byte ptr [xfer_opcode], 28h
        cmp     byte ptr [raw_minor], 3
        jne     raw_transfer
        mov     byte ptr [xfer_opcode], 2Ah
raw_transfer:
        mov     ax, word ptr es:[bp+8]
        mov     dx, word ptr es:[bp+10]
        call    xfer_sectors
        jnc     raw_transfer_done
        push    ax
        xor     ax, ax
        cmp     byte ptr [srb+SRB_Status], SS_ERR
        jne     raw_transfer_error_info
        cmp     byte ptr [srb+SRB_HaStat], 0
        jne     raw_transfer_error_info
        cmp     byte ptr [srb+SRB_TargStat], 2
        jne     raw_transfer_error_info
        mov     al, byte ptr [srb+SRB_CDB+10]
        and     al, 7Fh
        cmp     al, 70h
        je      raw_transfer_sense
        cmp     al, 71h
        jne     raw_transfer_no_sense
raw_transfer_sense:
        mov     al, byte ptr [srb+SRB_CDB+12]
        and     al, 0Fh
        mov     ah, byte ptr [srb+SRB_CDB+22]
        jmp     short raw_transfer_error_info
raw_transfer_no_sense:
        xor     ax, ax
raw_transfer_error_info:
        mov     word ptr es:[bp+14], ax
        pop     ax
        stc
raw_transfer_done:
        ret
raw_end:
        mov     ax, 001Eh
        call    medium_control_result
        jc      raw_end_failed
        mov     byte ptr [di+U_LOCKS], 0
raw_end_failed:
        pushf
        and     byte ptr [di+U_FLAGS], not (UF_RAW_ACTIVE or UF_RAW_WRITE or UF_MEDIA)
        mov     word ptr [di+U_RAW_TOKEN], 0
        popf
        ret
raw_ioctl endp

raw_read_capacity proc near
        mov     al, SRB_DIR_IN
        mov     cl, 10
        call    aspi_prepare
        mov     byte ptr [srb+SRB_CDB], 25h
        mov     word ptr [srb+SRB_BufLen], 8
        mov     word ptr [srb+SRB_BufPointer], offset raw_capacity_data
        mov     word ptr [srb+SRB_BufPointer+2], cs
        ; Poison so a short or untouched response cannot look like capacity.
        mov     word ptr [raw_capacity_data], 0FFFFh
        mov     word ptr [raw_capacity_data+2], 0FFFFh
        mov     word ptr [raw_capacity_data+4], 0FFFFh
        mov     word ptr [raw_capacity_data+6], 0FFFFh
        call    call_aspi
        call    aspi_result
        jnc     raw_capacity_validate
        call    sense_to_doserr
        stc
        ret
raw_capacity_validate:
        cmp     word ptr [raw_capacity_data+4], 0
        jne     raw_capacity_bad
        cmp     word ptr [raw_capacity_data+6], 2
        jne     raw_capacity_bad
        mov     ax, word ptr [raw_capacity_data+2]
        xchg    al, ah
        mov     dx, word ptr [raw_capacity_data]
        xchg    dl, dh
        add     ax, 1
        adc     dx, 0
        jc      raw_capacity_bad
        mov     word ptr [di+U_CAPACITY], ax
        mov     word ptr [di+U_CAPACITY+2], dx
        clc
        ret
raw_capacity_bad:
        mov     al, ERR_UNKNOWN_MEDIA
        stc
        ret
raw_read_capacity endp
