; Memory-only short logical READ POSITION. Big-endian test coordinates exceed
; signed LONG and WORD limits. Legacy/untrusted lengths must expose no address.
position_bytes db 0,2,0,0,89h,0ABh,0CDh,0EFh,0FEh,0DCh,0BAh,98h,0,0,0,0,0,0,0,0
native_position_command proc near
ifdef NATIVE_WIDE_TEST
        cmp byte ptr es:[bx+SRB_CDB+1],6
        jne position_not_wide
        jmp native_wide_position
position_not_wide:
endif
        jmp short position_mock_validate
position_mock_bad:
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
position_mock_validate:
        cmp byte ptr es:[bx+SRB_CDBLen],10
        jne position_mock_bad
        cmp byte ptr es:[bx+SRB_SenseLen],32
        jne position_mock_bad
ifdef NO_RESIDUAL
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN
else
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN or SRB_RESIDUAL
endif
        jne position_mock_bad
        cmp word ptr es:[bx+SRB_BufLen],20
        jne position_mock_bad
        cmp word ptr es:[bx+SRB_BufLen+2],0
        jne position_mock_bad
        mov si,1
position_cdb_zero:
        cmp byte ptr es:[bx+si+SRB_CDB],0
        jne position_mock_bad
        inc si
        cmp si,10
        jb position_cdb_zero
ifdef NATIVE_POSITION_KIND
if NATIVE_POSITION_KIND eq 1
        mov byte ptr cs:[position_bytes],4 ; BPU/LOLU
elseif NATIVE_POSITION_KIND eq 2
        mov byte ptr cs:[position_bytes],2 ; PERR
elseif NATIVE_POSITION_KIND eq 3
        mov byte ptr cs:[position_bytes],80h
        mov byte ptr cs:[position_bytes+1],0
        mov word ptr cs:[position_bytes+4],0
        mov word ptr cs:[position_bytes+6],0
        mov word ptr cs:[position_bytes+8],0
        mov word ptr cs:[position_bytes+10],0
elseif NATIVE_POSITION_KIND eq 4
        mov byte ptr cs:[position_bytes],40h
        mov byte ptr cs:[position_bytes+1],255
        mov word ptr cs:[position_bytes+4],0FFFFh
        mov word ptr cs:[position_bytes+6],0FFFFh
        mov word ptr cs:[position_bytes+8],0FFFFh
        mov word ptr cs:[position_bytes+10],0FFFFh
elseif NATIVE_POSITION_KIND eq 5
        mov byte ptr cs:[position_bytes],8 ; reserved flag
elseif NATIVE_POSITION_KIND eq 6
        mov byte ptr cs:[position_bytes+12],1
endif
endif
ifdef NATIVE_LOCATE_TEST
        mov al,byte ptr cs:[locate_partition]
        mov byte ptr cs:[position_bytes+1],al
        mov ax,word ptr cs:[locate_bytes]
        mov word ptr cs:[position_bytes+4],ax
        mov word ptr cs:[position_bytes+8],ax
        mov ax,word ptr cs:[locate_bytes+2]
        mov word ptr cs:[position_bytes+6],ax
        mov word ptr cs:[position_bytes+10],ax
endif
ifdef NATIVE_WIDE_TEST
        mov byte ptr cs:[position_bytes],0
        mov ax,word ptr cs:[locate_high]
        or ax,word ptr cs:[locate_high+2]
        jz position_wide_short_fits
        mov byte ptr cs:[position_bytes],4
position_wide_short_fits:
endif
        mov si,offset position_bytes
        mov cx,20
ifdef NATIVE_POSITION_KIND
if NATIVE_POSITION_KIND eq 7
        mov cx,12                      ; short transfer with SS_COMP
endif
endif
        call native_copy
ifdef NATIVE_POSITION_KIND
if NATIVE_POSITION_KIND eq 8
        mov word ptr es:[bx+SRB_BufLen+2],1
elseif NATIVE_POSITION_KIND eq 9
        and byte ptr es:[bx+SRB_Flags],not SRB_RESIDUAL
endif
endif
ifdef NATIVE_POSITION_FAULT
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+SRB_CDB+10],70h
        mov byte ptr es:[bx+SRB_CDB+10+7],6
        mov byte ptr es:[bx+SRB_CDB+10+2],3
if NATIVE_POSITION_FAULT eq 1
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_POSITION_FAULT eq 2
        mov byte ptr es:[bx+SRB_CDB+10+2],5
        mov byte ptr es:[bx+SRB_CDB+10+12],20h
elseif NATIVE_POSITION_FAULT eq 3
        mov byte ptr es:[bx+SRB_CDB+10],71h
elseif NATIVE_POSITION_FAULT eq 4
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_POSITION_FAULT eq 6
        mov byte ptr es:[bx+SRB_TargStat],8
elseif NATIVE_POSITION_FAULT eq 7
        mov byte ptr es:[bx+SRB_CDB+10+2],80h
endif
endif
        ret
native_position_command endp
