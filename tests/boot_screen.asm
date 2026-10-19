; Copy the VGA text screen to redirected stdout before AUTOEXEC output
; scrolls away CONFIG.SYS driver diagnostics. QEMU fixtures boot in mode 3.
        .8086
        option casemap:none
        .model tiny
        .code
        org     100h

start:
        push    cs
        pop     ds
        cld
        mov     ah, 0Fh
        int     10h
        cmp     al, 3
        jne     failed
        cmp     ah, 80
        jne     failed
        xor     ax, ax
        mov     al, bh
        mov     cl, 12
        shl     ax, cl                  ; active text page, 4096 bytes apart
        mov     si, ax
        mov     ax, 0B800h
        mov     es, ax
        mov     bp, 25
next_row:
        mov     di, offset row_buffer
        mov     cx, 80
next_cell:
        mov     al, byte ptr es:[si]
        mov     byte ptr [di], al
        inc     di
        add     si, 2                   ; skip the character's VGA attribute
        loop    next_cell
        mov     bx, 1
        mov     dx, offset row_buffer
        mov     cx, 82
        mov     ah, 40h
        int     21h
        jc      failed
        cmp     ax, 82
        jne     failed
        dec     bp
        jnz     next_row
        mov     ax, 4C00h
        int     21h
failed:
        mov     ax, 4C01h
        int     21h
row_buffer db 80 dup (0), 13, 10
        end start
