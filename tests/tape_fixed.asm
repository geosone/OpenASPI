; DOS-side ASPITAP fixed-block smoke test.

        .8086
        option casemap:none

        .model tiny
        .code
        org     100h

fail_if_carry macro target
        local   no_error
        jnc     no_error
        jmp     target
no_error:
endm

fail_if_no_carry macro target
        local   expected_error
        jc      expected_error
        jmp     target
expected_error:
endm

fail_if_not_equal macro target
        local   equal
        je      equal
        jmp     target
equal:
endm

start:
        push    cs
        pop     ds
        mov     ax, 3524h
        int     21h
        mov     word ptr [old_int24], bx
        mov     word ptr [old_int24+2], es
        mov     dx, offset critical_error
        mov     ax, 2524h
        int     21h

        mov     byte ptr [stage], '1'
        mov     dx, offset nrmt_name
        call    open_raw
        fail_if_carry failed
        mov     word ptr [handle], ax
        mov     bx, ax

        mov     byte ptr [stage], '2'
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+3], 81h
        fail_if_not_equal failed_close
        cmp     word ptr [status+6], 1024
        fail_if_not_equal failed_close

        ; Fixed requests must contain an integral number of device blocks.
        mov     byte ptr [stage], '3'
        mov     bx, word ptr [handle]
        mov     cx, 1
        mov     dx, offset transfer_buffer
        mov     ah, 3Fh
        int     21h
        fail_if_no_carry failed_close

        mov     byte ptr [stage], '4'
        mov     bx, word ptr [handle]
        mov     cx, 1024
        mov     dx, offset transfer_buffer
        mov     ah, 3Fh
        int     21h
        fail_if_carry failed_close
        cmp     ax, 1024
        fail_if_not_equal failed_close
        push    ds
        pop     es
        mov     di, offset transfer_buffer
        mov     cx, 1024
        mov     al, 5Ah
        repe    scasb
        fail_if_not_equal failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+4], 10h
        fail_if_not_equal failed_close
ifdef NO_RESIDUAL
        cmp     word ptr [status+0Ah], 0908h
else
        cmp     word ptr [status+0Ah], 0D08h
endif
        fail_if_not_equal failed_close

        mov     byte ptr [stage], '5'
        mov     bx, word ptr [handle]
        mov     cx, 1
        mov     dx, offset transfer_buffer
        mov     ah, 40h
        int     21h
        fail_if_no_carry failed_close

        push    ds
        pop     es
        mov     di, offset transfer_buffer
        mov     cx, 1024
        mov     al, 0A5h
        rep     stosb
        mov     byte ptr [stage], '6'
        mov     bx, word ptr [handle]
        mov     cx, 1024
        mov     dx, offset transfer_buffer
        mov     ah, 40h
        int     21h
        fail_if_carry failed_close
        cmp     ax, 1024
        fail_if_not_equal failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+4], 18h
        fail_if_not_equal failed_close
ifdef NO_RESIDUAL
        cmp     word ptr [status+0Ah], 110Ah
else
        cmp     word ptr [status+0Ah], 150Ah
endif
        fail_if_not_equal failed_close

        mov     byte ptr [stage], '7'
        mov     bx, word ptr [handle]
        mov     cx, 1024
        mov     dx, offset transfer_buffer
        mov     ah, 3Fh
        int     21h
        fail_if_no_carry failed_close

        call    close_handle
        call    restore_int24
        mov     dx, offset success_message
        mov     ah, 09h
        int     21h
        mov     ax, 4C00h
        int     21h

failed_close:
        call    close_handle
failed:
        call    restore_int24
        mov     dx, offset failure_message
        mov     ah, 09h
        int     21h
        mov     dl, byte ptr [stage]
        mov     ah, 02h
        int     21h
        mov     dx, offset newline
        mov     ah, 09h
        int     21h
        mov     ax, 4C01h
        int     21h

open_raw proc near
        mov     ax, 3D02h
        int     21h
        jc      open_done
        mov     bx, ax
        mov     ax, 4400h
        int     21h
        jc      open_failed
        or      dl, 20h
        xor     dh, dh
        mov     ax, 4401h
        int     21h
        jc      open_failed
        mov     ax, bx
        clc
open_done:
        ret
open_failed:
        mov     ah, 3Eh
        int     21h
        stc
        ret
open_raw endp

close_handle proc near
        mov     bx, word ptr [handle]
        mov     ah, 3Eh
        int     21h
        ret
close_handle endp

get_status proc near
        mov     bx, word ptr [handle]
        mov     ch, 07h
        mov     cl, 02h
        mov     dx, offset status
        mov     ax, 440Ch
        int     21h
        ret
get_status endp

restore_int24 proc near
        push    ds
        mov     dx, word ptr cs:[old_int24]
        mov     ax, word ptr cs:[old_int24+2]
        mov     ds, ax
        mov     ax, 2524h
        int     21h
        pop     ds
        ret
restore_int24 endp

critical_error proc far
        mov     al, 3
        iret
critical_error endp

nrmt_name       db      'NRMT0', 0
handle          dw      0
old_int24       dd      0
stage           db      '?'
status          db      14 dup (0)
transfer_buffer db      1024 dup (0)
success_message db      'OpenASPI fixed-block tape smoke test passed', 13, 10, '$'
failure_message db      'OpenASPI fixed-block tape smoke test FAILED at stage $'
newline         db      13, 10, '$'

        end     start
