; Real ASPIFDD resident raw API: ownership, bounds and cleanup failures.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h
        jmp start
FDD_DRIVER equ 1
        include common/aspi/dos_aspi.inc
        include common/dos/devreq.inc
        include common/dos/blkdrv.inc
msg_banner db '$'
msg_no_device db '$'
CHECK_EQUAL macro
        local ok
        je ok
        jmp failed
ok:
endm
SEND macro status, count
        mov word ptr [calls], 0
        call submit
        cmp word ptr [packet+RH_STATUS], status
        CHECK_EQUAL
        cmp word ptr [calls], count
        CHECK_EQUAL
        cmp byte ptr [guard1], 0A5h
        CHECK_EQUAL
        cmp byte ptr [guard2], 0A5h
        CHECK_EQUAL
        inc word ptr [step]
endm
packet db 32 dup (0)
guard1 db 0A5h
param db 'RAW1'
      dw 32,0
      dd 0
      dw 1,0
      dd 0,0,0,0
guard2 db 0A5h
buf db 512 dup (0)
capacity db 0,0,5,9Fh,0,0,2,0         ; last=1439, sector=512
strategy_ptr dw offset strategy,0
interrupt_ptr dw offset interrupt,0
calls dw 0
step dw 0
token dw 0
fault db 0
okmsg db 'Raw media session/bounds/error tests passed',13,10,'$'
badmsg db 'Raw media FAILED step $'
start:
        push cs
        pop ds
        push cs
        pop es
        mov word ptr [strategy_ptr+2], cs
        mov word ptr [interrupt_ptr+2], cs
        mov word ptr [aspi_entry], offset fake_aspi
        mov word ptr [aspi_entry+2], cs
        mov byte ptr [unit_count], 1
        mov byte ptr [unit_table+U_FLAGS], UF_REMOVABLE
        mov byte ptr [packet+RH_LENGTH], 32
        mov byte ptr [packet+RH_COMMAND], CMD_GEN_IOCTL
        mov byte ptr [packet+RH_IOCTL_CATEGORY], 80h
        mov word ptr [packet+RH_IOCTL_PARAM], offset param
        mov word ptr [packet+RH_IOCTL_PARAM+2], cs
        mov word ptr [param+16], offset buf
        mov word ptr [param+18], cs
        SEND ST_DONE,2
        cmp word ptr [param+20], 1440
        CHECK_EQUAL
        cmp word ptr [param+28], 0
        CHECK_EQUAL
        mov byte ptr [packet+RH_IOCTL_MINOR], 1
        SEND ST_DONE,3
        mov ax, word ptr [param+6]
        or ax, ax
        jnz have_token
        jmp failed
