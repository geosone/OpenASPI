; Execute the actual resident tape decoder with bounded synthetic SRBs.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h
        jmp start
        include common/aspi/dos_aspi.inc
TAPE_SENSE equ SRB_CDB+6
SENSE_FILEMARK equ 80h
SENSE_EOM equ 40h
SENSE_ILI equ 20h
        include common/aspi/tape_sense.inc
srb db ASPI_SRB_SIZE dup (0)
last_sense_key db 0
sense_response db 0
sense_asc_valid db 0
sense_asc db 0
sense_ascq db 0
sense_flags db 0
sense_info_valid db 0
sense_info_high dw 0
sense_info_low dw 0
step dw 0
ok db 'Resident tape sense validation passed',13,10,'$'
bad db 'Resident tape sense validation FAILED',13,10,'$'

EQCHECK macro
        local good
        je good
        jmp failed
good:
endm
DECODE macro response, flags, valid, information, asc_valid
        call remember_sense_key
        cmp byte ptr [sense_response],response
        EQCHECK
        cmp byte ptr [sense_flags],flags
        EQCHECK
        cmp byte ptr [sense_info_valid],valid
        EQCHECK
        cmp word ptr [sense_info_low],information
        EQCHECK
        cmp byte ptr [sense_asc_valid],asc_valid
        EQCHECK
        inc word ptr [step]
endm
INVALID macro
        DECODE 0,0,0,0,0
        cmp byte ptr [last_sense_key],0
        EQCHECK
        cmp word ptr [sense_asc],0
        EQCHECK
