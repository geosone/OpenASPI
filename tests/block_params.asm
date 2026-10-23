; Exercise actual SET/GET parameters and media-change paths; memory-only ASPI.
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
EQCHECK macro
        local okay
        je okay
        jmp failed
okay:
endm
SEND macro status, count
        mov word ptr [calls],0
        call submit
        cmp word ptr [packet+RH_STATUS],status
        EQCHECK
        cmp word ptr [calls],count
        EQCHECK
        call check_guards
        inc word ptr [step]
endm
template db 0EBh,3Ch,90h,'OPENASPI'
         dw 512
         db 1
         dw 1
         db 2
         dw 224,2880
         db 0F0h
         dw 9,18,2
         dd 0,0
         db 474 dup (0)
         dw 0AA55h
fat32_template db 0EBh,58h,90h,'OPENASPI'
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
param db 60 dup (0)
guard2 db 0A5h
saved db 60 dup (0)
result db 60 dup (0)
strategy_ptr dw offset strategy,0
interrupt_ptr dw offset interrupt,0
calls dw 0
step dw 0
fault db 0
bad db 0
physical dd 2880
boot_source dw offset template
partitioned db 0
sector_size dw 2
mbr db 446 dup (0)
    db 0,0,0,0,1,0,0,0
    dd 32,1440
    db 48 dup (0)
    dw 0AA55h
invalids dw 0,0706h, 7+BPB_BYTES,1024, 7+BPB_SPC,3
         dw 7+BPB_RESERVED,0, 7+BPB_FATS,3, 7+BPB_ROOT,0
         dw 7+BPB_FATSIZE,1, 7+BPB_HEADS,0, 7+BPB_SPT,64
         dw 4,0, 2,2, 1,5, 6,1, 0FFFFh,0
invalid_ptr dw offset invalids
ok db 'Block SET parameters, capacity, override and media-change tests passed',13,10,'$'
badmsg db 'Block parameters FAILED step $'
start:
        push cs
        pop ds
        push cs
        pop es
        mov word ptr [strategy_ptr+2],cs
        mov word ptr [interrupt_ptr+2],cs
        mov word ptr [aspi_entry],offset fake_aspi
        mov word ptr [aspi_entry+2],cs
        mov byte ptr [unit_count],2
        mov byte ptr [unit_table+U_FLAGS],UF_MEDIA or UF_REMOVABLE
        mov si,offset template+11
        mov di,offset unit_table+U_BPB
        mov cx,BPB_SIZE
        rep movsb
        mov si,offset template+11
        mov di,offset unit_table+U_DEFAULT_BPB
        mov cx,BPB_SIZE
        rep movsb
        mov word ptr [unit_table+UNIT_SIZE+U_DEFAULT_BPB+BPB_SPT],0A5A5h
        mov byte ptr [packet+RH_LENGTH],32
        mov byte ptr [packet+RH_COMMAND],CMD_GEN_IOCTL
        mov byte ptr [packet+RH_IOCTL_CATEGORY],8
        mov byte ptr [packet+RH_IOCTL_MINOR],40h
        call param_pointer
        mov byte ptr [param],4
        mov byte ptr [param+1],7
        mov word ptr [param+4],160
        mov si,offset template+11
        mov di,offset param+7
        mov cx,BPB_SIZE
        rep movsb
        mov word ptr [param+7+BPB_SPT],9
        SEND ST_DONE,2
        cmp word ptr [unit_table+U_DEFAULT_BPB+BPB_SPT],9
        EQCHECK
        cmp word ptr [unit_table+U_BPB+BPB_SPT],18
        EQCHECK
        cmp word ptr [unit_table+UNIT_SIZE+U_DEFAULT_BPB+BPB_SPT],0A5A5h
        EQCHECK
        mov byte ptr [param],5
        SEND ST_DONE,2
        cmp word ptr [unit_table+U_BPB+BPB_SPT],9
        EQCHECK
        mov si,offset param
        mov di,offset saved
        mov cx,60
        rep movsb
        ; Current GET and BUILD BPB must retain the override without rereading.
        mov byte ptr [packet+RH_IOCTL_MINOR],60h
        SEND ST_DONE,0
        cmp word ptr [param+7+BPB_SPT],9
        EQCHECK
        mov byte ptr [packet+RH_COMMAND],CMD_BUILD_BPB
        SEND ST_DONE,0
        cmp word ptr [unit_table+U_BPB+BPB_SPT],9
        EQCHECK
        ; Invalid input must neither reach ASPI nor commit any new state.
        mov byte ptr [packet+RH_COMMAND],CMD_GEN_IOCTL
        mov byte ptr [packet+RH_IOCTL_MINOR],40h
        call param_pointer
