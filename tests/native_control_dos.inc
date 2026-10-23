; Same installed DOS provider, independent native control packet.
control_guard db 0A5h
control_packet db NC_SIZE dup (0)
control_tail db 16 dup (0A5h)
control_saved db NC_SIZE dup (0)
native_controls_test proc near
        inc word ptr [step]
        mov al,0F1h
        call test_manager
        call control_init
        mov word ptr [control_packet+4],63
        call control_rejected
        call control_init
        mov word ptr [control_packet+6],0200h
        call control_rejected
        call control_init
        mov word ptr [control_packet+NC_OPERATION],0FFFFh
        call control_rejected
        call control_init
        mov word ptr [control_packet+NC_FLAGS],1
        call control_rejected
        call zero_calls
        call open_tape
        CFCHECK jnc
        mov [second],ax
        call control_init
        call control_submit
        CFCHECK jnc
        cmp word ptr [control_packet+NC_RESULT],2
        EQCHECK
        cmp word ptr [control_packet+NC_COMPLETION],0
        EQCHECK
        call zero_calls
        mov bx,[second]
        mov ah,3Eh
        int 21h
        CFCHECK jnc

        call control_init
        call control_submit
        CFCHECK jnc
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        cmp word ptr [control_packet+NC_COMPLETION],13h
        EQCHECK
        cmp word ptr [control_packet+NC_SESSION],0
        EQCHECK
        inc word ptr [step]
        call control_init
        mov word ptr [control_packet+4],80
        mov word ptr [control_packet+NC_OPERATION],1
        call control_submit
        CFCHECK jnc
        cmp word ptr [control_packet+4],64
        EQCHECK
        cmp byte ptr [control_packet+NC_OPCODE],1
        EQCHECK
ifdef NATIVE_CONTROL_FAULT
        cmp word ptr [control_packet+NC_RESULT],3
        EQCHECK
        cmp word ptr [control_packet+NC_COMPLETION],5 ; submitted; position unknown
        EQCHECK
if (NATIVE_CONTROL_FAULT eq 1) or (NATIVE_CONTROL_FAULT eq 5)
        cmp word ptr [control_packet+NC_DIAG],1
        EQCHECK
        cmp byte ptr [control_packet+NC_KEY],0
        EQCHECK
elseif NATIVE_CONTROL_FAULT eq 4
        cmp word ptr [control_packet+NC_DIAG],4
        EQCHECK
else
        cmp word ptr [control_packet+NC_DIAG],2
        EQCHECK
endif
else
        cmp word ptr [control_packet+NC_RESULT],0
        EQCHECK
        cmp word ptr [control_packet+NC_COMPLETION],0Bh
        EQCHECK
endif
        cmp byte ptr [control_guard],0A5h
        EQCHECK
        push cs
        pop es
        mov di,offset control_tail
        mov cx,16
        mov al,0A5h
        repe scasb
        EQCHECK
        mov al,0F0h
        call test_manager
        cmp word ptr [test_srb+4],2 ; one TUR and one REWIND, never retry
        EQCHECK
        cmp word ptr [test_srb+6],0
        EQCHECK
        ret
native_controls_test endp
control_init proc near
        push cs
        pop es
        mov di,offset control_packet
        mov cx,64
        xor al,al
        rep stosb
        mov word ptr [control_packet],544Fh
        mov word ptr [control_packet+2],5041h
        mov word ptr [control_packet+4],64
        mov word ptr [control_packet+6],NT_VERSION
        ret
control_init endp
control_submit proc near
        mov bx,[handle]
        mov cx,8001h
        mov dx,offset control_packet
        mov ax,440Ch
        int 21h
        ret
control_submit endp
control_rejected proc near
        push cs
        pop es
        mov si,offset control_packet
        mov di,offset control_saved
        mov cx,64
        rep movsb
        call control_submit
        CFCHECK jc
        mov si,offset control_packet
        mov di,offset control_saved
        mov cx,64
        repe cmpsb
        EQCHECK
        ret
control_rejected endp
