; Resident DOS binding for the pointer-free packets in openaspi/tape_api.h.
; DS=CS; the shared driver SRB and native staging buffers are non-reentrant.
; Validate request length, category, version and far-pointer range before
; copying or changing caller data. Snapshot queries perform no SCSI I/O;
; REFRESH uses bounded read-only probes and preserves legacy diagnostics.
; Busy/unsafe sessions expose session state without stale probe results.
;
; READ and WRITE share packet preparation in native_tape_read.inc. Explicit
; writer ownership/control lives in native_tape_write.inc. The long conditional
; jump macro below preserves 8086 compatibility without 386 near-conditionals.

        include common/aspi/native_tape_defs.inc
; Here condition selects the branch TO target. Two short branches and a
; near JMP extend the range on 8086. Do not read this like PB_CHECK/TR_CHECK,
; whose condition instead selects the accepted path past a failure jump.
NT_JUMP macro condition, target
        local yes, no
        condition yes
        jmp short no
yes:
        jmp target
no:
endm
native_info db NT_SIZE dup (0)
native_reply db 64 dup (0FFh)
native_saved db 64 dup (0)
native_argument dd 0
native_alloc dw 0
native_actual dw 0
native_opcode db 0
native_page db 0
native_page_ptr dw 0
native_control_block dw 0
native_control_flags dw 0
native_control_count dd 0
native_writer_block dw 0

; Select native QUERY/CONTROL/READ/WRITE/POSITION/LOCATE/PARTITIONS.
; Return CF set only for a rejected delivery/envelope; operation errors in a
; well-formed reply stay in its result/diagnostic fields and return CF clear.
; The selected handler validates the function-specific packet before processing.
native_tape_dispatch proc near
        cmp     byte ptr es:[bx], 23
        jb      native_dispatch_bad
        cmp     byte ptr es:[bx+REQ_FUNCTION], 0
        jne     native_dispatch_control
        jmp     native_tape_query
native_dispatch_control:
        cmp     byte ptr es:[bx+REQ_FUNCTION], 1
        jne     native_dispatch_read
        jmp     native_tape_control
native_dispatch_read:
        cmp     byte ptr es:[bx+REQ_FUNCTION], 2
        jne     native_dispatch_write
        jmp     native_tape_read
native_dispatch_write:
        cmp     byte ptr es:[bx+REQ_FUNCTION], 3
        jne     native_dispatch_position
        jmp     native_tape_write
native_dispatch_position:
        cmp     byte ptr es:[bx+REQ_FUNCTION], 4
        jne     native_dispatch_locate
        jmp     native_tape_position
native_dispatch_locate:
        cmp     byte ptr es:[bx+REQ_FUNCTION], 5
        jne     native_dispatch_partitions
        jmp     native_tape_locate
native_dispatch_partitions:
        cmp     byte ptr es:[bx+REQ_FUNCTION], 6
        jne     native_dispatch_alerts
        jmp     native_tape_partitions
native_dispatch_alerts:
        cmp     byte ptr es:[bx+REQ_FUNCTION], 7
        jne     native_dispatch_bad
        jmp     native_tape_alerts
native_dispatch_bad:
        stc
        ret
native_tape_dispatch endp

; CX = known output size; reject before touching caller memory outside it.
; Packet envelope validation precedes any copy into resident staging storage.
; Check segment wrap, the real-mode address limit and magic/size/version.
; Record-buffer overlap is checked separately by native_record_prepare.
native_packet proc near
        cmp     byte ptr es:[bx], 23
        jb      native_packet_bad
        les     di, dword ptr es:[bx+REQ_PARAMETER]
        mov     ax, cx
        dec     ax
        add     ax, di
        jc      native_packet_bad
        push    cx
        mov     cl, 4
        shr     ax, cl
        pop     cx
        mov     dx, es
        add     ax, dx
        jc      native_packet_bad
        mov     ax, es
        or      ax, di
        jz      native_packet_bad
        cmp     word ptr es:[di], 544Fh       ; OT
        jne     native_packet_bad
        cmp     word ptr es:[di+2], 5041h     ; AP
        jne     native_packet_bad
        cmp     word ptr es:[di+4], cx
        jb      native_packet_bad
        cmp     word ptr es:[di+6], NT_VERSION
        jne     native_packet_bad
        mov     word ptr [native_argument], di
        mov     word ptr [native_argument+2], es
        clc
        ret