endm
start:
        push cs
        pop ds
        mov byte ptr [srb+SRB_Cmd],SC_EXEC_SCSI_CMD
        mov byte ptr [srb+SRB_Status],SS_ERR
        mov byte ptr [srb+SRB_TargStat],2
        mov byte ptr [srb+SRB_CDBLen],6
        mov byte ptr [srb+SRB_SenseLen],32
        INVALID
        mov byte ptr [srb+TAPE_SENSE],0F0h
        mov byte ptr [srb+TAPE_SENSE+2],0E3h
        mov byte ptr [srb+TAPE_SENSE+6],9
        mov byte ptr [srb+TAPE_SENSE+7],6
        mov byte ptr [srb+TAPE_SENSE+12],4
        mov byte ptr [srb+TAPE_SENSE+13],1
        DECODE 70h,0E0h,1,9,1
        cmp byte ptr [last_sense_key],3
        EQCHECK
        cmp word ptr [sense_asc],0104h
        EQCHECK
        mov byte ptr [srb+SRB_HaStat],11h
        INVALID
        mov byte ptr [srb+SRB_HaStat],0
        mov byte ptr [srb+SRB_Status],SS_ABORTED
        INVALID
        mov byte ptr [srb+SRB_Status],SS_PENDING
        INVALID
        mov byte ptr [srb+SRB_Status],SS_ERR
        mov byte ptr [srb+SRB_TargStat],8
        INVALID
        mov byte ptr [srb+SRB_TargStat],2
        mov byte ptr [srb+SRB_Cmd],SC_RESET_DEV
        INVALID
        mov byte ptr [srb+SRB_Cmd],SC_EXEC_SCSI_CMD
        mov byte ptr [srb+SRB_CDBLen],10
        INVALID
        mov byte ptr [srb+SRB_CDBLen],6
        mov byte ptr [srb+SRB_SenseLen],7
        INVALID
        mov byte ptr [srb+SRB_SenseLen],33
        INVALID
        mov byte ptr [srb+SRB_SenseLen],8
        DECODE 70h,0E0h,1,9,0
        mov byte ptr [srb+SRB_SenseLen],32
        mov byte ptr [srb+TAPE_SENSE+7],5
        DECODE 70h,0E0h,1,9,0
        mov byte ptr [srb+TAPE_SENSE],71h
        DECODE 71h,0E0h,0,0,0

        ; Descriptor header and a complete stream descriptor followed by
        ; an information descriptor. Bounds exclude trailing plausible data.
        mov byte ptr [srb+TAPE_SENSE],72h
        mov byte ptr [srb+TAPE_SENSE+1],2
        mov byte ptr [srb+TAPE_SENSE+2],4
        mov byte ptr [srb+TAPE_SENSE+3],7
        mov byte ptr [srb+TAPE_SENSE+7],16
        mov byte ptr [srb+TAPE_SENSE+8],4
        mov byte ptr [srb+TAPE_SENSE+9],2
        mov byte ptr [srb+TAPE_SENSE+11],0E0h
        mov byte ptr [srb+TAPE_SENSE+12],0
        mov byte ptr [srb+TAPE_SENSE+13],10
        mov byte ptr [srb+TAPE_SENSE+14],80h
        mov word ptr [srb+TAPE_SENSE+16],0
        mov word ptr [srb+TAPE_SENSE+18],0
        mov word ptr [srb+TAPE_SENSE+20],0
        mov byte ptr [srb+TAPE_SENSE+22],0
        mov byte ptr [srb+TAPE_SENSE+23],9
        mov byte ptr [srb+SRB_SenseLen],8
        DECODE 72h,0,0,0,1
        mov byte ptr [srb+SRB_SenseLen],11
        DECODE 72h,0,0,0,1
        mov byte ptr [srb+SRB_SenseLen],12
        DECODE 72h,0E0h,0,0,1
        mov byte ptr [srb+SRB_SenseLen],23
        DECODE 72h,0E0h,0,0,1
        mov byte ptr [srb+SRB_SenseLen],24
        DECODE 72h,0E0h,1,9,1
        mov byte ptr [srb+TAPE_SENSE+7],0
        DECODE 72h,0,0,0,1
        mov byte ptr [srb+TAPE_SENSE+7],16
        mov byte ptr [srb+TAPE_SENSE+9],255
        DECODE 72h,0,0,0,1
        mov byte ptr [srb+TAPE_SENSE],0F2h
        INVALID
        mov byte ptr [srb+TAPE_SENSE],0F3h
        INVALID
        mov byte ptr [srb+TAPE_SENSE],73h
        DECODE 73h,0,0,0,1

        ; Autosense starts after a ten-byte CDB, not at the legacy +6 slot.
        ; Stale bytes in the shorter slot must not win over current sense.
        mov byte ptr [srb+SRB_CDBLen],10
        mov byte ptr [srb+SRB_SenseLen],32
        mov word ptr [srb+SRB_CDB+10],70h
        mov word ptr [srb+SRB_CDB+12],5
        mov word ptr [srb+SRB_CDB+14],0
        mov word ptr [srb+SRB_CDB+16],0600h
        mov word ptr [srb+SRB_CDB+22],20h
        mov di,1234h
        DECODE 70h,0,0,0,1
        cmp di,1234h
        EQCHECK
        cmp byte ptr [last_sense_key],5
        EQCHECK
        cmp byte ptr [sense_asc],20h
        EQCHECK
        mov word ptr [srb+SRB_CDB+10],0572h
        mov word ptr [srb+SRB_CDB+12],24h
        mov byte ptr [srb+SRB_CDB+17],0
        DECODE 72h,0,0,0,1
        cmp byte ptr [sense_asc],24h
        EQCHECK
        mov byte ptr [srb+SRB_CDBLen],16
        mov word ptr [srb+SRB_CDB+16],0572h
        mov word ptr [srb+SRB_CDB+18],24h
        mov byte ptr [srb+SRB_CDB+23],0
        DECODE 72h,0,0,0,1
        cmp byte ptr [last_sense_key],5
        EQCHECK
        mov byte ptr [srb+SRB_CDBLen],8
        INVALID
        mov byte ptr [srb+SRB_Status],SS_COMP
        mov byte ptr [srb+SRB_TargStat],0
        call check_tape_completion
        jnc success_host_test
        jmp failed
success_host_test:
        mov byte ptr [srb+SRB_HaStat],11h
        call check_tape_completion
        jc success_target_test
        jmp failed
success_target_test:
        mov byte ptr [srb+SRB_HaStat],0
        mov byte ptr [srb+SRB_TargStat],2
        call check_tape_completion
        jc passed
        jmp failed
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
