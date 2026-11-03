; ASPIFDD generic IOCTL 42h (format/verify track) and 68h (sense media type)
; against a memory-only ASPI manager. Every SCSI command is logged; each case
; compares the DOS status, the packet and the command log.
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
; RUN minor, status, expected log (0FFh-terminated)
RUN macro minor, status, expect
        mov byte ptr [packet+RH_IOCTL_MINOR],minor
        mov word ptr [logn],0
        mov word ptr [verified],0
        mov bx,offset packet
        call dword ptr [strategy_ptr]
        call dword ptr [interrupt_ptr]
        cmp word ptr [packet+RH_STATUS],status
        EQUAL
        cmp byte ptr [bad],0
        EQUAL
        mov si,offset expect
        call check_log
        EQUAL
        inc word ptr [step]
endm

packet db 32 dup (0)
args db 7 dup (0)
strategy_ptr dw offset strategy,0
interrupt_ptr dw offset interrupt,0
step dw 0
bad db 0
capacity dd 2880
caps_mode db 0                  ; 0 list, 1 ILLEGAL REQUEST, 2 no medium
caps_len db 16
caps_list db 0,0,0Bh,40h, 2, 0,2,0      ; current: 2880, formatted
          db 0,3,0C3h,0, 0, 0,2,0       ; formattable: 246528
          db 0,0,0Bh,40h, 0, 0,2,0      ; formattable: 2880
busy db 0                       ; TUR answers 02/04/04 this often
tur_fail db 0                   ; then a TUR fails with 03/31 (format failed)
log db 64 dup (0)
logn dw 0
seen_cdb db 12 dup (0)
seen_cdblen db 0
seen_param db 12 dup (0)
verify_lba dd 0
verified dw 0

l_status db 23h,0FFh
l_none db 0FFh
l_format_ufi db 23h,04h,0,0,0,25h,2Fh,0FFh
l_verify db 25h,2Fh,0FFh
l_format_sbc db 23h,25h,04h,0,0,25h,2Fh,0FFh
l_sbc_size db 23h,25h,0FFh
l_caps db 23h,0FFh
l_format_fail db 23h,04h,0,0,0,0FFh
l_capacity db 25h,0FFh
ufi_cdb db 04h,17h,0,0,0,0,0,0,0Ch,0,0,0
ufi_param db 0,0A2h,0,8, 0,0,0Bh,40h, 0,0,2,0
sbc_param db 0,02h,0,0

