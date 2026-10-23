; Real track handlers, numeric transfer pointers checked but never dereferenced
; by the memory-only ASPI mock. No real manager/device is accessed.
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
        local okay
        je okay
        jmp failed
okay:
endm
BR macro inverse, target
        local skip
        inverse skip
        jmp target
skip:
endm
RUN macro status, payload_count, capacity_count
        mov word ptr [payloads],0
        mov word ptr [capacities],0
        mov si,offset args
        mov di,offset snapshot
        mov cx,13
        rep movsb
        mov bx,offset packet
        call dword ptr [strategy_ptr]
        call dword ptr [interrupt_ptr]
        cmp word ptr [packet+RH_STATUS],status
        EQUAL
        cmp word ptr [payloads],payload_count
        EQUAL
        cmp word ptr [capacities],capacity_count
        EQUAL
        cmp byte ptr [bad],0
        EQUAL
        cmp byte ptr [guard1],0A5h
        EQUAL
        cmp byte ptr [guard2],0A5h
        EQUAL
        cmp byte ptr [packet+RH_IOCTL_MINOR],62h
        jne @F
        cmp byte ptr [expected_verify_result],0FFh
        je @F
        mov al,byte ptr [expected_verify_result]
        mov byte ptr [snapshot],al
@@:
        mov si,offset args
        mov di,offset snapshot
        mov cx,13
        repe cmpsb
        EQUAL
        inc word ptr [step]
endm
packet db 32 dup (0)
guard1 db 0A5h
args db 0
     dw 1,1927,0,66
     dw 0FFF0h,1000h
guard2 db 0A5h
snapshot db 13 dup (0)
strategy_ptr dw offset strategy,0
interrupt_ptr dw offset interrupt,0
step dw 0
payloads dw 0
capacities dw 0
bad db 0
capacity dd 1000000h
capacity_mode db 0
fail_chunk dw 0
sense_key db 3
opcode db 28h
expected_lba dd 65535
expected_left dw 66
expected_segment dw 1FFFh
expected_offset dw 0
expected_verify_result db 0FFh
ok db 'Block track CHS/buffer/chunk/verify/error tests passed',13,10,'$'
badmsg db 'Block track FAILED step $'
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
        mov byte ptr [unit_table+U_HA],2
        mov byte ptr [unit_table+U_TARGET],3
        mov byte ptr [unit_table+U_LUN],1
        mov word ptr [unit_table+U_START],4096 ; must NOT be added to CHS LBA
        mov word ptr [unit_table+U_BPB+BPB_BYTES],512
        mov word ptr [unit_table+U_BPB+BPB_SPT],17
        mov word ptr [unit_table+U_BPB+BPB_HEADS],2
        mov word ptr [unit_table+U_BPB+BPB_TOTAL16],1000
        mov byte ptr [packet+RH_LENGTH],32
        mov byte ptr [packet+RH_COMMAND],CMD_GEN_IOCTL
        mov byte ptr [packet+RH_IOCTL_CATEGORY],8
        call reset_case
        RUN ST_DONE,2,1
        call reset_case
        mov word ptr [args+7],130       ; contiguous data beyond 64 KiB
        mov word ptr [expected_left],130
        RUN ST_DONE,3,1
        call reset_case
        mov byte ptr [packet+RH_IOCTL_MINOR],41h
        mov byte ptr [opcode],2Ah
        RUN ST_DONE,2,1
        ; Keep a formatter's current BPB after successful track writes.
        test byte ptr [unit_table+U_FLAGS],UF_BPB_OVERRIDE
        jnz retained
        jmp failed
