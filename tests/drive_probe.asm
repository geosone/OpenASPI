; DRVPROBE X:\FILE - is the file there? Prints "PROBE FOUND" or "PROBE
; REFUSED", without the "Abort, Retry, Fail" prompt: a critical error fails
; the call. For tests of media a driver must refuse (tests/dos_sector2048.sh).
        .8086
        option casemap:none
        .model tiny
        .code
        org     100h

start:
        mov     dx, offset critical
        mov     ax, 2524h
        int     21h
        mov     si, 81h                         ; the argument, 0-terminated
skip:   lodsb
        cmp     al, ' '
        je      skip
        dec     si
        mov     dx, si
find_end:
        lodsb
        cmp     al, 0Dh
        je      at_end
        cmp     al, ' '
        jne     find_end
at_end: mov     byte ptr [si-1], 0
        mov     ah, 1Ah                         ; DTA
        push    dx
        mov     dx, offset dta
        int     21h
        pop     dx
        mov     ah, 4Eh
        xor     cx, cx
        int     21h
        mov     dx, offset found
        jnc     report
        mov     dx, offset refused
report: mov     ah, 09h
        int     21h
        mov     ax, 4C00h
        int     21h

critical:
        mov     al, 3                           ; fail the call
        iret

found   db      'PROBE FOUND', 13, 10, '$'
refused db      'PROBE REFUSED', 13, 10, '$'
dta     db      128 dup (0)
        end     start
