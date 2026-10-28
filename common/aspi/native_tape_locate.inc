; Explicit synchronous LOCATE(10), logical object coordinate. Unlike an
; observation this requires a clean native session; ambiguous failures latch
; FAILED and are never replayed or replaced by rewind/SPACE emulation.
native_tape_locate proc near
        mov cx,NC_SIZE
        call native_packet
        NT_JUMP jc,locate_bad
        mov bx,word ptr es:[di+NC_OPERATION]
        cmp bx,1
        NT_JUMP ja,locate_bad
        mov ax,word ptr es:[di+NC_FLAGS]
        cmp ax,1
        NT_JUMP ja,locate_bad
        cmp word ptr es:[di+NL_PARTITION+2],0
        NT_JUMP jne,locate_bad
        mov dx,word ptr es:[di+NL_PARTITION]
        cmp dx,255
        NT_JUMP ja,locate_bad
        or ax,ax
        jnz locate_valid
        or dx,dx                        ; CP clear ignores partition: require 0
        NT_JUMP jnz,locate_bad
locate_valid:
        push bx
        or bx,bx
        jz locate_short_high
        push word ptr es:[di+NL64_HIGH+2]
        push word ptr es:[di+NL64_HIGH]
        jmp short locate_high_saved
locate_short_high:
        xor bx,bx
        push bx
        push bx
locate_high_saved:
        push ax
        push dx
        push word ptr es:[di+NL_BLOCK+2]
        push word ptr es:[di+NL_BLOCK]
        push cs
        pop es
        mov di,offset native_info
        mov cx,NC_SIZE
        xor al,al
        rep stosb
        pop word ptr [native_info+NL_BLOCK]
        pop word ptr [native_info+NL_BLOCK+2]
        pop word ptr [native_info+NL_PARTITION]
        pop word ptr [native_info+NC_FLAGS]
        pop word ptr [native_info+NL64_HIGH]
        pop word ptr [native_info+NL64_HIGH+2]
        pop word ptr [native_info+NC_OPERATION]
        mov word ptr [native_info],544Fh
        mov word ptr [native_info+2],5041h
        mov word ptr [native_info+4],NC_SIZE
        mov word ptr [native_info+6],NT_VERSION
        call native_session_state
        mov word ptr [native_info+NC_SESSION],ax
        or ax,ax
        NT_JUMP jnz,locate_busy
        cmp byte ptr [tape_open_count],1
        NT_JUMP jne,locate_busy
        cmp word ptr [buffer_count],0
        NT_JUMP jne,locate_busy
        cmp byte ptr [request_rewind],0
        NT_JUMP jne,locate_busy
        cmp byte ptr [request_buffered],0
        NT_JUMP jne,locate_busy
        jmp short locate_submit
locate_bad:
        stc
        ret
locate_submit:
        call prepare_control_srb
        cmp word ptr [native_info+NC_OPERATION],1
        je locate_wide_submit
        mov byte ptr [srb+SRB_CDBLen],10
        mov byte ptr [srb+SRB_CDB],2Bh
        mov byte ptr [native_info+NC_OPCODE],2Bh
        cmp word ptr [native_info+NC_FLAGS],0
        je locate_partition_ready
        mov byte ptr [srb+SRB_CDB+1],2 ; CP only: BT and IMMED remain zero
        mov al,byte ptr [native_info+NL_PARTITION]
        mov byte ptr [srb+SRB_CDB+8],al
locate_partition_ready:
        mov ax,word ptr [native_info+NL_BLOCK+2]
        mov byte ptr [srb+SRB_CDB+3],ah
        mov byte ptr [srb+SRB_CDB+4],al
        mov ax,word ptr [native_info+NL_BLOCK]
        mov byte ptr [srb+SRB_CDB+5],ah
        mov byte ptr [srb+SRB_CDB+6],al
        jmp short locate_execute
locate_wide_submit:
        mov byte ptr [srb+SRB_CDBLen],16
        mov byte ptr [srb+SRB_CDB],92h
        mov byte ptr [native_info+NC_OPCODE],92h
        cmp word ptr [native_info+NC_FLAGS],0
        je locate_wide_partition_ready
        mov byte ptr [srb+SRB_CDB+1],2
        mov al,byte ptr [native_info+NL_PARTITION]
        mov byte ptr [srb+SRB_CDB+3],al
locate_wide_partition_ready:
        mov ax,word ptr [native_info+NL64_HIGH+2]
        mov byte ptr [srb+SRB_CDB+4],ah
        mov byte ptr [srb+SRB_CDB+5],al
        mov ax,word ptr [native_info+NL64_HIGH]
        mov byte ptr [srb+SRB_CDB+6],ah
        mov byte ptr [srb+SRB_CDB+7],al
        mov ax,word ptr [native_info+NL_BLOCK+2]
        mov byte ptr [srb+SRB_CDB+8],ah
        mov byte ptr [srb+SRB_CDB+9],al
        mov ax,word ptr [native_info+NL_BLOCK]
        mov byte ptr [srb+SRB_CDB+10],ah
        mov byte ptr [srb+SRB_CDB+11],al
locate_execute:
        mov word ptr [native_info+NC_COMPLETION],1
        call execute_control_srb
        jc locate_failed
        mov word ptr [native_info+NC_COMPLETION],3
        jmp short locate_output         ; not a BOT or absolute-position probe
locate_failed:
        call native_control_diagnostics
        mov word ptr [native_info+NC_COMPLETION],5
        or byte ptr [native_write_state],4
        call native_session_state
        mov word ptr [native_info+NC_SESSION],ax
        jmp short locate_output
locate_busy:
        mov word ptr [native_info+NC_RESULT],2
locate_output:
        les di,dword ptr [native_argument]
        mov si,offset native_info
        mov cx,NC_SIZE
        rep movsb
        clc
        ret
native_tape_locate endp
