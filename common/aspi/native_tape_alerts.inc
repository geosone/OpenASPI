; Explicit TapeAlert retrieval. A LOG SENSE read may acknowledge device flags:
; request acknowledgment is mandatory and no automatic polling/retry is used.
; Keep reported/active separate; parse all bounds before publishing any masks.
native_alert_reply db 512 dup (0FFh)
native_alert_masks db 16 dup (0)
native_alert_previous dw 0
native_tape_alerts proc near
        mov cx,NC_SIZE
        call native_packet
        jc alerts_bad
        cmp word ptr es:[di+NC_OPERATION],0
        jne alerts_bad
        cmp word ptr es:[di+NC_FLAGS],1
        jne alerts_bad
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
        mov word ptr [native_info+NC_FLAGS],1
        call native_session_state
        mov word ptr [native_info+NC_SESSION],ax
        test al,1Fh
        NT_JUMP jnz,alerts_busy
        cmp byte ptr [tape_open_count],1
        NT_JUMP jne,alerts_busy
        cmp word ptr [buffer_count],0
        NT_JUMP jne,alerts_busy
        cmp byte ptr [request_rewind],0
        NT_JUMP jne,alerts_busy
        cmp byte ptr [request_buffered],0
        NT_JUMP jne,alerts_busy
        jmp short alerts_prepare
alerts_bad:
        stc
        ret
alerts_prepare:
        mov si,offset last_scsi_status
        mov di,offset native_saved
        mov cx,block_limits-last_scsi_status
        rep movsb
        mov di,offset native_alert_reply
        mov cx,512
        mov al,0FFh
        rep stosb
        mov di,offset native_alert_masks
        mov cx,16
        xor al,al
        rep stosb
        call prepare_control_srb
        mov byte ptr [srb+SRB_CDBLen],10
        mov byte ptr [srb+SRB_CDB],4Dh
        mov byte ptr [srb+SRB_CDB+2],6Eh ; current values, TapeAlert page 2Eh
        mov byte ptr [srb+SRB_CDB+7],2   ; allocation 0200h
        mov byte ptr [native_info+NC_OPCODE],4Dh
        mov byte ptr [srb+SRB_Flags],SRB_DIR_IN
        test word ptr [adapter_ext_flags],HA_EXT_RESIDUAL
        jz alerts_flags_ready
        or byte ptr [srb+SRB_Flags],SRB_RESIDUAL
alerts_flags_ready:
        mov word ptr [srb+SRB_BufLen],512
        mov word ptr [srb+SRB_BufPointer],offset native_alert_reply
        mov word ptr [srb+SRB_BufPointer+2],cs
        mov word ptr [native_info+NC_COMPLETION],1
        call call_aspi
        call check_tape_completion
        NT_JUMP jc,alerts_command_failed
        mov word ptr [native_info+NC_COMPLETION],3
        test word ptr [adapter_ext_flags],HA_EXT_RESIDUAL
        NT_JUMP jz,alerts_unverified
        test byte ptr [srb+SRB_Flags],SRB_RESIDUAL
        NT_JUMP jz,alerts_malformed
        cmp word ptr [srb+SRB_BufLen+2],0
        NT_JUMP jne,alerts_malformed
        mov ax,512
        sub ax,word ptr [srb+SRB_BufLen]
        NT_JUMP jc,alerts_malformed
        cmp ax,4
        NT_JUMP jb,alerts_malformed
        mov dl,byte ptr [native_alert_reply]
        and dl,7Fh                    ; ignore DS, reject subpage form
        cmp dl,2Eh
        NT_JUMP jne,alerts_malformed
        cmp byte ptr [native_alert_reply+1],0
        NT_JUMP jne,alerts_malformed
        mov dh,byte ptr [native_alert_reply+2]
        mov dl,byte ptr [native_alert_reply+3]
        add dx,4
        NT_JUMP jc,alerts_malformed
        cmp dx,ax
        NT_JUMP ja,alerts_malformed
        mov di,offset native_alert_reply
        add di,dx
        mov si,offset native_alert_reply+4
        mov word ptr [native_alert_previous],0
alerts_next:
        cmp si,di
        je alerts_parsed
        mov ax,di
        sub ax,si
        cmp ax,4
        NT_JUMP jb,alerts_malformed
        xor cx,cx
        mov cl,byte ptr [si+3]
        add cx,4
        cmp cx,ax
        NT_JUMP ja,alerts_malformed
        mov dh,byte ptr [si]
        mov dl,byte ptr [si+1]
        cmp dx,word ptr [native_alert_previous]
        NT_JUMP jbe,alerts_malformed ; unique ascending parameters, including unknowns
        mov word ptr [native_alert_previous],dx
        cmp dx,64
        ja alerts_skip
        cmp byte ptr [si+3],1
        NT_JUMP jne,alerts_malformed
        test byte ptr [si+2],3       ; numeric flag, not a list parameter
        NT_JUMP jnz,alerts_malformed
        cmp byte ptr [si+4],1
        NT_JUMP ja,alerts_malformed
        push cx
        mov ax,dx
        dec ax
        mov bx,ax
        shr bx,1
        shr bx,1
        shr bx,1
        and ax,7
        mov cl,al
        mov al,1
        shl al,cl
        or byte ptr [native_alert_masks+bx],al
        cmp byte ptr [si+4],0
        je alerts_inactive
        or byte ptr [native_alert_masks+8+bx],al
alerts_inactive:
        pop cx
alerts_skip:
        add si,cx
        jmp alerts_next
alerts_parsed:
        mov si,offset native_alert_masks
        mov di,offset native_info+NA_REPORTED
        mov cx,16
        rep movsb
        mov word ptr [native_info+NA_VALID],1
        jmp short alerts_restore
alerts_malformed:
        mov word ptr [native_info+NC_RESULT],3
        mov word ptr [native_info+NC_DIAG],3
        jmp short alerts_restore
alerts_unverified:
        mov word ptr [native_info+NC_RESULT],1
        mov word ptr [native_info+NC_DIAG],5
        mov word ptr [native_info+NA_PROBE],1
        jmp short alerts_restore
alerts_command_failed:
        call native_read_diagnostics
alerts_restore:
        mov si,offset native_saved
        mov di,offset last_scsi_status
        mov cx,block_limits-last_scsi_status
        rep movsb
        jmp short alerts_output
alerts_busy:
        mov word ptr [native_info+NC_RESULT],2
alerts_output:
        les di,dword ptr [native_argument]
        mov si,offset native_info
        mov cx,NC_SIZE
        rep movsb
        clc
        ret
native_tape_alerts endp
