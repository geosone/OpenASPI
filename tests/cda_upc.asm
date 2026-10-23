; Real driver/far entry points against memory ASPI, followed by installed
; SHSUCDX forwarding checks on the disposable QEMU CD image (no MCN).
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
CASE macro fault,unit,bytes,header,pointer,state,status,count
        db fault,unit,bytes,header,pointer,state
        dw status,count
endm
packet db 32 dup (0)
guard_before db 0A5h
control db 14,10 dup (0A5h)
guard_after db 0A5h
calls dw 0
bad db 0
case_ptr dw 0
strategy_ptr dw strategy,0
interrupt_ptr dw interrupt,0
saved_mode db 0
test_mode db 0
code0 db '0123456789012'
code1 db '9876543210987'
result0 db 42h,01h,23h,45h,67h,89h,01h,20h,0,74h
result1 db 12h,98h,76h,54h,32h,10h,98h,70h,0,10h
msg_pass db 'ASPICDA UPC/MCVAL/BCD/error/guard tests passed',13,10,'$'
msg_forward db 'SHSUCDX UPC forwarding in analog/digital modes passed',13,10,'$'
msg_fail db 'ASPICDA UPC regression FAILED (case/status) $'
cases:
        CASE 0,0,11,20,0,0,0100h,2
        CASE 0,1,11,20,0,0,0100h,2
        CASE 0,0,11,20,0,1,0300h,2
        CASE 1,0,11,20,0,2,8108h,1     ; MCVAL clear must not discard pause
        CASE 2,0,11,20,0,0,8108h,1     ; all ASCII zero = no code
        CASE 3,0,11,20,0,0,810Ch,1     ; short declared response
        CASE 4,0,11,20,0,0,810Ch,1     ; too long declared response
        CASE 5,0,11,20,0,0,810Ch,1     ; wrong format
        CASE 6,0,11,20,0,0,810Ch,1     ; invalid first digit
        CASE 7,0,11,20,0,0,810Ch,1     ; invalid final digit
        CASE 8,0,11,20,0,0,810Ch,1     ; reserved zero field
        CASE 9,0,11,20,0,0,810Ch,1     ; AFRAME above 74
        CASE 10,0,11,20,0,0,810Ch,1    ; no reply (no stale MCN)
        CASE 11,0,11,20,0,0,810Ch,1    ; partial ASCII reply
        CASE 12,0,11,20,0,0,810Ch,1    ; reserved MCVAL flags
        CASE 13,0,11,20,0,0,810Ch,1    ; reserved header
        CASE 14,0,11,20,0,0,810Ch,1    ; reserved format field
        CASE 15,0,11,20,0,0,8108h,1    ; MCN unsupported
        CASE 16,0,11,20,0,2,8102h,1    ; no medium clears saved audio
        CASE 17,0,11,20,0,2,8108h,2    ; CONTROL failure retains saved audio
        CASE 18,0,11,20,0,0,810Ch,2    ; CONTROL reply malformed
        CASE 19,0,11,20,0,0,810Ch,2    ; CONTROL reply missing
        CASE 20,0,11,20,0,2,810Fh,1    ; medium replaced clears saved audio
        CASE 21,0,11,20,0,2,8102h,2    ; medium lost during CONTROL query
        CASE 0,0,10,20,0,0,8105h,0     ; short block
        CASE 0,0,11,19,0,0,8105h,0     ; short header
        CASE 0,0,11,20,1,0,8105h,0     ; null pointer
        CASE 0,0,11,20,2,0,8105h,0     ; segment crossing
cases_end:
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
        mov word ptr [case_ptr], offset cases
