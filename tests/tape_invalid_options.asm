; Invalid CONFIG.SYS options must leave neither tape header installed.
        .8086
        option casemap:none
        .model tiny
        .code
        org     100h

start:
        push    cs
        pop     ds
        mov     dx, offset rmt_name
        call    expect_absent
        jc      failed
        mov     dx, offset nrmt_name
        call    expect_absent
        jc      failed
        mov     dx, offset success_message
        mov     ah, 09h
        int     21h
        mov     ax, 4C00h
        int     21h
failed:
        mov     dx, offset failure_message
        mov     ah, 09h
        int     21h
        mov     ax, 4C01h
        int     21h

expect_absent proc near
        mov     ax, 3D00h
        int     21h
        jnc     unexpectedly_opened
        cmp     ax, 2                   ; file/device not found
        jne     absent_error
        clc
        ret
unexpectedly_opened:
        mov     bx, ax
        mov     ah, 3Eh
        int     21h
absent_error:
        stc
        ret
expect_absent endp

rmt_name        db 'RMT0', 0
nrmt_name       db 'NRMT0', 0
success_message db 'OpenASPI invalid tape options rejected', 13, 10, '$'
failure_message db 'OpenASPI invalid tape options FAILED', 13, 10, '$'
        end start
