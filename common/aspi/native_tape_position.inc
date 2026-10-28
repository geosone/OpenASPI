; Non-moving READ POSITION(10), short logical form (service action / BT zero).
; Keep coordinate reporting separate from writer recovery. Neither success nor
; failure changes native ownership, queued EOF, buffers or saved diagnostics.
; Address fields are published only after a proven complete 20-byte response;
; BPU/LOLU and PERR suppress coordinates instead of inventing block zero.
position_format dw 0
position_length dw 20
native_tape_position proc near
        mov cx,NC_SIZE
        call native_packet
        NT_JUMP jc,position_bad
        mov ax,word ptr es:[di+NC_OPERATION]
        cmp ax,1
        NT_JUMP ja,position_bad
        mov word ptr [position_format],ax
        mov word ptr [position_length],20
        or ax,ax
        jz position_format_ready
        mov word ptr [position_length],32
position_format_ready:
        cmp word ptr es:[di+NC_FLAGS],0
        NT_JUMP jne,position_bad
        push cs
        pop es
        mov di,offset native_info
        mov cx,NC_SIZE
        xor al,al
        rep stosb
        mov word ptr [native_info],544Fh
        mov word ptr [native_info+2],5041h
        mov word ptr [native_info+4],NC_SIZE
        mov word ptr [native_info+6],NT_VERSION
        mov ax,word ptr [position_format]
        mov word ptr [native_info+NC_OPERATION],ax
        call native_session_state
        mov word ptr [native_info+NC_SESSION],ax
        test al,1Fh                     ; allow retained native DIRTY/FAILED
        NT_JUMP jnz,position_busy
        cmp byte ptr [tape_open_count],1
        NT_JUMP jne,position_busy
        cmp word ptr [buffer_count],0
        NT_JUMP jne,position_busy
        cmp byte ptr [request_rewind],0
        NT_JUMP jne,position_busy
        cmp byte ptr [request_buffered],0
        NT_JUMP jne,position_busy
        jmp short position_prepare
position_bad:
        stc
        ret
position_prepare:
        mov si,offset last_scsi_status
        mov di,offset native_saved
        mov cx,block_limits-last_scsi_status
        rep movsb
        mov di,offset native_reply
        mov cx,word ptr [position_length]
        mov al,0FFh
        rep stosb
        call prepare_control_srb
        mov byte ptr [srb+SRB_CDBLen],10
        mov byte ptr [srb+SRB_CDB],34h
        cmp word ptr [position_format],1
        jne position_cdb_ready
        mov byte ptr [srb+SRB_CDB+1],6
position_cdb_ready:
        mov byte ptr [native_info+NC_OPCODE],34h
        mov byte ptr [srb+SRB_Flags],SRB_DIR_IN
        test word ptr [adapter_ext_flags],HA_EXT_RESIDUAL
        jz position_flags_ready
        or byte ptr [srb+SRB_Flags],SRB_RESIDUAL
position_flags_ready:
        mov ax,word ptr [position_length]
        mov word ptr [srb+SRB_BufLen],ax
        mov word ptr [srb+SRB_BufPointer],offset native_reply
        mov word ptr [srb+SRB_BufPointer+2],cs
        mov word ptr [native_info+NC_COMPLETION],1
        call call_aspi
        call check_tape_completion
        NT_JUMP jc,position_command_failed
        mov word ptr [native_info+NC_COMPLETION],3
        test word ptr [adapter_ext_flags],HA_EXT_RESIDUAL
        NT_JUMP jz,position_unverified
        test byte ptr [srb+SRB_Flags],SRB_RESIDUAL
        NT_JUMP jz,position_malformed
        cmp word ptr [srb+SRB_BufLen],0
        NT_JUMP jne,position_malformed
        cmp word ptr [srb+SRB_BufLen+2],0
        NT_JUMP jne,position_malformed
        cmp word ptr [position_format],1
        NT_JUMP je,position_parse_wide
        test byte ptr [native_reply],8   ; reserved in both old/new short forms
        NT_JUMP jnz,position_malformed
        cmp word ptr [native_reply+2],0
        NT_JUMP jne,position_malformed
        cmp byte ptr [native_reply+12],0
        NT_JUMP jne,position_malformed
        xor ah,ah
        mov al,byte ptr [native_reply]
        mov word ptr [native_info+NP_DEVICE],ax
        test al,6                       ; BPU/LOLU or position overflow/error
        NT_JUMP jnz,position_restore
        mov word ptr [native_info+NP_VALID],1
        mov al,byte ptr [native_reply+1]
        mov word ptr [native_info+NP_PARTITION],ax
        mov si,offset native_reply+4
        mov di,offset native_info+NP_FIRST
        call native_position_dword
        call native_position_dword
        jmp position_restore
position_parse_wide:
        test byte ptr [native_reply],32h ; reserved bits, not short-form flags
        NT_JUMP jnz,position_malformed
        cmp byte ptr [native_reply+1],0
        NT_JUMP jne,position_malformed
        cmp word ptr [native_reply+2],0
        NT_JUMP jne,position_malformed
        xor ah,ah
        mov al,byte ptr [native_reply]
        mov word ptr [native_info+NP64_DEVICE],ax
        test al,4                       ; LONU: partition and block unknown
        jnz position_wide_file
        or word ptr [native_info+NP_VALID],1
        mov si,offset native_reply+4
        mov di,offset native_info+NP_PARTITION
        call native_position_dword
        call native_position_qword
position_wide_file:
        test byte ptr [native_reply],8   ; MPU independently gates file number
        NT_JUMP jnz,position_restore
        or word ptr [native_info+NP_VALID],2
        mov si,offset native_reply+16
        mov di,offset native_info+NP64_FILE
        call native_position_qword
        jmp position_restore
position_unverified:
        ; A legacy manager cannot prove transfer length. Preserve this fact,
        ; return PARTIAL and do not expose a possibly stale logical address.
        mov word ptr [native_info+NC_RESULT],1
        mov word ptr [native_info+NC_DIAG],5
        cmp word ptr [position_format],1
        jne position_short_unverified
        mov word ptr [native_info+NP64_PROBE],1
        jmp position_restore
position_short_unverified:
        mov word ptr [native_info+NP_PROBE],1
        jmp position_restore
position_malformed:
        mov word ptr [native_info+NC_RESULT],3
        mov word ptr [native_info+NC_DIAG],3
        jmp position_restore
position_command_failed:
        call native_read_diagnostics
position_restore:
        mov si,offset native_saved
        mov di,offset last_scsi_status
        mov cx,block_limits-last_scsi_status
        rep movsb
        jmp short position_output
position_busy:
        mov word ptr [native_info+NC_RESULT],2
position_output:
        les di,dword ptr [native_argument]
        mov si,offset native_info
        mov cx,NC_SIZE
        rep movsb
        clc
        ret
native_tape_position endp

; Big-endian device DWORD at DS:SI -> little-endian packet DWORD at ES:DI.
; Paired 16-bit words preserve the full unsigned range on the 8086 provider.
native_position_dword proc near
        lodsw
        xchg al,ah
        mov word ptr es:[di+2],ax
        lodsw
        xchg al,ah
        mov word ptr es:[di],ax
        add di,4
        ret
native_position_dword endp

; Store big-endian 64-bit data as low/high DWORDs without a 64-bit scalar.
native_position_qword proc near
        mov dx,di
        add di,4
        call native_position_dword
        mov di,dx
        call native_position_dword
        add di,4
        ret
native_position_qword endp