native_packet_bad:
        stc
        ret
native_packet endp

; CF set rejects the packet without writing it or changing legacy diagnostics.
native_tape_query proc near
        mov     cx, NT_SIZE
        call    native_packet
        jc      native_bad_header
        mov     ax, word ptr es:[di+NT_FLAGS]
        test    ax, 0FFFEh
        jz      native_header_valid
native_bad_header:
        stc
        ret
native_header_valid:
        mov     word ptr [native_argument], di
        mov     word ptr [native_argument+2], es
        push    ax
        push    cs
        pop     es
        mov     di, offset native_info
        mov     cx, NT_SIZE
        xor     al, al
        rep     stosb
        pop     ax
        mov     word ptr [native_info+NT_FLAGS], ax
        mov     word ptr [native_info], 544Fh
        mov     word ptr [native_info+2], 5041h
        mov     word ptr [native_info+4], NT_SIZE
        mov     word ptr [native_info+6], NT_VERSION
        mov     word ptr [native_info+NT_VALID], 20h ; session only, no cached guesses
        mov     word ptr [native_info+NT_OPERATIONS], 0FFFFh
        mov     word ptr [native_info+NT_OPERATIONS+2], 1FFFh
        mov     al, byte ptr [tape_ha]
        mov     byte ptr [native_info+NT_ADDRESS], al
        mov     al, byte ptr [tape_target]
        mov     byte ptr [native_info+NT_ADDRESS+1], al
        mov     al, byte ptr [tape_lun]
        mov     byte ptr [native_info+NT_ADDRESS+2], al
        mov     byte ptr [native_info+NT_ADDRESS+3], 1 ; ASPI transport
        call    native_session_state
        mov     word ptr [native_info+NT_SESSION], ax
        test    byte ptr [native_info+NT_FLAGS], 1
        jnz     native_refresh
        jmp     native_output
native_refresh:
        ; Discovery must not consume media change during an active session,
        ; discard buffered data, wait out a rewind, or mask saved failures.
        or      ax, ax
        jnz     native_busy
        cmp     byte ptr [tape_open_count], 1
        jne     native_busy
        cmp     word ptr [buffer_count], 0
        jne     native_busy
        cmp     byte ptr [request_rewind], 0
        jne     native_busy
        cmp     byte ptr [request_buffered], 0
        je      native_probe_ready
native_busy:
        mov     word ptr [native_info+NT_RESULT], 2
        jmp     native_output
native_probe_ready:
        mov     si, offset last_scsi_status
        mov     di, offset native_saved
        mov     cx, block_limits-last_scsi_status
        rep     movsb
        mov     byte ptr [native_opcode], 12h
        mov     word ptr [native_alloc], 36
        call    native_send
        jc      native_probe_done
        call    native_parse_inquiry
        jc      native_probe_done
        mov     byte ptr [native_opcode], 5
        mov     word ptr [native_alloc], 6
        call    native_send
        jnc     native_limits_parse
        cmp     al, 4
        je      native_modes
        jmp     native_probe_done
native_limits_parse:
        call    native_parse_limits
        jc      native_probe_done
native_modes:
        mov     byte ptr [native_opcode], 1Ah
        mov     byte ptr [native_page], 0Fh
        mov     word ptr [native_alloc], 64
        call    native_send
        jnc     native_compression_parse
        cmp     al, 4
        je      native_config
        jmp     native_probe_done
native_compression_parse:
        call    native_parse_mode
        jc      native_probe_done
native_config:
        mov     byte ptr [native_page], 10h
        call    native_send
        jc      native_probe_done
        call    native_parse_mode
native_probe_done:
        mov     si, offset native_saved
        mov     di, offset last_scsi_status
        mov     cx, block_limits-last_scsi_status
        rep     movsb
        call    native_session_state     ; a probe may have latched attention
        mov     word ptr [native_info+NT_SESSION], ax
native_output:
        les     di, dword ptr [native_argument]
        mov     si, offset native_info
        mov     cx, NT_SIZE
        rep     movsb
        clc
        ret