next_invalid:
        mov si,offset saved
        mov di,offset param
        mov cx,60
        rep movsb
        mov si,word ptr [invalid_ptr]
        lodsw
        cmp ax,0FFFFh
        je invalid_done
        mov bx,ax
        lodsw
        mov word ptr [param+bx],ax
        mov word ptr [invalid_ptr],si
        mov word ptr [calls],0
        call submit
        test word ptr [packet+RH_STATUS],ST_ERROR
        jnz invalid_rejected
        jmp failed
invalid_rejected:
        cmp word ptr [calls],0
        EQCHECK
        cmp word ptr [unit_table+U_BPB+BPB_SPT],9
        EQCHECK
        call check_guards
        jmp next_invalid
invalid_done:
        mov si,offset saved
        mov di,offset param
        mov cx,60
        rep movsb
        ; Device capacity is independent of the BPB's claim.
        mov word ptr [physical],2800
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA,2
        cmp word ptr [unit_table+U_BPB+BPB_SPT],9
        EQCHECK
        test byte ptr [unit_table+U_FLAGS],UF_BPB_OVERRIDE
        EQCHECK
        mov word ptr [physical],2880
        SEND ST_DONE,2
        ; UNIT ATTENTION must discard the override before BUILD BPB.
        mov byte ptr [fault],6
        mov byte ptr [packet+RH_COMMAND],CMD_MEDIA_CHECK
        SEND ST_DONE,1
        cmp byte ptr [packet+RH_MEDIA_RET],0FFh
        EQCHECK
        test byte ptr [unit_table+U_FLAGS],UF_BPB_OVERRIDE
        EQCHECK
        mov byte ptr [fault],0
        mov byte ptr [packet+RH_COMMAND],CMD_BUILD_BPB
        SEND ST_DONE,1
        cmp word ptr [unit_table+U_BPB+BPB_SPT],18
        EQCHECK
        ; Reject physical remapping even when capacity would permit it.
        mov byte ptr [packet+RH_COMMAND],CMD_GEN_IOCTL
        mov byte ptr [packet+RH_IOCTL_MINOR],40h
        call param_pointer
        mov word ptr [param+7+BPB_HIDDEN],1
        mov word ptr [param+4],161
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA,2
        cmp word ptr [unit_table+U_BPB+BPB_SPT],18
        EQCHECK
        mov word ptr [param+7+BPB_HIDDEN],0
        mov word ptr [param+4],160
        ; No new BPB may cross the selected partition into adjacent data.
        mov byte ptr [partitioned],1
        mov word ptr [physical],4096
        mov word ptr [template+19],1440
        mov word ptr [param+7+BPB_HIDDEN],32
        mov word ptr [param+4],162
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA,3
        cmp word ptr [unit_table+U_BPB+BPB_SPT],18
        EQCHECK
        ; Non-512-byte capacity responses are not accepted as logical media.
        mov word ptr [sector_size],4
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA,1
        mov word ptr [sector_size],2
        mov byte ptr [partitioned],0
        ; Extended FAT32 BPBs use the same checked path.
        mov byte ptr [fat32_enabled],1
        mov word ptr [boot_source],offset fat32_template
        mov word ptr [physical],0
        mov word ptr [physical+2],3
        mov byte ptr [packet+RH_COMMAND],CMD_GEN_IOCTL
        mov byte ptr [packet+RH_IOCTL_CATEGORY],48h
        mov byte ptr [packet+RH_IOCTL_MINOR],40h
        call param_pointer
        mov byte ptr [param],5
        mov byte ptr [param+1],7
        mov word ptr [param+2],0
        mov word ptr [param+4],1536
        mov byte ptr [param+6],0
        mov si,offset fat32_template+11
        mov di,offset param+7
        mov cx,BPB_STORE_SIZE
        rep movsb
        mov word ptr [param+7+BPB_SPT],16
        SEND ST_DONE,2
        mov byte ptr [packet+RH_IOCTL_MINOR],60h
        SEND ST_DONE,0
        cmp word ptr [param+7+BPB_SPT],16
        EQCHECK
        cmp word ptr [param+7+25],1536
        EQCHECK
        mov byte ptr [packet+RH_IOCTL_MINOR],40h
        mov word ptr [param+7+33],1      ; root cluster one is invalid
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA,0
        ; A fixed unit invalidated by transport failure must be recoverable.
        mov word ptr [param+7+33],2
        mov byte ptr [param+1],5
        mov word ptr [param+2],1
        mov byte ptr [unit_table+U_FLAGS],UF_MEDIA or UF_FAT32
        mov byte ptr [fault],6
        SEND ST_DONE or ST_ERROR or ERR_MEDIA_CHANGE,1
        mov byte ptr [fault],0
        mov byte ptr [packet+RH_COMMAND],CMD_MEDIA_CHECK
        SEND ST_DONE,0
        cmp byte ptr [packet+RH_MEDIA_RET],0
        EQCHECK
        mov byte ptr [packet+RH_COMMAND],CMD_BUILD_BPB
        SEND ST_DONE,1
        cmp word ptr [unit_table+U_BPB+BPB_SPT],32
        EQCHECK
        cmp byte ptr [bad],0
        EQCHECK
        mov dx,offset ok
        mov ah,09h
        int 21h
        mov ax,4C00h
        int 21h
