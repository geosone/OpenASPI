; Disposable-media test: change only serial, read back, restore all fields.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h
        jmp start
original db 25 dup (0)
expected db 25 dup (0)
output db 25 dup (0)
drive db 0
saved db 0
ok db 'DOS Media-ID set/get/restore passed',13,10,'$'
bad db 'DOS Media-ID write FAILED',13,10,'$'
ifdef USE_FAT32
category equ 4800h
else
category equ 0800h
endif
CHECK macro
        local good
        jnc good
        jmp failed
good:
endm
start:
        push cs
        pop ds
        push cs
        pop es
        mov si,81h
skip_space:
        lodsb
        cmp al,' '
        je skip_space
        and al,0DFh
        sub al,'A'
        cmp al,25
        jbe drive_ok
        jmp failed
drive_ok:
        cmp byte ptr [si],':'
        je argument_ok
        jmp failed
argument_ok:
        inc al
        mov byte ptr [drive],al
        call live_parameters
        CHECK
        call live_tracks
        CHECK
        mov ax,4411h
        xor bx,bx
        mov bl,byte ptr [drive]
        mov cx,category+46h
        int 21h
        CHECK
        mov dx,offset original
        mov cl,66h
        call ioctl
        CHECK
        mov si,offset original
        mov di,offset expected
        mov cx,25
        rep movsb
        xor word ptr [expected+2],5A5Ah
        xor word ptr [expected+4],0A5A5h
        mov byte ptr [saved],1
        mov dx,offset expected
        mov cl,46h
        call ioctl
        CHECK
        mov dx,offset output
        mov cl,66h
        call ioctl
        CHECK
        mov si,offset expected
        mov di,offset output
        mov cx,25
        repe cmpsb
        jne failed
        call restore_id
        CHECK
        mov byte ptr [saved],0
        mov dx,offset output
        mov cl,66h
        call ioctl
        CHECK
        mov si,offset original
        mov di,offset output
        mov cx,25
        repe cmpsb
        jne failed
        mov dx,offset ok
        mov ah,09h
        int 21h
        mov ax,4C00h
        int 21h
failed:
        cmp byte ptr [saved],0
        je report
        call restore_id
report:
        mov dx,offset bad
        mov ah,09h
        int 21h
        mov ax,4C01h
        int 21h
restore_id proc near
        mov dx,offset original
        mov cl,46h
restore_id endp
ioctl proc near
        mov ch,category / 256
        mov ax,440Dh
        xor bx,bx
        mov bl,byte ptr [drive]
        int 21h
        ret
ioctl endp
        include tests/params_dos.inc
        include tests/track_dos.inc
        end start
