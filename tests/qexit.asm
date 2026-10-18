        .8086
        option casemap:none
        .model tiny
        .code
        org     100h

start:
        xor     al, al
        out     0F4h, al
        mov     ax, 4C00h
        int     21h

        end     start
