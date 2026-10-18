; DOS-side ASPITAP compatibility smoke test.

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

fail_if_not_equal macro target
        local   equal
        je      equal
        jmp     target
equal:
endm

start:
        push    cs
        pop     ds

        mov     byte ptr [stage], '1'
        mov     dx, offset rmt_name
        call    open_raw
        fail_if_carry failed
        mov     word ptr [handle], ax
        mov     bx, ax
        mov     byte ptr [stage], '2'
        call    get_status
        fail_if_carry failed_close
        mov     byte ptr [stage], 'D'
        cmp     byte ptr [status+0], 0
        fail_if_not_equal failed_close
        mov     byte ptr [stage], 'E'
        cmp     byte ptr [status+1], 0
        fail_if_not_equal failed_close
        mov     byte ptr [stage], 'F'
        cmp     byte ptr [status+2], 0
        fail_if_not_equal failed_close
        mov     byte ptr [stage], 'G'
        cmp     byte ptr [status+3], 80h
        fail_if_not_equal failed_close
        mov     byte ptr [stage], 'H'
        cmp     byte ptr [status+4], 04h
        fail_if_not_equal failed_close
        call    close_handle

        mov     byte ptr [stage], '3'
        mov     dx, offset nrmt_name
        call    open_raw
        fail_if_carry failed
        mov     word ptr [handle], ax
        mov     bx, ax
        mov     byte ptr [stage], '4'
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+4], 00h
        fail_if_not_equal failed_close

        mov     byte ptr [stage], '5'
        mov     cl, 03h                 ; ignore EOT errors
        mov     dx, offset status
        call    tape_ioctl
        fail_if_carry failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+4], 40h
        fail_if_not_equal failed_close

        mov     byte ptr [stage], '6'
        mov     cl, 04h                 ; enable EOT errors
        mov     dx, offset status
        call    tape_ioctl
        fail_if_carry failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+4], 00h
        fail_if_not_equal failed_close

        mov     byte ptr [stage], '7'
        mov     cl, 01h                 ; mtop: MTNOP
        mov     dx, offset control
        call    tape_ioctl
        fail_if_carry failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     word ptr [status+0Ah], 1800h
        fail_if_not_equal failed_close
        cmp     byte ptr [status+8], 0
        fail_if_not_equal failed_close
        cmp     byte ptr [status+9], 0
        fail_if_not_equal failed_close

        call    close_handle
        mov     dx, offset success_message
        mov     ah, 09h
        int     21h
        mov     ax, 4C00h
        int     21h

failed_close:
        call    close_handle
failed:
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
        mov     ax, 3D00h
        int     21h
        jc      open_done
        mov     byte ptr [stage], 'A'
        mov     bx, ax
        mov     ax, 4400h
        int     21h
        jc      open_failed
        mov     byte ptr [stage], 'B'
        or      dl, 20h
        xor     dh, dh
        mov     ax, 4401h
        int     21h
        jc      open_failed
        mov     byte ptr [stage], 'C'
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
        mov     cl, 02h
        mov     dx, offset status
        jmp     short tape_ioctl
get_status endp

tape_ioctl proc near
        mov     bx, word ptr [handle]
        mov     ch, 07h
        mov     ax, 440Ch
        int     21h
        ret
tape_ioctl endp

rmt_name        db      'RMT0', 0
nrmt_name       db      'NRMT0', 0
handle          dw      0
stage           db      '?'
control:
        dw      7                       ; MTNOP
        dd      1
status          db      14 dup (0)
success_message db      'OpenASPI tape IOCTL smoke test passed', 13, 10, '$'
failure_message db      'OpenASPI tape IOCTL smoke test FAILED at stage $'
newline         db      13, 10, '$'

        end     start
