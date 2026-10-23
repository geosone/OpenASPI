; Actual resident block/CD handlers against memory-only ASPI. No hardware.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h
        jmp test_start
ifdef TEST_CDA
ASPICDA_TEST equ 1
DRIVER_ENTRY textequ <test_start>
        include common/aspi/dos_aspi.inc
        include common/dos/devreq.inc
; Constants used before the driver is included at the end of this fixture.
U_DOOR_STATE equ 15
DOOR_LOCKED equ 1
DOOR_OPEN equ 2
UNIT_ENTRY equ 16
U_AUDIO_STATE equ 4
U_AUDIO_RANGE equ 5
U_AUDIO_CONTROL equ 14
else
FDD_DRIVER equ 1
        include common/aspi/dos_aspi.inc
        include common/dos/devreq.inc
        include common/dos/blkdrv.inc
msg_banner db '$'
msg_no_device db '$'
endif

CHECK_EQ macro
        local good
        je good
        jmp failed
good:
endm
SEND macro status, commands
        mov word ptr [calls], 0
        call submit
        cmp word ptr [packet+RH_STATUS], status
        CHECK_EQ
        cmp word ptr [calls], commands
        CHECK_EQ
        cmp byte ptr [bad], 0
        CHECK_EQ
        cmp byte ptr [guard_before], 0A5h
        CHECK_EQ
        cmp byte ptr [guard_after], 0A5h
        CHECK_EQ
        inc word ptr [step]
endm
EXPECT_LOCKS macro value
ifdef TEST_CDA
        cmp byte ptr [unit_table+U_DOOR_STATE], value
else
        cmp byte ptr [unit_table+U_LOCKS], value
endif
        CHECK_EQ
endm
SET_CONTROL macro function, value
        mov byte ptr [control], function
        mov byte ptr [control+1], value
endm

packet db 32 dup (0)
guard_before db 0A5h
control db 5 dup (0A5h)
guard_after db 0A5h
strategy_ptr dw offset strategy,0
interrupt_ptr dw offset interrupt,0
calls dw 0
step dw 0
bad db 0
fault db 0
expected_opcode db 1Eh
expected_value db 1
ok db 'Media control resident tests passed',13,10,'$'
failure db 'Media control FAILED step $'

test_start:
        push cs
        pop ds
        push cs
        pop es
        mov word ptr [strategy_ptr+2], cs
        mov word ptr [interrupt_ptr+2], cs
        mov word ptr [aspi_entry], offset fake_aspi
        mov word ptr [aspi_entry+2], cs
        mov byte ptr [unit_count], 2
        mov byte ptr [packet+RH_LENGTH], 32
        mov ax, cs
        inc ax                              ; aliased non-CS parameter segment
