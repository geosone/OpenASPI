; Exercise close REWIND's IMMED flag and the deferred readiness barrier.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h

check_carry macro
        local ok
        jnc ok
        jmp failed
ok:
endm
check_equal macro
        local ok
        je ok
        jmp failed
ok:
endm

start:
        push cs
        pop ds
        mov ax, 3524h
        int 21h
        mov word ptr [old_int24], bx
        mov word ptr [old_int24+2], es
        mov dx, offset critical_error
        mov ax, 2524h
        int 21h
        mov dx, offset rmt_name
        call open_raw
        check_carry
        mov bx, ax
        mov ah, 3Eh
        int 21h
        check_carry
        mov dx, offset nrmt_name
        call open_raw
        check_carry
        mov word ptr [handle], ax
        call get_status
        check_carry
ifdef WAIT_CLOSE
        cmp byte ptr [status+4], 0
else
        cmp byte ptr [status+4], 80h
endif
        check_equal

ifdef REWIND_MIDNIGHT
        ; Only the disposable QEMU guest clock is changed by this fixture.
        push es
        mov ax, 40h
        mov es, ax
        pushf
        cli
        mov word ptr es:[6Ch], 0FFFFh
        mov word ptr es:[6Eh], 17h
        popf
        pop es
endif

ifdef REWIND_READ
        mov bx, word ptr [handle]
        mov cx, 2
        mov dx, offset buffer
        mov ah, 3Fh
        int 21h
else
ifdef REWIND_WRITE
        mov bx, word ptr [handle]
        mov cx, 2
        mov dx, offset buffer
        mov ah, 40h
        int 21h
else
        mov bx, word ptr [handle]
        mov cx, 0701h
        mov dx, offset control
        mov ax, 440Ch
        int 21h
endif
endif
ifdef REWIND_ERROR
        jc expected_error
        jmp failed
expected_error:
else
        check_carry
endif
        call get_status
        check_carry
ifdef REWIND_ERROR
        cmp byte ptr [status+4], 80h
        check_equal
ifdef REWIND_TIMEOUT
        cmp byte ptr [status+8], 8       ; the timed-out poll was BUSY
else
        cmp byte ptr [status+9], 2
endif
else
ifdef REWIND_READ
        cmp byte ptr [status+4], 10h
else
ifdef REWIND_WRITE
        cmp byte ptr [status+4], 8
else
        cmp byte ptr [status+4], 0
endif
endif
endif
        check_equal
        mov bx, word ptr [handle]
        mov ah, 3Eh
        int 21h
        check_carry
        call restore_int24
        mov dx, offset success_message
        mov ah, 09h
        int 21h
        mov ax, 4C00h
        int 21h
failed:
        call restore_int24
        mov dx, offset failure_message
        mov ah, 09h
        int 21h
        mov ax, 4C01h
        int 21h

open_raw proc near
        mov ax, 3D02h
        int 21h
        jc open_done
        mov bx, ax
        mov ax, 4400h
        int 21h
        jc open_done
        or dl, 20h
        xor dh, dh
        mov ax, 4401h
        int 21h
        jc open_done
        mov ax, bx
open_done:
        ret
open_raw endp
get_status proc near
        mov bx, word ptr [handle]
        mov cx, 0702h
        mov dx, offset status
        mov ax, 440Ch
        int 21h
        ret
get_status endp
restore_int24 proc near
        push ds
        mov dx, word ptr cs:[old_int24]
        mov ax, word ptr cs:[old_int24+2]
        mov ds, ax
        mov ax, 2524h
        int 21h
        pop ds
        ret
restore_int24 endp
critical_error proc far
        mov al, 3
        iret
critical_error endp

rmt_name db 'RMT0', 0
nrmt_name db 'NRMT0', 0
handle dw 0
old_int24 dd 0
status db 14 dup (0)
control dw 7
        dd 0
buffer db 55h, 0AAh
success_message db 'OpenASPI rewind smoke test passed', 13, 10, '$'
failure_message db 'OpenASPI rewind smoke test FAILED', 13, 10, '$'
        end start
