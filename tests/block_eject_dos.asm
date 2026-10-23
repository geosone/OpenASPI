; After the F: scratch medium was ejected, current-parameter IOCTL must
; fail without overwriting the output with a cached BPB. DOS integration.
        .8086
        .model tiny
        .code
        org 100h
start:
        push cs
        pop ds
        mov ax, 440Dh
        mov bx, 6
        mov cx, 0860h
        mov dx, offset params
        int 21h
        jnc failed
        mov si, offset params+1
        mov cx, 31
check_guard:
        cmp byte ptr [si], 0A5h
        jne failed
        inc si
        loop check_guard
        mov dx, offset success
        mov ah, 9
        int 21h
        mov ax, 4C00h
        int 21h
failed:
        mov dx, offset failure
        mov ah, 9
        int 21h
        mov ax, 4C01h
        int 21h
params db 1,31 dup (0A5h)
success db 'Ejected FDD rejects fresh BPB without stale output',13,10,'$'
failure db 'Ejected FDD BPB FAILED',13,10,'$'
        end start
