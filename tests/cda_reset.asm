; Installed ASPICDA reset through a real ASPI manager (AHCIASPI in QEMU):
; lock, reset, then the lock must be gone and MEDIA CHANGED must report the
; change once. The batch file reads the CD again afterwards.
        .8086
        option casemap:none
        .model tiny
        .code
        org     100h

CFCHECK macro condition
        local good
        condition good
        jmp failed
good:
endm

start:
        push    cs
        pop     ds
        mov     byte ptr [stage], '1'
        mov     dx, offset device_name
        mov     ax, 3D02h
        int     21h
        CFCHECK jnc
        mov     word ptr [handle], ax
        mov     word ptr [control], 0101h       ; lock door
        mov     cx, 2
        call    ioctl_write
        CFCHECK jnc
        mov     byte ptr [stage], '2'
        call    device_status
        test    byte ptr [control+1], 2         ; bit 1 set: unlocked
        CFCHECK jz
        mov     byte ptr [stage], '3'
        mov     word ptr [control], 0002h       ; reset drive
        mov     cx, 1
        call    ioctl_write
        CFCHECK jnc
        mov     byte ptr [stage], '4'
        call    device_status
        test    byte ptr [control+1], 2
        CFCHECK jnz
        mov     byte ptr [stage], '5'
        call    media_changed
        cmp     byte ptr [control+1], 0FFh
        CFCHECK je
        mov     byte ptr [stage], '6'
        ; The device may still report its own reset; the latch is gone.
        call    media_changed
        call    media_changed
        cmp     byte ptr [control+1], 1
        CFCHECK je
        mov     bx, word ptr [handle]
        mov     ah, 3Eh
        int     21h
        mov     dx, offset msg_pass
        mov     ah, 09h
        int     21h
        mov     ax, 4C00h
        int     21h

failed:
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

ioctl_write proc near
        mov     bx, word ptr [handle]
        mov     dx, offset control
        mov     ax, 4403h
        int     21h
        ret
ioctl_write endp

device_status proc near
        mov     byte ptr [control], 6
        mov     cx, 5
        jmp     short ioctl_read
device_status endp

media_changed proc near
        mov     byte ptr [control], 9
        mov     cx, 2
ioctl_read::
        mov     byte ptr [control+1], 0A5h
        mov     bx, word ptr [handle]
        mov     dx, offset control
        mov     ax, 4402h
        int     21h
        CFCHECK jnc
        ret
media_changed endp

device_name     db      'ASPICDA0', 0
handle          dw      0
stage           db      '0'
control         db      8 dup (0)
msg_pass        db      'ASPICDA reset through the ASPI manager passed', 13, 10, '$'
msg_fail        db      'ASPICDA reset FAILED at stage $'
newline         db      13, 10, '$'

        end     start
