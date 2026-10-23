; Real block handlers, memory-only media. Faults must never become success.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h
        jmp start
ifdef TEST_FDD
FDD_DRIVER equ 1
endif
        include common/aspi/dos_aspi.inc
        include common/dos/devreq.inc
        include common/dos/blkdrv.inc
msg_banner db '$'
msg_no_device db '$'
CHECK_EQ macro
        local ok
        je ok
        jmp failed
ok:
endm
BR macro inverse, target
        local skip
        inverse skip
        jmp target
skip:
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
mbr db 446 dup (0)
    db 0,0,0,0,0Ch,0,0,0
    dd 32,196608
    db 48 dup (0)
    dw 0AA55h
primary db 512 dup (0)
backup db 512 dup (0)
expected db 512 dup (0)
packet db 32 dup (0)
guard1 db 0A5h
param dw 0
      dd 0AABBCCDDh
      db 'NEW LABEL  ','FATTEST '
guard2 db 0A5h
input_snapshot db 25 dup (0)
strategy_ptr dw offset strategy,0
interrupt_ptr dw offset interrupt,0
kind db 0                            ; FAT12 superfloppy / FAT16 MBR / FAT32 MBR
mode db 0                            ; success / protect / verify / bad backup / primary fail / extent / read error
writes dw 0
reads dw 0
bad db 0
metadata dw 27h
okmsg db 'Media-ID write, backup, extent and failure tests passed',13,10,'$'
badmsg db 'Media-ID write FAILED kind/mode $'
start:
        push cs
        pop ds
        push cs
        pop es
        mov word ptr [strategy_ptr+2],cs
        mov word ptr [interrupt_ptr+2],cs
        mov word ptr [aspi_entry],offset fake_aspi
        mov word ptr [aspi_entry+2],cs
        mov byte ptr [unit_count],1
        mov byte ptr [fat32_enabled],1
        mov byte ptr [packet+RH_LENGTH],32
        mov byte ptr [packet+RH_IOCTL_CATEGORY],8
        mov byte ptr [packet+RH_IOCTL_MINOR],46h
        mov byte ptr [packet+RH_COMMAND],CMD_GEN_IOCTL
        mov ax,cs
        inc ax
        mov word ptr [packet+RH_IOCTL_PARAM+2],ax
        mov word ptr [packet+RH_IOCTL_PARAM],offset param-16
        mov si,offset param
        mov di,offset input_snapshot
        mov cx,25
        rep movsb
next_case:
        mov word ptr [writes],0
        mov word ptr [reads],0
        mov word ptr [mbr+454],32
        mov word ptr [mbr+456],0
        mov byte ptr [unit_table+U_FLAGS],UF_REMOVABLE or UF_NOACCESS
        mov si,offset template
        mov di,offset primary
        mov cx,512
        rep movsb
        mov word ptr [metadata],43h
        mov byte ptr [mbr+450],0Ch
        mov word ptr [mbr+458],196608 mod 65536
        mov word ptr [mbr+460],196608 / 65536
        cmp byte ptr [kind],2
        BR jne, layout_ready
        mov word ptr [metadata],27h
        mov byte ptr [mbr+450],6
        mov word ptr [mbr+458],19200
        mov word ptr [mbr+460],0
        mov byte ptr [primary+13],2
        mov word ptr [primary+14],1
        mov word ptr [primary+17],512
        mov word ptr [primary+19],19200
        mov word ptr [primary+22],40
        mov word ptr [primary+32],0
        mov word ptr [primary+34],0
        cmp byte ptr [kind],0
        jne fat16_ready
        mov word ptr [primary+17],112
        mov word ptr [primary+19],1440
        mov word ptr [primary+22],3
        mov word ptr [primary+24],9
        mov word ptr [primary+26],2
fat16_ready:
        mov byte ptr [primary+38],29h
        mov si,offset param+2
        mov di,offset primary+39
        mov cx,23
        rep movsb
        mov word ptr [primary+39],3344h
        mov word ptr [primary+41],1122h
        mov byte ptr [primary+43],'O'
