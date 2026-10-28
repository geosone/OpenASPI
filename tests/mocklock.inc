; Memory-only medium removal policy, separate from writer ownership.
; Lock state survives counter reset and rewind. Never infer write protection.
native_lock_calls dw 0
native_locked db 0
native_lock_command proc near
        jmp short lock_mock_validate
lock_mock_bad:
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
lock_mock_validate:
        cmp byte ptr es:[bx+SRB_CDBLen],6
        jne lock_mock_bad
        cmp byte ptr es:[bx+SRB_SenseLen],32
        jne lock_mock_bad
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_NONE
        jne lock_mock_bad
        cmp word ptr es:[bx+SRB_BufLen],0
        jne lock_mock_bad
        cmp word ptr es:[bx+SRB_BufLen+2],0
        jne lock_mock_bad
        cmp word ptr es:[bx+SRB_BufPointer],0
        jne lock_mock_bad
        cmp word ptr es:[bx+SRB_BufPointer+2],0
        jne lock_mock_bad
        cmp word ptr es:[bx+SRB_CDB+1],0
        jne lock_mock_bad
        cmp byte ptr es:[bx+SRB_CDB+3],0
        jne lock_mock_bad
        cmp byte ptr es:[bx+SRB_CDB+4],1
        ja lock_mock_bad
        cmp byte ptr es:[bx+SRB_CDB+5],0
        jne lock_mock_bad
        inc word ptr cs:[native_lock_calls]
ifdef NATIVE_LOCK_FAULT
        cmp word ptr cs:[native_lock_calls],1
        jne lock_mock_success
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+TAPE_SENSE],70h
        mov byte ptr es:[bx+TAPE_SENSE+7],6
        mov byte ptr es:[bx+TAPE_SENSE+2],3
if NATIVE_LOCK_FAULT eq 1
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_LOCK_FAULT eq 2
        mov byte ptr es:[bx+TAPE_SENSE+2],5
        mov byte ptr es:[bx+TAPE_SENSE+12],20h
elseif NATIVE_LOCK_FAULT eq 3
        mov byte ptr es:[bx+TAPE_SENSE],71h
elseif NATIVE_LOCK_FAULT eq 4
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_LOCK_FAULT eq 6
        mov byte ptr es:[bx+SRB_TargStat],8
elseif NATIVE_LOCK_FAULT eq 7
        mov byte ptr es:[bx+TAPE_SENSE+2],80h
elseif NATIVE_LOCK_FAULT eq 8
        mov byte ptr es:[bx+TAPE_SENSE+2],6 ; current UNIT ATTENTION: reset
        mov byte ptr es:[bx+TAPE_SENSE+12],29h
endif
        ret
endif
lock_mock_success:
        mov al,byte ptr es:[bx+SRB_CDB+4]
        mov byte ptr cs:[native_locked],al
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        ret
native_lock_command endp

native_removal_prevented proc near
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+TAPE_SENSE],70h
        mov byte ptr es:[bx+TAPE_SENSE+2],5
        mov byte ptr es:[bx+TAPE_SENSE+7],6
        mov byte ptr es:[bx+TAPE_SENSE+12],53h
        mov byte ptr es:[bx+TAPE_SENSE+13],2
        ret
native_removal_prevented endp