test_next:
        call prepare_packet
        mov si, word ptr [case_ptr]
        mov al, byte ptr [si+1]
        mov byte ptr [packet+RH_UNIT], al
        mov al, byte ptr [si+2]
        xor ah, ah
        mov word ptr [packet+RH_COUNT], ax
        mov al, byte ptr [si+3]
        mov byte ptr [packet+RH_LENGTH], al
        mov al, byte ptr [si+5]
        mov byte ptr [unit_table+U_AUDIO_STATE], al
        mov byte ptr [unit_table+UNIT_ENTRY+U_AUDIO_STATE], al
        mov byte ptr [unit_table+U_AUDIO_RANGE], 1
        mov byte ptr [unit_table+UNIT_ENTRY+U_AUDIO_RANGE], 1
        mov word ptr [unit_table+U_AUDIO_START], 0300h
        mov word ptr [unit_table+U_AUDIO_END], 0400h
        mov word ptr [unit_table+UNIT_ENTRY+U_AUDIO_START], 0300h
        mov word ptr [unit_table+UNIT_ENTRY+U_AUDIO_END], 0400h
        cmp byte ptr [si+4], 1
        jne not_null
        mov word ptr [packet+RH_BUFFER], 0
        mov word ptr [packet+RH_BUFFER+2], 0
not_null:
        cmp byte ptr [si+4], 2
        jne packet_ready
        mov word ptr [packet+RH_BUFFER], 0FFFAh
        mov ax, cs
        sub ax, 100h                     ; far alias away from COM caller stack
        mov word ptr [packet+RH_BUFFER+2], ax
        mov es, ax
        mov byte ptr es:[0FFFAh], 14
        mov byte ptr es:[0FFFBh], 0A5h
        push cs
        pop es
packet_ready:
        mov bx, offset packet
        call dword ptr [strategy_ptr]
        call dword ptr [interrupt_ptr]
        mov si, word ptr [case_ptr]
        mov ax, word ptr [packet+RH_STATUS]
        cmp ax, word ptr [si+6]
        ASSERT_EQ
        mov ax, word ptr [calls]
        cmp ax, word ptr [si+8]
        ASSERT_EQ
        cmp byte ptr [bad], 0
        ASSERT_EQ
        call check_guards
        cmp word ptr [si+6], 8102h
        je check_lost_media
        cmp word ptr [si+6], 810Fh
        jne check_retained_audio
check_lost_media:
        cmp byte ptr [unit_table+U_AUDIO_STATE], 0
        ASSERT_EQ
        cmp byte ptr [unit_table+U_AUDIO_RANGE], 0
        ASSERT_EQ
        cmp word ptr [unit_table+U_AUDIO_START], 0
        ASSERT_EQ
        cmp word ptr [unit_table+U_AUDIO_END], 0
        ASSERT_EQ
        mov al, byte ptr [si+5]
        cmp byte ptr [unit_table+UNIT_ENTRY+U_AUDIO_STATE], al
        ASSERT_EQ
        cmp word ptr [unit_table+UNIT_ENTRY+U_AUDIO_START], 0300h
        ASSERT_EQ
        cmp word ptr [unit_table+UNIT_ENTRY+U_AUDIO_END], 0400h
        ASSERT_EQ
        jmp short check_audio_done
check_retained_audio:
        mov al, byte ptr [si+5]
        cmp byte ptr [unit_table+U_AUDIO_STATE], al
        ASSERT_EQ
        cmp byte ptr [unit_table+UNIT_ENTRY+U_AUDIO_STATE], al
        ASSERT_EQ
check_audio_done:
        cmp byte ptr [si+4], 2
        jne wrap_checked
        mov ax, word ptr [packet+RH_BUFFER+2]
        mov es, ax
        cmp byte ptr es:[0FFFBh], 0A5h
        push cs
        pop es
        ASSERT_EQ
wrap_checked:
        test word ptr [packet+RH_STATUS], ST_ERROR
        jz compare_success
        call check_unchanged
        jmp short case_done
compare_success:
        mov bx, offset result0
        cmp byte ptr [si+1], 0
        je compare_ready
        mov bx, offset result1
compare_ready:
        mov di, offset control+1
        mov cx, 10
compare_next:
        mov al, byte ptr [bx]
        cmp al, byte ptr [di]
        ASSERT_EQ
        inc bx
        inc di
        loop compare_next
case_done:
        add word ptr [case_ptr], 10
        cmp word ptr [case_ptr], offset cases_end
        jae tests_done
        jmp test_next
