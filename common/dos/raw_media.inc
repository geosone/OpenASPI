; Exclusive physical-media service for tools, not a filesystem entry point.
; A BEGIN-issued token identifies the owner until END; normal block requests
; must not bypass a conflicting raw session. LBAs are physical, not relative
; to the selected partition. Write sessions invalidate cached filesystem data.
; The packet retains driver/sense diagnostics for rescue policy even when DOS
; maps the final error. Category 80h here uses block IOCTL 440Dh and RAW1;
; it is distinct from the character-device OTAP protocol on IOCTL 440Ch.

; OpenASPI removable-media session API, category 80h, minors 0..4.
; 32-byte versioned packet: "RAW1", size WORD=32, token WORD,
; physical LBA DWORD, count WORD, mode WORD (BEGIN: 0 read / 1 write),
; buffer FAR, capacity DWORD, selected FAT volume start/length DWORDs.
; INFO=0 BEGIN=1 READ=2 WRITE=3 END=4. No filesystem is required.
raw_sequence dw 0
raw_minor db 0

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
        call    block_read_capacity
        jnc     raw_capacity_ready
        call    raw_set_error
        ret
raw_capacity_ready:
        call    load_volume
        jnc     raw_volume_ready
        cmp     al, ERR_UNKNOWN_MEDIA
        je      raw_volume_ready
        call    raw_set_error
        stc
        ret
raw_volume_ready:
        cmp     byte ptr [raw_minor], 0
        je      raw_info_output
        mov     ax, 011Eh
        call    medium_control_result
        jnc     raw_prevented
        call    raw_set_error
        ret
; Publish the claim only after hardware PREVENT succeeds. Token zero means
; no owner, so skip it when the 16-bit sequence wraps. The token associates
; subsequent operations with this unit's session; it is not authentication.
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
; READ/WRITE/END require both active state and the matching token. Packet
; bytes 8..15 change meaning between INFO output and data input: address and
; capability information must be cached by the client before filling LBA/count.
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
; Bound the complete count*512 buffer before submission. Reject offset wrap
; and a physical address past real-mode memory; checking only the FAR pointer's
; starting offset would miss a buffer whose final sector crosses the limit.
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
        call    raw_set_error
        ret
raw_transfer_done:
        ret
; END attempts hardware ALLOW once. Even on failure, retire token/raw state
; and invalidate filesystem caches; do not leave an apparently usable session.
; On failed ALLOW the lock count remains, so later code cannot claim a physical
; unlock occurred. Preserve carry/AL while clearing only software session state.
raw_end:
        mov     ax, 001Eh
        call    medium_control_result
        jnc     raw_end_unlocked
        call    raw_set_error
        jmp     short raw_end_failed
raw_end_unlocked:
        mov     byte ptr [di+U_LOCKS], 0
raw_end_failed:
        pushf
        and     byte ptr [di+U_FLAGS], not (UF_RAW_ACTIVE or UF_RAW_WRITE or UF_MEDIA or UF_BPB_OVERRIDE)
        mov     word ptr [di+U_RAW_TOKEN], 0
        popf
        ret
raw_ioctl endp

; DOS kernels map driver errors differently. Return the original driver
; error and checked autosense alongside CF, rather than guessing from AX.
raw_set_error proc near
        mov     byte ptr es:[bp+13], al
        push    ax
        call    aspi_sense
        mov     word ptr es:[bp+14], ax
        pop     ax
        stc
        ret
raw_set_error endp
