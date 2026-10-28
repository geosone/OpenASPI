; Memory-only LOCATE target, shared with READ POSITION for independent readback.
; Counter resets leave the physical cursor alone. No host tape is attached.
locate_calls dw 0
locate_partition db 2
locate_high db 0,0,0,0
locate_bytes db 0,0,0,0                 ; big-endian logical object address
native_locate_command proc near
        jmp short locate_mock_validate
locate_mock_bad:
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
locate_mock_validate:
        cmp byte ptr es:[bx+SRB_CDBLen],10
        jne locate_mock_bad
        cmp byte ptr es:[bx+SRB_SenseLen],32
        jne locate_mock_bad
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_NONE
        jne locate_mock_bad
        cmp word ptr es:[bx+SRB_BufLen],0
        jne locate_mock_bad
        cmp word ptr es:[bx+SRB_BufLen+2],0
        jne locate_mock_bad
        cmp word ptr es:[bx+SRB_BufPointer],0
        jne locate_mock_bad
        cmp word ptr es:[bx+SRB_BufPointer+2],0
        jne locate_mock_bad
        mov al,byte ptr es:[bx+SRB_CDB+1]
        cmp al,2
        je locate_mock_cp
        or al,al
        jne locate_mock_bad
        cmp byte ptr es:[bx+SRB_CDB+8],0
        jne locate_mock_bad
locate_mock_cp:
        cmp byte ptr es:[bx+SRB_CDB+2],0
        jne locate_mock_bad
        cmp byte ptr es:[bx+SRB_CDB+7],0
        jne locate_mock_bad
        cmp byte ptr es:[bx+SRB_CDB+9],0
        jne locate_mock_bad
        inc word ptr cs:[locate_calls]
ifdef NATIVE_LOCATE_FAULT
        cmp word ptr cs:[locate_calls],1
        jne locate_mock_success
        ; Failed motion may have moved. Observation must not clear FAILED.
        mov word ptr cs:[locate_bytes],0ADDEh
        mov word ptr cs:[locate_bytes+2],0EFBEh
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+SRB_CDB+10],70h
        mov byte ptr es:[bx+SRB_CDB+17],6
        mov byte ptr es:[bx+SRB_CDB+12],3
if NATIVE_LOCATE_FAULT eq 1
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_LOCATE_FAULT eq 2
        mov byte ptr es:[bx+SRB_CDB+12],5
        mov byte ptr es:[bx+SRB_CDB+22],20h
elseif NATIVE_LOCATE_FAULT eq 3
        mov byte ptr es:[bx+SRB_CDB+10],71h
elseif NATIVE_LOCATE_FAULT eq 4
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_LOCATE_FAULT eq 6
        mov byte ptr es:[bx+SRB_TargStat],8
elseif NATIVE_LOCATE_FAULT eq 7
        mov byte ptr es:[bx+SRB_CDB+12],80h
elseif NATIVE_LOCATE_FAULT eq 8
        mov byte ptr es:[bx+SRB_CDB+10],72h
        mov byte ptr es:[bx+SRB_CDB+11],5
        mov byte ptr es:[bx+SRB_CDB+12],24h
        mov byte ptr es:[bx+SRB_CDB+17],0
endif
        ret
endif
locate_mock_success:
ifdef NATIVE_WIDE_TEST
        mov word ptr cs:[locate_high],0
        mov word ptr cs:[locate_high+2],0
endif
        test byte ptr es:[bx+SRB_CDB+1],2
        jz locate_mock_keep_partition
        mov al,byte ptr es:[bx+SRB_CDB+8]
        mov byte ptr cs:[locate_partition],al
locate_mock_keep_partition:
        mov ax,word ptr es:[bx+SRB_CDB+3]
        mov word ptr cs:[locate_bytes],ax
        mov ax,word ptr es:[bx+SRB_CDB+5]
        mov word ptr cs:[locate_bytes+2],ax
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        ret
native_locate_command endp