tests_done:
        mov dx, offset msg_pass
        mov ah, 09h
        int 21h
        ; Installed QEMU data CD has no usable MCN. Check that SHSUCDX
        ; forwards this IOCTL and preserves the error/output in both modes.
        mov ax, 15FFh
        mov bx, 0CDDAh
        mov cx, 1
        int 2Fh
        cmp ax, 0CDDAh
        ASSERT_EQ
        mov byte ptr [saved_mode], bl
forward_next:
        mov dl, byte ptr [test_mode]
        call set_audio_mode
        call prepare_packet
        mov bx, offset packet
        mov cx, 'R'-'A'
        mov ax, 1510h
        int 2Fh
        jnc forwarding_called
        jmp test_fail
forwarding_called:
        cmp word ptr [packet+RH_STATUS], 8108h
        ASSERT_EQ
        call check_unchanged
        call check_guards
        inc byte ptr [test_mode]
        cmp byte ptr [test_mode], 2
        jb forward_next
        mov dl, byte ptr [saved_mode]
        call set_audio_mode
        mov dx, offset msg_forward
        mov ah, 09h
        int 21h
        mov ax, 4C00h
        int 21h

prepare_packet proc near
        mov di, offset packet
        mov cx, 32
        xor al, al
        rep stosb
        mov di, offset guard_before
        mov cx, 13
        mov al, 0A5h
        rep stosb
        mov byte ptr [control], 14
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_IN
        mov byte ptr [packet+RH_LENGTH], 20
        mov word ptr [packet+RH_COUNT], 11
        mov word ptr [packet+RH_BUFFER], offset control-16
        mov ax, cs
        inc ax
        mov word ptr [packet+RH_BUFFER+2], ax
        mov word ptr [calls], 0
        mov byte ptr [bad], 0
        ret
prepare_packet endp
check_guards proc near
        cmp byte ptr [guard_before], 0A5h
        ASSERT_EQ
        cmp byte ptr [guard_after], 0A5h
        ASSERT_EQ
        cmp byte ptr [control], 14
        ASSERT_EQ
        ret
check_guards endp
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
set_audio_mode proc near
        mov ax, 15FFh
        mov bx, 0CDDAh
        mov cx, 2
        int 2Fh
        cmp ax, 0CDDAh
        ASSERT_EQ
        ret
set_audio_mode endp
test_fail:
        mov dx, offset msg_fail
        mov ah, 09h
        int 21h
        mov bx, word ptr [case_ptr]
        sub bx, offset cases
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
        inc word ptr cs:[calls]
        mov si, word ptr cs:[case_ptr]
        mov al, byte ptr cs:[si+1]
        cmp byte ptr cs:[srb+SRB_Target], al
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB], 42h
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDBLen], 10
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+2], 40h
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+6], 0
        BAD_NE
        cmp byte ptr cs:[srb+SRB_Flags], SRB_DIR_IN
        BAD_NE
        mov ax, cs
        cmp word ptr cs:[srb+SRB_BufPointer+2], ax
        BAD_NE
        mov al, byte ptr cs:[si]
        cmp byte ptr cs:[srb+SRB_CDB+3], 2
        je fake_mcn
        jmp fake_position
fake_mcn:
        cmp word ptr cs:[calls], 1
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+1], 0
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+8], 24
        BAD_NE
        cmp word ptr cs:[srb+SRB_BufLen], 24
        BAD_NE
        cmp word ptr cs:[srb+SRB_BufPointer], offset mcn_data
        BAD_NE
        cmp al, 15
        jne mcn_not_illegal
        mov al, 5
        jmp fake_error
mcn_not_illegal:
        cmp al, 16
        jne mcn_not_absent
        mov al, 2
        jmp fake_error
mcn_not_absent:
        cmp al, 20
        jne mcn_not_changed
        mov al, 6
        jmp fake_error
mcn_not_changed:
        cmp al, 10
        jne mcn_reply
        jmp fake_success
mcn_reply:
        push cs
        pop es
        mov di, offset mcn_data
        mov cx, 24
        xor al, al
        rep stosb
        mov word ptr cs:[mcn_data+2], 1400h
        mov byte ptr cs:[mcn_data+4], 2
        mov byte ptr cs:[mcn_data+8], 80h
        mov di, offset mcn_data+9
        mov bx, si                         ; save case pointer across code copy
        mov si, offset code0
        cmp byte ptr cs:[bx+1], 0
        je mcn_copy
        mov si, offset code1
