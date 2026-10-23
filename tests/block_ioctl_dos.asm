; End-to-end DOS INT 21h IOCTL against E: stick, F: ZIP, G: superfloppy
; in dos_disk.sh. All calls are non-destructive parameter/capability reads.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h
REQUIRE_CLEAR macro
        local clear_ok
        jnc clear_ok
        jmp failed
clear_ok:
endm
start:
        push cs
        pop ds
next_drive:
        mov byte ptr [stage], 0
        mov ax, 4411h
        mov bl, [drive]
        mov cx, 0860h
        int 21h
        REQUIRE_CLEAR
        or ax, ax
        jz capability_ok
        jmp failed
capability_ok:
        inc byte ptr [stage]
        mov byte ptr [parameters], 4
        call get_parameters
        REQUIRE_CLEAR
        inc byte ptr [stage]
        call check_parameters
        REQUIRE_CLEAR
        inc byte ptr [stage]
        mov byte ptr [parameters], 5
        call get_parameters
        REQUIRE_CLEAR
        inc byte ptr [stage]
        call check_parameters
        REQUIRE_CLEAR
        inc byte ptr [stage]
        mov ax, 4411h
        mov bl, [drive]
        mov cx, 0842h                           ; format must not be advertised
        int 21h
        jnc failed
        mov byte ptr [stage], 6
        mov ax, 4411h
        mov bl, [drive]
        mov cx, 0866h
        int 21h
        REQUIRE_CLEAR
        mov byte ptr [stage], 7
        mov word ptr [media_id], 0
        mov ax, 440Dh
        mov bl, [drive]
        mov cx, 0866h
        mov dx, offset media_id
        int 21h
        REQUIRE_CLEAR
        mov byte ptr [stage], 8
        call check_media_id
        REQUIRE_CLEAR
        inc byte ptr [drive]
        cmp byte ptr [drive], 8
        jae finished_drives
        jmp next_drive
finished_drives:
        mov dx, offset success
        mov ah, 09h
        int 21h
        mov ax, 4C00h
        int 21h
failed:
        mov word ptr [error_code], ax
        mov dx, offset failure
        mov ah, 09h
        int 21h
        mov dl, [drive]
        add dl, '0'
        mov ah, 02h
        int 21h
        mov dl, [stage]
        add dl, '0'
        int 21h
        mov dx, offset ax_text
        mov ah, 09h
        int 21h
        mov bx, word ptr [error_code]
        mov bp, 4
print_hex:
        mov cl, 4
        rol bx, cl
        mov dl, bl
        and dl, 0Fh
        add dl, '0'
        cmp dl, '9'
        jbe hex_digit
        add dl, 7
hex_digit:
        mov ah, 02h
        int 21h
        dec bp
        jnz print_hex
        mov ax, 4C01h
        int 21h
get_parameters proc near
        mov ax, 440Dh
        mov bl, [drive]
        mov cx, 0860h
        mov dx, offset parameters
        int 21h
        ret
get_parameters endp
check_parameters proc near
        cmp word ptr [parameters+7], 512
        jne invalid
        cmp byte ptr [guard], 0A5h
        jne invalid
        xor bh, bh
        mov bl, [drive]
        sub bx, 5
        shl bx, 1
        mov ax, [hidden+bx]
        cmp word ptr [parameters+7+17], ax
        jne invalid
        cmp word ptr [parameters+7+19], 0
        jne invalid
        clc
        ret
invalid:
        stc
        ret
check_parameters endp
check_media_id proc near
        cmp byte ptr [id_guard], 0A5h
        jne id_invalid
        cmp word ptr [media_id], 0
        jne id_invalid
        xor bh, bh
        mov bl, [drive]
        sub bx, 5
        mov si, bx
        shl bx, 1
        shl bx, 1
        mov ax, word ptr [serials+bx]
        cmp word ptr [media_id+2], ax
        jne id_invalid
        mov ax, word ptr [serials+bx+2]
        cmp word ptr [media_id+4], ax
        jne id_invalid
        mov ax, si
        mov cx, 11
        mul cx
        mov si, offset labels
        add si, ax
        push cs
        pop es
        mov di, offset media_id+6
        mov cx, 11
        repe cmpsb
        jne id_invalid
        mov si, offset expected_fs
        mov di, offset media_id+17
        mov cx, 8
        repe cmpsb
        jne id_invalid
        clc
        ret
id_invalid:
        stc
        ret
check_media_id endp
drive db 5
stage db 0
error_code dw 0
hidden dw 63, 32, 0
parameters db 32 dup (0)
guard db 0A5h
media_id db 25 dup (0)
id_guard db 0A5h
serials dd 11112222h, 33334444h, 55556666h
labels db 'STICK      ', 'ZIPDISK    ', 'SUPERDISK  '
expected_fs db 'FAT16   '
success db 'DOS block IOCTL end-to-end tests passed',13,10,'$'
failure db 'DOS block IOCTL end-to-end FAILED drive/stage $'
ax_text db ' AX=$'
        end start