native_tape_query endp

; Read-only probe transport. Poison the reply allocation before submission.
; If residuals were negotiated, require a bounded returned residual and derive
; actual bytes; otherwise mark length unverified and parse conservatively within
; the allocation. No status/identity string can substitute for those checks.
native_send proc near
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_Flags], SRB_DIR_IN
        test    word ptr [adapter_ext_flags], HA_EXT_RESIDUAL
        jz      native_send_legacy
        or      byte ptr [srb+SRB_Flags], SRB_RESIDUAL
        jmp     short native_send_buffer
native_send_legacy:
        or      word ptr [native_info+88], 1
native_send_buffer:
        mov     di, offset native_reply
        mov     cx, 64
        mov     al, 0FFh
        rep     stosb
        mov     ax, word ptr [native_alloc]
        mov     word ptr [srb+SRB_BufLen], ax
        mov     word ptr [srb+SRB_BufPointer], offset native_reply
        mov     word ptr [srb+SRB_BufPointer+2], cs
        mov     al, byte ptr [native_opcode]
        mov     byte ptr [srb+SRB_CDB], al
        cmp     al, 5
        je      native_send_submit
        mov     al, byte ptr [native_alloc]
        mov     byte ptr [srb+SRB_CDB+4], al
        cmp     byte ptr [native_opcode], 1Ah
        jne     native_send_submit
        mov     al, byte ptr [native_page]
        mov     byte ptr [srb+SRB_CDB+2], al
native_send_submit:
        call    call_aspi
        call    check_tape_completion
        jc      native_command_failed
        mov     ax, word ptr [native_alloc]
        test    word ptr [adapter_ext_flags], HA_EXT_RESIDUAL
        jz      native_send_count_ready
        test    byte ptr [srb+SRB_Flags], SRB_RESIDUAL
        NT_JUMP jz, native_malformed
        cmp     word ptr [srb+SRB_BufLen+2], 0
        NT_JUMP jne, native_malformed
        sub     ax, word ptr [srb+SRB_BufLen]
        NT_JUMP jc, native_malformed
native_send_count_ready:
        mov     word ptr [native_actual], ax
        clc
        ret
native_command_failed:
        call    remember_sense_key
        call    native_classify_error
        jmp     native_failure
; Keep the first QUERY diagnostic while later optional probes may continue.
; PARTIAL still exposes separately validated groups; missing groups are unknown.
; Malformed reply bytes must not fabricate decoded sense for the diagnostic.
; The query's saved legacy diagnostic snapshot is restored before returning.
native_failure:
        mov     word ptr [native_info+NT_RESULT], 1
        cmp     word ptr [native_info+NT_DIAG], 0
        jne     native_failure_done
        xor     ah, ah
        mov     word ptr [native_info+NT_DIAG], ax
        mov     ah, byte ptr [srb+SRB_HaStat]
        mov     byte ptr [native_info+NT_HOST], ah
        mov     ah, byte ptr [srb+SRB_TargStat]
        mov     byte ptr [native_info+NT_TARGET], ah
        cmp     al, 3
        je      native_failure_done
        mov     ah, byte ptr [last_sense_key]
        mov     byte ptr [native_info+NT_KEY], ah
        mov     ah, byte ptr [sense_response]
        mov     byte ptr [native_info+NT_RESPONSE], ah
        mov     ah, byte ptr [sense_asc]
        mov     byte ptr [native_info+NT_ASC], ah
        mov     ah, byte ptr [sense_ascq]
        mov     byte ptr [native_info+NT_ASCQ], ah
native_failure_done:
        stc
        ret
native_malformed::
        mov     al, 3
        jmp     native_failure
native_send endp

; Publish IDENTITY only after a 36-byte standard reply identifies an attached
; sequential-access device and declares enough additional bytes. Vendor/product/
; revision are 28 fixed-width printable bytes, copied without NUL terminators;
; private/vendor extension bytes do not become native identity fields.
native_parse_inquiry proc near
        cmp     word ptr [native_actual], 36
        NT_JUMP jb, native_malformed
        mov     al, byte ptr [native_reply]
        and     al, 0E0h
        NT_JUMP jnz, native_malformed
        mov     al, byte ptr [native_reply]
        and     al, 1Fh
        cmp     al, 1
        NT_JUMP jne, native_malformed
        cmp     byte ptr [native_reply+4], 31
        NT_JUMP jb, native_malformed
        mov     si, offset native_reply+8
        mov     cx, 28
