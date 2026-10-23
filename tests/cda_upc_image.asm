; Positive installed-driver check for the CUE fixture's 0123456789012 MCN.
; No mock manager: SHSUCDX -> ASPICDA -> ASPI -> emulated CD-ROM backend.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h
start:
        push cs
        pop ds
        push cs
        pop es
        mov word ptr [packet+16], cs
ifdef EXPECT_HIGH
        mov word ptr [packet+14], offset header_control
        mov word ptr [packet+18], 5
        mov bx, offset packet
        mov cx, 'R'-'A'
        mov ax, 1510h
        int 2Fh
        jc high_failed
        test word ptr [packet+3], 8000h
        jnz high_failed
        cmp word ptr [header_control+3], 0A000h
        jb high_failed
        mov dx, offset manager_name
        mov ax, 3D00h
        int 21h
        jc high_failed
        mov bx, ax
        mov dx, offset manager_entry
        mov cx, 4
        mov ax, 4402h
        int 21h
        pushf
        mov ah, 3Eh
        int 21h
        popf
        jc failed
        cmp word ptr [manager_entry+2], 0A000h
        jb high_failed
        jmp short high_verified
high_failed:
        jmp failed
high_verified:
        mov dx, offset msg_high
        mov ah, 09h
        int 21h
        mov word ptr [packet+14], offset control
        mov word ptr [packet+18], 11
endif
        mov bx, offset packet
        mov cx, 'R'-'A'
        mov ax, 1510h
        int 2Fh
        jc failed
        test word ptr [packet+3], 8000h
        jnz failed
        cmp byte ptr [control+1], 42h         ; data track CONTROL=4, ADR=2
        jne failed
        mov si, offset expected
        mov di, offset control+2
        mov cx, 7
        cld
        repe cmpsb
        jne failed
        cmp byte ptr [control+9], 0
        jne failed
        mov al, byte ptr [control+10]
        cmp al, 74h
        ja failed
        and al, 0Fh
        cmp al, 9
        ja failed
        cmp byte ptr [guard_before], 0A5h
        jne failed
        cmp byte ptr [guard_after], 0A5h
        jne failed
        mov dx, offset msg_pass
        mov ah, 09h
        int 21h
        mov ax, 4C00h
        int 21h
failed:
        mov dx, offset msg_fail
        mov ah, 09h
        int 21h
        mov bx, word ptr [packet+3]
        mov cx, 4
hex_next:
        push cx
        mov cl, 4
        rol bx, cl
        pop cx
        mov dl, bl
        and dl, 0Fh
        add dl, '0'
        cmp dl, '9'
        jbe hex_emit
        add dl, 'A'-'9'-1
hex_emit:
        mov ah, 02h
        int 21h
        loop hex_next
        mov ax, 4C01h
        int 21h
packet db 20,0,3
       dw 0
       db 8 dup (0)
       db 0
       dw control,0
       dw 11
guard_before db 0A5h
control db 14,10 dup (0A5h)
guard_after db 0A5h
expected db 01h,23h,45h,67h,89h,01h,20h
msg_pass db 'ASPICDA image UPC 0123456789012 passed',13,10,'$'
msg_fail db 'ASPICDA image UPC FAILED, status $'
ifdef EXPECT_HIGH
header_control db 0,4 dup (0)
manager_name db 'SCSIMGR$',0
manager_entry dd 0
msg_high db 'ASPI manager and ASPICDA verified in upper memory',13,10,'$'
endif
        end start
