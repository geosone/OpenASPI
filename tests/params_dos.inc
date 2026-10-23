; Live DOS parameter roundtrip, shared by legacy and FAT32 test clients.
ifdef USE_FAT32
live_parameter_size equ 60
else
live_parameter_size equ 32
endif
live_parameter db live_parameter_size dup (0)
live_original db live_parameter_size dup (0)
live_saved db 0
live_okmsg db 'DOS parameter set/get/restore passed',13,10,'$'
LP_CHECK macro condition
        local okay
        condition okay
        jmp live_parameter_failed
okay:
endm
live_parameters proc near
        mov byte ptr [live_saved],0
        mov byte ptr [live_parameter],5
        mov cl,60h
        call live_parameter_ioctl
        LP_CHECK jnc
        push cs
        pop es
        mov si,offset live_parameter
        mov di,offset live_original
        mov cx,live_parameter_size
        rep movsb
        mov byte ptr [live_saved],1
        mov word ptr [live_parameter+7+13],63
        mov word ptr [live_parameter+7+15],256
        mov ax,word ptr [live_parameter+7+8]
        xor dx,dx
        or ax,ax
        jnz live_parameter_total
        mov ax,word ptr [live_parameter+7+21]
        mov dx,word ptr [live_parameter+7+23]
live_parameter_total:
        add ax,word ptr [live_parameter+7+17]
        adc dx,word ptr [live_parameter+7+19]
        LP_CHECK jnc
        mov cx,16128
        cmp dx,cx
        LP_CHECK jb
        div cx
        or dx,dx
        jz live_parameter_cylinders
        inc ax
        LP_CHECK jnz
live_parameter_cylinders:
        mov word ptr [live_parameter+4],ax
        mov cl,40h
        call live_parameter_ioctl
        LP_CHECK jnc
        mov cl,60h
        call live_parameter_ioctl
        LP_CHECK jnc
        cmp word ptr [live_parameter+7+13],63
        LP_CHECK je
        cmp word ptr [live_parameter+7+15],256
        LP_CHECK je
        call live_parameter_restore
        LP_CHECK jnc
        mov cl,60h
        call live_parameter_ioctl
        LP_CHECK jnc
        push cs
        pop es
        mov si,offset live_parameter
        mov di,offset live_original
        mov cx,live_parameter_size
        repe cmpsb
        LP_CHECK je
        mov byte ptr [live_saved],0
        mov dx,offset live_okmsg
        mov ah,09h
        int 21h
        clc
        ret
live_parameter_failed:
        cmp byte ptr [live_saved],0
        je live_parameter_error
        call live_parameter_restore
live_parameter_error:
        stc
        ret
live_parameters endp
live_parameter_restore proc near
        push cs
        pop es
        mov si,offset live_original
        mov di,offset live_parameter
        mov cx,live_parameter_size
        rep movsb
        mov cl,40h
live_parameter_restore endp
live_parameter_ioctl proc near
        mov ax,440Dh
        mov ch,category / 256
        xor bx,bx
        mov bl,byte ptr [drive]
        mov dx,offset live_parameter
        int 21h
        ret
live_parameter_ioctl endp
