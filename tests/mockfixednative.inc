; Two 512-byte blocks per command; deliberately different from byte counts.
ifndef NATIVE_FIXED_READ_CASE
NATIVE_FIXED_READ_CASE = 0
endif
ifndef NATIVE_FIXED_WRITE_CASE
NATIVE_FIXED_WRITE_CASE = 0
endif
native_fixed_bytes db 1024 dup (5Ah)
native_fixed_header proc near
        cmp byte ptr es:[bx+SRB_CDBLen],6
        jne fixed_header_bad
        cmp byte ptr es:[bx+SRB_CDB+1],1
        jne fixed_header_bad
        cmp byte ptr es:[bx+SRB_CDB+2],0
        jne fixed_header_bad
        cmp word ptr es:[bx+SRB_CDB+3],0200h ; two blocks, not 1024 bytes
        jne fixed_header_bad
        cmp byte ptr es:[bx+SRB_CDB+5],0
        jne fixed_header_bad
        cmp word ptr es:[bx+SRB_BufLen],1024
        jne fixed_header_bad
        cmp word ptr es:[bx+SRB_BufLen+2],0
        jne fixed_header_bad
        clc
        ret
fixed_header_bad:
        stc
        ret
native_fixed_header endp
native_fixed_bad proc near
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
native_fixed_bad endp
native_fixed_read proc near
        call native_fixed_header
        jnc fixed_read_valid
        jmp native_fixed_bad
fixed_read_valid:
ifdef NO_RESIDUAL
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN
else
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN or SRB_RESIDUAL
endif
        je fixed_read_flags
        jmp native_fixed_bad
fixed_read_flags:
        mov si,offset native_fixed_bytes
        mov cx,1024
if NATIVE_FIXED_READ_CASE eq 1 or NATIVE_FIXED_READ_CASE eq 12
        xor cx,cx
elseif NATIVE_FIXED_READ_CASE ne 0
        mov cx,512
endif
        call native_copy
if NATIVE_FIXED_READ_CASE ne 0
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+TAPE_SENSE],0F0h
        mov byte ptr es:[bx+TAPE_SENSE+7],6
        mov byte ptr es:[bx+TAPE_SENSE+6],1 ; residual blocks, not bytes
if NATIVE_FIXED_READ_CASE eq 1 or NATIVE_FIXED_READ_CASE eq 2 or NATIVE_FIXED_READ_CASE eq 12
        mov byte ptr es:[bx+TAPE_SENSE+2],80h
if NATIVE_FIXED_READ_CASE eq 1 or NATIVE_FIXED_READ_CASE eq 12
        mov byte ptr es:[bx+TAPE_SENSE+6],2
endif
elseif NATIVE_FIXED_READ_CASE eq 3
        mov byte ptr es:[bx+TAPE_SENSE+2],40h
elseif NATIVE_FIXED_READ_CASE eq 7
        mov byte ptr es:[bx+TAPE_SENSE+2],20h
elseif NATIVE_FIXED_READ_CASE eq 8
        mov byte ptr es:[bx+TAPE_SENSE+2],3
else
        mov byte ptr es:[bx+TAPE_SENSE+2],80h
endif
if NATIVE_FIXED_READ_CASE eq 4
        mov word ptr es:[bx+SRB_BufLen],513
elseif NATIVE_FIXED_READ_CASE eq 5
        mov byte ptr es:[bx+TAPE_SENSE+6],0
elseif NATIVE_FIXED_READ_CASE eq 6
        mov byte ptr es:[bx+TAPE_SENSE+5],1 ; 256*512 overflows DOS byte count
        mov byte ptr es:[bx+TAPE_SENSE+6],0
elseif NATIVE_FIXED_READ_CASE eq 9
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_FIXED_READ_CASE eq 10
        mov byte ptr es:[bx+TAPE_SENSE],0F1h
elseif NATIVE_FIXED_READ_CASE eq 11
        mov word ptr es:[bx+SRB_BufLen],1025
elseif NATIVE_FIXED_READ_CASE eq 12
        mov byte ptr es:[bx+TAPE_SENSE],70h ; no valid INFORMATION
endif
endif
        ret
native_fixed_read endp
native_fixed_write proc near
        call native_fixed_header
        jnc fixed_write_valid
        jmp native_fixed_bad
fixed_write_valid:
ifdef NO_RESIDUAL
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_OUT
else
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_OUT or SRB_RESIDUAL
endif
        je fixed_write_flags
        jmp native_fixed_bad
fixed_write_flags:
        push ds
        push es
        push bx
        lds si,dword ptr es:[bx+SRB_BufPointer]
        push cs
        pop es
        mov di,offset native_fixed_bytes
        mov cx,1024
        repe cmpsb
        pop bx
        pop es
        pop ds
        je fixed_write_data
        jmp native_fixed_bad
fixed_write_data:
        inc word ptr cs:[native_writes]
        mov byte ptr es:[bx+SRB_Status],SS_COMP
ifndef NO_RESIDUAL
        mov word ptr es:[bx+SRB_BufLen],0
endif
if NATIVE_FIXED_WRITE_CASE eq 1
        mov word ptr es:[bx+SRB_BufLen],512
elseif NATIVE_FIXED_WRITE_CASE eq 3
        mov word ptr es:[bx+SRB_BufLen],513
elseif NATIVE_FIXED_WRITE_CASE ne 0
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+TAPE_SENSE],70h
        mov byte ptr es:[bx+TAPE_SENSE+7],6
        mov byte ptr es:[bx+TAPE_SENSE+2],7
        mov byte ptr es:[bx+TAPE_SENSE+12],27h
if NATIVE_FIXED_WRITE_CASE eq 2
ifndef NO_RESIDUAL
        mov word ptr es:[bx+SRB_BufLen],1024
endif
elseif NATIVE_FIXED_WRITE_CASE eq 4
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_FIXED_WRITE_CASE eq 5
        mov byte ptr es:[bx+TAPE_SENSE],71h
elseif NATIVE_FIXED_WRITE_CASE eq 6 or NATIVE_FIXED_WRITE_CASE eq 7
        mov byte ptr es:[bx+TAPE_SENSE+2],40h
        mov byte ptr es:[bx+TAPE_SENSE+12],0
if NATIVE_FIXED_WRITE_CASE eq 7
        mov word ptr es:[bx+SRB_BufLen],512
endif
elseif NATIVE_FIXED_WRITE_CASE eq 8
        mov byte ptr es:[bx+TAPE_SENSE+2],3
        mov word ptr es:[bx+SRB_BufLen],512
endif
endif
        ret
native_fixed_write endp