layout_ready:
        cmp byte ptr [mode],7
        jne snapshot_ready
        mov word ptr [primary+50],0
snapshot_ready:
        mov si,offset primary
        mov di,offset expected
        mov cx,512
        rep movsb
        mov si,offset param+2
        mov di,offset expected
        add di,word ptr [metadata]
        mov cx,23
        rep movsb
        mov si,offset primary
        mov di,offset backup
        mov cx,512
        rep movsb
        ; Backup has its own unrelated boot code, which must be preserved.
        mov byte ptr [backup+400],0A7h
        cmp byte ptr [mode],3
        jne not_bad_backup
        cmp byte ptr [kind],2
        jne corrupt_primary
        inc word ptr [backup+24]
        jmp short not_bad_backup
corrupt_primary:
        mov bx,word ptr [metadata]
        mov byte ptr [primary+bx-1],0
not_bad_backup:
        cmp byte ptr [mode],8
        jb check_extent_size
        cmp byte ptr [kind],0
        je corrupt_size
        cmp byte ptr [mode],8
        je corrupt_zero_extent
        cmp byte ptr [mode],10
        je corrupt_zero_start
        mov word ptr [mbr+454],0FFF0h
        mov word ptr [mbr+456],0FFFFh
        jmp short issue_set
corrupt_zero_start:
        mov word ptr [mbr+454],0
        mov word ptr [mbr+456],0
        jmp short issue_set
corrupt_zero_extent:
        mov word ptr [mbr+458],0
        mov word ptr [mbr+460],0
        jmp short issue_set
check_extent_size:
        cmp byte ptr [mode],5
        jne issue_set
        cmp byte ptr [kind],0
        je corrupt_size
        mov word ptr [mbr+458],1
        mov word ptr [mbr+460],0
        jmp short issue_set
corrupt_size:
        mov word ptr [primary+19],0
        mov word ptr [primary+32],0
        mov word ptr [primary+34],0
issue_set:
        call submit
        cmp byte ptr [mode],0
        BR jne, expect_success
        cmp byte ptr [mode],7
        BR jne, expect_success
        test word ptr [packet+RH_STATUS],ST_ERROR
        BR jnz, failed
        test byte ptr [unit_table+U_FLAGS],UF_MEDIA
        CHECK_EQ
        cmp byte ptr [mode],3
        je no_writes
        cmp byte ptr [mode],5
        je no_writes
        cmp byte ptr [mode],6
        je no_writes
        cmp byte ptr [mode],8
        jae no_writes
        mov ax,1
        cmp byte ptr [mode],4
        jne check_failed_writes
        cmp byte ptr [kind],2
        jne check_failed_writes
        inc ax
check_failed_writes:
        cmp word ptr [writes],ax
        CHECK_EQ
        cmp byte ptr [mode],1
        BR je, next_mode
        cmp word ptr [packet+RH_STATUS],ST_DONE or ST_ERROR or ERR_WRITE_PROTECT
        CHECK_EQ
        mov si,offset primary
        mov di,offset media_id_primary
        mov cx,512
        repe cmpsb
        CHECK_EQ
        jmp short next_mode
no_writes:
        cmp word ptr [writes],0
        CHECK_EQ
        jmp short next_mode
expect_success:
        cmp word ptr [packet+RH_STATUS],ST_DONE
        CHECK_EQ
        mov si,offset primary
        mov di,offset expected
        mov cx,512
        repe cmpsb
        CHECK_EQ
        mov ax,1
        cmp byte ptr [kind],2
        jne expect_writes
        cmp byte ptr [mode],7
        je expect_writes
        inc ax
        mov si,offset backup+43h
        mov di,offset param+2
        mov cx,23
        repe cmpsb
        CHECK_EQ
        cmp byte ptr [backup+400],0A7h
        CHECK_EQ
        mov byte ptr [expected+400],0A7h
        mov si,offset backup
        mov di,offset expected
        mov cx,512
        repe cmpsb
        CHECK_EQ