retained:
        call reset_case
        mov word ptr [fail_chunk],1
        RUN ST_DONE or ST_ERROR or ERR_READ,1,1
        test byte ptr [unit_table+U_FLAGS],UF_MEDIA or UF_BPB_OVERRIDE
        EQUAL
        call reset_case
        mov byte ptr [packet+RH_IOCTL_MINOR],41h
        mov byte ptr [opcode],2Ah
        mov word ptr [fail_chunk],2
        mov byte ptr [sense_key],7
        RUN ST_DONE or ST_ERROR or ERR_WRITE_PROTECT,2,1
        call reset_case
        mov word ptr [capacity],0
        mov word ptr [capacity+2],1
        RUN ST_DONE or ST_ERROR or ERR_NOT_FOUND,0,1
        mov word ptr [capacity+2],100h
        call reset_case
        mov word ptr [args+1],2
        RUN ST_DONE or ST_ERROR or ERR_NOT_FOUND,0,1
        call reset_case
        mov word ptr [unit_table+U_BPB+BPB_HEADS],256
        mov word ptr [unit_table+U_BPB+BPB_SPT],63
        mov word ptr [capacity],0FFFFh
        mov word ptr [capacity+2],0FFFFh
        mov word ptr [args+1],255
        mov word ptr [args+3],0FFFFh
        mov word ptr [args+5],62
        mov word ptr [args+7],1
        mov word ptr [expected_lba],0FFFFh
        mov word ptr [expected_lba+2],3EFFh
        mov word ptr [expected_left],1
        RUN ST_DONE,1,1
        mov word ptr [unit_table+U_BPB+BPB_HEADS],2
        mov word ptr [unit_table+U_BPB+BPB_SPT],17
        mov word ptr [capacity],0
        mov word ptr [capacity+2],100h
        call reset_case
        mov word ptr [args+5],17
        RUN ST_DONE or ST_ERROR or ERR_NOT_FOUND,0,1
        call reset_case
        mov word ptr [unit_table+U_BPB+BPB_HEADS],257
        RUN ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA,0,1
        mov word ptr [unit_table+U_BPB+BPB_HEADS],2
        call reset_case
        mov word ptr [unit_table+U_BPB+BPB_SPT],0
        RUN ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA,0,1
        mov word ptr [unit_table+U_BPB+BPB_SPT],17
        call reset_case
        mov byte ptr [args],4
        RUN ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0,0
        call reset_case
        mov word ptr [args+9],0
        mov word ptr [args+11],0
        RUN ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0,0
        call reset_case
        mov word ptr [args+9],0
        mov word ptr [args+11],0FFFFh
        RUN ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0,0
        call reset_case
        mov word ptr [args+7],16
        mov word ptr [args+9],0
        mov word ptr [args+11],0FE00h ; buffer ending exactly at 1 MiB
        mov word ptr [expected_segment],0FE00h
        mov word ptr [expected_left],16
        RUN ST_DONE,1,1
        call reset_case
        mov word ptr [args+7],0
        RUN ST_DONE,0,0
        call reset_case
        mov word ptr [packet+RH_IOCTL_PARAM],0FFF4h
        RUN ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0,0
        call reset_case
        mov byte ptr [packet+RH_IOCTL_CATEGORY],48h
        RUN ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0,0
        mov byte ptr [fat32_enabled],1
        RUN ST_DONE,2,1
        mov byte ptr [packet+RH_IOCTL_CATEGORY],8
        call reset_case
        mov byte ptr [capacity_mode],1
        RUN ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA,0,1
        call reset_case
        mov byte ptr [capacity_mode],2
        RUN ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA,0,1
        ; Multi-track VERIFY has no data buffer, even with stale junk there.
        call reset_case
        call verify_case
        RUN ST_DONE,2,1
        call reset_case
        call verify_case
        mov word ptr [args+5],15
        mov word ptr [expected_left],255
        RUN ST_DONE,4,1
        call reset_case
        call verify_case
        mov word ptr [unit_table+U_BPB+BPB_TOTAL16],100
        mov byte ptr [expected_verify_result],2
        RUN ST_DONE or ST_ERROR or ERR_NOT_FOUND,0,1
        mov word ptr [unit_table+U_BPB+BPB_TOTAL16],1000
        call reset_case
        call verify_case
        mov word ptr [unit_table+U_START],0FFF0h
        mov word ptr [unit_table+U_START+2],0FFFFh
        mov byte ptr [expected_verify_result],2
        RUN ST_DONE or ST_ERROR or ERR_NOT_FOUND,0,1
        mov word ptr [unit_table+U_START],4096
        mov word ptr [unit_table+U_START+2],0
        call reset_case
        call verify_case
        mov word ptr [fail_chunk],1
        mov byte ptr [sense_key],5
        mov byte ptr [args],0
        mov word ptr [expected_left],17
        mov byte ptr [expected_verify_result],1
        RUN ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,1,1
        call reset_case
        call verify_case
        mov byte ptr [args],0
        mov word ptr [expected_left],17
        mov word ptr [fail_chunk],1
        mov byte ptr [sense_key],2
        mov byte ptr [expected_verify_result],3
        RUN ST_DONE or ST_ERROR or ERR_NOT_READY,1,1
        call reset_case
        call verify_case
        mov byte ptr [args],0
        mov word ptr [args+5],0FFFFh ; ignored for single-track mode
        mov word ptr [expected_left],17
        RUN ST_DONE,1,1
        call reset_case
        call verify_case
        mov word ptr [args+5],16      ; 272 sectors exceeds 255-sector limit
        mov byte ptr [expected_verify_result],2
        RUN ST_DONE or ST_ERROR or ERR_NOT_FOUND,0,1
        call reset_case
        call verify_case
        mov word ptr [args+5],0
        RUN ST_DONE,0,0
        call reset_case
        call verify_case
        mov byte ptr [args],3
        mov byte ptr [expected_verify_result],0FFh
        RUN ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0,0
        call reset_case
        call verify_case
        mov word ptr [packet+RH_IOCTL_PARAM],0FFFCh
        mov byte ptr [expected_verify_result],0FFh
        RUN ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0,0
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
reset_case proc near
        mov byte ptr [unit_table+U_FLAGS],UF_MEDIA or UF_BPB_OVERRIDE or UF_NOACCESS
        mov byte ptr [packet+RH_IOCTL_MINOR],61h
        mov word ptr [packet+RH_IOCTL_PARAM],offset args
        mov word ptr [packet+RH_IOCTL_PARAM+2],cs
        mov byte ptr [args],0
        mov word ptr [args+1],1
        mov word ptr [args+3],1927
        mov word ptr [args+5],0
        mov word ptr [args+7],66
        mov word ptr [args+9],0FFF0h
        mov word ptr [args+11],1000h
        mov byte ptr [opcode],28h
        mov word ptr [expected_lba],0FFFFh
        mov word ptr [expected_lba+2],0
        mov word ptr [expected_left],66
        mov word ptr [expected_segment],1FFFh
        mov word ptr [expected_offset],0
        mov word ptr [fail_chunk],0
        mov byte ptr [sense_key],3
        mov byte ptr [capacity_mode],0
        mov byte ptr [expected_verify_result],0FFh
        ret
