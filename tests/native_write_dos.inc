WRITE_RESULT = 0
WRITE_ACTUAL = 8
WRITE_COMPLETION = 23h
WRITE_DIAG = 0
WRITE_STREAM = 0
WRITE_STATE = 30h
ifdef NATIVE_WRITE_CASE
WRITE_RESULT = 3
WRITE_COMPLETION = 25h
WRITE_DIAG = 2
WRITE_STATE = 70h
if NATIVE_WRITE_CASE eq 1
WRITE_ACTUAL = 4
WRITE_DIAG = 5
WRITE_STREAM = 8
elseif NATIVE_WRITE_CASE eq 2 or NATIVE_WRITE_CASE eq 7
WRITE_ACTUAL = 0
WRITE_COMPLETION = 5
WRITE_DIAG = 1
elseif NATIVE_WRITE_CASE eq 4 or NATIVE_WRITE_CASE eq 8
WRITE_ACTUAL = 4
WRITE_STREAM = 8
elseif NATIVE_WRITE_CASE eq 5
WRITE_ACTUAL = 0
WRITE_COMPLETION = 5
WRITE_DIAG = 3
elseif NATIVE_WRITE_CASE eq 6
WRITE_ACTUAL = 0
WRITE_COMPLETION = 5
endif
if NATIVE_WRITE_CASE eq 4 or NATIVE_WRITE_CASE eq 9
WRITE_STREAM = WRITE_STREAM or 2
endif
ifdef NO_RESIDUAL
WRITE_ACTUAL = 0
WRITE_COMPLETION = 5
endif
endif
native_writes_test proc near
        inc word ptr [step]
        mov al,0F1h
        call test_manager
        call write_init
        call write_submit
        CFCHECK jnc
        cmp word ptr [record_packet+NC_RESULT],2
        EQCHECK
        inc word ptr [step]
        call open_tape
        CFCHECK jnc
        mov [second],ax
        mov ax,2
        call writer_control
        cmp word ptr [control_packet+NC_RESULT],2
        EQCHECK
        mov bx,[second]
        mov ah,3Eh
        int 21h
        CFCHECK jnc
        inc word ptr [step]
        mov ax,2
        call writer_control
ifdef NATIVE_FIXED_LIMITS
        cmp word ptr [control_packet+NC_RESULT],4
        EQCHECK
        cmp word ptr [control_packet+NC_COMPLETION],0
        EQCHECK
        call zero_calls
        ret
else
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        cmp word ptr [control_packet+NC_COMPLETION],42h
        EQCHECK
        inc word ptr [step]
        call open_tape                  ; DOS can open; mutators stay blocked
        CFCHECK jnc
        mov [second],ax
        inc word ptr [step]
        call prepare
        mov word ptr [info+NT_FLAGS],1
        call query
        CFCHECK jnc
        cmp word ptr [info+NT_RESULT],2
        EQCHECK
        cmp word ptr [info+NT_SESSION],50h
        EQCHECK
        call record_init
        call record_submit
        CFCHECK jnc
        cmp word ptr [record_packet+NC_RESULT],2
        EQCHECK
        mov ax,1
        call writer_control
        cmp word ptr [control_packet+NC_RESULT],2
        EQCHECK
        ; Legacy movement must not slip through the native claim.
        mov bx,[handle]
        mov dx,offset writer_legacy
        mov cx,0701h
        mov ax,440Ch
        int 21h
        CFCHECK jc
        call zero_calls
        mov bx,[second]
        mov ah,3Eh
        int 21h
        CFCHECK jnc
        mov ax,6
        call writer_control
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        mov ax,1
        call writer_control
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        mov al,0F1h
        call test_manager
        mov ax,2
        call writer_control
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        inc word ptr [step]
        call write_init
        ; All header/range checks also apply to WRITE without changing claim.
        mov word ptr [record_packet+NR_OFFSET],offset record_packet
        call write_rejected
        call zero_calls
        call write_one
ifdef NATIVE_WRITE_CASE
        call write_init
        call write_submit
        CFCHECK jnc
        cmp word ptr [record_packet+NC_RESULT],2
        EQCHECK
        mov ax,3
        call writer_control
        cmp word ptr [control_packet+NC_RESULT],2
        EQCHECK
        mov ax,4
        call writer_control
        cmp word ptr [control_packet+NC_RESULT],2
        EQCHECK
        mov ax,5
        call writer_control
        cmp word ptr [control_packet+NC_RESULT],2
        EQCHECK
        call writer_abort_rewind
else
        mov ax,3
        call writer_control
ifdef NATIVE_FINISH_FAULT
if NATIVE_FINISH_FAULT eq 1
        call writer_failed_control
        jmp writer_main_done
endif
endif
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        mov ax,4
        call writer_control
ifdef NATIVE_FINISH_FAULT
if NATIVE_FINISH_FAULT eq 2
        call writer_failed_control
        jmp writer_main_done
endif
endif
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        mov ax,5
        call writer_control
ifdef NATIVE_FINISH_FAULT
if NATIVE_FINISH_FAULT eq 3
        call writer_failed_control
        jmp writer_main_done
endif
endif
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        cmp word ptr [control_packet+NC_COMPLETION],83h
        EQCHECK
