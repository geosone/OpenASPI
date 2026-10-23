ifndef NATIVE_FIXED_READ_CASE
NATIVE_FIXED_READ_CASE = 0
endif
ifndef NATIVE_FIXED_WRITE_CASE
NATIVE_FIXED_WRITE_CASE = 0
endif
FR_RESULT = 0
FR_DIAG = 0
FR_COMPLETION = 23h
FR_ACTUAL = 1024
FR_STREAM = 0
if NATIVE_FIXED_READ_CASE ne 0
FR_RESULT = 3
FR_DIAG = 2
FR_COMPLETION = 5
FR_ACTUAL = 0
if NATIVE_FIXED_READ_CASE eq 1 or NATIVE_FIXED_READ_CASE eq 2 or NATIVE_FIXED_READ_CASE eq 3
FR_RESULT = 5
FR_COMPLETION = 23h
FR_STREAM = 9
if NATIVE_FIXED_READ_CASE ne 1
FR_ACTUAL = 512
endif
if NATIVE_FIXED_READ_CASE eq 3
FR_STREAM = 10
endif
elseif NATIVE_FIXED_READ_CASE eq 4 or NATIVE_FIXED_READ_CASE eq 5 or NATIVE_FIXED_READ_CASE eq 6 or NATIVE_FIXED_READ_CASE eq 11
FR_DIAG = 3
elseif NATIVE_FIXED_READ_CASE eq 7 or NATIVE_FIXED_READ_CASE eq 8
FR_COMPLETION = 25h
FR_ACTUAL = 512
FR_STREAM = 8
if NATIVE_FIXED_READ_CASE eq 7
FR_STREAM = 12
endif
elseif NATIVE_FIXED_READ_CASE eq 9
FR_DIAG = 1
elseif NATIVE_FIXED_READ_CASE eq 12
FR_STREAM = 1
endif
endif
FW_RESULT = 0
FW_DIAG = 0
FW_COMPLETION = 23h
FW_ACTUAL = 1024
FW_STREAM = 0
if NATIVE_FIXED_WRITE_CASE ne 0
FW_RESULT = 3
FW_DIAG = 2
FW_COMPLETION = 25h
if NATIVE_FIXED_WRITE_CASE eq 1
FW_DIAG = 5
FW_ACTUAL = 512
FW_STREAM = 8
elseif NATIVE_FIXED_WRITE_CASE eq 2
FW_ACTUAL = 0
FW_STREAM = 8
ifdef NO_RESIDUAL
FW_COMPLETION = 5
FW_STREAM = 0
endif
elseif NATIVE_FIXED_WRITE_CASE eq 3 or NATIVE_FIXED_WRITE_CASE eq 4 or NATIVE_FIXED_WRITE_CASE eq 5
FW_COMPLETION = 5
FW_ACTUAL = 0
if NATIVE_FIXED_WRITE_CASE eq 3
FW_DIAG = 3
elseif NATIVE_FIXED_WRITE_CASE eq 4
FW_DIAG = 1
endif
elseif NATIVE_FIXED_WRITE_CASE eq 6
FW_STREAM = 2
elseif NATIVE_FIXED_WRITE_CASE eq 7 or NATIVE_FIXED_WRITE_CASE eq 8
FW_ACTUAL = 512
FW_STREAM = 8
if NATIVE_FIXED_WRITE_CASE eq 7
FW_STREAM = 10
endif
endif
endif
fixed_function dw 8002h
fixed_guard db 0A5h
fixed_data db 1024 dup (0A5h)
fixed_tail db 0A5h
native_fixed_io_test proc near
        inc word ptr [step]
        mov al,0F1h
        call test_manager
        xor ax,ax
        call fixed_init
        mov word ptr [record_packet+NR_BLOCK],0
        call fixed_rejected
        xor ax,ax
        call fixed_init
        mov word ptr [record_packet+NR_REQUESTED],1023
        call fixed_rejected
        xor ax,ax
        call fixed_init
        mov word ptr [record_packet+NR_BLOCK],256
        call fixed_rejected
        xor ax,ax
        call fixed_init
        mov word ptr [record_packet+NR_BLOCK+2],1
        call fixed_rejected
        xor ax,ax
        call fixed_init
        mov word ptr [record_packet+NC_FLAGS],0
        call fixed_rejected
        xor ax,ax
        call fixed_init
        mov word ptr [record_packet+NR_OFFSET],offset record_packet
        call fixed_rejected
        call zero_calls
        xor ax,ax
        call fixed_init
        call fixed_submit
        CFCHECK jnc
        cmp word ptr [record_packet+NC_RESULT],FR_RESULT
        EQCHECK
        cmp word ptr [record_packet+NC_DIAG],FR_DIAG
        EQCHECK
        cmp word ptr [record_packet+NC_COMPLETION],FR_COMPLETION
        EQCHECK
        cmp word ptr [record_packet+NR_ACTUAL],FR_ACTUAL
        EQCHECK
        cmp word ptr [record_packet+NR_STREAM],FR_STREAM
        EQCHECK
        call fixed_echo
