; Stateful tests of the real ASPICDA strategy/interrupt. Memory-only ASPI;
; no installed manager, physical drive or audio output is used.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h
        jmp test_start
ASPICDA_TEST equ 1
DRIVER_ENTRY textequ <test_start>
ASSERT_EQ macro
        local ok
        je ok
        jmp test_fail
ok:
endm
BAD_NE macro
        local ok
        je ok
        mov byte ptr cs:[bad], 1
ok:
endm
SEND macro status
        mov word ptr [expected], status
        call send_request
endm
COMMAND macro command, status
        mov al, command
        call prepare_request
        SEND status
endm
PLAY macro status
        mov al, CMD_PLAY_AUDIO
        call prepare_request
        mov ax, word ptr [desired_start]
        mov word ptr [packet+RH_CD_PLAYSTART], ax
        mov word ptr [packet+RH_CD_PLAYCOUNT], 75
        SEND status
endm
QUERY macro function, status
        mov al, function
        call prepare_ioctl
        SEND status
endm
TRAY macro function, status
        mov al, function
        call prepare_ioctl
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_OUT
        SEND status
endm
CHECK_STATE macro unit, state
        cmp byte ptr [unit_table+unit*UNIT_ENTRY+U_AUDIO_STATE], state
        ASSERT_EQ
endm
CHECK_RANGE macro paused, start_second, start_frame, end_second
        cmp word ptr [control+1], paused
        ASSERT_EQ
        cmp byte ptr [control+3], start_frame
        ASSERT_EQ
        cmp byte ptr [control+4], start_second
        ASSERT_EQ
        cmp word ptr [control+5], 0
        ASSERT_EQ
        cmp word ptr [control+7], end_second shl 8
        ASSERT_EQ
        cmp word ptr [control+9], 0
        ASSERT_EQ
endm

packet db 32 dup (0)
guard_before db 0A5h
control db 11 dup (0A5h)
guard_after db 0A5h
strategy_ptr dw strategy,0
interrupt_ptr dw interrupt,0
expected dw 0
step dw 0
bad db 0
test_unit db 0
desired_start dw 75
hardware_state db 15h,15h
fault_opcode db 0
fault_sense db 5
bad_position db 0
tur_sense db 0
control_calls dw 0
query_calls dw 0
calls_before dw 0
msg_pass db 'ASPICDA per-unit audio state/busy/failure tests passed',13,10,'$'
msg_fail db 'ASPICDA audio state regression FAILED at step $'

