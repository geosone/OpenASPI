; Live write protection of D: (tests/dos_disk_protect.sh: a read-only QEMU
; USB disk, so the target answers WRITE with DATA PROTECT). Absolute writes
; must fail with DOS error 00h without INT 24h, DOS writes must reach INT 24h
; with error 00h, and the unit must stay readable with unchanged data.
        .8086
        option casemap:none
        .model tiny
        .code
        org     100h

CHECK macro condition
        local good
        condition good
        jmp failed
good:
endm

start:
        push    cs
        pop     ds
        push    cs
        pop     es
        cld
        mov     word ptr [packet+8], cs
        mov     ax, 3524h
        int     21h
        mov     word ptr [old_24], bx
        mov     word ptr [old_24+2], es
        push    cs
        pop     es
        mov     dx, offset critical
        mov     ax, 2524h
        int     21h
        ; 1: absolute read of the boot sector
        mov     word ptr [packet+6], offset sector_a
        call    absolute_read
        CHECK   jnc
        ; 2: absolute write: DOS error 00h (write protect), no INT 24h.
        ; DOS 7 halts on direct writes without a level-0 volume lock; older
        ; DOS rejects the lock call, which is harmless.
        inc     byte ptr [stage]
        mov     ax, 440Dh
        mov     bx, 0004h                       ; D:, level 0
        mov     cx, 084Ah                       ; lock logical volume
        xor     dx, dx
        int     21h
        mov     word ptr [packet+6], offset sector_a
        mov     al, 3
        mov     cx, 0FFFFh
        mov     bx, offset packet
        int     26h
        pop     dx                              ; flags left by INT 26h
        pushf
        push    ax
        mov     ax, 440Dh
        mov     bx, 0004h
        mov     cx, 086Ah                       ; unlock logical volume
        int     21h
        pop     ax
        popf
        CHECK   jc
        cmp     al, 0
        CHECK   je
        cmp     byte ptr [critical_calls], 0
        CHECK   je
        ; 3: create a file: INT 24h with error 00h, the call fails
        inc     byte ptr [stage]
        mov     dx, offset file_name
        xor     cx, cx
        mov     ah, 3Ch
        int     21h
        CHECK   jc
        cmp     byte ptr [critical_calls], 0
        CHECK   jne
        cmp     byte ptr [critical_code], 0
        CHECK   je
        ; 4: still readable, the same boot sector
        inc     byte ptr [stage]
        mov     word ptr [packet+6], offset sector_b
        call    absolute_read
        CHECK   jnc
        mov     si, offset sector_a
        mov     di, offset sector_b
        mov     cx, 256
        repe    cmpsw
        CHECK   je
        call    restore_24
        mov     dx, offset msg_pass
        mov     ah, 09h
        int     21h
        mov     ax, 4C00h
        int     21h

failed:
        call    restore_24
        mov     dx, offset msg_fail
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

; INT 25h with the large-disk packet; CF from DOS.
absolute_read proc near
        mov     al, 3
        mov     cx, 0FFFFh
        mov     bx, offset packet
        int     25h
        pop     dx
        ret
absolute_read endp

restore_24 proc near
        push    ds
        lds     dx, dword ptr cs:[old_24]
        mov     ax, 2524h
        int     21h
        pop     ds
        ret
restore_24 endp

; Record the driver error (DI low byte) and fail the call.
critical proc far
        inc     byte ptr cs:[critical_calls]
        mov     ax, di
        mov     byte ptr cs:[critical_code], al
        mov     al, 3
        iret
critical endp

old_24          dd      0
critical_calls  db      0
critical_code   db      0FFh
stage           db      '1'
packet          dd      0                       ; sector
                dw      1                       ; count
                dw      0, 0                    ; buffer offset, segment
file_name       db      'D:\NEW.TXT', 0
msg_pass        db      'Live block write protection passed', 13, 10, '$'
msg_fail        db      'Live block write protection FAILED at stage $'
newline         db      13, 10, '$'
sector_a        db      512 dup (0)
sector_b        db      512 dup (0)

        end     start
