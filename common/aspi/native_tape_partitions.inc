; Read-only reported partition layout. MODE SENSE page 11h may describe a
; pending configuration or a previous medium: publish raw bounded facts only,
; never a target whitelist or partition creation. Preserve legacy diagnostics,
; queued EOF and native uncertainty; no retry, TUR or mode change is implicit.
native_tape_partitions proc near
        mov cx,NC_SIZE
        call native_packet
        jc partitions_bad
        cmp word ptr es:[di+NC_OPERATION],0
        jne partitions_bad
        cmp word ptr es:[di+NC_FLAGS],0
        jne partitions_bad
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
        call native_session_state
        mov word ptr [native_info+NC_SESSION],ax
        test al,1Fh
        NT_JUMP jnz,partitions_busy
        cmp byte ptr [tape_open_count],1
        NT_JUMP jne,partitions_busy
        cmp word ptr [buffer_count],0
        NT_JUMP jne,partitions_busy
        cmp byte ptr [request_rewind],0
        NT_JUMP jne,partitions_busy
        cmp byte ptr [request_buffered],0
        NT_JUMP jne,partitions_busy
        jmp short partitions_prepare
partitions_bad:
        stc
        ret
partitions_prepare:
        mov si,offset last_scsi_status
        mov di,offset native_saved
        mov cx,block_limits-last_scsi_status
        rep movsb
        mov di,offset native_reply
        mov cx,64
        mov al,0FFh
        rep stosb
        call prepare_control_srb
        mov byte ptr [srb+SRB_CDB],1Ah
        mov byte ptr [srb+SRB_CDB+2],11h
        mov byte ptr [srb+SRB_CDB+4],64
        mov byte ptr [native_info+NC_OPCODE],1Ah
        mov byte ptr [srb+SRB_Flags],SRB_DIR_IN
        test word ptr [adapter_ext_flags],HA_EXT_RESIDUAL
        jz partitions_flags_ready
        or byte ptr [srb+SRB_Flags],SRB_RESIDUAL
partitions_flags_ready:
        mov word ptr [srb+SRB_BufLen],64
        mov word ptr [srb+SRB_BufPointer],offset native_reply
        mov word ptr [srb+SRB_BufPointer+2],cs
        mov word ptr [native_info+NC_COMPLETION],1
        call call_aspi
        call check_tape_completion
        NT_JUMP jc,partitions_command_failed
        mov word ptr [native_info+NC_COMPLETION],3
        test word ptr [adapter_ext_flags],HA_EXT_RESIDUAL
        NT_JUMP jz,partitions_unverified
        test byte ptr [srb+SRB_Flags],SRB_RESIDUAL
        NT_JUMP jz,partitions_malformed
        cmp word ptr [srb+SRB_BufLen+2],0
        NT_JUMP jne,partitions_malformed
        mov ax,64
        sub ax,word ptr [srb+SRB_BufLen]
        NT_JUMP jc,partitions_malformed
        mov word ptr [native_actual],ax
        mov byte ptr [native_page],11h
        call native_find_mode_page
        NT_JUMP jc,partitions_malformed
        cmp cx,8
        jb partitions_malformed
        test cl,1                       ; complete two-byte size descriptors
        jnz partitions_malformed
        cmp byte ptr [si+7],0
        jne partitions_malformed
        sub cx,8
        shr cx,1
        mov word ptr [native_info+NM_DESCRIPTORS],cx
        xor ah,ah
        mov al,byte ptr [si+2]
        mov word ptr [native_info+NM_MAX],ax
        mov al,byte ptr [si+3]
        mov word ptr [native_info+NM_DEFINED],ax
        mov al,byte ptr [si+4]
        mov word ptr [native_info+NM_FLAGS],ax
        mov al,byte ptr [si+5]
        mov word ptr [native_info+NM_RECOGNITION],ax
        mov al,byte ptr [si+6]
        mov word ptr [native_info+NM_UNITS],ax
        mov word ptr [native_info+NM_VALID],1
        jmp short partitions_restore
partitions_malformed:
        mov word ptr [native_info+NC_RESULT],3
        mov word ptr [native_info+NC_DIAG],3
        jmp short partitions_restore
partitions_unverified:
        mov word ptr [native_info+NC_RESULT],1
        mov word ptr [native_info+NC_DIAG],5
        mov word ptr [native_info+NM_PROBE],1
        jmp short partitions_restore
partitions_command_failed:
        call native_read_diagnostics
partitions_restore:
        mov si,offset native_saved
        mov di,offset last_scsi_status
        mov cx,block_limits-last_scsi_status
        rep movsb
        jmp short partitions_output
partitions_busy:
        mov word ptr [native_info+NC_RESULT],2
partitions_output:
        les di,dword ptr [native_argument]
        mov si,offset native_info
        mov cx,NC_SIZE
        rep movsb
        clc
        ret
native_tape_partitions endp
