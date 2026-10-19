; Verify the ASPITAPE -m and -s CONFIG.SYS compatibility switches.

        .8086
        option casemap:none

        .model tiny
        .code
        org     100h

start:
        push    cs
        pop     ds

        mov     dx, offset nrmt_name
        call    open_raw
        jc      failed
        mov     word ptr [handle1], ax

        mov     dx, offset nrmt_name
        call    open_raw
        jc      failed_close1
        mov     word ptr [handle2], ax

        ; -m permits data transfer while two handles are open.
        mov     bx, word ptr [handle2]
        mov     cx, 2
        mov     dx, offset buffer
        mov     ah, 3Fh
        int     21h
        jc      failed_close2
        cmp     ax, 2
        jne     failed_close2

        mov     bx, word ptr [handle1]
        mov     ah, 3Eh
        int     21h
        jc      failed_close2

        ; -s permits the one-byte requests rejected by the default guard.
        mov     bx, word ptr [handle2]
        mov     cx, 1
        mov     dx, offset buffer
        mov     ah, 3Fh
        int     21h
        jc      failed_close2
        cmp     ax, 1
        jne     failed_close2

        mov     bx, word ptr [handle2]
        mov     cx, 1
        mov     dx, offset payload
        mov     ah, 40h
        int     21h
        jc      failed_close2
        cmp     ax, 1
        jne     failed_close2

        mov     bx, word ptr [handle2]
        mov     ah, 3Eh
        int     21h
        jc      failed
        mov     dx, offset success_message
        mov     ah, 09h
        int     21h
        mov     ax, 4C00h
        int     21h

failed_close2:
        mov     bx, word ptr [handle2]
        mov     ah, 3Eh
        int     21h
failed_close1:
        mov     bx, word ptr [handle1]
        mov     ah, 3Eh
        int     21h
failed:
        mov     dx, offset failure_message
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

nrmt_name       db      'NRMT0', 0
handle1         dw      0
handle2         dw      0
buffer          db      2 dup (0)
payload         db      5Ah
success_message db      'OpenASPI tape option smoke test passed', 13, 10, '$'
failure_message db      'OpenASPI tape option smoke test FAILED', 13, 10, '$'

        end     start