native_identity_check:
        lodsb
        cmp     al, 20h
        NT_JUMP jb, native_malformed
        cmp     al, 7Eh
        NT_JUMP ja, native_malformed
        loop    native_identity_check
        mov     si, offset native_reply+8
        mov     di, offset native_info+NT_VENDOR
        mov     cx, 28
        rep     movsb
        or      word ptr [native_info+NT_VALID], 1
        clc
        ret
native_parse_inquiry endp

; READ BLOCK LIMITS is a six-byte big-endian payload: granularity exponent,
; 24-bit maximum and 16-bit minimum. Validate reserved bits, size and ordering
; before setting LIMITS valid. A zero maximum remains an unspecified upper bound,
; not proof that zero-length records or unlimited provider transfers are allowed.
native_parse_limits proc near
        cmp     word ptr [native_actual], 6
        NT_JUMP jb, native_malformed
        test    byte ptr [native_reply], 0E0h
        NT_JUMP jnz, native_malformed
        xor     ax, ax
        mov     al, byte ptr [native_reply+1]
        mov     word ptr [native_info+NT_MAX+2], ax
        mov     ah, byte ptr [native_reply+2]
        mov     al, byte ptr [native_reply+3]
        mov     word ptr [native_info+NT_MAX], ax
        mov     dh, byte ptr [native_reply+4]
        mov     dl, byte ptr [native_reply+5]
        mov     word ptr [native_info+NT_MIN], dx
        cmp     word ptr [native_info+NT_MAX+2], 0
        jne     native_limits_nonzero
        or      ax, ax
        jz      native_limits_nonzero     ; zero = no specified upper limit
        cmp     ax, dx
        NT_JUMP jb, native_malformed
; READ BLOCK LIMITS encodes granularity as an exponent in the low five bits.
; Build the 32-bit step 1<<exponent using paired SHL/RCL, so exponents above 15
; do not vanish in a WORD. Maximum zero means unspecified, not an empty range.
native_limits_nonzero:
        xor     cx, cx
        mov     cl, byte ptr [native_reply]
        and     cl, 1Fh
        mov     ax, 1
        xor     dx, dx
        jcxz    native_limits_granularity
native_limits_shift:
        shl     ax, 1
        rcl     dx, 1
        loop    native_limits_shift
native_limits_granularity:
        mov     word ptr [native_info+92], ax
        mov     word ptr [native_info+94], dx
        or      word ptr [native_info+NT_VALID], 2
        clc
        ret
native_parse_limits endp

; MODE SENSE(6): bound the header, descriptor area and every returned page
; before publishing any fields. Page location depends on descriptor length.
; MODE SENSE parsing must honor the returned header, block-descriptor length
; and each page's declared extent. Optional absence means unknown capability;
; it must not become an inferred disabled/unsupported setting.
native_find_mode_page proc near
        cmp     word ptr [native_actual], 4
        NT_JUMP jb, native_find_bad
        xor     dx, dx
        mov     dl, byte ptr [native_reply]
        inc     dx
        cmp     dx, word ptr [native_actual]
        NT_JUMP ja, native_find_bad
        cmp     dx, 4
        NT_JUMP jb, native_find_bad
        xor     bx, bx
        mov     bl, byte ptr [native_reply+3]
        test    bl, 7
        NT_JUMP jnz, native_find_bad
        add     bx, 4
        cmp     bx, dx
        NT_JUMP ja, native_find_bad
        mov     word ptr [native_page_ptr], 0
