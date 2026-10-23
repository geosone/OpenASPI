; Live roundtrip on disposable images from dos_disk.sh / dos_fat32.sh.
; Write only the identical sector just read, then compare a fresh read.
live_track_args db 0
                dw 0,0,0,1
                dw offset live_track_a,0
live_verify_args db 0
                 dw 0,0
live_verify_guard db 0A5h
live_track_a db 512 dup (0)
live_track_b db 512 dup (0)
live_track_id db 25 dup (0)
live_track_ok db 'DOS physical track read/write/verify passed',13,10,'$'
LT_CHECK macro condition
        local okay
        condition okay
        jmp live_track_failed
okay:
endm
live_tracks proc near
        ; Refresh actual volume metadata to discard the preceding BPB override.
        ; This also tests normal track writes and the subsequent BPB reload.
        mov dx,offset live_track_id
        mov cl,66h
        call live_track_ioctl
        LT_CHECK jnc
        mov cl,41h
        call live_track_query
        LT_CHECK jnc
        mov cl,61h
        call live_track_query
        LT_CHECK jnc
        mov cl,62h
        call live_track_query
        LT_CHECK jnc
        mov word ptr [live_track_args+11],cs
        mov word ptr [live_track_args+9],offset live_track_a
        mov dx,offset live_track_args
        mov cl,61h
        call live_track_ioctl
        LT_CHECK jnc
        cmp word ptr [live_track_a+510],0AA55h
        LT_CHECK je
        mov ax,word ptr [live_parameter+7+17]
        mov bx,word ptr [live_parameter+7+19]
        mov cx,ax
        or cx,bx
        jz live_track_superfloppy
        ; CHS 0:0:0 must return the MBR, not the partition boot sector.
        cmp word ptr [live_track_a+454],ax
        LT_CHECK je
        cmp word ptr [live_track_a+456],bx
        LT_CHECK je
        jmp short live_track_identity_write
live_track_superfloppy:
        cmp word ptr [live_track_a+11],512
        LT_CHECK je
live_track_identity_write:
        mov dx,offset live_track_args
        mov cl,41h
        call live_track_ioctl
        LT_CHECK jnc
        mov word ptr [live_track_args+9],offset live_track_b
        mov dx,offset live_track_args
        mov cl,61h
        call live_track_ioctl
        LT_CHECK jnc
        push cs
        pop es
        mov si,offset live_track_a
        mov di,offset live_track_b
        mov cx,512
        repe cmpsb
        LT_CHECK je
        mov dx,offset live_verify_args
        mov cl,62h
        call live_track_ioctl
        LT_CHECK jnc
        cmp byte ptr [live_verify_guard],0A5h
        LT_CHECK je
        mov dx,offset live_track_ok
        mov ah,09h
        int 21h
        clc
        ret
live_track_failed:
        stc
        ret
live_tracks endp
live_track_query proc near
        mov ax,4411h
        mov ch,category / 256
        xor bx,bx
        mov bl,byte ptr [drive]
        int 21h
        ret
live_track_query endp
live_track_ioctl proc near
        mov ax,440Dh
        mov ch,category / 256
        xor bx,bx
        mov bl,byte ptr [drive]
        int 21h
        ret
live_track_ioctl endp