ifdef TEST_CDA
        mov byte ptr [unit_table+UNIT_ENTRY+1], 1
        mov byte ptr [unit_table+U_AUDIO_CONTROL], 2
        mov word ptr [packet+RH_BUFFER+2], ax
        mov word ptr [packet+RH_BUFFER], offset control-16
        mov word ptr [packet+RH_COUNT], 2
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_OUT
        SET_CONTROL 1,1
        SEND ST_DONE,1
        EXPECT_LOCKS DOOR_LOCKED
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_IN
        mov word ptr [packet+RH_COUNT], 5
        SET_CONTROL 6,0A5h
        SEND ST_DONE,0
        test byte ptr [control+1], 2
        CHECK_EQ
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_OUT
        mov word ptr [packet+RH_COUNT], 2
        ; Locked eject fails locally, even if the device would accept it.
        SET_CONTROL 0,0
        SEND ST_DONE or ST_ERROR or ERR_GENERAL,0
        EXPECT_LOCKS DOOR_LOCKED
        ; Unit 1 is independent; close/eject must not clear unit 0's lock.
        mov byte ptr [packet+RH_UNIT], 1
        mov byte ptr [expected_opcode], 1Bh
        mov byte ptr [expected_value], 3
        SET_CONTROL 5,0
        SEND ST_DONE,1
        EXPECT_LOCKS DOOR_LOCKED
        mov byte ptr [packet+RH_UNIT], 0
        mov byte ptr [expected_opcode], 1Eh
        mov byte ptr [expected_value], 0
        mov byte ptr [fault], 5
        SET_CONTROL 1,0
        SEND ST_DONE or ST_ERROR or ERR_NOT_FOUND,1
        EXPECT_LOCKS DOOR_LOCKED
        mov byte ptr [fault], 0
        SEND ST_DONE,1
        EXPECT_LOCKS 0
        mov byte ptr [fault], 5
        mov byte ptr [expected_value], 1
        SET_CONTROL 1,1
        SEND ST_DONE or ST_ERROR or ERR_NOT_FOUND,1
        EXPECT_LOCKS 0
        mov byte ptr [fault], 0
        ; Invalid lock values and truncated/wrapping packets cannot send ASPI.
        SET_CONTROL 1,2
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        SET_CONTROL 1,1
        mov word ptr [packet+RH_COUNT], 1
        SEND ST_DONE or ST_ERROR or 5,0
        mov word ptr [packet+RH_COUNT], 2
        ; At FFFF the control byte exists but its value would wrap.
        mov bx, 0FFFFh
        mov byte ptr [bx], 1
        mov word ptr [packet+RH_BUFFER], 0FFFFh
        mov word ptr [packet+RH_BUFFER+2], cs
        SEND ST_DONE or ST_ERROR or 5,0
        mov word ptr [packet+RH_BUFFER], offset control
        ; Successful eject invalidates audio only for the selected unit.
        mov byte ptr [unit_table+U_AUDIO_STATE], 2
        mov byte ptr [unit_table+U_AUDIO_RANGE], 1
        mov byte ptr [unit_table+UNIT_ENTRY+U_AUDIO_STATE], 2
        mov byte ptr [expected_opcode], 1Bh
        mov byte ptr [expected_value], 2
        SET_CONTROL 0,0
        SEND ST_DONE,1
        EXPECT_LOCKS DOOR_OPEN
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_IN
        mov word ptr [packet+RH_COUNT], 5
        SET_CONTROL 6,0A5h
        SEND ST_DONE,0
        mov al, byte ptr [control+1]
        and al, 3
        cmp al, 3
        CHECK_EQ
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_OUT
        mov word ptr [packet+RH_COUNT], 2
        cmp byte ptr [unit_table+U_AUDIO_STATE], 0
        CHECK_EQ
        cmp byte ptr [unit_table+U_AUDIO_RANGE], 0
        CHECK_EQ
        cmp byte ptr [unit_table+UNIT_ENTRY+U_AUDIO_STATE], 2
        CHECK_EQ
        mov byte ptr [fault], 2
        mov byte ptr [expected_value], 3
        SET_CONTROL 5,0
        SEND ST_DONE or ST_ERROR or ERR_NOT_READY,1
        EXPECT_LOCKS DOOR_OPEN
        mov byte ptr [fault], 0
        SEND ST_DONE,1
        EXPECT_LOCKS 0
else
        mov word ptr [packet+RH_IOCTL_PARAM+2], ax
        mov word ptr [packet+RH_IOCTL_PARAM], offset control-16
        mov byte ptr [packet+RH_IOCTL_CATEGORY], 8
        mov byte ptr [packet+RH_IOCTL_MINOR], 48h
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_QUERY
        mov byte ptr [unit_table+U_FLAGS], UF_REMOVABLE or UF_MEDIA
        mov byte ptr [unit_table+UNIT_SIZE+U_FLAGS], UF_REMOVABLE
        SEND ST_DONE,0
        mov byte ptr [packet+RH_COMMAND], CMD_GEN_IOCTL
        SET_CONTROL 2,0A5h
        SEND ST_DONE,0
        EXPECT_LOCKS 0
        cmp byte ptr [control+1], 0
        CHECK_EQ
        SET_CONTROL 0,0A5h
        SEND ST_DONE,1
        EXPECT_LOCKS 1
        cmp byte ptr [control+1], 1
        CHECK_EQ
        SEND ST_DONE,0
        EXPECT_LOCKS 2
        mov byte ptr [packet+RH_IOCTL_MINOR], 49h
        SEND ST_DONE or ST_ERROR or ERR_GENERAL,0
        EXPECT_LOCKS 2
        mov byte ptr [packet+RH_IOCTL_MINOR], 48h
        SET_CONTROL 1,0A5h
        SEND ST_DONE,0
        EXPECT_LOCKS 1
        mov byte ptr [expected_value], 0
        mov byte ptr [fault], 5
        SET_CONTROL 1,0A5h
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,1
        EXPECT_LOCKS 1
        cmp byte ptr [control+1], 0A5h
        CHECK_EQ
        mov byte ptr [fault], 0
        SEND ST_DONE,1
        EXPECT_LOCKS 0
        SEND ST_DONE or ST_ERROR or ERR_GENERAL,0
        SET_CONTROL 0,0A5h
        mov byte ptr [expected_value], 1
        mov byte ptr [fault], 5
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,1
        EXPECT_LOCKS 0
        mov byte ptr [fault], 2
        SEND ST_DONE or ST_ERROR or ERR_NOT_READY,1
        mov byte ptr [fault], 3
        SEND ST_DONE or ST_ERROR or ERR_READ,1
        mov byte ptr [fault], 0FFh
        SEND ST_DONE or ST_ERROR or ERR_GENERAL,1
        EXPECT_LOCKS 0
        cmp byte ptr [control+1], 0A5h
        CHECK_EQ
        mov byte ptr [fault], 0
        mov byte ptr [unit_table+U_LOCKS], 0FFh
        SEND ST_DONE or ST_ERROR or ERR_GENERAL,0
        EXPECT_LOCKS 0FFh
        mov byte ptr [packet+RH_UNIT], 1
        SET_CONTROL 2,0A5h
        SEND ST_DONE,0
        cmp byte ptr [control+1], 0
        CHECK_EQ
        mov byte ptr [packet+RH_UNIT], 0
        mov byte ptr [unit_table+U_LOCKS], 0
        SET_CONTROL 3,0A5h
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        mov word ptr [packet+RH_IOCTL_PARAM], 0FFFFh
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        mov word ptr [packet+RH_IOCTL_PARAM], 0
        mov word ptr [packet+RH_IOCTL_PARAM+2], 0
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        ; Eject accepts a NULL parameter pointer, invalidates BPB only on success.
        mov byte ptr [packet+RH_IOCTL_MINOR], 49h
        mov byte ptr [expected_opcode], 1Bh
        mov byte ptr [expected_value], 2
        mov byte ptr [fault], 2
        SEND ST_DONE or ST_ERROR or ERR_NOT_READY,1
        test byte ptr [unit_table+U_FLAGS], UF_MEDIA
        jnz still_media
        jmp failed