native_find_next:
        cmp     bx, dx
        je      native_find_checked
        mov     ax, dx
        sub     ax, bx
        cmp     ax, 2
        NT_JUMP jb, native_find_bad
        mov     si, offset native_reply
        add     si, bx
        test    byte ptr [si], 40h        ; subpage form is not this binding's request
        NT_JUMP jnz, native_find_bad
        xor     cx, cx
        mov     cl, byte ptr [si+1]
        add     cx, 2
        cmp     cx, ax
        NT_JUMP ja, native_find_bad
        mov     al, byte ptr [si]
        and     al, 3Fh                   ; PS is not part of the page code
        cmp     al, byte ptr [native_page]
        jne     native_find_skip
        cmp     word ptr [native_page_ptr], 0
        NT_JUMP jne, native_find_bad    ; conflicting duplicate page
        mov     word ptr [native_page_ptr], si
native_find_skip:
        add     bx, cx
        jmp     native_find_next
native_find_checked:
        mov     si, word ptr [native_page_ptr]
        or      si, si
        NT_JUMP jz, native_find_bad
        xor cx,cx
        mov cl,byte ptr [si+1]
        add cx,2
        clc
        ret
native_find_bad:
        stc
        ret
native_find_mode_page endp

native_parse_mode proc near
        call native_find_mode_page
        NT_JUMP jc,native_malformed
        cmp cx,16
        NT_JUMP jb,native_malformed
        cmp     byte ptr [native_page], 0Fh
        jne     native_config_page
        test    byte ptr [si+2], 3Fh      ; compression page reserved bits
        NT_JUMP jnz, native_malformed
        or      word ptr [native_info+NT_KNOWN], 1
        or      word ptr [native_info+NT_VALID], 8
        test    byte ptr [si+2], 40h      ; DCC
        jz      native_mode_header
        or      word ptr [native_info+NT_SUPPORTED], 1
        test    byte ptr [si+2], 80h      ; DCE
        jz      native_mode_header
        or      word ptr [native_info+NT_STATE], 1
        jmp     short native_mode_header
native_config_page:
        or      word ptr [native_info+NT_VALID], 10h
        test    byte ptr [si+8], 20h      ; RSM current setting, not an API operation
        jz      native_mode_header
        or      word ptr [native_info+NT_STATE], 4
native_mode_header:
        or      word ptr [native_info+NT_VALID], 4
        and     word ptr [native_info+NT_STATE], not 2
        test    byte ptr [native_reply+2], 80h
        jz      native_mode_block
        or      word ptr [native_info+NT_STATE], 2
native_mode_block:
        cmp     byte ptr [native_reply+3], 8
        jb      native_mode_done
        xor     ax, ax
        mov     al, byte ptr [native_reply+9]
        mov     word ptr [native_info+NT_BLOCK+2], ax
        mov     ah, byte ptr [native_reply+10]
        mov     al, byte ptr [native_reply+11]
        mov     word ptr [native_info+NT_BLOCK], ax
        and     word ptr [native_info+NT_STATE], not 8
        or      ax, word ptr [native_info+NT_BLOCK+2]
        jz      native_mode_block_ready
        or      word ptr [native_info+NT_STATE], 8
native_mode_block_ready:
        or      word ptr [native_info+NT_VALID], 40h
native_mode_done:
        clc
        ret
native_parse_mode endp

; Build the public session mask from separate legacy and native state.
; Native active/dirty/failed bits are shifted into bits 4..6; preserving their
; separate storage prevents legacy close from finalizing a native stream.
; A latched UNIT ATTENTION also reports FAILED: the existing v1 bit already means
; "position unknown until explicit REWIND", so old SDK validators stay valid.
native_session_state proc near
        xor     ax, ax
        cmp     byte ptr [rewind_pending], 0
        je      native_state_written
        or      al, 1
native_state_written:
        test    byte ptr [device_state], MT_STATE_WRITTEN
        jz      native_state_buffered
        or      al, 2
native_state_buffered:
        cmp     byte ptr [session_buffered], 0
        je      native_state_error
        or      al, 4
native_state_error:
        cmp     byte ptr [write_error_valid], 0
        je      native_state_done
        or      al, 8
native_state_done:
        mov     ah, byte ptr [native_write_state]
        shl     ah, 1
        shl     ah, 1
        shl     ah, 1
        shl     ah, 1
        or      al, ah
        cmp     byte ptr [media_attention], 0
        je      native_state_attention_done
        or      al, 40h
native_state_attention_done:
        xor     ah, ah
        ret
native_session_state endp

