; ASPIFDD generic IOCTL 42h (format and verify track) and 68h (sense media
; type), category 08h. See docs/block-format.md.
;
; A block device has no tracks of its own; FORMAT UNIT formats the whole
; medium. So 42h for the first track (cylinder 0, head 0) formats the whole
; medium to the size of the current BPB (the one set with 40h, else the
; medium's, else the installation default), and every 42h verifies its
; tracks with VERIFY(10). The size must be one READ FORMAT CAPACITIES lists.
; Track addresses are device-absolute, as for 41h/61h.
;
; Two FORMAT UNIT forms (U_XFLAGS XF_UFI, from the INQUIRY name at INIT):
;   LS-120/240, SuperDisk (SFF-8070i): 12-byte CDB 04 17 .. 00 0C, list
;     header 00 A2 00 08 (FOV, DCRT, IMMED) + capacity descriptor
;     (blocks, 00, 000200h), as Linux ide-floppy sends it
;   others (SBC): 6-byte CDB 04 10, list header 00 02 00 00 (IMMED): the
;     device's own format of its current capacity, which must then be the
;     requested size
; With IMMED the drive returns at once; TEST UNIT READY is asked once per
; timer tick while it reports "not ready, operation in progress" (02/04),
; at most about an hour. FORMAT UNIT is never repeated.

XF_UFI          equ     04h             ; SFF-8070i FORMAT UNIT (LS-120)

fmt_packet      db      7 dup (0)
fmt_argument    dd      0
fmt_bpb         dw      0               ; BPB the geometry comes from
fmt_total       dd      0               ; sectors to format to
fmt_lba         dd      0
fmt_count       dw      0
fmt_param       db      12 dup (0)

ufi_models      db      'LS-120', 0, 'LS-240', 0, 'SUPERDISK', 0, 0

; INIT: XF_UFI for an LS-120 class drive (inquiry_data of DI's unit)
format_profile proc near
        push    si
        mov     si, offset ufi_models
        call    inquiry_has_model
        pop     si
        jc      format_profile_done
        or      byte ptr [di+U_XFLAGS], XF_UFI
format_profile_done:
        ret
format_profile endp

FM_CHECK macro condition, failure
        local okay
        condition okay
        jmp failure
okay:
endm

; 42h. ES:BX request, DS=CS.
ioctl_format proc near
        les     bp, dword ptr es:[bx+RH_IOCTL_PARAM]
        mov     word ptr [fmt_argument], bp
        mov     word ptr [fmt_argument+2], es
        mov     ax, es
        or      ax, bp
        FM_CHECK jnz, fmt_bad_packet
        cmp     bp, 0FFFBh                      ; five bytes
        FM_CHECK jbe, fmt_bad_packet
        mov     al, byte ptr es:[bp]
        test    al, 0FCh                        ; bit 0 status, bit 1 tracks
        FM_CHECK jz, fmt_bad_packet
        mov     cx, 5
        test    al, 2
        jz      fmt_copy
        cmp     bp, 0FFF9h
        FM_CHECK jbe, fmt_bad_packet
        mov     cx, 7
fmt_copy:
        push    ds
        push    es
        pop     ds
        push    cs
        pop     es
        mov     si, bp
        mov     di, offset fmt_packet
        rep     movsb
        pop     ds
        ; as 41h/61h/62h, also with access off (47h): FORMAT turns it on
        ; only after formatting
        mov     di, word ptr [unit_ptr]
        ; the geometry: 40h's BPB, else the medium's, else the default
        lea     ax, [di+U_BPB]
        test    byte ptr [di+U_FLAGS], UF_BPB_OVERRIDE
        jnz     fmt_bpb_ready
        call    load_volume
        lea     ax, [di+U_BPB]
        jnc     fmt_bpb_ready
        lea     ax, [di+U_DEFAULT_BPB]
fmt_bpb_ready:
        mov     word ptr [fmt_bpb], ax
        mov     si, ax
        cmp     word ptr [si+BPB_BYTES], 512
        FM_CHECK je, fmt_geometry_bad
        mov     cx, word ptr [si+BPB_HEADS]
        or      cx, cx
        FM_CHECK jnz, fmt_geometry_bad
        cmp     cx, 256
        FM_CHECK jbe, fmt_geometry_bad
        mov     bx, word ptr [si+BPB_SPT]
        or      bx, bx
        FM_CHECK jnz, fmt_geometry_bad
        cmp     bx, 63
        FM_CHECK jbe, fmt_geometry_bad
        mov     ax, word ptr [si+BPB_TOTAL16]
        xor     dx, dx
        or      ax, ax
        jnz     fmt_total_ready
        mov     ax, word ptr [si+BPB_TOTAL32]
        mov     dx, word ptr [si+BPB_TOTAL32+2]
fmt_total_ready:
        mov     word ptr [fmt_total], ax
        mov     word ptr [fmt_total+2], dx
        or      ax, dx
        FM_CHECK jnz, fmt_geometry_bad
        test    byte ptr [fmt_packet], 1
        jz      fmt_track
        jmp     fmt_status
fmt_track:
        ; the tracks: LBA (cylinder * heads + head) * sectors/track
        cmp     word ptr [fmt_packet+1], cx
        FM_CHECK jb, fmt_range_bad
        mov     ax, 1
        test    byte ptr [fmt_packet], 2
        jz      fmt_count_ready
        mov     ax, word ptr [fmt_packet+5]
        or      ax, ax
        jnz     fmt_count_ready
        clc                                     ; no tracks: nothing to do
        ret
fmt_count_ready:
        mul     bx
        or      dx, dx
        FM_CHECK jz, fmt_range_bad
        mov     word ptr [fmt_count], ax
        mov     ax, word ptr [fmt_packet+3]
        mul     cx
        add     ax, word ptr [fmt_packet+1]
        adc     dx, 0
        FM_CHECK jnc, fmt_range_bad
        mov     si, dx
        mul     bx
        mov     cx, ax
        mov     bp, dx
        mov     ax, si
        mul     bx
        or      dx, dx
        FM_CHECK jz, fmt_range_bad
        add     ax, bp
        FM_CHECK jnc, fmt_range_bad
        mov     word ptr [fmt_lba], cx
        mov     word ptr [fmt_lba+2], ax
        add     cx, word ptr [fmt_count]
        adc     ax, 0
        FM_CHECK jnc, fmt_range_bad
        cmp     ax, word ptr [fmt_total+2]
        FM_CHECK jbe, fmt_range_bad
        jb      fmt_in_volume
        cmp     cx, word ptr [fmt_total]
        FM_CHECK jbe, fmt_range_bad
fmt_in_volume:
        mov     ax, word ptr [fmt_lba]
        or      ax, word ptr [fmt_lba+2]
        FM_CHECK jz, fmt_verify
        ; the first track: the whole medium
        call    format_caps
        cmp     al, 0
        je      fmt_unit
        mov     ah, al
        mov     al, ERR_NOT_READY
        cmp     ah, 3
        FM_CHECK jne, fmt_failed
        mov     al, ERR_UNKNOWN_MEDIA           ; size not offered
        cmp     ah, 2
        FM_CHECK jne, fmt_failed
        mov     al, ERR_UNKNOWN_CMD             ; no READ FORMAT CAPACITIES
        jmp     fmt_failed
fmt_unit:
        call    format_unit
        FM_CHECK jnc, fmt_device_failed
fmt_verify:
        mov     di, word ptr [unit_ptr]
        call    block_read_capacity
        FM_CHECK jnc, fmt_device_failed
        mov     ax, word ptr [fmt_lba]
        mov     dx, word ptr [fmt_lba+2]
        add     ax, word ptr [fmt_count]
        adc     dx, 0
        cmp     dx, word ptr [di+U_CAPACITY+2]
        FM_CHECK jbe, fmt_range_bad
        jb      fmt_verify_next
        cmp     ax, word ptr [di+U_CAPACITY]
        FM_CHECK jbe, fmt_range_bad
fmt_verify_next:
        mov     cx, word ptr [fmt_count]
        cmp     cx, CHUNK_SECTORS
        jbe     fmt_verify_chunk
        mov     cx, CHUNK_SECTORS
fmt_verify_chunk:
        mov     byte ptr [xfer_opcode], 2Fh     ; VERIFY(10), BYTCHK=0
        mov     ax, word ptr [fmt_lba]
        mov     dx, word ptr [fmt_lba+2]
        call    xfer_sectors
        FM_CHECK jnc, fmt_device_failed
        add     word ptr [fmt_lba], cx
        adc     word ptr [fmt_lba+2], 0
        sub     word ptr [fmt_count], cx
        jnz     fmt_verify_next
        clc
        ret
fmt_status:
        ; status call: can this size be formatted? 0 yes, 1 no format
        ; support, 2 not this size, 3 no medium
        call    format_caps
        les     bp, dword ptr [fmt_argument]
        mov     byte ptr es:[bp], al
        clc
        ret
fmt_bad_packet:
        mov     al, ERR_UNKNOWN_CMD
        stc
        ret
fmt_geometry_bad:
        mov     al, ERR_UNKNOWN_MEDIA
        stc
        ret
fmt_range_bad:
        mov     al, ERR_NOT_FOUND
        stc
        ret
fmt_device_failed:
fmt_failed:
        ; the medium is no longer what DOS has cached
        mov     di, word ptr [unit_ptr]
        and     byte ptr [di+U_FLAGS], not UF_MEDIA
        stc
        ret
ioctl_format endp

; READ FORMAT CAPACITIES: is fmt_total (512-byte blocks) offered?
; AL = 0 yes, 1 command not supported, 2 not offered, 3 no medium.
format_caps proc near
        push    bx
        push    cx
        push    si
        mov     al, SRB_DIR_IN
        mov     cl, 10
        call    aspi_prepare
        mov     byte ptr [srb+SRB_CDB], 23h
        mov     byte ptr [srb+SRB_CDB+8], 252
        mov     word ptr [srb+SRB_BufLen], 252
        mov     word ptr [srb+SRB_BufPointer], offset sector_buf
        mov     word ptr [srb+SRB_BufPointer+2], cs
        mov     byte ptr [sector_buf+3], 0
        call    call_aspi
        call    aspi_result
        jnc     fc_list
        call    aspi_sense
        jc      fc_unsupported
        cmp     ax, 3A02h                       ; NOT READY, no medium
        je      fc_no_medium
fc_unsupported:
        mov     al, 1
        jmp     short fc_done
fc_list:
        mov     cl, byte ptr [sector_buf+3]     ; list length, 8 per entry
        cmp     cl, 248
        jbe     fc_length
        mov     cl, 248
fc_length:
        shr     cl, 1
        shr     cl, 1
        shr     cl, 1
        xor     ch, ch
        jcxz    fc_not_offered
        mov     si, offset sector_buf+4
        mov     al, byte ptr [si+4]             ; current/maximum: its kind
        and     al, 3
        cmp     al, 3
        je      fc_no_medium
fc_entry:
        ; blocks (big-endian) = fmt_total, block length 512
        mov     ax, word ptr [si]
        xchg    al, ah
        cmp     ax, word ptr [fmt_total+2]
        jne     fc_next
        mov     ax, word ptr [si+2]
        xchg    al, ah
        cmp     ax, word ptr [fmt_total]
        jne     fc_next
        cmp     byte ptr [si+5], 0
        jne     fc_next
        cmp     word ptr [si+6], 0002h          ; 00 02 00
        jne     fc_next
        mov     al, 0
        jmp     short fc_done
fc_next:
        add     si, 8
        loop    fc_entry
fc_not_offered:
        mov     al, 2
        jmp     short fc_done
fc_no_medium:
        mov     al, 3
fc_done:
        pop     si
        pop     cx
        pop     bx
        ret
format_caps endp

; FORMAT UNIT of the whole medium to fmt_total, then wait for it. CF/AL.
format_unit proc near
        mov     di, word ptr [unit_ptr]
        test    byte ptr [di+U_XFLAGS], XF_WPROT
        jz      fu_writable
        mov     al, ERR_WRITE_PROTECT
        stc
        ret
fu_writable:
        ; the cached volume is gone from here on, also if this fails
        and     byte ptr [di+U_FLAGS], not UF_MEDIA
        push    es
        push    cs
        pop     es
        push    di
        mov     di, offset fmt_param
        mov     cx, 12
        xor     al, al
        rep     stosb
        pop     di
        pop     es
        test    byte ptr [di+U_XFLAGS], XF_UFI
        jz      fu_sbc
        mov     byte ptr [fmt_param+1], 0A2h    ; FOV, DCRT, IMMED
        mov     byte ptr [fmt_param+3], 8
        mov     ax, word ptr [fmt_total+2]
        xchg    al, ah
        mov     word ptr [fmt_param+4], ax
        mov     ax, word ptr [fmt_total]
        xchg    al, ah
        mov     word ptr [fmt_param+6], ax
        mov     byte ptr [fmt_param+10], 02h    ; 512-byte blocks
        mov     al, SRB_DIR_OUT
        mov     cl, 12
        call    aspi_prepare
        mov     byte ptr [srb+SRB_CDB+1], 17h   ; FmtData, format code 7
        mov     byte ptr [srb+SRB_CDB+8], 12
        mov     word ptr [srb+SRB_BufLen], 12
        jmp     short fu_send
fu_sbc:
        ; the device formats its current capacity: that must be the size
        call    block_read_capacity
        jnc     fu_capacity
        ret
fu_capacity:
        mov     ax, word ptr [di+U_CAPACITY]
        cmp     ax, word ptr [fmt_total]
        jne     fu_size
        mov     ax, word ptr [di+U_CAPACITY+2]
        cmp     ax, word ptr [fmt_total+2]
        je      fu_size_ok
fu_size:
        mov     al, ERR_UNKNOWN_MEDIA
        stc
        ret
fu_size_ok:
        mov     byte ptr [fmt_param+1], 02h     ; IMMED
        mov     al, SRB_DIR_OUT
        mov     cl, 6
        call    aspi_prepare
        mov     byte ptr [srb+SRB_CDB+1], 10h   ; FmtData
        mov     word ptr [srb+SRB_BufLen], 4
fu_send:
        mov     byte ptr [srb+SRB_CDB], 04h
        mov     word ptr [srb+SRB_BufPointer], offset fmt_param
        mov     word ptr [srb+SRB_BufPointer+2], cs
        call    call_aspi
        call    aspi_result
        jnc     fu_wait
        call    sense_to_doserr
        stc
        ret
fu_wait:
        ; TEST UNIT READY once per tick while "operation in progress"
        mov     cx, 65520                       ; about an hour
fu_poll:
        push    cx
        call    test_unit_ready
        pop     cx
        jnc     fu_done
        call    aspi_sense
        jc      fu_poll_failed
        cmp     al, 6                           ; UNIT ATTENTION: again
        je      fu_tick
        cmp     ax, 0402h                       ; NOT READY, in progress
        jne     fu_poll_failed
fu_tick:
        call    wait_tick
        loop    fu_poll
        mov     al, ERR_NOT_READY
        stc
        ret
fu_poll_failed:
        call    sense_to_doserr
        stc
        ret
fu_done:
        mov     byte ptr [aspi_attention], 0    ; the change is this format
        clc
        ret
format_unit endp

; Wait for the next BIOS timer tick.
wait_tick proc near
        push    ax
        push    es
        xor     ax, ax
        mov     es, ax
        sti
        mov     ax, word ptr es:[046Ch]
wait_tick_loop:
        cmp     ax, word ptr es:[046Ch]
        je      wait_tick_loop
        pop     es
        pop     ax
        ret
wait_tick endp

; 68h: byte 0 = 1 when the medium has the drive's default type, byte 1 =
; the type (02h 720 KB, 07h 1.44 MB, 09h 2.88 MB). Other sizes have no
; type: unknown media.
ioctl_media_type proc near
        les     bp, dword ptr es:[bx+RH_IOCTL_PARAM]
        mov     ax, es
        or      ax, bp
        jz      mt_bad_packet
        cmp     bp, 0FFFEh
        jae     mt_bad_packet
        mov     di, word ptr [unit_ptr]
        push    es
        push    bp
        call    block_read_capacity
        pop     bp
        pop     es
        jc      mt_failed
        cmp     word ptr [di+U_CAPACITY+2], 0
        jne     mt_unknown
        mov     ax, word ptr [di+U_CAPACITY]
        mov     dl, 02h
        cmp     ax, 1440
        je      mt_type
        mov     dl, 07h
        cmp     ax, 2880
        je      mt_type
        mov     dl, 09h
        cmp     ax, 5760
        jne     mt_unknown
mt_type:
        mov     dh, 0
        cmp     ax, word ptr [di+U_DEFAULT_BPB+BPB_TOTAL16]
        jne     mt_store
        mov     dh, 1
mt_store:
        mov     byte ptr es:[bp], dh
        mov     byte ptr es:[bp+1], dl
        clc
        ret
mt_unknown:
        mov     al, ERR_UNKNOWN_MEDIA
mt_failed:
        stc
        ret
mt_bad_packet:
        mov     al, ERR_UNKNOWN_CMD
        stc
        ret
ioctl_media_type endp
