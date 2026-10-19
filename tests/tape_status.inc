; Shared DOS ABI check. Every status read checks destination guards and
; compares the explicitly requested 16-byte snapshot with the legacy form.
status_require_success macro
        local ok
        jnc ok
        jmp status_check_failed
ok:
endm
status_require_equal macro
        local ok
        je ok
        jmp status_check_failed
ok:
endm
checked_mtget proc near
        push si
        push di
        mov word ptr [status+14], 0A55Ah
        mov word ptr [status+16], 0A55Ah
        mov bx, word ptr [handle]
        mov cx, 0702h
        mov dx, offset status
        mov ax, 440Ch
        int 21h
        status_require_success
        cmp word ptr [status+16], 0A55Ah
        status_require_equal
ifdef STATUS16
        ; Normalize the -2 legacy entry point for the existing assertions.
        mov ax, word ptr [status+4]
        mov dl, al
        and dl, 1Fh
        and al, 0C0h
        shr al, 1
        or dl, al
        test ah, 1
        jz status_normalize_ready
        or dl, 80h
status_normalize_ready:
        mov byte ptr [status+4], dl
        mov byte ptr [status+5], 0
        mov ax, word ptr [status+8]
        mov word ptr [status+6], ax
        mov ax, word ptr [status+10]
        mov word ptr [status+8], ax
        mov ax, word ptr [status+12]
        mov word ptr [status+10], ax
        mov ax, word ptr [status+14]
        mov word ptr [status+12], ax
else
        cmp word ptr [status+14], 0A55Ah
        status_require_equal
endif
        mov word ptr [status_extended+16], 0A55Ah
        mov bx, word ptr [handle]
        mov cx, 0705h
        mov dx, offset status_extended
        mov ax, 440Ch
        int 21h
        status_require_success
        cmp word ptr [status_extended+16], 0A55Ah
        status_require_equal
        mov si, offset status
        mov di, offset status_extended
        mov cx, 4
status_compare_address:
        mov al, byte ptr [si]
        cmp al, byte ptr [di]
        status_require_equal
        inc si
        inc di
        loop status_compare_address
        xor ah, ah
        mov al, byte ptr [status+4]
        mov dl, al
        and al, 1Fh
        and dl, 60h
        shl dl, 1
        or al, dl
        test byte ptr [status+4], 80h
        jz status_compare_state
        mov ah, 1
status_compare_state:
        mov dx, word ptr [status_extended+4]
        and dl, 0DFh                   ; MTOP has no manual-ABI equivalent
        cmp ax, dx
        status_require_equal
        cmp byte ptr [status_extended+6], 0
        status_require_equal
        mov si, offset status+6
        mov di, offset status_extended+8
        mov cx, 8
status_compare_tail:
        mov al, byte ptr [si]
        cmp al, byte ptr [di]
        status_require_equal
        inc si
        inc di
        loop status_compare_tail
        pop di
        pop si
        clc
        ret
status_check_failed:
        pop di
        pop si
        stc
        ret
checked_mtget endp
status_extended db 18 dup (0)