; Only trustworthy current target sense can classify an unsupported command.
; Return AL diagnostic class: transport=1, target=2, unsupported=4. Promotion
; to unsupported requires checked current sense key 5 and ASC 20h/24h; deferred
; or unavailable ASC stays a target diagnostic. This classification itself does
; not retry, fall back, release ownership or declare a known tape position.
native_classify_error proc near
        mov     al, 1
        cmp     byte ptr [srb+SRB_Status], SS_ERR
        jne     native_classified
        cmp     byte ptr [srb+SRB_HaStat], 0
        jne     native_classified
        mov     al, 2
        cmp     byte ptr [last_sense_key], 5
        jne     native_classified
        cmp     byte ptr [sense_asc_valid], 0
        je      native_classified
        cmp     byte ptr [sense_response], 70h
        je      native_classify_asc
        cmp     byte ptr [sense_response], 72h
        jne     native_classified
native_classify_asc:
        cmp     byte ptr [sense_asc], 20h
        je      native_classify_unsupported
        cmp     byte ptr [sense_asc], 24h
        jne     native_classified
native_classify_unsupported:
        mov     al, 4
native_classified:
        ret
native_classify_error endp

; Validate operation/flags/fixed-block extension before clearing reply staging.
; Copy only accepted request fields into the new reply, then select ordinary
; READY/REWIND, SPACE/LOAD/UNLOAD or the writer state machine.
; Control block_size is at byte 28;
; using the record packet's byte-44 extension would read a different wire field.
native_tape_control proc near
        mov     cx, NC_SIZE
        call    native_packet
        jc      native_control_bad
        mov     ax, word ptr es:[di+NC_FLAGS]
        cmp     ax, 1
        ja      native_control_bad
        mov     word ptr [native_control_flags], ax
        cmp     word ptr es:[di+NC_BLOCK+2], 0
        jne     native_control_bad
        mov     dx, word ptr es:[di+NC_BLOCK]
        mov     word ptr [native_control_block], dx
        or      ax, ax
        jz      native_control_variable
        cmp     word ptr es:[di+NC_OPERATION], 2
        jne     native_control_bad
        or      dx, dx
        jz      native_control_bad
        cmp     word ptr [tape_fixed_block], 0
        je      native_control_mode_valid
        cmp     dx, word ptr [tape_fixed_block]
        jne     native_control_bad
        jmp     short native_control_mode_valid
native_control_variable:
        or      dx, dx
        jne     native_control_bad
native_control_mode_valid:
        mov     ax, word ptr es:[di+NC_OPERATION]
        cmp     ax, 17
        ja      native_control_bad
        mov     dx, word ptr es:[di+NC_COUNT]
        mov     cx, word ptr es:[di+NC_COUNT+2]
        cmp     ax, 17
        je      native_control_zero_count
        cmp     ax, 14
        jae     native_control_signed_count
        cmp     ax, 7
        jb      native_control_zero_count
        cmp     ax, 9
        jae     native_control_zero_count
native_control_signed_count:
        cmp     cx, 007Fh                ; canonical signed 24-bit count
        jbe     native_control_count_valid
        cmp     cx, 0FF80h
        jae     native_control_count_valid
        jmp     short native_control_bad
native_control_zero_count:
        or      dx, cx
        jnz     native_control_bad
native_control_count_valid:
        mov     dx, word ptr es:[di+NC_COUNT]
        mov     word ptr [native_control_count], dx
        mov     word ptr [native_control_count+2], cx
        jmp     short native_control_valid
native_control_bad:
        stc
        ret
native_control_valid:
        push    ax
        push    cs
        pop     es
        mov     di, offset native_info
        mov     cx, NC_SIZE
        xor     al, al
        rep     stosb
        pop     ax
        mov     word ptr [native_info+NC_OPERATION], ax
        mov     ax, word ptr [native_control_count]
        mov     word ptr [native_info+NC_COUNT], ax
        mov     ax, word ptr [native_control_count+2]
        mov     word ptr [native_info+NC_COUNT+2], ax
        mov     ax, word ptr [native_control_flags]
        mov     word ptr [native_info+NC_FLAGS], ax
        mov     ax, word ptr [native_control_block]
        mov     word ptr [native_info+NC_BLOCK], ax
        mov     word ptr [native_info], 544Fh
        mov     word ptr [native_info+2], 5041h
        mov     word ptr [native_info+4], NC_SIZE
        mov     word ptr [native_info+6], NT_VERSION
        call    native_session_state
        mov     word ptr [native_info+NC_SESSION], ax
        ; Enum 17 is an owned write, despite following the motion enums.
        cmp     word ptr [native_info+NC_OPERATION], 17
        jne     native_control_select_motion
        jmp     native_write_control
