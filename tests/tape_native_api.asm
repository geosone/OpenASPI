; Installed native query: negotiation, bounds, no-I/O snapshots and probes.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h
        include common/aspi/dos_aspi.inc
        include common/aspi/native_tape_defs.inc
NATIVE_KIND = 0
ifdef NATIVE_HOST
NATIVE_KIND = 1
endif
ifdef NATIVE_SHORT
NATIVE_KIND = 2
endif
ifdef NATIVE_RESIDUAL_BAD
NATIVE_KIND = 2
endif
ifdef NATIVE_BAD_PAGE
NATIVE_KIND = 3
endif
ifdef NATIVE_BAD_DESCRIPTOR
NATIVE_KIND = 3
endif
EQCHECK macro
        local good
        je good
        jmp failed
good:
endm
CFCHECK macro condition
        local good
        condition good
        jmp failed
good:
endm
        jmp start
guard_before db 0A5h
info db NT_SIZE dup (0)
guard_after db 16 dup (0A5h)
saved_info db NT_SIZE dup (0)
old_status db 16 dup (0)
new_status db 16 dup (0)
entry dd 0
test_srb db ASPI_SRB_SIZE dup (0)
old24 dd 0
handle dw 0
second dw 0
step dw 0
name_tape db 'NRMT0',0
name_manager db 'SCSIMGR$',0
ok db 'Native tape API negotiation/probe/guard tests passed',13,10,'$'
bad db 'Native tape API FAILED step $'
start:
        push cs
        pop ds
        cld
        mov ax,3524h
        int 21h
        mov word ptr [old24],bx
        mov word ptr [old24+2],es
        mov dx,offset critical
        mov ax,2524h
        int 21h
        mov dx,offset name_manager
        mov ax,3D00h
        int 21h
        CFCHECK jnc
        mov bx,ax
        mov dx,offset entry
        mov cx,4
        mov ax,4402h
        int 21h
        CFCHECK jnc
        mov ah,3Eh
        int 21h
        call open_tape
        CFCHECK jnc
        mov [handle],ax
        mov bx,ax
        mov dx,offset old_status
        mov cx,0705h
        mov ax,440Ch
        int 21h
        CFCHECK jnc
        mov al,0F1h
        call test_manager

        call prepare
        call query
        CFCHECK jnc
        cmp word ptr [info+NT_RESULT],0
        EQCHECK
        cmp word ptr [info+NT_VALID],20h
        EQCHECK
        cmp word ptr [info+NT_OPERATIONS],0FFFFh
        EQCHECK
        call zero_calls
        inc word ptr [step]

        ; Unsupported/short/version/flag requests cannot change caller bytes.
        call prepare
        mov word ptr [info+6],0200h
        call rejected
        call prepare
        mov word ptr [info+4],127
        call rejected
        call prepare
        mov word ptr [info+NT_FLAGS],2
        call rejected
        call prepare
        mov byte ptr [info],'X'
        call rejected
        call prepare
        mov cx,8004h
        mov dx,offset info
        mov bx,[handle]
        mov ax,440Ch
        int 21h
        CFCHECK jc
        call zero_calls
        inc word ptr [step]

        ; A cross-segment pointer is rejected before reading the header.
        mov bx,[handle]
        mov cx,8000h
        mov dx,0FF81h
        mov ax,440Ch
        int 21h
        CFCHECK jc
        push ds
        mov ax,0FFFFh
        mov ds,ax
        xor dx,dx
        mov ax,440Ch
        int 21h
        pop ds
        CFCHECK jc
        call zero_calls
        inc word ptr [step]

        ; A second owner makes explicit probing BUSY, without manager calls.
        call open_tape
        CFCHECK jnc
        mov [second],ax
        call prepare
        mov word ptr [info+NT_FLAGS],1
        call query
        CFCHECK jnc
        cmp word ptr [info+NT_RESULT],2
        EQCHECK
        call zero_calls
        mov bx,[second]
        mov ah,3Eh
        int 21h
        CFCHECK jnc
        inc word ptr [step]

        call prepare
        mov word ptr [info+4],160 ; extra caller capacity is not output space
        mov word ptr [info+NT_FLAGS],1
        call query
        CFCHECK jnc
        cmp word ptr [info+4],128
        EQCHECK
        cmp byte ptr [guard_before],0A5h
        EQCHECK
        push cs
        pop es
        mov di,offset guard_after
        mov cx,16
        mov al,0A5h
        repe scasb
        EQCHECK
        mov al,0F0h
        call test_manager
        cmp word ptr [test_srb+6],0
        EQCHECK
if NATIVE_KIND eq 1
        cmp word ptr [test_srb+4],1
        EQCHECK
        cmp word ptr [info+NT_DIAG],1
        EQCHECK
        cmp byte ptr [info+NT_HOST],11h
        EQCHECK
        cmp byte ptr [info+NT_KEY],0
        EQCHECK
elseif NATIVE_KIND eq 2
        cmp word ptr [test_srb+4],1
        EQCHECK
        cmp word ptr [info+NT_DIAG],3
        EQCHECK
elseif NATIVE_KIND eq 3
        cmp word ptr [test_srb+4],3
        EQCHECK
        cmp word ptr [info+NT_DIAG],3
        EQCHECK
else
        cmp word ptr [test_srb+4],4
        EQCHECK
ifdef NATIVE_FIXED_LIMITS
        cmp word ptr [info+NT_MIN],512
