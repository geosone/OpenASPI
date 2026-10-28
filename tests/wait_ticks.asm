; WAIT.COM: waits about eight seconds (146 BIOS ticks), for media changes
; made by the host during a QEMU test.  nasm -f bin -o WAIT.COM wait_ticks.asm
        org     100h
        xor     ax, ax
        mov     es, ax
        mov     bx, [es:46Ch]
.wait:  sti
        hlt
        mov     ax, [es:46Ch]
        sub     ax, bx
        cmp     ax, 146
        jb      .wait
        mov     ax, 4C00h
        int     21h