native_control_select_motion:
        cmp     word ptr [native_info+NC_OPERATION], 7
        jae     native_control_motion
        cmp     word ptr [native_info+NC_OPERATION], 2
        jb      native_control_ordinary
        jmp     native_write_control
; Ordinary/movement commands may not interfere with native or legacy writes.
; LOAD/UNLOAD and removal controls preserve abandoned DIRTY/FAILED;
; SPACE requires a clean native session. Only successful REWIND clears it.
; READY/REWIND may not interfere with a native writer, buffered/legacy writes
; or saved failures. READY can inspect pending rewind, whereas another REWIND
; cannot. Claim/alias/buffer guards apply before submission, so BUSY reports
; no command completion facts. Session bits are public flags, not private state.
native_control_motion:
        cmp     word ptr [native_info+NC_OPERATION], 14
        jae     native_control_space_guard
        cmp     word ptr [native_info+NC_OPERATION], 10
        jae     native_control_ordinary  ; explicit media recovery preserves FAILED
native_control_space_guard:
        test    al, 60h                  ; DIRTY/FAILED needs explicit rewind
        NT_JUMP jnz, native_control_busy
native_control_ordinary:
        test    al, 10h
        NT_JUMP jnz, native_control_busy
        test    al, 0Eh                   ; written/buffered/saved failure
        jnz     native_control_busy
        test    al, 1                     ; READY may inspect a pending rewind
        jz      native_control_owner
        cmp     word ptr [native_info+NC_OPERATION], 0
        jne     native_control_busy
native_control_owner:
        cmp     byte ptr [tape_open_count], 1
        jne     native_control_busy
        cmp     word ptr [buffer_count], 0
        jne     native_control_busy
        cmp     byte ptr [request_rewind], 0
        jne     native_control_busy
        cmp     byte ptr [request_buffered], 0
        je      native_control_submit
native_control_busy:
        mov     word ptr [native_info+NC_RESULT], 2
        jmp     native_control_output
native_control_submit:
        call    prepare_control_srb
        mov     ax, word ptr [native_info+NC_OPERATION]
        or      ax, ax
        je      native_control_cdb_ready
        cmp     ax, 14
        jae     native_control_space
        cmp     ax, 12
        jae     native_control_removal
        cmp     ax, 10
        jae     native_control_media
        cmp     ax, 7
        jae     native_control_space
        mov     byte ptr [srb+SRB_CDB], SCSI_REWIND ; IMMED remains zero
        jmp     short native_control_cdb_ready
native_control_removal:
        ; Non-moving PREVENT/ALLOW: no persistent-prevent or reserved bits.
        ; Failure must not turn a previously clean position into uncertainty.
        mov     byte ptr [srb+SRB_CDB], SCSI_PREVENT
        cmp     ax, 12
        jne     native_control_cdb_ready
        mov     byte ptr [srb+SRB_CDB+4], 1
        jmp     short native_control_cdb_ready
native_control_media:
        ; Sequential-access LOAD/UNLOAD: byte 4 LOAD=1/0, RETEN/IMMED=0.
        ; Do not reuse CD START STOP's LoEj bits for a tape command.
        mov     byte ptr [srb+SRB_CDB], SCSI_LOAD
        cmp     ax, 10
        jne     native_control_cdb_ready
        mov     byte ptr [srb+SRB_CDB+4], 1
        jmp     short native_control_cdb_ready
native_control_space:
        mov     byte ptr [srb+SRB_CDB], SCSI_SPACE
        cmp     ax, 14
        jb      native_control_space_base
        sub     ax, 12                   ; sequential filemarks=2, setmarks=4/5
        cmp     al, 2
        je      native_control_space_code
        inc     al
        jmp     short native_control_space_code
