; Synchronous WRITE FILEMARKS with WSMK. Counts attempts separately from data,
; filemarks and zero-mark flushes; every profile is memory-only.
native_setmarks dw 0
SW_REQUIRE macro condition
        local accepted
        condition accepted
        jmp setwrite_bad
accepted:
endm
native_write_setmark_command proc near
        cmp byte ptr es:[bx+SRB_CDBLen],6
        SW_REQUIRE je
        cmp byte ptr es:[bx+SRB_SenseLen],32
        SW_REQUIRE je
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_NONE
        SW_REQUIRE je
        cmp word ptr es:[bx+SRB_BufLen],0
        SW_REQUIRE je
        cmp word ptr es:[bx+SRB_BufLen+2],0
        SW_REQUIRE je
        cmp word ptr es:[bx+SRB_BufPointer],0
        SW_REQUIRE je
        cmp word ptr es:[bx+SRB_BufPointer+2],0
        SW_REQUIRE je
        cmp byte ptr es:[bx+SRB_CDB+1],2 ; WSMK only, no IMMED
        SW_REQUIRE je
        cmp word ptr es:[bx+SRB_CDB+2],0
        SW_REQUIRE je
        cmp byte ptr es:[bx+SRB_CDB+4],1
        SW_REQUIRE je
        cmp byte ptr es:[bx+SRB_CDB+5],0
        SW_REQUIRE je
        inc word ptr cs:[native_setmarks]
        mov byte ptr es:[bx+SRB_Status],SS_COMP
ifdef NATIVE_SETWRITE_FAULT
        cmp word ptr cs:[native_setmarks],1
        jne setwrite_done
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+TAPE_SENSE],70h
        mov byte ptr es:[bx+TAPE_SENSE+7],6
        mov byte ptr es:[bx+TAPE_SENSE+2],3
        mov byte ptr es:[bx+TAPE_SENSE+12],0Ch
if NATIVE_SETWRITE_FAULT eq 1
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_SETWRITE_FAULT eq 2
        mov byte ptr es:[bx+TAPE_SENSE+2],5
        mov byte ptr es:[bx+TAPE_SENSE+12],20h
elseif NATIVE_SETWRITE_FAULT eq 3
        mov byte ptr es:[bx+TAPE_SENSE],71h
elseif NATIVE_SETWRITE_FAULT eq 4
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_SETWRITE_FAULT eq 6
        mov byte ptr es:[bx+SRB_TargStat],8
elseif NATIVE_SETWRITE_FAULT eq 7
        mov byte ptr es:[bx+TAPE_SENSE+2],80h
        mov byte ptr es:[bx+TAPE_SENSE+12],0
        mov byte ptr es:[bx+TAPE_SENSE+13],1
elseif NATIVE_SETWRITE_FAULT eq 8
        mov byte ptr es:[bx+TAPE_SENSE],72h
        mov byte ptr es:[bx+TAPE_SENSE+1],5
        mov byte ptr es:[bx+TAPE_SENSE+2],24h
        mov byte ptr es:[bx+TAPE_SENSE+7],0
elseif NATIVE_SETWRITE_FAULT eq 9
        mov byte ptr es:[bx+TAPE_SENSE+2],7
        mov byte ptr es:[bx+TAPE_SENSE+12],27h
endif
endif
setwrite_done:
        ret
setwrite_bad:
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
native_write_setmark_command endp
