; Run the real INIT/enumeration path against memory-only ASPI, including
; two populated host adapters and a nonzero LUN. No real device is used.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h
        jmp test_start
ifdef TEST_FDD
FDD_DRIVER equ 1
endif
        include common/aspi/dos_aspi.inc
        include common/dos/devreq.inc
        include common/dos/blkdrv.inc
msg_banner db '$'
msg_no_device db '$'

REQUIRE macro
        local okay
        je okay
        jmp failed
okay:
endm

BRANCH macro inverse, target
        local skip
        inverse skip
        jmp target
skip:
endm

old21 dd 0
packet db 32 dup (0)
strategy_addr dw offset strategy, 0
interrupt_addr dw offset interrupt, 0
mode db 0
bad db 0
queries dw 0
reads dw 0
boot db 0EBh,3Ch,90h,'OPENASPI'
     dw 512
     db 2
     dw 1
     db 2
     dw 112,1440
     db 0F9h
     dw 3,9,2
     dd 0,0
     db 474 dup (0)
     dw 0AA55h
okay_msg db 'Block INIT BIOS ownership tests passed',13,10,'$'
failed_msg db 'Block INIT BIOS ownership FAILED, mode $'

test_start:
        push cs
        pop ds
        push cs
        pop es
        mov word ptr [strategy_addr+2], cs
        mov word ptr [interrupt_addr+2], cs
        mov ax,3521h
        int 21h
        mov word ptr [old21], bx
        mov word ptr [old21+2], es
        mov dx,offset hook21
        mov ax,2521h
        int 21h
next_case:
        mov byte ptr [unit_count],0
        mov byte ptr [ownership_warned],0
        mov word ptr [queries],0
        mov word ptr [reads],0
        push cs
        pop es
        mov di,offset packet
        mov cx,32
        xor ax,ax
        rep stosb
        mov byte ptr [packet+RH_LENGTH],23
        mov byte ptr [packet+RH_INIT_DRIVE],3
        mov bx,offset packet
        call dword ptr [strategy_addr]
        call dword ptr [interrupt_addr]
        cmp byte ptr [bad],0
        REQUIRE
        cmp word ptr [packet+RH_STATUS],ST_DONE
        REQUIRE
        cmp word ptr [queries],3
        REQUIRE
        xor ax,ax
        cmp byte ptr [mode],0
        je expect_three
        cmp byte ptr [mode],2
        je expect_three
        cmp byte ptr [mode],3
        je expect_three
        cmp byte ptr [mode],9
        je expect_two
        cmp byte ptr [mode],10
        jne count_ready
expect_two:
        mov al,2
        jmp short count_ready
expect_three:
        mov al,3
count_ready:
        cmp byte ptr [unit_count],al
        REQUIRE
        cmp byte ptr [packet+RH_INIT_UNITS],al
        REQUIRE
        cmp word ptr [reads],ax
        REQUIRE
        cmp byte ptr [mode],3
        je check_warning
        cmp byte ptr [mode],10
        jne check_other_warning
check_warning:
        cmp byte ptr [ownership_warned],1
        REQUIRE
        jmp short check_units
check_other_warning:
        cmp byte ptr [ownership_warned],0
        REQUIRE
check_units:
        cmp al,0
        je advance_case
        cmp byte ptr [unit_table+U_HA],0
        REQUIRE
        cmp byte ptr [unit_table+U_TARGET],2
        REQUIRE
        xor ah,ah
        cmp byte ptr [mode],9
        jne check_first_lun
        inc ah
check_first_lun:
        cmp byte ptr [unit_table+U_LUN],ah
        REQUIRE
        dec al
        mov ah,UNIT_SIZE
        mul ah
        mov di,ax
        cmp byte ptr [unit_table+di+U_HA],12
        REQUIRE
        cmp byte ptr [unit_table+di+U_TARGET],31
        REQUIRE
        cmp byte ptr [unit_table+di+U_LUN],0
        REQUIRE