test_start:
        push cs
        pop ds
        push cs
        pop es
        cld
        mov word ptr [strategy_ptr+2], cs
        mov word ptr [interrupt_ptr+2], cs
        mov word ptr [aspi_entry], offset fake_aspi
        mov word ptr [aspi_entry+2], cs
        mov byte ptr [unit_count], 2
        mov byte ptr [unit_table+UNIT_ENTRY+1], 1
        QUERY 15,0100h
        CHECK_RANGE 0,0,0,0
        COMMAND CMD_RESUME_AUDIO,8103h
        COMMAND CMD_STOP_AUDIO,0100h
        cmp word ptr [query_calls], 0
        ASSERT_EQ
        cmp word ptr [control_calls], 0
        ASSERT_EQ
        PLAY 0100h
        CHECK_STATE 0,1
        QUERY 15,0300h
        CHECK_RANGE 0,3,0,4
        QUERY 6,0300h
        mov ax, word ptr [control+1]
        and ax, 0400h
        cmp ax, 0400h
        ASSERT_EQ
        COMMAND CMD_OPEN,0300h
        COMMAND CMD_CLOSE,0300h
        COMMAND CMD_INPUT_FLUSH,0300h
        mov ax, word ptr [control_calls]
        mov word ptr [calls_before], ax
        PLAY 8302h                         ; cannot replace active audio
        mov ax, word ptr [control_calls]
        cmp ax, word ptr [calls_before]
        ASSERT_EQ
        mov al, 15
        call prepare_ioctl
        mov word ptr [packet+RH_COUNT], 10
        SEND 8105h                         ; no stale busy on next error
        call check_unchanged
        mov byte ptr [fault_opcode], 4Bh
        COMMAND CMD_STOP_AUDIO,8108h
        CHECK_STATE 0,1
        mov byte ptr [fault_opcode], 0
        QUERY 15,0300h
        CHECK_RANGE 0,3,0,4
        COMMAND CMD_STOP_AUDIO,0100h
        CHECK_STATE 0,2
        QUERY 15,0100h
        CHECK_RANGE 1,3,30,4               ; saved resume position
        QUERY 6,0100h
        mov ax, word ptr [control+1]
        and ax, 0400h
        cmp ax, 0
        ASSERT_EQ
        mov byte ptr [fault_opcode], 4Bh
        COMMAND CMD_RESUME_AUDIO,8108h
        CHECK_STATE 0,2
        mov byte ptr [fault_opcode], 0
        COMMAND CMD_RESUME_AUDIO,0100h
        CHECK_STATE 0,1
        QUERY 15,0300h
        CHECK_RANGE 0,3,30,4
        mov byte ptr [bad_position], 1
        QUERY 15,810Ch
        call check_unchanged
        CHECK_STATE 0,1
        mov byte ptr [bad_position], 2
        QUERY 15,810Ch                     ; malformed status header
        call check_unchanged
        CHECK_STATE 0,1
        mov byte ptr [bad_position], 0
        mov byte ptr [fault_opcode], 42h
        COMMAND CMD_OPEN,8108h
        CHECK_STATE 0,1
        mov byte ptr [fault_opcode], 0
        mov byte ptr [hardware_state], 13h
        QUERY 15,0100h                     ; completion, no current Q data
        CHECK_RANGE 0,3,30,4
        CHECK_STATE 0,0
        COMMAND CMD_OPEN,0100h
        COMMAND CMD_RESUME_AUDIO,8103h

        ; Failed PLAY must retain the old completed range.
        mov byte ptr [fault_opcode], 47h
        mov word ptr [desired_start], 150
        PLAY 8108h
        CHECK_STATE 0,0
        mov byte ptr [fault_opcode], 0
        QUERY 15,0100h
        CHECK_RANGE 0,3,30,4
        mov word ptr [desired_start], 75
        PLAY 0100h
        mov byte ptr [test_unit], 1
        mov word ptr [desired_start], 150
        PLAY 0100h
        QUERY 15,0300h
        CHECK_RANGE 0,4,0,5
        COMMAND CMD_STOP_AUDIO,0100h
        CHECK_STATE 1,2
        QUERY 15,0100h
        CHECK_RANGE 1,4,30,5
        mov byte ptr [test_unit], 0
        QUERY 15,0300h
        CHECK_RANGE 0,3,0,4
        CHECK_STATE 0,1
        mov byte ptr [test_unit], 1
        mov byte ptr [fault_opcode], 1Bh
        TRAY 0,8108h                       ; failed eject keeps pause/range
        CHECK_STATE 1,2
        mov byte ptr [fault_opcode], 0
        TRAY 0,0100h
        CHECK_STATE 1,0
        QUERY 15,0100h
        CHECK_RANGE 0,0,0,0
        CHECK_STATE 0,1
        mov byte ptr [test_unit], 0
        mov byte ptr [fault_opcode], 42h
        mov byte ptr [fault_sense], 2
        QUERY 15,8102h                     ; lost medium invalidates resume
        call check_unchanged
        CHECK_STATE 0,0
        mov byte ptr [fault_opcode], 0
        mov byte ptr [fault_sense], 5
        COMMAND CMD_RESUME_AUDIO,8103h
        QUERY 15,0100h
        CHECK_RANGE 0,0,0,0

        ; Second STOP discards a paused range, without sending another PAUSE.
        mov word ptr [desired_start], 75
        PLAY 0100h
        COMMAND CMD_STOP_AUDIO,0100h
        mov ax, word ptr [control_calls]
        mov word ptr [calls_before], ax
        COMMAND CMD_STOP_AUDIO,0100h
        mov ax, word ptr [control_calls]
        cmp ax, word ptr [calls_before]
        ASSERT_EQ
        CHECK_STATE 0,0
        QUERY 15,0100h
        CHECK_RANGE 0,0,0,0
        COMMAND CMD_RESUME_AUDIO,8103h
        PLAY 0100h
        mov byte ptr [hardware_state], 0   ; unsupported status, no fake idle
        QUERY 15,8103h
        call check_unchanged
        CHECK_STATE 0,1
        mov byte ptr [hardware_state], 0FFh
        QUERY 15,810Ch
        call check_unchanged
        CHECK_STATE 0,1
        mov byte ptr [hardware_state], 14h ; stopped due to error: not busy
        QUERY 15,0100h
        CHECK_STATE 0,0
        PLAY 0100h
        mov byte ptr [hardware_state], 15h
        QUERY 15,0100h
        CHECK_STATE 0,0
        PLAY 0100h
        mov byte ptr [fault_opcode], 1Bh
        TRAY 5,8108h
        CHECK_STATE 0,1
        mov byte ptr [fault_opcode], 0
        TRAY 5,0100h
        CHECK_STATE 0,0
        QUERY 15,0100h
        CHECK_RANGE 0,0,0,0
        PLAY 0100h
        mov byte ptr [fault_opcode], 42h
        mov byte ptr [fault_sense], 6
        QUERY 15,810Fh                     ; replacement medium: no old resume
        call check_unchanged
        CHECK_STATE 0,0
        mov byte ptr [fault_opcode], 0
        mov byte ptr [fault_sense], 5
        COMMAND CMD_RESUME_AUDIO,8103h
        QUERY 15,0100h
        CHECK_RANGE 0,0,0,0
        ; Media-change queries consume the same notifications as audio/UPC.
        PLAY 0100h
        COMMAND CMD_STOP_AUDIO,0100h
        mov byte ptr [tur_sense], 6
        QUERY 9,0100h
        cmp byte ptr [control+1], 0FFh
        ASSERT_EQ
        CHECK_STATE 0,0
        cmp byte ptr [unit_table+U_AUDIO_RANGE], 0
        ASSERT_EQ
        COMMAND CMD_RESUME_AUDIO,8103h
        PLAY 0100h
        mov byte ptr [tur_sense], 2
        QUERY 9,0100h
        cmp byte ptr [control+1], 0
        ASSERT_EQ
        CHECK_STATE 0,0
        cmp byte ptr [unit_table+U_AUDIO_RANGE], 0
        ASSERT_EQ
        mov byte ptr [tur_sense], 0
        mov dx, offset msg_pass
        mov ah, 09h
        int 21h
        mov ax, 4C00h
        int 21h