if FR_ACTUAL gt 0
        push cs
        pop es
        mov di,offset fixed_data
        mov cx,FR_ACTUAL
        mov al,5Ah
        repe scasb
        EQCHECK
endif
        ; Establish BOT explicitly before switching from reading to writing.
        call control_init
        mov word ptr [control_packet+NC_OPERATION],1
        call control_submit
        CFCHECK jnc
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        inc word ptr [step]
        call control_init
        mov word ptr [control_packet+NC_OPERATION],2
        mov word ptr [control_packet+NC_FLAGS],1
        mov word ptr [control_packet+NC_BLOCK],512
        call control_submit
        CFCHECK jnc
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        cmp word ptr [control_packet+NC_COMPLETION],42h
        EQCHECK
        cmp word ptr [control_packet+NC_BLOCK],512
        EQCHECK
        mov word ptr [fixed_function],8003h
        mov ax,1
        call fixed_init
        mov word ptr [record_packet+NC_FLAGS],0
        mov word ptr [record_packet+NR_BLOCK],0
        call fixed_rejected              ; claim cannot silently change mode
        push cs
        pop es
        mov di,offset fixed_data
        mov cx,1024
        mov al,5Ah
        rep stosb
        mov ax,1
        call fixed_init
        call fixed_submit
        CFCHECK jnc
        cmp word ptr [record_packet+NC_RESULT],FW_RESULT
        EQCHECK
        cmp word ptr [record_packet+NC_DIAG],FW_DIAG
        EQCHECK
        cmp word ptr [record_packet+NC_COMPLETION],FW_COMPLETION
        EQCHECK
        cmp word ptr [record_packet+NR_ACTUAL],FW_ACTUAL
        EQCHECK
        cmp word ptr [record_packet+NR_STREAM],FW_STREAM
        EQCHECK
        call fixed_echo
if NATIVE_FIXED_WRITE_CASE ne 0
        call fixed_submit
        CFCHECK jnc
        cmp word ptr [record_packet+NC_RESULT],2
        EQCHECK
        call control_init
        mov word ptr [control_packet+NC_OPERATION],6
        call control_submit
        CFCHECK jnc
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        call control_init
        mov word ptr [control_packet+NC_OPERATION],1
        call control_submit
        CFCHECK jnc
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
else
        call control_init
        mov word ptr [control_packet+NC_OPERATION],3
        call control_submit
        CFCHECK jnc
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        call control_init
        mov word ptr [control_packet+NC_OPERATION],4
        call control_submit
        CFCHECK jnc
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        call control_init
        mov word ptr [control_packet+NC_OPERATION],5
        call control_submit
        CFCHECK jnc
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
endif
        mov bx,[handle]
        mov ah,3Eh
        int 21h
        CFCHECK jnc
        call open_tape
        CFCHECK jnc
        mov [handle],ax
        mov al,0F0h
        call test_manager
        cmp word ptr [test_srb+6],0
        EQCHECK
        cmp word ptr [test_srb+8],1
        EQCHECK
if NATIVE_FIXED_WRITE_CASE ne 0
        cmp word ptr [test_srb+4],4
        EQCHECK
        cmp word ptr [test_srb+10],0
        EQCHECK
        cmp word ptr [test_srb+12],0
        EQCHECK
else
        cmp word ptr [test_srb+4],6
        EQCHECK
        cmp word ptr [test_srb+10],1
        EQCHECK
        cmp word ptr [test_srb+12],2
        EQCHECK
endif
        ret
native_fixed_io_test endp
fixed_init proc near
        push ax
        call record_init
        pop ax
        mov word ptr [record_packet+NC_OPERATION],ax
        mov word ptr [record_packet+NC_FLAGS],1
        mov word ptr [record_packet+NR_REQUESTED],1024
        mov word ptr [record_packet+NR_BLOCK],512
        mov word ptr [record_packet+NR_OFFSET],offset fixed_data
        ret
fixed_init endp
fixed_submit proc near
        mov bx,[handle]
        mov cx,word ptr [fixed_function]
        mov dx,offset record_packet
        mov ax,440Ch
        int 21h
        ret
fixed_submit endp
fixed_rejected proc near
        push cs
        pop es
        mov si,offset record_packet
        mov di,offset record_saved
        mov cx,NR_SIZE
        rep movsb
        call fixed_submit
        CFCHECK jc
        mov si,offset record_packet
        mov di,offset record_saved
        mov cx,NR_SIZE
        repe cmpsb
        EQCHECK
        ret
fixed_rejected endp
fixed_echo proc near
        cmp word ptr [record_packet+NC_FLAGS],1
        EQCHECK
        cmp word ptr [record_packet+NR_BLOCK],512
        EQCHECK
        cmp word ptr [record_packet+NR_REQUESTED],1024
        EQCHECK
        cmp byte ptr [fixed_guard],0A5h
        EQCHECK
        cmp byte ptr [fixed_tail],0A5h
        EQCHECK
        cmp word ptr [record_tail],0A5A5h
        EQCHECK
        ret
fixed_echo endp