native_control_space_base:
        sub     ax, 7                    ; RECORDS=0, FILEMARKS=1, EOD=3
        cmp     al, 2
        jne     native_control_space_code
        inc     al
native_control_space_code:
        mov     byte ptr [srb+SRB_CDB+1], al
        mov     ax, word ptr [native_info+NC_COUNT+2]
        mov     byte ptr [srb+SRB_CDB+2], al
        mov     ax, word ptr [native_info+NC_COUNT]
        mov     byte ptr [srb+SRB_CDB+3], ah
        mov     byte ptr [srb+SRB_CDB+4], al
native_control_cdb_ready:
        mov     al, byte ptr [srb+SRB_CDB]
        mov     byte ptr [native_info+NC_OPCODE], al
        mov     word ptr [native_info+NC_COMPLETION], 1
        call    execute_control_srb
        jc      native_control_failed
        mov     byte ptr [rewind_pending], 0
        or      word ptr [native_info+NC_COMPLETION], 2
        cmp     word ptr [native_info+NC_OPERATION], 7
        jae     native_control_finished   ; media/motion completion is not BOT evidence
        cmp     word ptr [native_info+NC_OPERATION], 0
        jne     native_control_bot
        or      word ptr [native_info+NC_COMPLETION], 10h
        jmp     short native_control_finished
native_control_bot:
        mov     byte ptr [native_write_state], 0
        mov     byte ptr [media_attention], 0
        or      word ptr [native_info+NC_COMPLETION], 8
        jmp     short native_control_finished
native_control_failed:
        call    native_control_diagnostics
        cmp     word ptr [native_info+NC_OPERATION], 0
        je      native_control_finished
        cmp     word ptr [native_info+NC_OPERATION], 12
        jb      native_control_failed_motion
        cmp     word ptr [native_info+NC_OPERATION], 14
        jb      native_control_finished  ; only removal policy is non-moving
native_control_failed_motion:
        or      word ptr [native_info+NC_COMPLETION], 4
        cmp     word ptr [native_info+NC_OPERATION], 7
        jb      native_control_finished
        or      byte ptr [native_write_state], 4 ; motion failure retains uncertainty
native_control_finished:
        call    native_session_state
        mov     word ptr [native_info+NC_SESSION], ax
native_control_output:
        les     di, dword ptr [native_argument]
        mov     si, offset native_info
        mov     cx, NC_SIZE
        rep     movsb
        clc
        ret
native_tape_control endp

        include common/aspi/native_tape_read.inc

        include common/aspi/native_tape_write.inc

        include common/aspi/native_tape_position.inc

; Shared CONTROL/LOCATE diagnostic prefix. Capture command error only; each
; operation decides independently whether failure changes position/session.
native_control_diagnostics proc near
        call record_driver_error
        call native_copy_diagnostics
        ret
native_control_diagnostics endp

; Read-only callers save/restore legacy diagnostics around the whole probe.
native_read_diagnostics proc near
        call remember_sense_key
        call native_copy_diagnostics
        ret
native_read_diagnostics endp
native_copy_diagnostics proc near
        mov     word ptr [native_info+NC_RESULT], 3
        call    native_classify_error
        xor     ah, ah
        mov     word ptr [native_info+NC_DIAG], ax
        mov     al, byte ptr [srb+SRB_HaStat]
        mov     byte ptr [native_info+NC_HOST], al
        mov     al, byte ptr [srb+SRB_TargStat]
        mov     byte ptr [native_info+NC_TARGET], al
        mov     al, byte ptr [last_sense_key]
        mov     byte ptr [native_info+NC_KEY], al
        mov     al, byte ptr [sense_response]
        mov     byte ptr [native_info+NC_RESPONSE], al
        mov     al, byte ptr [sense_asc]
        mov     byte ptr [native_info+NC_ASC], al
        mov     al, byte ptr [sense_ascq]
        mov     byte ptr [native_info+NC_ASCQ], al
        ret
native_copy_diagnostics endp

        include common/aspi/native_tape_locate.inc

        include common/aspi/native_tape_partitions.inc

        include common/aspi/native_tape_alerts.inc
