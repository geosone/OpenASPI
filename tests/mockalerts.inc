; Memory-only TapeAlert log. Successive explicit reads return a fresh snapshot;
; no counter reset/implicit status query is allowed to request this page.
AL_REQUIRE macro condition
        local accepted
        condition accepted
        jmp alert_mock_bad
accepted:
endm
alert_mock_data db 512 dup (0)
native_alerts_reply proc near
        cmp byte ptr es:[bx+SRB_CDBLen],10
        AL_REQUIRE je
        cmp byte ptr es:[bx+SRB_SenseLen],32
        AL_REQUIRE je
ifdef NO_RESIDUAL
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN
else
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN or SRB_RESIDUAL
endif
        AL_REQUIRE je
        cmp word ptr es:[bx+SRB_BufLen],512
        AL_REQUIRE je
        cmp word ptr es:[bx+SRB_BufLen+2],0
        AL_REQUIRE je
        cmp byte ptr es:[bx+SRB_CDB+1],0
        AL_REQUIRE je
        cmp byte ptr es:[bx+SRB_CDB+2],6Eh
        AL_REQUIRE je
        cmp word ptr es:[bx+SRB_CDB+3],0
        AL_REQUIRE je
        cmp word ptr es:[bx+SRB_CDB+5],0
        AL_REQUIRE je
        cmp word ptr es:[bx+SRB_CDB+7],2
        AL_REQUIRE je
        cmp byte ptr es:[bx+SRB_CDB+9],0
        AL_REQUIRE je
        push es
        push cs
        pop es
        mov di,offset alert_mock_data
        mov cx,512
        xor al,al
        rep stosb
        pop es
        mov byte ptr cs:[alert_mock_data],2Eh
        mov byte ptr cs:[alert_mock_data+3],25
        mov di,offset alert_mock_data+4
        mov ax,1
        call alert_mock_parameter
        mov ax,20
        call alert_mock_parameter
        mov ax,32
        call alert_mock_parameter
        mov ax,33
        call alert_mock_parameter
        mov ax,64
        call alert_mock_parameter
        mov byte ptr cs:[alert_mock_data+13],1 ; flag 20 active
        mov byte ptr cs:[alert_mock_data+18],1 ; flag 32 active
        mov byte ptr cs:[alert_mock_data+28],1 ; flag 64 active
        mov cx,29
ifdef NATIVE_ALERTS_KIND
if NATIVE_ALERTS_KIND eq 1 or NATIVE_ALERTS_KIND eq 2
        mov byte ptr cs:[alert_mock_data+2],1
        mov byte ptr cs:[alert_mock_data+3],40h
        mov di,offset alert_mock_data+4
        mov ax,1
alert_mock_all:
        call alert_mock_parameter
if NATIVE_ALERTS_KIND eq 1
        mov byte ptr cs:[di-1],1
endif
        inc ax
        cmp ax,65
        jb alert_mock_all
        mov cx,324
elseif NATIVE_ALERTS_KIND eq 3
        mov byte ptr cs:[alert_mock_data+3],0
        mov cx,4
elseif NATIVE_ALERTS_KIND eq 4
        dec cx                        ; declared page exceeds transfer
elseif NATIVE_ALERTS_KIND eq 5
        mov byte ptr cs:[alert_mock_data],6Eh ; unsupported subpage form
elseif NATIVE_ALERTS_KIND eq 6
        mov byte ptr cs:[alert_mock_data+1],1
elseif NATIVE_ALERTS_KIND eq 7
        mov byte ptr cs:[alert_mock_data+10],1 ; duplicate code
elseif NATIVE_ALERTS_KIND eq 8
        mov byte ptr cs:[alert_mock_data+4],0FFh ; unsorted following a future code
elseif NATIVE_ALERTS_KIND eq 9
        mov byte ptr cs:[alert_mock_data+7],2   ; wrong known parameter size
elseif NATIVE_ALERTS_KIND eq 10
        mov byte ptr cs:[alert_mock_data+13],2  ; non-boolean value
elseif NATIVE_ALERTS_KIND eq 11
        mov byte ptr cs:[alert_mock_data+6],41h ; list parameter, not numeric
elseif NATIVE_ALERTS_KIND eq 12
        mov byte ptr cs:[alert_mock_data+3],26  ; incomplete trailing header
        mov cx,30
elseif NATIVE_ALERTS_KIND eq 15
        mov byte ptr cs:[alert_mock_data+29],0
        mov byte ptr cs:[alert_mock_data+30],65
        mov byte ptr cs:[alert_mock_data+32],0 ; complete unknown zero-length field
        mov byte ptr cs:[alert_mock_data+3],29
        mov cx,33
elseif NATIVE_ALERTS_KIND eq 16
        mov byte ptr cs:[alert_mock_data],0AEh ; DS bit is not a page code
elseif NATIVE_ALERTS_KIND eq 17
        mov byte ptr cs:[alert_mock_data+3],0
        mov byte ptr cs:[alert_mock_data+2],2 ; page length exceeds allocation
elseif NATIVE_ALERTS_KIND eq 18
        mov byte ptr cs:[alert_mock_data+5],0 ; invalid parameter zero
endif
endif
        mov si,offset alert_mock_data
        call native_copy
ifdef NATIVE_ALERTS_KIND
if NATIVE_ALERTS_KIND eq 13
        mov word ptr es:[bx+SRB_BufLen+2],1
elseif NATIVE_ALERTS_KIND eq 14
        and byte ptr es:[bx+SRB_Flags],not SRB_RESIDUAL
endif
endif
ifdef NATIVE_ALERTS_FAULT
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+SRB_CDB+10],70h
        mov byte ptr es:[bx+SRB_CDB+12],3
        mov byte ptr es:[bx+SRB_CDB+17],6
if NATIVE_ALERTS_FAULT eq 1
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_ALERTS_FAULT eq 2
        mov byte ptr es:[bx+SRB_CDB+12],5
        mov byte ptr es:[bx+SRB_CDB+22],20h
elseif NATIVE_ALERTS_FAULT eq 3
        mov byte ptr es:[bx+SRB_CDB+10],71h
elseif NATIVE_ALERTS_FAULT eq 4
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_ALERTS_FAULT eq 6
        mov byte ptr es:[bx+SRB_TargStat],8
elseif NATIVE_ALERTS_FAULT eq 7
        mov byte ptr es:[bx+SRB_CDB+10],72h
        mov byte ptr es:[bx+SRB_CDB+11],5
        mov byte ptr es:[bx+SRB_CDB+12],24h
        mov byte ptr es:[bx+SRB_CDB+17],0
endif
endif
        ret
alert_mock_bad:
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
native_alerts_reply endp
alert_mock_parameter proc near
        mov byte ptr cs:[di],ah
        mov byte ptr cs:[di+1],al
        mov byte ptr cs:[di+2],40h
        mov byte ptr cs:[di+3],1
        mov byte ptr cs:[di+4],0
        add di,5
        ret
alert_mock_parameter endp