expect_writes:
        cmp word ptr [writes],ax
        CHECK_EQ
next_mode:
        mov si,offset param
        mov di,offset input_snapshot
        mov cx,25
        repe cmpsb
        CHECK_EQ
        cmp byte ptr [guard1],0A5h
        CHECK_EQ
        cmp byte ptr [guard2],0A5h
        CHECK_EQ
        cmp word ptr [param],0
        CHECK_EQ
        cmp byte ptr [bad],0
        CHECK_EQ
        inc byte ptr [mode]
        cmp byte ptr [mode],11
        BR jae, next_case
        mov byte ptr [mode],0
        inc byte ptr [kind]
        cmp byte ptr [kind],3
        BR jae, next_case
        mov dx,offset okmsg
        mov ah,09h
        int 21h
        mov ax,4C00h
        int 21h
failed:
        mov dx,offset badmsg
        mov ah,09h
        int 21h
        mov al,byte ptr [kind]
        call print_digit
        mov al,byte ptr [mode]
        call print_digit
        mov ax,4C01h
        int 21h
submit proc near
        push cs
        pop es
        mov bx,offset packet
        call dword ptr [strategy_ptr]
        call dword ptr [interrupt_ptr]
        ret
submit endp
fake_aspi proc far
        cmp word ptr [srb+SRB_CDB+2],0
        BR je, fake_bad
        cmp byte ptr [srb+SRB_CDB+4],0
        BR je, fake_bad
        mov byte ptr [srb+SRB_Status],SS_COMP
        cmp byte ptr [srb+SRB_CDB],28h
        je fake_read
        cmp byte ptr [srb+SRB_CDB],2Ah
        BR je, fake_bad
        inc word ptr [writes]
        cmp byte ptr [mode],1
        BR jne, fake_protected
        cmp byte ptr [mode],4
        jne fake_locate
        cmp byte ptr [srb+SRB_CDB+5],38
        BR je, fake_error
        jmp short fake_locate
fake_read:
        inc word ptr [reads]
        cmp byte ptr [mode],6
        je fake_error
fake_locate:
        mov si,offset primary
        mov al,byte ptr [srb+SRB_CDB+5]
        cmp al,0
        jne fake_partition
        cmp byte ptr [kind],0
        je fake_copy
        mov si,offset mbr
        cmp byte ptr [srb+SRB_CDB],28h
        BR je, fake_bad
        jmp short fake_copy
fake_partition:
        cmp al,32
        je fake_copy
        cmp al,38
        BR je, fake_bad
        mov si,offset backup
fake_copy:
        cmp word ptr [srb+SRB_BufLen],512
        BR je, fake_bad
        cmp byte ptr [srb+SRB_CDB+8],1
        BR je, fake_bad
        mov cx,512
        cmp byte ptr [srb+SRB_CDB],28h
        jne fake_store
        les di,dword ptr [srb+SRB_BufPointer]
        rep movsb
        cmp byte ptr [mode],2
        jne fake_done
        cmp word ptr [writes],0
        je fake_done
        xor byte ptr es:[di-112],1
        jmp short fake_done
fake_store:
        mov di,si
        lds si,dword ptr [srb+SRB_BufPointer]
        push cs
        pop es
        rep movsb
        jmp short fake_done
fake_bad:
        mov byte ptr [bad],1
fake_error:
        mov al,2
        jmp short fake_sense
fake_protected:
        mov al,7
fake_sense:
        mov byte ptr [srb+SRB_Status],SS_ERR
        mov byte ptr [srb+SRB_TargStat],2
        mov byte ptr [srb+SRB_CDB+10],70h
        mov byte ptr [srb+SRB_CDB+10+7],6
        mov byte ptr [srb+SRB_CDB+12],al
fake_done:
        ret
fake_aspi endp
        end start