endif
writer_main_done:
        mov bx,[handle]
        mov ah,3Eh
        int 21h
        CFCHECK jnc
        ; Closing a completed/released writer must not append legacy marks.
        mov al,0F0h
        call test_manager
        cmp word ptr [test_srb+6],0
        EQCHECK
        cmp word ptr [test_srb+8],1
        EQCHECK
ifdef NATIVE_WRITE_CASE
        cmp word ptr [test_srb+4],2 ; one WRITE and recovery REWIND
        EQCHECK
        cmp word ptr [test_srb+10],0
        EQCHECK
        cmp word ptr [test_srb+12],0
        EQCHECK
elseifdef NATIVE_FINISH_FAULT
if NATIVE_FINISH_FAULT eq 1
        cmp word ptr [test_srb+4],3
        EQCHECK
        cmp word ptr [test_srb+10],0
        EQCHECK
        cmp word ptr [test_srb+12],1
elseif NATIVE_FINISH_FAULT eq 2
        cmp word ptr [test_srb+4],4
        EQCHECK
        cmp word ptr [test_srb+10],1
        EQCHECK
        cmp word ptr [test_srb+12],1
else
        cmp word ptr [test_srb+4],5
        EQCHECK
        cmp word ptr [test_srb+10],1
        EQCHECK
        cmp word ptr [test_srb+12],2
endif
        EQCHECK
else
        cmp word ptr [test_srb+4],4
        EQCHECK
        cmp word ptr [test_srb+10],1
        EQCHECK
        cmp word ptr [test_srb+12],2
        EQCHECK
endif
        call open_tape
        CFCHECK jnc
        mov [handle],ax
        inc word ptr [step]
        mov al,0F1h
        call test_manager
        mov ax,2
        call writer_control
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        call write_one
        ; DOS can ignore CLOSE errors; query must retain the unfinished state.
        mov bx,[handle]
        mov ah,3Eh
        int 21h
        call open_tape
        CFCHECK jnc
        mov [handle],ax
        call prepare
        call query
        CFCHECK jnc
        cmp word ptr [info+NT_SESSION],60h
        EQCHECK
        mov ax,2
        call writer_control
        cmp word ptr [control_packet+NC_RESULT],2
        EQCHECK
        mov ax,1
        call writer_control
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        cmp word ptr [control_packet+NC_SESSION],0
        EQCHECK
        mov al,0F0h
        call test_manager
        cmp word ptr [test_srb+4],2
        EQCHECK
        cmp word ptr [test_srb+8],1
        EQCHECK
        cmp word ptr [test_srb+10],0
        EQCHECK
        cmp word ptr [test_srb+12],0
        EQCHECK
        cmp word ptr [test_srb+6],0
        EQCHECK
        ret
endif
native_writes_test endp
writer_legacy dw 7
              dd 0
writer_control proc near
        push ax
        call control_init
        pop ax
        mov word ptr [control_packet+NC_OPERATION],ax
        call control_submit
        CFCHECK jnc
        ret
writer_control endp
writer_failed_control proc near
        cmp word ptr [control_packet+NC_RESULT],3
        EQCHECK
        cmp word ptr [control_packet+NC_COMPLETION],5
        EQCHECK
        cmp word ptr [control_packet+NC_SESSION],70h
        EQCHECK
        mov ax,5
        call writer_control
        cmp word ptr [control_packet+NC_RESULT],2
        EQCHECK
        call writer_abort_rewind
        ret
writer_failed_control endp
writer_abort_rewind proc near
        mov ax,6
        call writer_control
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        cmp word ptr [control_packet+NC_COMPLETION],82h
        EQCHECK
        cmp word ptr [control_packet+NC_SESSION],60h
        EQCHECK
        mov ax,2
        call writer_control
        cmp word ptr [control_packet+NC_RESULT],2
        EQCHECK
        mov ax,1
        call writer_control
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        cmp word ptr [control_packet+NC_SESSION],0
        EQCHECK
        ret
writer_abort_rewind endp
write_init proc near
        call record_init
        mov word ptr [record_packet+NC_OPERATION],1
        push cs
        pop es
        mov si,offset record_expected
        mov di,offset record_data
        mov cx,8
        rep movsb
        ret
write_init endp
write_submit proc near
        mov bx,[handle]
        mov cx,8003h
        mov dx,offset record_packet
        mov ax,440Ch
        int 21h
        ret
write_submit endp
write_one proc near
        call write_init
        call write_submit
        CFCHECK jnc
        cmp word ptr [record_packet+NC_RESULT],WRITE_RESULT
        EQCHECK
        cmp word ptr [record_packet+NR_ACTUAL],WRITE_ACTUAL
        EQCHECK
        cmp word ptr [record_packet+NC_COMPLETION],WRITE_COMPLETION
        EQCHECK
        cmp word ptr [record_packet+NC_DIAG],WRITE_DIAG
        EQCHECK
        cmp word ptr [record_packet+NR_STREAM],WRITE_STREAM
        EQCHECK
        cmp word ptr [record_packet+NC_SESSION],WRITE_STATE
        EQCHECK
        ret
write_one endp
write_rejected proc near
        push cs
        pop es
        mov si,offset record_packet
        mov di,offset record_saved
        mov cx,NR_SIZE
        rep movsb
        call write_submit
        CFCHECK jc
        mov si,offset record_packet
        mov di,offset record_saved
        mov cx,NR_SIZE
        repe cmpsb
        EQCHECK
        ret
write_rejected endp
