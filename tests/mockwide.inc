; Memory-only wide cursor. One counter for LOCATE(16), shared physical low/high
; cursor with LOCATE(10); no disk/tape/controller on the host is accessed.
wide_calls dw 0
wide_data db 0,0,0,0,0,0,0,2, 16 dup (0), 8 dup (0A5h)
native_wide_locate proc near
        jmp short wide_locate_validate
wide_bad:
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
wide_locate_validate:
        cmp byte ptr es:[bx+SRB_CDBLen],16
        jne wide_bad
        cmp byte ptr es:[bx+SRB_SenseLen],32
        jne wide_bad
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_NONE
        jne wide_bad
        cmp word ptr es:[bx+SRB_BufLen],0
        jne wide_bad
        cmp word ptr es:[bx+SRB_BufLen+2],0
        jne wide_bad
        cmp word ptr es:[bx+SRB_BufPointer],0
        jne wide_bad
        cmp word ptr es:[bx+SRB_BufPointer+2],0
        jne wide_bad
        cmp byte ptr es:[bx+SRB_CDB+2],0
        jne wide_bad
        cmp word ptr es:[bx+SRB_CDB+12],0
        jne wide_bad
        cmp word ptr es:[bx+SRB_CDB+14],0
        jne wide_bad
        mov al,byte ptr es:[bx+SRB_CDB+1]
        cmp al,2
        je wide_locate_cp
        or al,al
        jne wide_bad
        cmp byte ptr es:[bx+SRB_CDB+3],0
        jne wide_bad
wide_locate_cp:
        inc word ptr cs:[wide_calls]
ifdef NATIVE_WIDE_FAULT
        cmp word ptr cs:[wide_calls],1
        jne wide_locate_good
        mov word ptr cs:[locate_high],0ADDEh
        mov word ptr cs:[locate_high+2],0EFBEh
        mov word ptr cs:[locate_bytes],0EDFEh
        mov word ptr cs:[locate_bytes+2],0CEFAh
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+SRB_CDB+16],70h
        mov byte ptr es:[bx+SRB_CDB+18],3
        mov byte ptr es:[bx+SRB_CDB+23],6
if NATIVE_WIDE_FAULT eq 1
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_WIDE_FAULT eq 2
        mov byte ptr es:[bx+SRB_CDB+18],5
        mov byte ptr es:[bx+SRB_CDB+28],20h
elseif NATIVE_WIDE_FAULT eq 3
        mov byte ptr es:[bx+SRB_CDB+16],71h
elseif NATIVE_WIDE_FAULT eq 4
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_WIDE_FAULT eq 5
        mov byte ptr es:[bx+SRB_CDB+16],72h
        mov byte ptr es:[bx+SRB_CDB+17],5
        mov byte ptr es:[bx+SRB_CDB+18],24h
        mov byte ptr es:[bx+SRB_CDB+23],0
elseif NATIVE_WIDE_FAULT eq 6
        mov byte ptr es:[bx+SRB_TargStat],8
endif
        ret
endif
wide_locate_good:
        test byte ptr es:[bx+SRB_CDB+1],2
        jz wide_keep_partition
        mov al,byte ptr es:[bx+SRB_CDB+3]
        mov byte ptr cs:[locate_partition],al
wide_keep_partition:
        mov ax,word ptr es:[bx+SRB_CDB+4]
        mov word ptr cs:[locate_high],ax
        mov ax,word ptr es:[bx+SRB_CDB+6]
        mov word ptr cs:[locate_high+2],ax
        mov ax,word ptr es:[bx+SRB_CDB+8]
        mov word ptr cs:[locate_bytes],ax
        mov ax,word ptr es:[bx+SRB_CDB+10]
        mov word ptr cs:[locate_bytes+2],ax
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        ret
native_wide_locate endp

native_wide_position proc near
        jmp short wide_position_validate
wide_bad:
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
wide_position_validate:
        cmp byte ptr es:[bx+SRB_CDBLen],10
        jne wide_bad
        cmp byte ptr es:[bx+SRB_SenseLen],32
        jne wide_bad
ifdef NO_RESIDUAL
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN
else
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN or SRB_RESIDUAL
endif
        jne wide_bad
        cmp word ptr es:[bx+SRB_BufLen],32
        jne wide_bad
        cmp word ptr es:[bx+SRB_BufLen+2],0
        jne wide_bad
        cmp byte ptr es:[bx+SRB_CDB+1],6
        jne wide_bad
        mov si,2
wide_position_zero:
        cmp byte ptr es:[bx+si+SRB_CDB],0
        jne wide_bad
        inc si
        cmp si,10
        jb wide_position_zero
ifdef NATIVE_UI_TEST
        cmp byte ptr cs:[native_media_loaded],0
        jne wide_ui_loaded
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+SRB_CDB+10],70h
        mov byte ptr es:[bx+SRB_CDB+12],2
        mov byte ptr es:[bx+SRB_CDB+17],6
        mov byte ptr es:[bx+SRB_CDB+22],3Ah
        ret
wide_ui_loaded:
endif
        mov al,byte ptr cs:[locate_partition]
        mov byte ptr cs:[wide_data+7],al
        mov ax,word ptr cs:[locate_high]
        mov word ptr cs:[wide_data+8],ax
        mov ax,word ptr cs:[locate_high+2]
        mov word ptr cs:[wide_data+10],ax
        mov ax,word ptr cs:[locate_bytes]
        mov word ptr cs:[wide_data+12],ax
        mov ax,word ptr cs:[locate_bytes+2]
        mov word ptr cs:[wide_data+14],ax
        mov byte ptr cs:[wide_data+19],1
        mov byte ptr cs:[wide_data+23],7 ; logical file = 4294967303
ifdef NATIVE_WIDE_CASE
if NATIVE_WIDE_CASE eq 1
        mov byte ptr cs:[wide_data],4
elseif NATIVE_WIDE_CASE eq 2
        mov byte ptr cs:[wide_data],8
elseif NATIVE_WIDE_CASE eq 3
        mov byte ptr cs:[wide_data],12
elseif NATIVE_WIDE_CASE eq 4
        mov byte ptr cs:[wide_data],20h
elseif NATIVE_WIDE_CASE eq 7
        mov byte ptr cs:[wide_data+1],1
elseif NATIVE_WIDE_CASE eq 9
        mov word ptr cs:[wide_data+4],0FFFFh
        mov word ptr cs:[wide_data+6],0FFFFh
endif
endif
        mov si,offset wide_data
        mov cx,32
ifdef NATIVE_WIDE_CASE
if NATIVE_WIDE_CASE eq 5
        mov cx,16
endif
endif
        call native_copy
ifdef NATIVE_WIDE_CASE
if NATIVE_WIDE_CASE eq 6
        and byte ptr es:[bx+SRB_Flags],not SRB_RESIDUAL
elseif NATIVE_WIDE_CASE eq 8
        mov word ptr es:[bx+SRB_BufLen+2],1
endif
endif
ifdef NATIVE_WIDE_POS_FAULT
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_HaStat],11h
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+SRB_CDB+10],70h
        mov byte ptr es:[bx+SRB_CDB+12],5
        mov byte ptr es:[bx+SRB_CDB+17],6
        mov byte ptr es:[bx+SRB_CDB+22],20h
endif
        ret
native_wide_position endp