still_media:
        mov byte ptr [fault], 0
        SEND ST_DONE,1
        test byte ptr [unit_table+U_FLAGS], UF_MEDIA
        CHECK_EQ
        ; Fixed units do not advertise or execute these operations.
        mov byte ptr [unit_table+U_FLAGS], 0
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_QUERY
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        mov byte ptr [packet+RH_IOCTL_MINOR], 48h
        SEND ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD,0
        ; EDR query layout and standard query must agree without ASPI traffic.
        mov byte ptr [unit_table+U_FLAGS], UF_REMOVABLE
        mov byte ptr [packet+RH_LENGTH], 16h
        mov byte ptr [packet+RH_MEDIA], 0
        mov word ptr [packet+RH_COUNT], 0848h
        SEND ST_DONE,0
        cmp word ptr [packet+RH_COUNT], 0
        CHECK_EQ
        mov word ptr [packet+RH_COUNT], 0849h
        SEND ST_DONE,0
endif
        mov dx, offset ok
        mov ah, 9
        int 21h
        mov ax, 4C00h
        int 21h
failed:
        mov dx, offset failure
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
        cmp byte ptr cs:[srb+SRB_Cmd], SC_EXEC_SCSI_CMD
        jne fake_bad
        mov al, byte ptr cs:[packet+RH_UNIT]
        cmp byte ptr cs:[srb+SRB_Target], al
        jne fake_bad
        mov al, byte ptr cs:[expected_opcode]
        cmp byte ptr cs:[srb+SRB_CDB], al
        jne fake_bad
        mov al, byte ptr cs:[expected_value]
        cmp byte ptr cs:[srb+SRB_CDB+4], al
        jne fake_bad
        cmp byte ptr cs:[srb+SRB_CDBLen], 6
        jne fake_bad
        cmp byte ptr cs:[srb+SRB_Flags], SRB_DIR_NONE
        jne fake_bad
        cmp word ptr cs:[srb+SRB_BufLen], 0
        jne fake_bad
        cmp word ptr cs:[srb+SRB_BufLen+2], 0
        jne fake_bad
        cmp word ptr cs:[srb+SRB_BufPointer], 0
        jne fake_bad
        cmp word ptr cs:[srb+SRB_BufPointer+2], 0
        jne fake_bad
        cmp word ptr cs:[srb+SRB_CDB+1], 0
        jne fake_bad
        cmp byte ptr cs:[srb+SRB_CDB+3], 0
        jne fake_bad
        cmp byte ptr cs:[srb+SRB_CDB+5], 0
        jne fake_bad
        mov al, byte ptr cs:[fault]
        or al, al
        jnz fake_error
        mov byte ptr cs:[srb+SRB_Status], SS_COMP
        ret
fake_bad:
        mov byte ptr cs:[bad], 1
        mov al, 5
fake_error:
        mov byte ptr cs:[srb+SRB_Status], SS_ERR
        cmp al, 0FFh
        je fake_done
        mov byte ptr cs:[srb+SRB_TargStat], 2
        mov byte ptr cs:[srb+SRB_CDB+6],70h
        mov byte ptr cs:[srb+SRB_CDB+6+7],6
        mov byte ptr cs:[srb+SRB_CDB+6+2], al
fake_done:
        ret
fake_aspi endp
ifdef TEST_CDA
finish_fixture macro
        include drivers/aspicda/aspicda.asm
endm
else
finish_fixture macro
        end test_start
endm
endif
        finish_fixture