failed:
        mov dx,offset badmsg
        mov ah,09h
        int 21h
        mov ax,word ptr [step]
        call print_digit
        mov ax,4C01h
        int 21h
param_pointer proc near
        mov ax,cs
        inc ax
        mov word ptr [packet+RH_IOCTL_PARAM+2],ax
        mov word ptr [packet+RH_IOCTL_PARAM],offset param-16
        ret
param_pointer endp
submit proc near
        push cs
        pop es
        mov bx,offset packet
        call dword ptr [strategy_ptr]
        call dword ptr [interrupt_ptr]
        ret
submit endp
check_guards proc near
        cmp byte ptr [guard1],0A5h
        EQCHECK
        cmp byte ptr [guard2],0A5h
        EQCHECK
        ret
check_guards endp
fake_aspi proc far
        inc word ptr [calls]
        mov byte ptr [srb+SRB_Status],SS_COMP
        cmp byte ptr [fault],0
        jne fake_error
        cmp byte ptr [srb+SRB_CDB],0
        jne fake_data_command
        jmp fake_done
fake_data_command:
        cmp byte ptr [srb+SRB_CDB],25h
        je fake_capacity
        cmp byte ptr [srb+SRB_CDB],28h
        jne fake_bad
        mov si,word ptr [boot_source]
        cmp byte ptr [partitioned],0
        je fake_volume
        cmp byte ptr [srb+SRB_CDB+5],0
        jne fake_volume
        mov si,offset mbr
fake_volume:
        les di,dword ptr [srb+SRB_BufPointer]
        mov cx,512
        rep movsb
        jmp short fake_done
fake_capacity:
        les di,dword ptr [srb+SRB_BufPointer]
        mov ax,word ptr [physical]
        mov dx,word ptr [physical+2]
        sub ax,1
        sbb dx,0
        xchg al,ah
        xchg dl,dh
        mov word ptr es:[di],dx
        mov word ptr es:[di+2],ax
        mov word ptr es:[di+4],0
        mov ax,word ptr [sector_size]
        mov word ptr es:[di+6],ax
        jmp short fake_done
fake_bad:
        mov byte ptr [bad],1
fake_error:
        mov byte ptr [srb+SRB_Status],SS_ERR
        mov byte ptr [srb+SRB_TargStat],2
        xor bx,bx
        mov bl,byte ptr [srb+SRB_CDBLen]
        mov al,byte ptr [fault]
        mov byte ptr [srb+SRB_CDB+bx],70h
        mov byte ptr [srb+SRB_CDB+bx+7],6
        mov byte ptr [srb+SRB_CDB+bx+2],al
fake_done:
        ret
fake_aspi endp
        end start
