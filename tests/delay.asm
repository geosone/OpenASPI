; DELAY.SYS - wait about two seconds during CONFIG.SYS, then unload
;
; QEMU's emulated AMD 53C974/DC-390 controller must be started without SCSI
; targets so that SeaBIOS can finish.  The mhVTL targets are hot-plugged while
; this helper delays the following DOS ASPI manager.

        option casemap:none
        .model tiny
        .386
        .code
        org     0

        dd      0FFFFFFFFh
        dw      8000h
        dw      strategy
        dw      interrupt
        db      'DELAY$$$'

request dd      0

strategy:
        mov     word ptr cs:[request], bx
        mov     word ptr cs:[request+2], es
        retf

interrupt:
        pushad
        push    ds
        push    es
        push    0040h
        pop     ds
        sti
        mov     cx, 37                  ; approximately two BIOS seconds

tick:
        mov     ax, word ptr ds:[006Ch]

wait_tick:
        cmp     ax, word ptr ds:[006Ch]
        je      wait_tick
        loop    tick

        les     bx, dword ptr cs:[request]
        mov     word ptr es:[bx+0Eh], 0 ; no resident part remains
        mov     word ptr es:[bx+10h], cs
        mov     word ptr es:[bx+3], 0100h
        pop     es
        pop     ds
        popad
        retf

        end
