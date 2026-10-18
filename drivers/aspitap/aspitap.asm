; ASPITAP.SYS bootstrap driver for OpenASPI.
;
; This first image proves the Linux JWasm build and DOS device-driver loader
; layout.  It intentionally rejects every request except INIT.  ASPI discovery,
; additional device headers, IOCTL and data transfer are not implemented yet.

        .8086
        option casemap:none

        .model tiny
        .code
        org     0

driver_start:
        dd      0FFFFFFFFh              ; end of DOS device chain
        dw      08000h                  ; character device, no I/O yet
        dw      strategy
        dw      interrupt
        db      'RMT0    '

request_ptr     dd      0

strategy proc far
        mov     word ptr cs:[request_ptr], bx
        mov     word ptr cs:[request_ptr+2], es
        ret
strategy endp

interrupt proc far
        push    ax
        push    bx
        push    dx
        push    ds
        push    es

        les     bx, cs:[request_ptr]
        cmp     byte ptr es:[bx+2], 0   ; INIT request?
        jne     unsupported

        mov     word ptr es:[bx+0Eh], offset resident_end
        mov     word ptr es:[bx+10h], cs
        mov     word ptr es:[bx+3], 0100h

        push    cs
        pop     ds
        mov     dx, offset banner
        mov     ah, 09h
        int     21h
        jmp     short request_done

unsupported:
        mov     word ptr es:[bx+3], 8103h ; done + error + unknown command

request_done:
        pop     es
        pop     ds
        pop     dx
        pop     bx
        pop     ax
        ret
interrupt endp

banner  db      'OpenASPI ASPITAP prototype: no tape I/O yet', 13, 10, '$'

resident_end label byte

        end     driver_start