else
        cmp word ptr [info+NT_MIN],1
endif
        EQCHECK
ifdef NATIVE_FIXED_LIMITS
        cmp word ptr [info+NT_MAX],512
elseifdef NATIVE_UNLIMITED
        cmp word ptr [info+NT_MAX],0
else
        cmp word ptr [info+NT_MAX],8000h
endif
        EQCHECK
        cmp word ptr [info+NT_MAX+2],0
        EQCHECK
        cmp word ptr [info+NT_ADDRESS],0
        EQCHECK
        cmp byte ptr [info+NT_ADDRESS+3],1
        EQCHECK
ifdef NATIVE_NO_COMP
        cmp word ptr [info+NT_RESULT],1
        EQCHECK
        cmp word ptr [info+NT_VALID],77h
        EQCHECK
        cmp word ptr [info+NT_KNOWN],0
        EQCHECK
        cmp word ptr [info+NT_DIAG],4
        EQCHECK
        cmp byte ptr [info+NT_ASC],24h
        EQCHECK
else
        cmp word ptr [info+NT_RESULT],0
        EQCHECK
ifdef NATIVE_NO_DESCRIPTOR
        cmp word ptr [info+NT_VALID],3Fh
        EQCHECK
        cmp word ptr [info+NT_BLOCK],0
        EQCHECK
        cmp word ptr [info+NT_STATE],7
        EQCHECK
else
        cmp word ptr [info+NT_VALID],7Fh
        EQCHECK
ifdef NATIVE_GRANULARITY
        cmp word ptr [info+NT_BLOCK],513
else
        cmp word ptr [info+NT_BLOCK],512
endif
        EQCHECK
ifdef NATIVE_NO_DCC
        cmp word ptr [info+NT_STATE],14
else
        cmp word ptr [info+NT_STATE],15
endif
        EQCHECK
endif
        cmp word ptr [info+NT_KNOWN],1
        EQCHECK
ifdef NATIVE_NO_DCC
        cmp word ptr [info+NT_SUPPORTED],0
else
        cmp word ptr [info+NT_SUPPORTED],1
endif
        EQCHECK
endif
endif
if NATIVE_KIND eq 0
ifdef NATIVE_GRANULARITY
        cmp word ptr [info+92],4
else
        cmp word ptr [info+92],1
endif
        EQCHECK
endif
ifdef NO_RESIDUAL
        cmp word ptr [info+88],1
else
        cmp word ptr [info+88],0
endif
        EQCHECK
        inc word ptr [step]
        mov bx,[handle]
        mov dx,offset new_status
        mov cx,0705h
        mov ax,440Ch
        int 21h
        CFCHECK jnc
        push cs
        pop es
        mov si,offset old_status
        mov di,offset new_status
        mov cx,16
        repe cmpsb
        EQCHECK
        call native_controls_test
        call native_records_test
ifdef NATIVE_FIXED_IO_TEST
        call native_fixed_io_test
endif
ifdef NATIVE_WRITE_TEST
        call native_writes_test
endif
        mov bx,[handle]
        mov ah,3Eh
        int 21h
        CFCHECK jnc
        call restore24
        mov dx,offset ok
        mov ah,9
        int 21h
        mov ax,4C00h
        int 21h
failed:
        call restore24
        mov dx,offset bad
        mov ah,9
        int 21h
        mov ax,[step]
        aam
        add ax,3030h
        push ax
        mov dl,ah
        mov ah,2
        int 21h
        pop dx
        mov ah,2
        int 21h
        mov ax,4C01h
        int 21h
critical proc far
        mov al,3
        iret
critical endp
restore24 proc near
        push ds
        lds dx,dword ptr [old24]
        mov ax,2524h
        int 21h
        pop ds
        ret
restore24 endp
prepare proc near
        push cs
        pop es
        mov di,offset info
        xor al,al
        mov cx,NT_SIZE
        rep stosb
        mov word ptr [info],544Fh
        mov word ptr [info+2],5041h
        mov word ptr [info+4],128
        mov word ptr [info+6],NT_VERSION
        ret
prepare endp
query proc near
        mov bx,[handle]
        mov cx,8000h
        mov dx,offset info
        mov ax,440Ch
        int 21h
        ret
query endp
rejected proc near
        push cs
        pop es
        mov si,offset info
        mov di,offset saved_info
        mov cx,128
        rep movsb
        call query
        CFCHECK jc
        mov si,offset info
        mov di,offset saved_info
        mov cx,128
        repe cmpsb
        EQCHECK
        call zero_calls
        inc word ptr [step]
        ret
rejected endp
open_tape proc near
        mov dx,offset name_tape
        mov ax,3D00h
        int 21h
        ret
open_tape endp
test_manager proc near
        push cs
        mov dx,offset test_srb
        push dx
        mov byte ptr [test_srb],al
        call dword ptr [entry]
        add sp,4
        ret
test_manager endp
zero_calls proc near
        mov al,0F0h
        call test_manager
        cmp word ptr [test_srb+4],0
        EQCHECK
        cmp word ptr [test_srb+6],0
        EQCHECK
        ret
zero_calls endp
        include tests/native_control_dos.inc
        include tests/native_record_dos.inc
ifdef NATIVE_WRITE_TEST
        include tests/native_write_dos.inc
endif
ifdef NATIVE_FIXED_IO_TEST
        include tests/native_fixed_dos.inc
endif
        end start