prepare_request proc near
        push ax
        mov di, offset packet
        mov cx, 32
        xor al, al
        rep stosb
        pop ax
        mov byte ptr [packet+RH_COMMAND], al
        mov byte ptr [packet+RH_LENGTH], 22
        mov al, byte ptr [test_unit]
        mov byte ptr [packet+RH_UNIT], al
        ret
prepare_request endp

prepare_ioctl proc near
        push ax
        mov al, CMD_IOCTL_IN
        call prepare_request
        mov di, offset guard_before
        mov cx, 13
        mov al, 0A5h
        rep stosb
        pop ax
        mov byte ptr [control], al
        mov word ptr [packet+RH_COUNT], 11
        mov word ptr [packet+RH_BUFFER], offset control-16
        mov ax, cs
        inc ax
        mov word ptr [packet+RH_BUFFER+2], ax
        ret
prepare_ioctl endp

send_request proc near
        inc word ptr [step]
        mov bx, offset packet
        call dword ptr [strategy_ptr]
        call dword ptr [interrupt_ptr]
        mov ax, word ptr [packet+RH_STATUS]
        cmp ax, word ptr [expected]
        ASSERT_EQ
        cmp byte ptr [bad], 0
        ASSERT_EQ
        cmp byte ptr [guard_before], 0A5h
        ASSERT_EQ
        cmp byte ptr [guard_after], 0A5h
        ASSERT_EQ
        ret
send_request endp

check_unchanged proc near
        mov di, offset control+1
        mov cx, 10
unchanged_next:
        cmp byte ptr [di], 0A5h
        ASSERT_EQ
        inc di
        loop unchanged_next
        ret
check_unchanged endp

test_fail:
        mov dx, offset msg_fail
        mov ah, 09h
        int 21h
        mov bx, word ptr [step]
        call print_hex
        mov bx, word ptr [packet+RH_STATUS]
        call print_hex
        mov ax, 4C01h
        int 21h
print_hex proc near
        mov cx, 4
hex_next:
        push cx
        mov cl, 4
        rol bx, cl
        pop cx
        mov dl, bl
        and dl, 0Fh
        add dl, '0'
        cmp dl, '9'
        jbe hex_emit
        add dl, 'A'-'9'-1
hex_emit:
        mov ah, 02h
        int 21h
        loop hex_next
        mov dl, ' '
        mov ah, 02h
        int 21h
        ret
print_hex endp