have_token:
        mov word ptr [token], ax
        ; A live session blocks all normal DOS data/control calls.
        mov byte ptr [packet+RH_COMMAND], CMD_WRITE
        SEND ST_DONE or ST_ERROR or ERR_NOT_READY,0
        mov byte ptr [packet+RH_COMMAND], CMD_GEN_IOCTL
        mov byte ptr [packet+RH_IOCTL_MINOR], 2
        mov word ptr [param+6], 0
        SEND ST_DONE or ST_ERROR or ERR_NOT_READY,0
        mov ax, word ptr [token]
        mov word ptr [param+6], ax
        mov word ptr [param+8], 1439
        SEND ST_DONE,1
        mov word ptr [param+8], 1440
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        mov word ptr [param+8], 0FFFFh
        mov word ptr [param+10], 0FFFFh
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        mov word ptr [param+8], 0
        mov word ptr [param+10], 0
        mov word ptr [param+12], 0
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        mov word ptr [param+12], 33
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        mov word ptr [param+12], 1
        mov word ptr [param+16], 0FFFFh
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        mov word ptr [param+16], 0
        mov word ptr [param+18], 0FFFFh
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        mov word ptr [param+18], 0
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        mov word ptr [param+16], offset buf
        mov word ptr [param+18], cs
        mov byte ptr [packet+RH_IOCTL_MINOR], 3
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        mov byte ptr [packet+RH_IOCTL_MINOR], 4
        SEND ST_DONE,1
        cmp byte ptr [unit_table+U_LOCKS], 0
        CHECK_EQUAL
        test byte ptr [unit_table+U_FLAGS], UF_RAW_ACTIVE
        CHECK_EQUAL
        mov byte ptr [packet+RH_IOCTL_MINOR], 2
        SEND ST_DONE or ST_ERROR or ERR_NOT_READY,0
        mov word ptr [param+14], 1
        mov byte ptr [packet+RH_IOCTL_MINOR], 1
        SEND ST_DONE,3
        mov byte ptr [packet+RH_IOCTL_MINOR], 3
        mov byte ptr [fault], 7
        SEND ST_DONE or ST_ERROR or ERR_WRITE_PROTECT,1
        mov byte ptr [fault], 0
        SEND ST_DONE,1
        mov byte ptr [fault], 2
        mov byte ptr [packet+RH_IOCTL_MINOR], 4
        SEND ST_DONE or ST_ERROR or ERR_NOT_READY,1
        ; Failed ALLOW must release software ownership, retain the real lock.
        test byte ptr [unit_table+U_FLAGS], UF_RAW_ACTIVE
        CHECK_EQUAL
        cmp byte ptr [unit_table+U_LOCKS], 1
        CHECK_EQUAL
        mov byte ptr [packet+RH_IOCTL_MINOR], 1
        SEND ST_DONE or ST_ERROR or ERR_NOT_READY,0
        mov byte ptr [fault], 0
        mov byte ptr [packet+RH_IOCTL_CATEGORY], 8
        mov byte ptr [packet+RH_IOCTL_MINOR], 48h
        mov byte ptr [param], 1
        SEND ST_DONE,1
        cmp byte ptr [unit_table+U_LOCKS], 0
        CHECK_EQUAL
        mov byte ptr [packet+RH_IOCTL_CATEGORY], 80h
        mov byte ptr [packet+RH_IOCTL_MINOR], 0
        mov byte ptr [param], 'R'
        mov byte ptr [unit_table+U_FLAGS], 0
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        mov dx, offset okmsg
        mov ah, 9
        int 21h
        mov ax, 4C00h
        int 21h
failed:
        mov dx, offset badmsg
        mov ah, 9
        int 21h
        mov ax, word ptr [step]
        aam
        add ax, 3030h
        push ax
        mov dl, ah
        mov ah, 2
        int 21h
        pop dx
        mov ah, 2
        int 21h
        mov ax, 4C01h
        int 21h
submit proc near
        push cs
        pop es
        mov bx, offset packet
        call dword ptr [strategy_ptr]
        call dword ptr [interrupt_ptr]
        ret
submit endp
fake_aspi proc far
        inc word ptr cs:[calls]
        mov al, byte ptr cs:[fault]
        or al, al
        jnz fake_fail
        cmp byte ptr cs:[srb+SRB_CDB], 25h
        je fake_capacity
        cmp byte ptr cs:[srb+SRB_CDB], 28h
        jne fake_success
        les di, dword ptr cs:[srb+SRB_BufPointer]
        mov cx, 512
        xor al, al
        rep stosb
        jmp short fake_success
fake_capacity:
        push cs
        pop ds
        mov si, offset capacity
        les di, dword ptr cs:[srb+SRB_BufPointer]
        mov cx, 8
        rep movsb
fake_success:
        mov byte ptr cs:[srb+SRB_Status], SS_COMP
        ret
fake_fail:
        mov byte ptr cs:[srb+SRB_Status], SS_ERR
        mov byte ptr cs:[srb+SRB_TargStat], 2
        xor bx, bx
        mov bl, byte ptr cs:[srb+SRB_CDBLen]
        mov byte ptr cs:[srb+SRB_CDB+bx+2], al
        ret
fake_aspi endp
        end start
