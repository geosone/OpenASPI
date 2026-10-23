; Real block entry points with memory-only ASPI; no real device is accessed.
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
EQUAL macro
        local ok
        je ok
        jmp failed
ok:
endm
SEND macro status, expected_calls
        mov word ptr [calls],0
        call submit
        cmp word ptr [packet+RH_STATUS],status
        EQUAL
        cmp word ptr [calls],expected_calls
        EQUAL
        cmp byte ptr [guard1],0A5h
        EQUAL
        cmp byte ptr [guard2],0A5h
        EQUAL
        inc word ptr [step]
endm
packet db 32 dup (0)
guard1 db 0A5h
param db 0,0A5h
guard2 db 0A5h
buffer db 512 dup (0)
strategy_ptr dw offset strategy,0
interrupt_ptr dw offset interrupt,0
calls dw 0
step dw 0
fault db 0
okmsg db 'Block access policy/logical mapping tests passed',13,10,'$'
badmsg db 'Block access policy FAILED step $'
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
        mov byte ptr [unit_table+UNIT_SIZE+U_FLAGS],UF_MEDIA
        mov word ptr [unit_table+U_BPB+BPB_TOTAL16],1440
        mov word ptr [unit_table+UNIT_SIZE+U_BPB+BPB_TOTAL16],1440
        mov byte ptr [packet+RH_LENGTH],32
        call control_packet
        mov byte ptr [packet+RH_COMMAND],CMD_IOCTL_QUERY
        SEND ST_DONE,0
        mov byte ptr [packet+RH_IOCTL_MINOR],47h
        SEND ST_DONE,0
        call control_packet
        SEND ST_DONE,0
        cmp byte ptr [param+1],1
        EQUAL
        mov byte ptr [packet+RH_IOCTL_MINOR],47h
        mov byte ptr [param+1],0
        SEND ST_DONE,0
        mov byte ptr [packet+RH_IOCTL_MINOR],67h
        SEND ST_DONE,0
        cmp byte ptr [param+1],0
        EQUAL
        ; Disabled normal read/write/write-with-verify never reaches ASPI.
        call data_packet
        mov byte ptr [packet+RH_COMMAND],CMD_READ
        SEND ST_DONE or ST_ERROR or ERR_GENERAL,0
        cmp word ptr [packet+RH_COUNT],0
        EQUAL
        mov word ptr [packet+RH_COUNT],1
        mov byte ptr [packet+RH_COMMAND],CMD_WRITE
        SEND ST_DONE or ST_ERROR or ERR_GENERAL,0
        mov word ptr [packet+RH_COUNT],1
        mov byte ptr [packet+RH_COMMAND],CMD_WRITE_VERIFY
        SEND ST_DONE or ST_ERROR or ERR_GENERAL,0
        ; Even an access-denied request must respect its declared length.
        mov byte ptr [packet+RH_LENGTH],5
        mov word ptr [packet+RH_COUNT],0A55Ah
        SEND ST_DONE or ST_ERROR or 5,0
        cmp word ptr [packet+RH_COUNT],0A55Ah
        EQUAL
        mov byte ptr [packet+RH_LENGTH],32
        ; Another unit remains accessible; mappings report no alternate.
        mov byte ptr [packet+RH_UNIT],1
        mov word ptr [packet+RH_COUNT],1
        mov byte ptr [packet+RH_COMMAND],CMD_READ
        SEND ST_DONE,1
        call control_packet
        SEND ST_DONE,0
        cmp byte ptr [param+1],1
        EQUAL
        mov byte ptr [packet+RH_COMMAND],CMD_GET_LOGICAL
        SEND ST_DONE,0
        cmp byte ptr [packet+RH_UNIT],0
        EQUAL
        mov byte ptr [packet+RH_UNIT],2
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_UNIT,0
        cmp byte ptr [packet+RH_UNIT],2
        EQUAL
        mov byte ptr [packet+RH_UNIT],0
        mov byte ptr [packet+RH_UNIT],1
        mov byte ptr [packet+RH_COMMAND],CMD_SET_LOGICAL
        SEND ST_DONE,0
        cmp byte ptr [packet+RH_UNIT],0
        EQUAL
        ; Policy queries work without media and do not manipulate locks.
        and byte ptr [unit_table+U_FLAGS],not UF_MEDIA
        call control_packet
        SEND ST_DONE,0
        cmp byte ptr [param+1],0
        EQUAL
        cmp byte ptr [unit_table+U_LOCKS],0
        EQUAL
        mov byte ptr [param],1
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        cmp byte ptr [param+1],0
        EQUAL
        mov byte ptr [param],0
        mov byte ptr [packet+RH_LENGTH],22
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        mov byte ptr [packet+RH_LENGTH],32
        mov word ptr [packet+RH_IOCTL_PARAM],0
        mov word ptr [packet+RH_IOCTL_PARAM+2],0
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        mov word ptr [packet+RH_IOCTL_PARAM],0FFFFh
        mov word ptr [packet+RH_IOCTL_PARAM+2],cs
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        call param_pointer
        mov byte ptr [packet+RH_IOCTL_MINOR],47h
        mov byte ptr [param],1
        mov byte ptr [param+1],1
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        test byte ptr [unit_table+U_FLAGS],UF_NOACCESS
        jne still_disabled
        jmp failed
