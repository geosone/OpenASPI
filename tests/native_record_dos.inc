record_packet db NR_SIZE dup (0)
record_tail db 16 dup (0A5h)
record_saved db NR_SIZE dup (0)
record_guard db 0A5h
record_data db 8 dup (0A5h)
record_data_tail db 0A5h
record_expected db 'RECORD01'
RECORD_RESULT = 0
RECORD_ACTUAL = 8
RECORD_FLAGS = 23h
RECORD_STREAM = 0
RECORD_DIAG = 0
ifdef NATIVE_READ_CASE
if NATIVE_READ_CASE eq 1 or NATIVE_READ_CASE eq 2 or NATIVE_READ_CASE eq 3 or NATIVE_READ_CASE eq 4 or NATIVE_READ_CASE eq 11
RECORD_RESULT = 5
RECORD_DIAG = 2
elseif NATIVE_READ_CASE ne 12
RECORD_RESULT = 3
RECORD_DIAG = 2
RECORD_FLAGS = 25h
endif
if NATIVE_READ_CASE eq 1 or NATIVE_READ_CASE eq 3 or NATIVE_READ_CASE eq 10
RECORD_ACTUAL = 4
RECORD_STREAM = 8
elseif NATIVE_READ_CASE eq 2 or NATIVE_READ_CASE eq 4 or NATIVE_READ_CASE eq 11 or NATIVE_READ_CASE eq 12
RECORD_ACTUAL = 0
RECORD_STREAM = 8
elseif NATIVE_READ_CASE eq 5 or NATIVE_READ_CASE eq 6 or NATIVE_READ_CASE eq 7 or NATIVE_READ_CASE eq 8
RECORD_ACTUAL = 0
RECORD_FLAGS = 5
endif
if NATIVE_READ_CASE eq 1
RECORD_STREAM = 12
elseif NATIVE_READ_CASE eq 2 or NATIVE_READ_CASE eq 3
RECORD_STREAM = 9
elseif NATIVE_READ_CASE eq 4
RECORD_STREAM = 10
elseif NATIVE_READ_CASE eq 5
RECORD_DIAG = 1
elseif NATIVE_READ_CASE eq 6 or NATIVE_READ_CASE eq 8
RECORD_DIAG = 3
elseif NATIVE_READ_CASE eq 9
RECORD_STREAM = 14h
elseif NATIVE_READ_CASE eq 11
RECORD_STREAM = 28h
endif
endif
ifdef NATIVE_FIXED_LIMITS
RECORD_RESULT = 4
RECORD_ACTUAL = 0
RECORD_FLAGS = 0
RECORD_STREAM = 0
RECORD_DIAG = 4
endif
native_records_test proc near
        inc word ptr [step]
        mov al,0F1h
        call test_manager
        call record_init
        mov word ptr [record_packet+NR_REQUESTED],0
        call record_rejected
        call record_init
        mov word ptr [record_packet+NR_REQUESTED+2],1
        call record_rejected
        call record_init
        mov word ptr [record_packet+NC_FLAGS],1
        call record_rejected
        call record_init
        mov word ptr [record_packet+NC_OPERATION],1
        call record_rejected
        call record_init
        mov word ptr [record_packet+4],63
        call record_rejected
        call record_init
        mov word ptr [record_packet+6],0200h
        call record_rejected
        call record_init
        mov word ptr [record_packet+NR_OFFSET],0FFFCh
        call record_rejected
        call record_init
        mov word ptr [record_packet+NR_OFFSET],0
        mov word ptr [record_packet+NR_SEGMENT],0
        call record_rejected
        call record_init
        mov word ptr [record_packet+NR_OFFSET],0FFFCh
        mov word ptr [record_packet+NR_SEGMENT],0FFFFh
        call record_rejected
        call record_init
        mov word ptr [record_packet+NR_OFFSET],10h
        mov word ptr [record_packet+NR_SEGMENT],0FFFFh
        call record_rejected
        call record_init
        mov word ptr [record_packet+NR_OFFSET],offset record_packet
        call record_rejected
        ; Physically identical overlap expressed with a different segment.
        call record_init
        mov ax,ds
        dec ax
        mov word ptr [record_packet+NR_SEGMENT],ax
        mov word ptr [record_packet+NR_OFFSET],offset record_packet+16
        call record_rejected
        call zero_calls
        call open_tape
        CFCHECK jnc
        mov [second],ax
        call record_init
        call record_submit
        CFCHECK jnc
        cmp word ptr [record_packet+NC_RESULT],2
        EQCHECK
        cmp word ptr [record_packet+NC_COMPLETION],0
        EQCHECK
        call zero_calls
        mov bx,[second]
        mov ah,3Eh
        int 21h
        CFCHECK jnc
        inc word ptr [step]
        call record_one
        ; No queued synthetic EOF: the next native read is another CDB.
        call record_one
        mov al,0F0h
        call test_manager
