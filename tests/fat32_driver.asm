; Extended BPB and malformed FAT32 checks through actual resident handlers.
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
CHECK_EQ macro
        local good
        je good
        jmp failed
good:
endm
VALID macro
        local good
        call check_boot_sector
        jnc good
        jmp failed
good:
endm
INVALID macro
        local good
        call check_boot_sector
        jc good
        jmp failed
good:
endm
SEND macro expected
        push cs
        pop es
        mov bx, offset packet
        call dword ptr [strategy_ptr]
        call dword ptr [interrupt_ptr]
        cmp word ptr [packet+RH_STATUS], expected
        CHECK_EQ
        cmp byte ptr [guard1], 0A5h
        CHECK_EQ
        cmp byte ptr [guard2], 0A5h
        CHECK_EQ
endm
template db 0EBh,58h,90h,'OPENASPI'
         dw 512
         db 1
         dw 32
         db 2
         dw 0,0
         db 0F8h
         dw 0,32,8
         dd 0,196608,1536
         dw 0,0
         dd 2
         dw 1,6
         db 12 dup (0)
         db 80h,0,29h
         dd 11223344h
         db 'NO NAME    ','FAT32   '
         db 420 dup (0)
         dw 0AA55h
packet db 32 dup (0)
guard1 db 0A5h
output db 60 dup (0A5h)
guard2 db 0A5h
strategy_ptr dw offset strategy,0
interrupt_ptr dw offset interrupt,0
ok db 'FAT32 BPB/IOCTL/validation tests passed',13,10,'$'
bad db 'FAT32 resident validation FAILED',13,10,'$'
start:
        push cs
        pop ds
        push cs
        pop es
        mov byte ptr [fat32_enabled], 1
        mov si, offset template
        mov di, offset sector_buf
        mov cx, 512
        rep movsb
        VALID
        mov byte ptr [sector_buf+13], 3
        INVALID
        mov byte ptr [sector_buf+13], 1
        mov word ptr [sector_buf+36], 1
        INVALID
        mov word ptr [sector_buf+36], 1536
        mov word ptr [sector_buf+44], 1
        INVALID
        mov word ptr [sector_buf+44], 2
        mov word ptr [sector_buf+46], 4
        INVALID
        mov word ptr [sector_buf+46], 0
        mov word ptr [sector_buf+48], 32
        INVALID
        mov word ptr [sector_buf+48], 1
        mov word ptr [sector_buf+40], 82h
        INVALID
        mov word ptr [sector_buf+40], 0
        mov word ptr [sector_buf+42], 1
        INVALID
        mov word ptr [sector_buf+42], 0
        mov byte ptr [fat32_enabled], 0
        INVALID
        mov byte ptr [fat32_enabled], 1
        VALID
        mov word ptr [strategy_ptr+2], cs
        mov word ptr [interrupt_ptr+2], cs
        mov word ptr [aspi_entry], offset fake_aspi
        mov word ptr [aspi_entry+2], cs
        mov byte ptr [unit_count], 1
        mov byte ptr [unit_table+U_FLAGS], UF_REMOVABLE
        mov byte ptr [packet+RH_LENGTH], 32
        mov byte ptr [packet+RH_COMMAND], CMD_GEN_IOCTL
        mov byte ptr [packet+RH_IOCTL_CATEGORY], 48h
        mov byte ptr [packet+RH_IOCTL_MINOR], 60h
        mov ax, cs
        inc ax
        mov word ptr [packet+RH_IOCTL_PARAM+2], ax
        mov word ptr [packet+RH_IOCTL_PARAM], offset output-16
        mov byte ptr [output], 1
        SEND ST_DONE
        cmp word ptr [output+7+25], 1536
        CHECK_EQ
        cmp word ptr [output+7+33], 2
        CHECK_EQ
        cmp byte ptr [output], 1
        CHECK_EQ
        ; Legacy descriptor cannot return a truncated FAT32 BPB as success.
        mov byte ptr [packet+RH_IOCTL_CATEGORY], 8
        SEND ST_DONE or ST_ERROR or ERR_NOT_READY
        mov byte ptr [packet+RH_IOCTL_CATEGORY], 48h
        mov byte ptr [packet+RH_IOCTL_MINOR], 66h
        mov word ptr [output], 0
        SEND ST_DONE
        cmp word ptr [output+2], 3344h
        CHECK_EQ
        cmp word ptr [output+4], 1122h
        CHECK_EQ
        cmp word ptr [output+17], 'AF'
        CHECK_EQ
        cmp word ptr [output+19], '3T'
        CHECK_EQ
        mov dx, offset ok
        mov ah, 9
        int 21h
        mov ax, 4C00h
        int 21h
failed:
        mov dx, offset bad
        mov ah, 9
        int 21h
        mov ax, 4C01h
        int 21h
fake_aspi proc far
        push cs
        pop ds
        mov si, offset template
        les di, dword ptr cs:[srb+SRB_BufPointer]
        mov cx, 512
        rep movsb
        mov byte ptr cs:[srb+SRB_Status], SS_COMP
        ret
fake_aspi endp
        end start
