; Shared resident ASPI completion/sense parser, no manager or hardware.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h
        jmp start
        include common/aspi/dos_aspi.inc
        include common/aspi/aspi_client.inc

CHECK macro condition
        local good
        condition good
        jmp failed
good:
endm
EXPECT macro value
        call aspi_result
        CHECK jc
        cmp ax,value
        CHECK je
endm
lengths db 6,10,12,16
ok db 'ASPI completion/sense validation passed',13,10,'$'
bad db 'ASPI completion/sense validation FAILED',13,10,'$'
start:
        push cs
        pop ds
        cld
        mov si,offset lengths
        mov di,4
next_length:
        xor cx,cx
        mov cl,[si]
        mov al,SRB_DIR_NONE
        call aspi_prepare
        xor bx,bx
        mov bl,[si]
        mov byte ptr [srb+SRB_Status],SS_ERR
        mov byte ptr [srb+SRB_TargStat],2
        ; Untouched autosense cannot be interpreted as a media error.
        EXPECT 0
        mov byte ptr [srb+bx+SRB_CDB],70h
        mov byte ptr [srb+bx+SRB_CDB+2],7
        mov byte ptr [srb+bx+SRB_CDB+7],6
        mov byte ptr [srb+bx+SRB_CDB+12],27h
        EXPECT 2707h
        call aspi_sense
        CHECK jnc
        mov byte ptr [srb+SRB_Cmd],SC_RESET_DEV
        EXPECT 0
        mov byte ptr [srb+SRB_Cmd],SC_EXEC_SCSI_CMD
        mov byte ptr [srb+bx+SRB_CDB],0F1h
        EXPECT 2707h
        mov byte ptr [srb+SRB_HaStat],11h
        EXPECT 0
        mov byte ptr [srb+SRB_HaStat],0
        mov byte ptr [srb+SRB_Status],SS_ABORTED
        EXPECT 0
        mov byte ptr [srb+SRB_Status],SS_PENDING
        EXPECT 0
        mov byte ptr [srb+SRB_Status],SS_ERR
        mov byte ptr [srb+SRB_TargStat],8
        EXPECT 0
        mov byte ptr [srb+SRB_TargStat],2
        mov byte ptr [srb+SRB_SenseLen],7
        EXPECT 0
        mov byte ptr [srb+SRB_SenseLen],8
        EXPECT 7
        mov byte ptr [srb+SRB_SenseLen],14
        mov byte ptr [srb+bx+SRB_CDB+7],4
        EXPECT 7
        mov byte ptr [srb+SRB_SenseLen],255
        EXPECT 0
        mov byte ptr [srb+SRB_SenseLen],14
        mov byte ptr [srb+bx+SRB_CDB],72h
        mov byte ptr [srb+bx+SRB_CDB+1],5
        mov byte ptr [srb+bx+SRB_CDB+2],20h
        EXPECT 2005h
        mov byte ptr [srb+bx+SRB_CDB],73h
        EXPECT 2005h
        mov byte ptr [srb+bx+SRB_CDB],0F2h
        EXPECT 0
        mov byte ptr [srb+bx+SRB_CDB],72h
        mov byte ptr [srb+SRB_CDBLen],255
        EXPECT 0
        mov byte ptr [srb+SRB_CDBLen],7
        EXPECT 0
        mov byte ptr [srb+SRB_CDBLen],bl
        mov byte ptr [srb+SRB_Status],SS_COMP
        EXPECT 0                        ; contradictory target status
        mov byte ptr [srb+SRB_TargStat],0
        mov byte ptr [srb+SRB_HaStat],11h
        EXPECT 0
        mov byte ptr [srb+SRB_HaStat],0
        call aspi_result
        CHECK jnc
        or al,al
        CHECK jz
        ; The next command clears even a plausible old response.
        mov cl,bl
        mov al,SRB_DIR_NONE
        call aspi_prepare
        mov byte ptr [srb+SRB_Status],SS_ERR
        mov byte ptr [srb+SRB_TargStat],2
        EXPECT 0
        ; Only checked current UNIT ATTENTION sets aspi_attention.
        cmp byte ptr [aspi_attention],0
        CHECK je
        mov byte ptr [srb+bx+SRB_CDB],71h
        mov byte ptr [srb+bx+SRB_CDB+2],6
        mov byte ptr [srb+bx+SRB_CDB+7],6
        EXPECT 6
        cmp byte ptr [aspi_attention],0
        CHECK je
        mov byte ptr [srb+SRB_HaStat],11h
        mov byte ptr [srb+bx+SRB_CDB],70h
        EXPECT 0
        cmp byte ptr [aspi_attention],0
        CHECK je
        mov byte ptr [srb+SRB_HaStat],0
        mov byte ptr [srb+bx+SRB_CDB],0F0h
        EXPECT 6
        cmp byte ptr [aspi_attention],1
        CHECK je
        mov byte ptr [aspi_attention],0
        mov byte ptr [srb+bx+SRB_CDB],72h
        mov byte ptr [srb+bx+SRB_CDB+1],2
        mov byte ptr [srb+bx+SRB_CDB+2],3Ah
        EXPECT 3A02h
        cmp byte ptr [aspi_attention],0
        CHECK je
        mov byte ptr [srb+bx+SRB_CDB+1],6
        mov byte ptr [srb+bx+SRB_CDB+2],28h
        EXPECT 2806h
        cmp byte ptr [aspi_attention],1
        CHECK je
        mov byte ptr [aspi_attention],0
        inc si
        dec di
        jz passed
        jmp next_length
passed:
        mov dx,offset ok
        mov ah,9
        int 21h
        mov ax,4C00h
        int 21h
failed:
        mov dx,offset bad
        mov ah,9
        int 21h
        mov ax,4C01h
        int 21h
        end start
