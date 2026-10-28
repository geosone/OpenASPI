; Installed ASPICDA across a real QEMU CD exchange (tests/cda_swap.py swaps
; the medium when it sees the prompt). The first commands after the exchange
; consume the drive's NOT READY and UNIT ATTENTION; MEDIA CHANGED must still
; report the exchange once, and the volume size must come from the new disc.
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
        call    media_changed
        cmp     byte ptr [control+1], 1
        CFCHECK je
        call    volume_size
        CFCHECK jnc
        mov     ax, word ptr [control+1]
        mov     word ptr [size_a], ax
        mov     ax, word ptr [control+3]
        mov     word ptr [size_a+2], ax
        mov     dx, offset msg_prompt
        mov     ah, 09h
        int     21h
        xor     ah, ah
        int     16h
        mov     byte ptr [stage], '2'
        ; The drive first reports NOT READY (no medium), then the UNIT
        ; ATTENTION; the test, not the driver, polls a bounded number of times.
        mov     cx, 10
swap_size_poll:
        push    cx
        call    volume_size
        pop     cx
        jnc     swap_size_ready
        loop    swap_size_poll
        jmp     failed
swap_size_ready:
        mov     ax, word ptr [control+1]
        mov     dx, word ptr [control+3]
        cmp     ax, word ptr [size_a]
        jne     swap_size_changed
        cmp     dx, word ptr [size_a+2]
        CFCHECK jne
swap_size_changed:
        mov     byte ptr [stage], '3'
        call    media_changed
        cmp     byte ptr [control+1], 0FFh
        CFCHECK je
        mov     byte ptr [stage], '4'
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

; CF from the driver, the dword size in control+1
volume_size proc near
        mov     byte ptr [control], 8
        mov     cx, 5
        jmp     short ioctl_read
volume_size endp

media_changed proc near
        mov     byte ptr [control], 9
        mov     cx, 2
        call    ioctl_read
        CFCHECK jnc
        ret
media_changed endp

ioctl_read proc near
        mov     byte ptr [control+1], 0A5h
        mov     bx, word ptr [handle]
        mov     dx, offset control
        mov     ax, 4402h
        int     21h
        ret
ioctl_read endp

device_name     db      'ASPICDA0', 0
handle          dw      0
stage           db      '0'
size_a          dd      0
control         db      8 dup (0)
msg_prompt      db      'SWAP CD NOW', 13, 10, '$'
msg_pass        db      'ASPICDA media exchange through the ASPI manager passed', 13, 10, '$'
msg_fail        db      'ASPICDA media exchange FAILED at stage $'
newline         db      13, 10, '$'

        end     start