reset_case endp
verify_case proc near
        mov byte ptr [packet+RH_IOCTL_MINOR],62h
        mov byte ptr [opcode],2Fh
        mov byte ptr [args],1
        mov word ptr [args+1],1
        mov word ptr [args+3],1
        mov word ptr [args+5],5
        mov word ptr [expected_lba],4147 ; volume-relative 51 plus U_START 4096
        mov word ptr [expected_left],85
        mov byte ptr [expected_verify_result],0
        ret
verify_case endp
fake_aspi proc far
        cmp byte ptr [srb+SRB_HaId],2
        BR je, fake_bad
        cmp byte ptr [srb+SRB_Target],3
        BR je, fake_bad
        cmp byte ptr [srb+SRB_Lun],1
        BR je, fake_bad
        mov byte ptr [srb+SRB_Status],SS_COMP
        cmp byte ptr [srb+SRB_CDB],25h
        BR jne, fake_capacity
        inc word ptr [payloads]
        mov al,byte ptr [opcode]
        cmp byte ptr [srb+SRB_CDB],al
        BR je, fake_bad
        mov ax,word ptr [srb+SRB_CDB+4]
        mov dx,word ptr [srb+SRB_CDB+2]
        xchg al,ah
        xchg dl,dh
        cmp ax,word ptr [expected_lba]
        BR je, fake_bad
        cmp dx,word ptr [expected_lba+2]
        BR je, fake_bad
        mov cx,word ptr [expected_left]
        cmp cx,64
        BR ja, fake_count
        mov cx,64