fake_aspi proc far
        xor bx, bx
        mov bl, byte ptr cs:[srb+SRB_Target]
        cmp bl, byte ptr cs:[test_unit]
        BAD_NE
        cmp bl, 1
        jbe fake_unit_ok
        mov byte ptr cs:[bad], 1
        xor bx, bx
fake_unit_ok:
        mov al, byte ptr cs:[srb+SRB_CDB]
        cmp byte ptr cs:[fault_opcode], 0
        je fake_dispatch
        cmp al, byte ptr cs:[fault_opcode]
        jne fake_dispatch
        mov al, byte ptr cs:[fault_sense]
        jmp fake_error
fake_dispatch:
        or al, al
        jnz fake_non_tur
        mov al, byte ptr cs:[tur_sense]
        or al, al
        jnz fake_tur_error
        jmp fake_success
fake_tur_error:
        jmp fake_error
fake_non_tur:
        cmp al, 5Ah                         ; optional channel-capability probe
        jne fake_dispatch_audio
        mov al, 5
        jmp fake_error
fake_dispatch_audio:
        cmp al, 42h
        je fake_query
        jmp fake_control
fake_query:
        inc word ptr cs:[query_calls]
        cmp byte ptr cs:[srb+SRB_Flags], SRB_DIR_IN
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+1], 2
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+2], 40h
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+3], 1
        BAD_NE
        cmp word ptr cs:[srb+SRB_BufLen], 16
        BAD_NE
        mov al, byte ptr cs:[hardware_state+bx]
        mov byte ptr cs:[sub_position], 0
        mov byte ptr cs:[sub_position+1], al
        cmp al, 11h
        je fake_position
        cmp al, 12h
        je fake_position
        ; Terminal replies intentionally have no valid current-Q payload.
        mov word ptr cs:[sub_position+2], 0
        jmp fake_success
fake_position:
        mov word ptr cs:[sub_position+2], 0C00h
        mov word ptr cs:[sub_position+4], 1001h
        mov word ptr cs:[sub_position+6], 0101h
        mov word ptr cs:[sub_position+8], 0
        mov byte ptr cs:[sub_position+10], 3
        add byte ptr cs:[sub_position+10], bl
        mov byte ptr cs:[sub_position+11], 30
        mov word ptr cs:[sub_position+12], 0
        mov word ptr cs:[sub_position+14], 1E01h
        cmp byte ptr cs:[bad_position], 2
        jne fake_check_position
        mov word ptr cs:[sub_position+2], 0B00h
fake_check_position:
        cmp byte ptr cs:[bad_position], 1
        jne fake_position_ok
        mov byte ptr cs:[sub_position+10], 60
fake_position_ok:
        jmp fake_success
fake_control:
        inc word ptr cs:[control_calls]
        cmp byte ptr cs:[srb+SRB_Flags], SRB_DIR_NONE
        BAD_NE
        cmp word ptr cs:[srb+SRB_BufLen], 0
        BAD_NE
        cmp word ptr cs:[srb+SRB_BufLen+2], 0
        BAD_NE
        cmp al, 47h
        jne fake_pause
        mov byte ptr cs:[hardware_state+bx], 11h
        jmp short fake_success
fake_pause:
        cmp al, 4Bh
        jne fake_tray
        mov al, byte ptr cs:[srb+SRB_CDB+8]
        cmp al, 1
        jbe fake_pause_ok
        mov byte ptr cs:[bad], 1
fake_pause_ok:
        mov byte ptr cs:[hardware_state+bx], 12h
        or al, al
        jz fake_success
        mov byte ptr cs:[hardware_state+bx], 11h
        jmp short fake_success
fake_tray:
        cmp al, 1Bh
        BAD_NE
        mov byte ptr cs:[hardware_state+bx], 15h
fake_success:
        mov byte ptr cs:[srb+SRB_Status], SS_COMP
        ret
fake_error:
        mov byte ptr cs:[srb+SRB_Status], SS_ERR
        mov byte ptr cs:[srb+SRB_TargStat], 2
        xor bx, bx
        mov bl, byte ptr cs:[srb+SRB_CDBLen]
        mov byte ptr cs:[srb+SRB_CDB+bx],70h
        mov byte ptr cs:[srb+SRB_CDB+bx+7],6
        mov byte ptr cs:[srb+SRB_CDB+bx+2], al
        ret
fake_aspi endp

        include drivers/aspicda/aspicda.asm
