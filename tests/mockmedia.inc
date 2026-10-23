; Synchronous sequential LOAD/UNLOAD: no host device or changer access.
; The loaded state survives counter resets, so recovery must really LOAD.
native_media_calls dw 0
native_media_loaded db 1
native_media_command proc near
        jmp short media_mock_validate
media_mock_bad:
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
media_mock_validate:
        cmp byte ptr es:[bx+SRB_CDBLen],6
        jne media_mock_bad
        cmp byte ptr es:[bx+SRB_SenseLen],32
        jne media_mock_bad
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_NONE
        jne media_mock_bad
        cmp word ptr es:[bx+SRB_BufLen],0
        jne media_mock_bad
        cmp word ptr es:[bx+SRB_BufLen+2],0
        jne media_mock_bad
        cmp word ptr es:[bx+SRB_BufPointer],0
        jne media_mock_bad
        cmp word ptr es:[bx+SRB_BufPointer+2],0
        jne media_mock_bad
        cmp word ptr es:[bx+SRB_CDB+1],0
        jne media_mock_bad
        cmp byte ptr es:[bx+SRB_CDB+3],0
        jne media_mock_bad
        cmp byte ptr es:[bx+SRB_CDB+4],1
        ja media_mock_bad
        cmp byte ptr es:[bx+SRB_CDB+5],0
        jne media_mock_bad
        inc word ptr cs:[native_media_calls]
ifdef NATIVE_MEDIA_FAULT
        cmp word ptr cs:[native_media_calls],1
        jne media_mock_success
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+TAPE_SENSE],70h
        mov byte ptr es:[bx+TAPE_SENSE+7],6
        mov byte ptr es:[bx+TAPE_SENSE+2],3
if NATIVE_MEDIA_FAULT eq 1
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_MEDIA_FAULT eq 2
        mov byte ptr es:[bx+TAPE_SENSE+2],5
        mov byte ptr es:[bx+TAPE_SENSE+12],20h
elseif NATIVE_MEDIA_FAULT eq 3
        mov byte ptr es:[bx+TAPE_SENSE],71h
elseif NATIVE_MEDIA_FAULT eq 4
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_MEDIA_FAULT eq 6
        mov byte ptr es:[bx+SRB_TargStat],8
elseif NATIVE_MEDIA_FAULT eq 7
        mov byte ptr es:[bx+TAPE_SENSE+2],80h
endif
        ret
endif
media_mock_success:
        mov al,byte ptr es:[bx+SRB_CDB+4]
        mov byte ptr cs:[native_media_loaded],al
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        ret
native_media_command endp

native_media_read proc near
        cmp byte ptr cs:[native_media_loaded],0
        jne media_mock_bad
        cmp byte ptr es:[bx+SRB_CDBLen],6
        jne media_mock_bad
ifdef NO_RESIDUAL
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN
else
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN or SRB_RESIDUAL
endif
        jne media_mock_bad
        ; Preserve the requested residual: no bytes transferred, no FILEMARK.
        jmp native_media_notready
media_mock_bad:
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
native_media_read endp
native_media_notready proc near
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+TAPE_SENSE],70h
        mov byte ptr es:[bx+TAPE_SENSE+2],2
        mov byte ptr es:[bx+TAPE_SENSE+7],6
        mov byte ptr es:[bx+TAPE_SENSE+12],3Ah
        ret
native_media_notready endp