ifdef NATIVE_FIXED_LIMITS
        cmp word ptr [test_srb+4],0
else
        cmp word ptr [test_srb+4],2
endif
        EQCHECK
        cmp word ptr [test_srb+6],0
        EQCHECK
        ret
native_records_test endp
record_one proc near
        call record_init
        call record_submit
        CFCHECK jnc
        cmp word ptr [record_packet+NC_RESULT],RECORD_RESULT
        EQCHECK
        cmp word ptr [record_packet+NR_ACTUAL],RECORD_ACTUAL
        EQCHECK
        cmp word ptr [record_packet+NR_ACTUAL+2],0
        EQCHECK
        cmp word ptr [record_packet+NC_COMPLETION],RECORD_FLAGS
        EQCHECK
        cmp word ptr [record_packet+NR_STREAM],RECORD_STREAM
        EQCHECK
        cmp word ptr [record_packet+NC_DIAG],RECORD_DIAG
        EQCHECK
ifdef NATIVE_FIXED_LIMITS
        cmp byte ptr [record_packet+NC_OPCODE],0
else
        cmp byte ptr [record_packet+NC_OPCODE],8
endif
        EQCHECK
        cmp word ptr [record_packet+NR_REQUESTED],8
        EQCHECK
        cmp byte ptr [record_guard],0A5h
        EQCHECK
        cmp byte ptr [record_data_tail],0A5h
        EQCHECK
        push cs
        pop es
        mov di,offset record_tail
        mov cx,16
        mov al,0A5h
        repe scasb
        EQCHECK
if RECORD_ACTUAL gt 0
        mov si,offset record_data
        mov di,offset record_expected
        mov cx,RECORD_ACTUAL
        repe cmpsb
        EQCHECK
endif
        ret
record_one endp
record_init proc near
        push cs
        pop es
        mov di,offset record_packet
        mov cx,NR_SIZE
        xor al,al
        rep stosb
        mov word ptr [record_packet],544Fh
        mov word ptr [record_packet+2],5041h
        mov word ptr [record_packet+4],NR_SIZE
        mov word ptr [record_packet+6],NT_VERSION
        mov word ptr [record_packet+NR_REQUESTED],8
        mov word ptr [record_packet+NR_OFFSET],offset record_data
        mov ax,ds
        mov word ptr [record_packet+NR_SEGMENT],ax
        ret
record_init endp
record_submit proc near
        mov bx,[handle]
        mov cx,8002h
        mov dx,offset record_packet
        mov ax,440Ch
        int 21h
        ret
record_submit endp
record_rejected proc near
        push cs
        pop es
        mov si,offset record_packet
        mov di,offset record_saved
        mov cx,NR_SIZE
        rep movsb
        call record_submit
        CFCHECK jc
        mov si,offset record_packet
        mov di,offset record_saved
        mov cx,NR_SIZE
        repe cmpsb
        EQCHECK
        ret
record_rejected endp