still_disabled:
        mov byte ptr [param],0
        ; Nonzero SET normalizes to enabled; FAT32 categories are gated.
        mov byte ptr [fat32_enabled],1
        mov byte ptr [packet+RH_IOCTL_CATEGORY],48h
        mov byte ptr [param+1],0FEh
        SEND ST_DONE,0
        mov byte ptr [packet+RH_IOCTL_MINOR],67h
        SEND ST_DONE,0
        cmp byte ptr [param+1],1
        EQUAL
        mov byte ptr [fat32_enabled],0
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        ; Hardware write protection does not change the software flag.
        or byte ptr [unit_table+U_FLAGS],UF_MEDIA
        call data_packet
        mov byte ptr [packet+RH_COMMAND],CMD_READ
        SEND ST_DONE,1
        mov byte ptr [fault],7
        mov byte ptr [packet+RH_COMMAND],CMD_WRITE
        SEND ST_DONE or ST_ERROR or ERR_WRITE_PROTECT,1
        call control_packet
        SEND ST_DONE,0
        cmp byte ptr [param+1],1
        EQUAL
        ; EDR-DOS query packets must advertise both operations consistently.
        mov byte ptr [packet+RH_LENGTH],22
        mov byte ptr [packet+RH_COMMAND],CMD_IOCTL_QUERY
        mov byte ptr [packet+RH_MEDIA],0
        mov word ptr [packet+RH_COUNT],0847h
        SEND ST_DONE,0
        cmp word ptr [packet+RH_COUNT],0
        EQUAL
        mov word ptr [packet+RH_COUNT],0867h
        SEND ST_DONE,0
        mov dx,offset okmsg
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
submit proc near
        push cs
        pop es
        mov bx,offset packet
        call dword ptr [strategy_ptr]
        call dword ptr [interrupt_ptr]
        ret
submit endp
param_pointer proc near
        mov ax,cs
        inc ax
        mov word ptr [packet+RH_IOCTL_PARAM+2],ax
        mov word ptr [packet+RH_IOCTL_PARAM],offset param-16
        ret
param_pointer endp
control_packet proc near
        mov byte ptr [packet+RH_COMMAND],CMD_GEN_IOCTL
        mov byte ptr [packet+RH_IOCTL_CATEGORY],8
        mov byte ptr [packet+RH_IOCTL_MINOR],67h
        call param_pointer
        ret
control_packet endp
data_packet proc near
        mov word ptr [packet+RH_START],0
        mov word ptr [packet+RH_COUNT],1
        mov word ptr [packet+RH_BUFFER],offset buffer
        mov word ptr [packet+RH_BUFFER+2],cs
        ret
data_packet endp
fake_aspi proc far
        inc word ptr [calls]
        mov byte ptr [srb+SRB_Status],SS_COMP
        cmp byte ptr [fault],0
        je fake_done
        mov byte ptr [srb+SRB_Status],SS_ERR
        mov byte ptr [srb+SRB_TargStat],2
        mov byte ptr [srb+SRB_CDB+10],70h
        mov byte ptr [srb+SRB_CDB+10+7],6
        mov byte ptr [srb+SRB_CDB+12],7
fake_done:
        ret
fake_aspi endp
        end start