advance_case:
        inc byte ptr [mode]
        cmp byte ptr [mode],11
        BRANCH jae, next_case
        call restore21
        mov dx,offset okay_msg
        mov ah,09h
        int 21h
        mov ax,4C00h
        int 21h
failed:
        call restore21
        mov dx,offset failed_msg
        mov ah,09h
        int 21h
        mov dl,byte ptr [mode]
        add dl,'0'
        mov ah,02h
        int 21h
        mov ax,4C01h
        int 21h
restore21 proc near
        push ds
        lds dx,dword ptr [old21]
        mov ax,2521h
        int 21h
        pop ds
        ret
restore21 endp

; Intercept only this embedded driver's open/read-entry/close operations.
hook21 proc far
        push bp
        mov bp,sp
        cmp ax,3D00h
        jne hook_read
        cmp dx,offset aspi_manager_name
        jne hook_chain
        mov ax,0F123h
        jmp short hook_ok
hook_read:
        cmp bx,0F123h
        jne hook_chain
        cmp ax,4402h
        jne hook_close
        cmp dx,offset aspi_entry
        jne hook_bad
        cmp cx,4
        jne hook_bad
        mov word ptr [aspi_entry],offset fake_aspi
        mov word ptr [aspi_entry+2],cs
        mov ax,4
        jmp short hook_ok
hook_close:
        cmp ah,3Eh
        jne hook_chain
        xor ax,ax
hook_ok:
        and word ptr ss:[bp+6],0FFFEh
        pop bp
        iret
hook_bad:
        mov byte ptr [bad],1
        jmp short hook_ok
hook_chain:
        pop bp
        jmp dword ptr cs:[old21]
hook21 endp

fake_aspi proc far
        push bp
        mov bp,sp
        cmp word ptr ss:[bp+6],offset srb
        BRANCH je, fake_bad
        mov ax,cs
        cmp word ptr ss:[bp+8],ax
        BRANCH je, fake_bad
        cmp word ptr [srb+SRB_Hdr_Rsvd],0
        BRANCH je, fake_bad
        cmp word ptr [srb+SRB_Hdr_Rsvd+2],0
        BRANCH je, fake_bad
        mov byte ptr [srb+SRB_Status],SS_COMP
        mov al,byte ptr [srb+SRB_Cmd]
        cmp al,SC_HA_INQUIRY
        BRANCH jne, fake_ha
        cmp al,SC_GET_DEV_TYPE
        BRANCH jne, fake_type
        cmp al,SC_GET_DISK_INFO
        BRANCH jne, fake_info
        cmp al,SC_EXEC_SCSI_CMD
        BRANCH je, fake_bad
        jmp fake_exec
fake_ha:
        mov byte ptr [srb+HA_Count],13
        mov byte ptr [srb+HA_SCSI_ID],7
        mov byte ptr [srb+HA_Unique+3],32
        jmp fake_done
fake_type:
        cmp byte ptr [srb+SRB_HaId],0
        BRANCH je, fake_second
        cmp byte ptr [srb+SRB_Target],2
        BRANCH je, fake_absent
        cmp byte ptr [srb+SRB_Lun],1
        BRANCH jbe, fake_absent
        jmp short fake_present
fake_second:
        cmp byte ptr [srb+SRB_HaId],12
        BRANCH je, fake_absent
        cmp byte ptr [srb+SRB_Target],31
        BRANCH je, fake_absent
        cmp byte ptr [srb+SRB_Lun],0
        BRANCH je, fake_absent
fake_present:
        mov byte ptr [srb+SRB_DeviceType],ASPI_DEV_DISK
        jmp fake_done
fake_absent:
        mov byte ptr [srb+SRB_Status],SS_NO_DEVICE
        jmp fake_done