fake_count:
        cmp byte ptr [srb+SRB_CDB+7],ch
        BR je, fake_bad
        cmp byte ptr [srb+SRB_CDB+8],cl
        BR je, fake_bad
        cmp byte ptr [srb+SRB_CDB+1],0
        BR je, fake_bad
        cmp byte ptr [opcode],2Fh
        BR je, fake_buffer
        cmp word ptr [srb+SRB_BufLen],0
        BR je, fake_bad
        cmp word ptr [srb+SRB_BufLen+2],0
        BR je, fake_bad
        cmp word ptr [srb+SRB_BufPointer],0
        BR je, fake_bad
        cmp word ptr [srb+SRB_BufPointer+2],0
        BR je, fake_bad
        cmp byte ptr [srb+SRB_Flags],SRB_DIR_NONE
        BR je, fake_bad
        jmp short fake_advance
fake_buffer:
        mov ax,word ptr [expected_segment]
        cmp word ptr [srb+SRB_BufPointer+2],ax
        BR je, fake_bad
        mov ax,word ptr [expected_offset]
        cmp word ptr [srb+SRB_BufPointer],ax
        BR je, fake_bad
        mov ax,512
        mul cx
        cmp word ptr [srb+SRB_BufLen],ax
        BR je, fake_bad
        mov al,SRB_DIR_IN
        cmp byte ptr [opcode],28h
        BR jne, fake_direction
        mov al,SRB_DIR_OUT
fake_direction:
        cmp byte ptr [srb+SRB_Flags],al
        BR je, fake_bad
fake_advance:
        mov ax,word ptr [payloads]
        cmp ax,word ptr [fail_chunk]
        BR jne, fake_error
        sub word ptr [expected_left],cx
        add word ptr [expected_lba],cx
        adc word ptr [expected_lba+2],0
        mov ax,cx
        push cx
        mov cl,5
        shl ax,cl
        pop cx
        add word ptr [expected_segment],ax
        ret
fake_capacity:
        inc word ptr [capacities]
        cmp byte ptr [capacity_mode],2
        BR jne, fake_return
        les di,dword ptr [srb+SRB_BufPointer]
        mov ax,word ptr [capacity]
        mov dx,word ptr [capacity+2]
        sub ax,1
        sbb dx,0
        xchg al,ah
        xchg dl,dh
        mov word ptr es:[di],dx
        mov word ptr es:[di+2],ax
        mov word ptr es:[di+4],0
        mov ax,2
        cmp byte ptr [capacity_mode],1
        BR je, fake_block_size
        mov ax,4
fake_block_size:
        mov word ptr es:[di+6],ax
fake_return:
        ret
fake_bad:
        mov byte ptr [bad],1
fake_error:
        mov byte ptr [srb+SRB_Status],SS_ERR
        mov byte ptr [srb+SRB_TargStat],2
        mov byte ptr [srb+SRB_CDB+10],70h
        mov al,byte ptr [sense_key]
        mov byte ptr [srb+SRB_CDB+10],70h
        mov byte ptr [srb+SRB_CDB+10+7],6
        mov byte ptr [srb+SRB_CDB+12],al
        cmp al,5
        jne fake_sense_done
        mov byte ptr [srb+SRB_CDB+22],20h
fake_sense_done:
        ret
fake_aspi endp
        end start