ok db 'Block format/media type tests passed',13,10,'$'
badmsg db 'Block format FAILED step $'

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
        mov word ptr [unit_table+U_DEFAULT_BPB+BPB_TOTAL16],2880
        mov byte ptr [packet+RH_LENGTH],32
        mov byte ptr [packet+RH_COMMAND],CMD_GEN_IOCTL
        mov byte ptr [packet+RH_IOCTL_CATEGORY],8
        mov word ptr [packet+RH_IOCTL_PARAM],offset args
        mov word ptr [packet+RH_IOCTL_PARAM+2],cs

        ; 0: status call, 1.44 MB offered
        call reset_case
        mov byte ptr [args],1
        RUN 42h,ST_DONE,l_status
        cmp byte ptr [args],0
        EQUAL
        ; 1: a size not offered
        call reset_case
        mov byte ptr [args],1
        mov word ptr [unit_table+U_BPB+BPB_TOTAL16],1440
        mov word ptr [unit_table+U_BPB+BPB_SPT],9
        RUN 42h,ST_DONE,l_status
        cmp byte ptr [args],2
        EQUAL
        ; 2: no medium
        call reset_case
        mov byte ptr [args],1
        mov byte ptr [caps_mode],2
        RUN 42h,ST_DONE,l_status
        cmp byte ptr [args],3
        EQUAL
        ; 3: no READ FORMAT CAPACITIES
        call reset_case
        mov byte ptr [args],1
        mov byte ptr [caps_mode],1
        RUN 42h,ST_DONE,l_status
        cmp byte ptr [args],1
        EQUAL
        ; 4: first track, LS-120 form: FORMAT UNIT, wait, VERIFY
        call reset_case
        RUN 42h,ST_DONE,l_format_ufi
        cmp byte ptr [seen_cdblen],12
        EQUAL
        mov si,offset ufi_cdb
        mov di,offset seen_cdb
        mov cx,12
        repe cmpsb
        EQUAL
        mov si,offset ufi_param
        mov di,offset seen_param
        mov cx,12
        repe cmpsb
        EQUAL
        cmp word ptr [verify_lba],0
        EQUAL
        cmp word ptr [verified],18
        EQUAL
        ; the formatted medium is no longer cached; 40h's BPB stays
        mov al,byte ptr [unit_table+U_FLAGS]
        and al,UF_MEDIA or UF_BPB_OVERRIDE
        cmp al,UF_BPB_OVERRIDE
        EQUAL
        ; 5: another track is verified only
        call reset_case
        mov word ptr [args+1],1                 ; head 1
        mov word ptr [args+3],1                 ; cylinder 1
        RUN 42h,ST_DONE,l_verify
        cmp word ptr [verify_lba],54
        EQUAL
        cmp word ptr [verified],18
        EQUAL
        ; 6: two tracks from the first: format, then 36 sectors verified
        call reset_case
        mov byte ptr [args],2
        mov word ptr [args+5],2
        RUN 42h,ST_DONE,l_format_ufi
        cmp word ptr [verified],36
        EQUAL
        ; 7: SBC form for other drives, of the current capacity
        call reset_case
        and byte ptr [unit_table+U_XFLAGS],not XF_UFI
        mov byte ptr [busy],1
        RUN 42h,ST_DONE,l_format_sbc
        cmp byte ptr [seen_cdblen],6
        EQUAL
        cmp word ptr [seen_cdb],1004h
        EQUAL
        mov si,offset sbc_param
        mov di,offset seen_param
        mov cx,4
        repe cmpsb
        EQUAL
        ; 8: SBC with another capacity: not formatted
        call reset_case
        and byte ptr [unit_table+U_XFLAGS],not XF_UFI
        mov word ptr [capacity],0C300h
        mov word ptr [capacity+2],3
        RUN 42h,ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA,l_sbc_size
        ; 9: write-protected medium: no FORMAT UNIT
        call reset_case
        or byte ptr [unit_table+U_XFLAGS],XF_WPROT
        RUN 42h,ST_DONE or ST_ERROR or ERR_WRITE_PROTECT,l_caps
        ; 10: size not offered: no FORMAT UNIT
        call reset_case
        mov word ptr [unit_table+U_BPB+BPB_TOTAL16],1440
        mov word ptr [unit_table+U_BPB+BPB_SPT],9
        RUN 42h,ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA,l_caps
        ; 11: a track beyond the size: nothing sent
        call reset_case
        mov word ptr [args+3],80
        RUN 42h,ST_DONE or ST_ERROR or ERR_NOT_FOUND,l_none
        ; 12: unknown flags
        call reset_case
        mov byte ptr [args],4
        RUN 42h,ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,l_none
        ; 13: the format fails while the drive works on it (03/31)
        call reset_case
        mov byte ptr [tur_fail],1
        RUN 42h,ST_DONE or ST_ERROR or ERR_READ,l_format_fail
        ; 14: 68h, 1.44 MB, the drive's default
        call reset_case
        RUN 68h,ST_DONE,l_capacity
        cmp word ptr [args],0701h
        EQUAL
        ; 15: 68h, 720 KB
        call reset_case
        mov word ptr [capacity],1440
        RUN 68h,ST_DONE,l_capacity
        cmp word ptr [args],0200h
        EQUAL
        ; 16: 68h, 120 MB: no DOS media type
        call reset_case
        mov word ptr [capacity],0C300h
        mov word ptr [capacity+2],3
        mov word ptr [args],0AAAAh
        RUN 68h,ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA,l_capacity
        cmp word ptr [args],0AAAAh
        EQUAL

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
        mov si,offset log               ; the commands sent, in hex
        mov cx,word ptr [logn]
        jcxz failed_end
failed_log:
        mov dl,' '
        mov ah,02h
        int 21h
        lodsb
        push ax
        mov cl,4
        shr al,cl
        call hex_digit
        pop ax
        call hex_digit
        mov cx,word ptr [logn]
        sub cx,si
        add cx,offset log
        jnz failed_log
failed_end:
        mov ax,4C01h
        int 21h

hex_digit proc near
        and al,0Fh
        add al,'0'
        cmp al,'9'
        jbe hex_ready
        add al,7
hex_ready:
        mov dl,al
        mov ah,02h
        int 21h
        ret
hex_digit endp

; 1.44 MB set with 40h, an LS-120 class drive, 1.44 MB medium
reset_case proc near
        mov byte ptr [unit_table+U_FLAGS],UF_REMOVABLE or UF_MEDIA or UF_BPB_OVERRIDE
        mov byte ptr [unit_table+U_XFLAGS],XF_UFI
        mov word ptr [unit_table+U_BPB+BPB_BYTES],512
        mov word ptr [unit_table+U_BPB+BPB_SPT],18
        mov word ptr [unit_table+U_BPB+BPB_HEADS],2
        mov word ptr [unit_table+U_BPB+BPB_TOTAL16],2880
        mov byte ptr [args],0
        mov word ptr [args+1],0
        mov word ptr [args+3],0
        mov word ptr [args+5],0
        mov word ptr [capacity],2880
        mov word ptr [capacity+2],0
        mov byte ptr [caps_mode],0
        mov byte ptr [busy],2
        mov byte ptr [tur_fail],0
        mov byte ptr [seen_cdblen],0
        ret
reset_case endp