fake_info:
        inc word ptr [queries]
        cmp byte ptr [srb+SRB_Flags],0
        BRANCH je, fake_bad
        cmp byte ptr [srb+SRB_DriveFlags],0FFh
        BRANCH je, fake_bad
        mov al,byte ptr [mode]
        cmp al,10
        BRANCH jne, fake_mixed_support
        cmp al,9
        BRANCH je, fake_info_mode
        mov al,DISK_INT13_AND_DOS
        cmp byte ptr [srb+SRB_HaId],0
        BRANCH je, fake_info_free
        cmp byte ptr [srb+SRB_Lun],0
        BRANCH jne, fake_info_mode
fake_info_free:
        mov al,DISK_INT13
        jmp short fake_info_mode
fake_mixed_support:
        mov al,DISK_NOT_INT13
        cmp byte ptr [srb+SRB_HaId],0
        jne fake_info_mode
        mov al,DISK_INT13_AND_DOS
        cmp byte ptr [srb+SRB_Lun],1
        je fake_info_mode
        mov al,3                     ; unsupported only for this candidate
fake_info_mode:
        cmp al,2
        BRANCH ja, fake_info_flag
        cmp al,3
        BRANCH jne, fake_unsupported
        cmp al,4
        BRANCH jne, fake_error
        cmp al,5
        BRANCH jne, fake_invalid_ha
        cmp al,6
        BRANCH jne, fake_absent
        cmp al,7
        BRANCH je, fake_done                ; success with untouched output
        mov al,3                     ; invalid ownership enum
fake_info_flag:
        mov byte ptr [srb+SRB_DriveFlags],al
        mov byte ptr [srb+SRB_Int13DriveInfo],80h
        jmp fake_done
fake_unsupported:
        mov byte ptr [srb+SRB_Status],SS_INVALID_CMD
        jmp fake_done
fake_invalid_ha:
        mov byte ptr [srb+SRB_Status],SS_INVALID_HA
        jmp fake_done
fake_error:
        mov byte ptr [srb+SRB_Status],SS_ERR
        jmp fake_done
fake_exec:
        cmp byte ptr [srb+SRB_CDB],12h
        BRANCH je, fake_data
        les di,dword ptr [srb+SRB_BufPointer]
        xor ax,ax
        mov cx,INQUIRY_LEN
        rep stosb
        mov byte ptr [inquiry_data+1],80h
ifdef TEST_FDD
        mov word ptr [inquiry_data+16],'IZ'
        mov byte ptr [inquiry_data+18],'P'
endif
        jmp fake_done
fake_data:
        ; Excluded candidates must never reach TUR or READ.
        mov al,byte ptr [mode]
        cmp al,1
        BRANCH jne, fake_bad
        cmp al,4
        BRANCH jae, fake_data_allowed
        cmp al,10
        BRANCH jne, fake_mixed_data
        cmp al,9
        BRANCH je, fake_bad
        cmp byte ptr [srb+SRB_HaId],0
        BRANCH je, fake_data_allowed
        cmp byte ptr [srb+SRB_Lun],0
        BRANCH jne, fake_bad
        jmp short fake_data_allowed
fake_mixed_data:
        cmp byte ptr [srb+SRB_HaId],0
        jne fake_data_allowed
        cmp byte ptr [srb+SRB_Lun],1
        BRANCH jne, fake_bad
fake_data_allowed:
        cmp byte ptr [srb+SRB_CDB],0
        BRANCH jne, fake_done
        cmp byte ptr [srb+SRB_CDB],28h
        BRANCH je, fake_bad
        inc word ptr [reads]
        mov si,offset boot
        les di,dword ptr [srb+SRB_BufPointer]
        mov cx,512
        rep movsb
        jmp fake_done
fake_bad:
        mov byte ptr [bad],1
        mov byte ptr [srb+SRB_Status],SS_ERR
fake_done:
        pop bp
        ret
fake_aspi endp
        end test_start