mcn_copy:
        mov cx, 13
        rep movsb
        mov si, bx
        mov byte ptr cs:[mcn_data+23], 74
        cmp byte ptr cs:[si+1], 0
        je mcn_faults
        mov byte ptr cs:[mcn_data+23], 10
mcn_faults:
        mov al, byte ptr cs:[si]
        cmp al, 1
        jne fault2
        mov byte ptr cs:[mcn_data+8], 0
        mov byte ptr cs:[mcn_data+9], 'X'     ; invalid field ignored when MCVAL=0
fault2:
        cmp al, 2
        jne fault3
        mov di, offset mcn_data+9
        mov cx, 13
        push ax
        mov al, '0'
        rep stosb
        pop ax
fault3:
        cmp al, 3
        jne fault4
        mov byte ptr cs:[mcn_data+3], 19
fault4:
        cmp al, 4
        jne fault5
        mov byte ptr cs:[mcn_data+3], 21
fault5:
        cmp al, 5
        jne fault6
        mov byte ptr cs:[mcn_data+4], 1
fault6:
        cmp al, 6
        jne fault7
        mov byte ptr cs:[mcn_data+9], '/'
fault7:
        cmp al, 7
        jne fault8
        mov byte ptr cs:[mcn_data+21], ':'
fault8:
        cmp al, 8
        jne fault9
        mov byte ptr cs:[mcn_data+22], 1
fault9:
        cmp al, 9
        jne fault11
        mov byte ptr cs:[mcn_data+23], 75
fault11:
        cmp al, 11
        jne fault12
        mov byte ptr cs:[mcn_data+21], 0FFh
fault12:
        cmp al, 12
        jne fault13
        mov byte ptr cs:[mcn_data+8], 81h
fault13:
        cmp al, 13
        jne fault14
        mov byte ptr cs:[mcn_data], 1
fault14:
        cmp al, 14
        jne mcn_done
        mov byte ptr cs:[mcn_data+5], 1
mcn_done:
        jmp fake_success
fake_position:
        cmp byte ptr cs:[srb+SRB_CDB+3], 1
        BAD_NE
        cmp word ptr cs:[calls], 2
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+1], 2
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+8], 16
        BAD_NE
        cmp word ptr cs:[srb+SRB_BufLen], 16
        BAD_NE
        cmp word ptr cs:[srb+SRB_BufPointer], offset sub_position
        BAD_NE
        cmp al, 17
        jne position_not_illegal
        mov al, 5
        jmp short fake_error
position_not_illegal:
        cmp al, 21
        jne position_medium_ready
        mov al, 2
        jmp short fake_error
position_medium_ready:
        cmp al, 19
        je fake_success
        mov word ptr cs:[sub_position], 1500h
        mov word ptr cs:[sub_position+2], 0C00h
        mov word ptr cs:[sub_position+4], 1401h
        mov word ptr cs:[sub_position+6], 0101h
        mov word ptr cs:[sub_position+8], 0
        mov word ptr cs:[sub_position+10], 0002h
        mov word ptr cs:[sub_position+12], 0
        mov word ptr cs:[sub_position+14], 0
        cmp byte ptr cs:[si+1], 0
        je position_fault
        mov byte ptr cs:[sub_position+5], 11h
position_fault:
        cmp al, 18
        jne fake_success
        mov byte ptr cs:[sub_position+4], 2
fake_success:
        mov byte ptr cs:[srb+SRB_Status], SS_COMP
        ret
fake_error:
        mov byte ptr cs:[srb+SRB_Status], SS_ERR
        mov byte ptr cs:[srb+SRB_TargStat], 2
        mov byte ptr cs:[srb+SRB_CDB+10],70h
        mov byte ptr cs:[srb+SRB_CDB+10+7],6
        mov byte ptr cs:[srb+SRB_CDB+12], al
        ret
fake_aspi endp

        include drivers/aspicda/aspicda.asm
