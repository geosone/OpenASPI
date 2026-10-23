; Memory-only SPACE command qualification. No media/controller access.
native_space_calls dw 0
space_expected db 0,0,0,1, 0,0FFh,0FFh,0FFh, 0,7Fh,0FFh,0FFh
               db 0,80h,0,0, 0,0,0,0, 1,0,0,2, 1,0FFh,0FFh,0FEh, 3,0,0,0
native_space_command proc near
        cmp byte ptr es:[bx+SRB_CDBLen],6
        jne space_mock_bad
        cmp byte ptr es:[bx+SRB_SenseLen],32
        jne space_mock_bad
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_NONE
        jne space_mock_bad
        cmp word ptr es:[bx+SRB_BufLen],0
        jne space_mock_bad
        cmp word ptr es:[bx+SRB_BufLen+2],0
        jne space_mock_bad
        cmp word ptr es:[bx+SRB_BufPointer],0
        jne space_mock_bad
        cmp word ptr es:[bx+SRB_BufPointer+2],0
        jne space_mock_bad
        cmp byte ptr es:[bx+SRB_CDB+5],0
        jne space_mock_bad
ifdef NATIVE_SPACE_FAULT
        xor si,si                        ; fault and recovery both request +1
else
        mov si,word ptr cs:[native_space_calls]
        cmp si,8
        jae space_mock_bad
        shl si,1
        shl si,1
endif
        mov ax,word ptr cs:[si+space_expected]
        cmp word ptr es:[bx+SRB_CDB+1],ax
        jne space_mock_bad
        mov ax,word ptr cs:[si+space_expected+2]
        cmp word ptr es:[bx+SRB_CDB+3],ax
        jne space_mock_bad
        inc word ptr cs:[native_space_calls]
        mov byte ptr es:[bx+SRB_Status],SS_COMP
ifdef NATIVE_SPACE_FAULT
        cmp word ptr cs:[native_space_calls],1
        jne space_mock_done
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+TAPE_SENSE],70h
        mov byte ptr es:[bx+TAPE_SENSE+7],6
        mov byte ptr es:[bx+TAPE_SENSE+2],3
if NATIVE_SPACE_FAULT eq 1
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_SPACE_FAULT eq 2
        mov byte ptr es:[bx+TAPE_SENSE+2],5
        mov byte ptr es:[bx+TAPE_SENSE+12],20h
elseif NATIVE_SPACE_FAULT eq 3
        mov byte ptr es:[bx+TAPE_SENSE],71h
elseif NATIVE_SPACE_FAULT eq 4
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_SPACE_FAULT eq 5
        mov byte ptr es:[bx+TAPE_SENSE+2],80h ; mark is not successful SPACE
endif
endif
space_mock_done:
        ret
space_mock_bad:
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
native_space_command endp