; the log equals the 0FFh-terminated list at SI? ZF
check_log proc near
        mov di,offset log
        mov cx,word ptr [logn]
check_log_next:
        lodsb
        cmp al,0FFh
        je check_log_end
        jcxz check_log_differs
        cmp al,byte ptr [di]
        jne check_log_differs
        inc di
        dec cx
        jmp short check_log_next
check_log_end:
        or cx,cx
        ret
check_log_differs:
        or sp,sp                        ; ZF clear
        ret
check_log endp

; check condition with fixed sense AL key, AH ASC, DL ASCQ
fake_check proc near
        mov byte ptr [srb+SRB_Status],SS_ERR
        mov byte ptr [srb+SRB_TargStat],2
        mov bl,byte ptr [srb+SRB_CDBLen]
        xor bh,bh
        mov byte ptr [srb+bx+SRB_CDB],70h
        mov byte ptr [srb+bx+SRB_CDB+2],al
        mov byte ptr [srb+bx+SRB_CDB+7],10
        mov byte ptr [srb+bx+SRB_CDB+12],ah
        mov byte ptr [srb+bx+SRB_CDB+13],dl
        ret
fake_check endp

fake_aspi proc far
        push cs
        pop es
        cmp byte ptr [srb+SRB_HaId],2
        BR je, fake_bad
        cmp byte ptr [srb+SRB_Target],3
        BR je, fake_bad
        mov byte ptr [srb+SRB_Status],SS_COMP
        mov al,byte ptr [srb+SRB_CDB]
        mov bx,word ptr [logn]
        cmp bx,64
        BR jb, fake_bad
        mov byte ptr [log+bx],al
        inc word ptr [logn]
        cmp al,25h
        BR jne, fake_capacity
        cmp al,23h
        BR jne, fake_caps
        cmp al,04h
        BR jne, fake_format
        cmp al,00h
        BR jne, fake_tur
        cmp al,2Fh
        BR jne, fake_verify
        jmp fake_bad                    ; nothing else is expected
fake_capacity:
        les di,dword ptr [srb+SRB_BufPointer]
        mov ax,word ptr [capacity]
        mov dx,word ptr [capacity+2]
        sub ax,1
        sbb dx,0
        xchg dl,dh
        xchg al,ah
        mov word ptr es:[di],dx
        mov word ptr es:[di+2],ax
        mov word ptr es:[di+4],0
        mov word ptr es:[di+6],0002h    ; 00 00 02 00: 512
        ret
fake_caps:
        cmp byte ptr [caps_mode],1
        jne fake_caps_medium
        mov ax,2005h                    ; ILLEGAL REQUEST, invalid opcode
        xor dl,dl
        call fake_check
        ret
fake_caps_medium:
        cmp byte ptr [caps_mode],2
        jne fake_caps_list
        mov ax,3A02h
        xor dl,dl
        call fake_check
        ret
fake_caps_list:
        les di,dword ptr [srb+SRB_BufPointer]
        mov word ptr es:[di],0
        mov byte ptr es:[di+2],0
        mov al,byte ptr [caps_len]
        mov byte ptr es:[di+3],al
        add di,4
        mov si,offset caps_list
        mov cx,24
        rep movsb
        ret
fake_format:
        mov al,byte ptr [srb+SRB_CDBLen]
        mov byte ptr [seen_cdblen],al
        mov si,offset srb+SRB_CDB
        mov di,offset seen_cdb
        mov cx,12
        rep movsb
        cmp byte ptr [srb+SRB_Flags],SRB_DIR_OUT
        BR je, fake_bad
        mov cx,word ptr [srb+SRB_BufLen]
        cmp cx,12
        BR jbe, fake_bad
        push ds
        lds si,dword ptr [srb+SRB_BufPointer]
        mov di,offset seen_param
        rep movsb
        pop ds
        ret
fake_tur:
        cmp byte ptr [busy],0
        je fake_tur_ready
        dec byte ptr [busy]
        mov ax,0402h                    ; NOT READY, format in progress
        mov dl,4
        call fake_check
        ret
fake_tur_ready:
        cmp byte ptr [tur_fail],0
        je fake_done
        mov ax,3103h                    ; MEDIUM ERROR, format failed
        mov dl,1
        call fake_check
        ret
fake_verify:
        mov ax,word ptr [srb+SRB_CDB+4]
        mov dx,word ptr [srb+SRB_CDB+2]
        xchg al,ah
        xchg dl,dh
        cmp word ptr [verified],0
        jne fake_verify_count
        mov word ptr [verify_lba],ax
        mov word ptr [verify_lba+2],dx
fake_verify_count:
        mov ah,byte ptr [srb+SRB_CDB+7]
        mov al,byte ptr [srb+SRB_CDB+8]
        add word ptr [verified],ax
        ret
fake_bad:
        mov byte ptr [bad],1
        mov byte ptr [srb+SRB_Status],SS_ERR
fake_done:
        ret
fake_aspi endp
        end start
