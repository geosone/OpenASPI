; Memory-only classified READ marks. Match CDB, data direction and byte/block
; units independently of the C consumer; never touch a host SCSI device.
SM_REQUIRE macro condition
        local accepted
        condition accepted
        jmp setmark_bad
accepted:
endm
native_setmark_read proc near
        cmp byte ptr es:[bx+SRB_CDBLen],6
        SM_REQUIRE je
        cmp byte ptr es:[bx+SRB_SenseLen],32
        SM_REQUIRE je
        cmp word ptr es:[bx+SRB_BufLen+2],0
        SM_REQUIRE je
        cmp byte ptr es:[bx+SRB_CDB+2],0
        SM_REQUIRE je
        cmp byte ptr es:[bx+SRB_CDB+3],0
        SM_REQUIRE je
        cmp byte ptr es:[bx+SRB_CDB+5],0
        SM_REQUIRE je
ifdef NO_RESIDUAL
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN
else
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN or SRB_RESIDUAL
endif
        SM_REQUIRE je
ifdef NATIVE_SETMARK_FIXED
        cmp byte ptr es:[bx+SRB_CDB+1],1
        SM_REQUIRE je
        mov ax,word ptr es:[bx+SRB_BufLen]
        cmp ax,512
        je setmark_fixed_length
        cmp ax,1024
        SM_REQUIRE je
setmark_fixed_length:
        mov cl,9
        shr ax,cl
        cmp al,byte ptr es:[bx+SRB_CDB+4]
        SM_REQUIRE je
else
        cmp byte ptr es:[bx+SRB_CDB+1],0
        SM_REQUIRE je
        cmp byte ptr es:[bx+SRB_CDB+4],8
        SM_REQUIRE je
        cmp word ptr es:[bx+SRB_BufLen],8
        SM_REQUIRE je
endif
        xor cx,cx
ifdef NATIVE_SETMARK_DATA
ifdef NATIVE_SETMARK_FIXED
        cmp word ptr es:[bx+SRB_BufLen],1024
        jne setmark_copy
        mov cx,512
else
        mov cx,4
endif
endif
setmark_copy:
        mov si,offset setmark_bytes
        call native_copy
        mov ax,word ptr cs:[native_length] ; bytes remaining, also for legacy ASPI
ifdef NATIVE_SETMARK_FIXED
        mov cl,9
        shr ax,cl                       ; sense information uses blocks
endif
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
ifdef NATIVE_SETMARK_DESCRIPTOR
        mov byte ptr es:[bx+TAPE_SENSE],72h
        mov byte ptr es:[bx+TAPE_SENSE+3],3
        mov byte ptr es:[bx+TAPE_SENSE+7],16
        mov byte ptr es:[bx+TAPE_SENSE+9],0Ah
        mov byte ptr es:[bx+TAPE_SENSE+10],80h
        mov byte ptr es:[bx+TAPE_SENSE+19],al
        mov byte ptr es:[bx+TAPE_SENSE+20],4
        mov byte ptr es:[bx+TAPE_SENSE+21],2
        mov byte ptr es:[bx+TAPE_SENSE+23],80h
else
        mov byte ptr es:[bx+TAPE_SENSE],0F0h
        mov byte ptr es:[bx+TAPE_SENSE+2],80h
        mov byte ptr es:[bx+TAPE_SENSE+6],al
        mov byte ptr es:[bx+TAPE_SENSE+7],6
        mov byte ptr es:[bx+TAPE_SENSE+13],3
endif
ifdef NATIVE_SETMARK_NOINFO
ifdef NATIVE_SETMARK_DESCRIPTOR
        mov byte ptr es:[bx+TAPE_SENSE+10],0
else
        and byte ptr es:[bx+TAPE_SENSE],7Fh
endif
endif
ifdef NATIVE_SETMARK_FAULT
if NATIVE_SETMARK_FAULT eq 1
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_SETMARK_FAULT eq 2
ifdef NATIVE_SETMARK_DESCRIPTOR
        mov byte ptr es:[bx+TAPE_SENSE],73h
else
        mov byte ptr es:[bx+TAPE_SENSE],0F1h
endif
elseif NATIVE_SETMARK_FAULT eq 3
        mov byte ptr es:[bx+SRB_Status],SS_COMP
elseif NATIVE_SETMARK_FAULT eq 4
ifdef NATIVE_SETMARK_DESCRIPTOR
        mov byte ptr es:[bx+TAPE_SENSE+1],3
else
        or byte ptr es:[bx+TAPE_SENSE+2],3
endif
elseif NATIVE_SETMARK_FAULT eq 5
ifdef NATIVE_SETMARK_DESCRIPTOR
        mov byte ptr es:[bx+TAPE_SENSE+23],0
else
        mov byte ptr es:[bx+TAPE_SENSE+2],0
endif
elseif NATIVE_SETMARK_FAULT eq 6
ifdef NATIVE_SETMARK_DESCRIPTOR
        inc byte ptr es:[bx+TAPE_SENSE+19]
else
        inc byte ptr es:[bx+TAPE_SENSE+6]
endif
elseif NATIVE_SETMARK_FAULT eq 7
ifdef NATIVE_SETMARK_DESCRIPTOR
        mov byte ptr es:[bx+TAPE_SENSE+3],1
else
        mov byte ptr es:[bx+TAPE_SENSE+13],1
endif
endif
endif
        ret
setmark_bad:
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
native_setmark_read endp
setmark_bytes db 512 dup (5Ah)
