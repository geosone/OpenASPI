; Real ASPICDA strategy/interrupt; only memory-backed ASPI is used.
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
packet db 32 dup (0)
guard_before db 0A5h
control db 11 dup (0A5h)
guard_after db 0A5h
calls dw 0
bad db 0
case_ptr dw 0
strategy_ptr dw strategy,0
interrupt_ptr dw interrupt,0
msg_pass db 'ASPICDA head/Q-channel packet/error/guard tests passed',13,10,'$'
msg_fail db 'ASPICDA head/Q-channel regression FAILED',13,10,'$'
head_lba db 1,0,78h,56h,34h,12h,5 dup (0A5h)
head_msf db 1,1,56,34,12,0,5 dup (0A5h)
q_result db 12,41h,12h,12,0,1,2,0,12,34,56
q_leadout db 12,41h,0AAh,12,0,1,2,0,12,34,56
; function, head mode, header length, buffer count, fault, pointer kind,
; expected DOS status WORD, expected ASPI calls WORD (10 bytes/case).
cases:
        db 1,0,20,6,0,0
        dw 0100h,1
        db 1,1,20,6,0,0
        dw 0100h,1
        db 12,0A5h,20,11,0,0
        dw 0100h,1
        db 12,0A5h,20,11,1,0            ; ILLEGAL REQUEST
        dw 8108h,1
        db 1,0,20,6,2,0                ; no medium
        dw 8102h,1
        db 12,0A5h,20,11,3,0           ; short declared payload
        dw 810Ch,1
        db 12,0A5h,20,11,4,0           ; wrong format
        dw 810Ch,1
        db 12,0A5h,20,11,5,0           ; track zero
        dw 810Ch,1
        db 12,0A5h,20,11,6,0           ; invalid index
        dw 810Ch,1
        db 1,1,20,6,7,0                ; invalid absolute seconds
        dw 810Ch,1
        db 12,0A5h,20,11,8,0           ; invalid relative frames
        dw 810Ch,1
        db 12,0A5h,20,11,9,0           ; no returned data (no stale answer)
        dw 810Ch,1
        db 12,0A5h,20,11,10,0          ; missing MSF bytes
        dw 810Ch,1
        db 12,0A5h,20,11,11,0          ; reserved MSF byte nonzero
        dw 810Ch,1
        db 12,0A5h,20,11,12,0          ; invalid minutes
        dw 810Ch,1
        db 12,0A5h,20,11,13,0          ; lead-out marker retained
        dw 0100h,1
        db 12,0A5h,20,10,0,0           ; short control block
        dw 8105h,0
        db 1,0,20,5,0,0
        dw 8105h,0
        db 1,2,20,6,0,0                ; invalid head addressing mode
        dw 8103h,0
        db 12,0A5h,19,11,0,0           ; short request
        dw 8105h,0
        db 12,0A5h,20,0,0,0
        dw 8105h,0
        db 12,0A5h,20,11,0,1           ; null control block
        dw 8105h,0
        db 12,0A5h,20,11,0,2           ; control block crossing segment
        dw 8105h,0
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
        mov byte ptr [unit_count], 1
        mov word ptr [case_ptr], offset cases
test_next:
        mov di, offset packet
        mov cx, 32
        xor al, al
        rep stosb
        mov di, offset guard_before
        mov cx, 13
        mov al, 0A5h
        rep stosb
        mov word ptr [calls], 0
        mov byte ptr [bad], 0
        mov si, word ptr [case_ptr]
        mov al, byte ptr [si]
        mov byte ptr [control], al
        mov al, byte ptr [si+1]
        mov byte ptr [control+1], al
        mov al, byte ptr [si+2]
        mov byte ptr [packet+RH_LENGTH], al
        mov al, byte ptr [si+3]
        xor ah, ah
        mov word ptr [packet+RH_COUNT], ax
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_IN
        ; Non-CS far buffer, physically aliasing control.
        mov ax, cs
        inc ax
        mov word ptr [packet+RH_BUFFER+2], ax
        mov word ptr [packet+RH_BUFFER], offset control-16
        cmp byte ptr [si+5], 1
        jne not_null
        mov word ptr [packet+RH_BUFFER], 0
        mov word ptr [packet+RH_BUFFER+2], 0
not_null:
        cmp byte ptr [si+5], 2
        jne packet_ready
        mov word ptr [packet+RH_BUFFER], 0FFFAh
        ; Alias inside our COM allocation, away from the caller stack
        ; at CS:FFFE. The far offset still crosses a segment boundary.
        mov ax, cs
        sub ax, 100h
        mov word ptr [packet+RH_BUFFER+2], ax
        mov es, ax
        mov byte ptr es:[0FFFAh], 12
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
        cmp byte ptr [guard_before], 0A5h
        ASSERT_EQ
        cmp byte ptr [guard_after], 0A5h
        ASSERT_EQ
        cmp byte ptr [si+5], 2
        jne guards_done
        mov ax, word ptr [packet+RH_BUFFER+2]
        mov es, ax
        cmp byte ptr es:[0FFFBh], 0A5h
        push cs
        pop es
        ASSERT_EQ
guards_done:
        cmp word ptr [si+6], 0100h
        je compare_success
        mov ax, word ptr [control]
        cmp ax, word ptr [si]
        ASSERT_EQ
        mov di, offset control+2
        mov cx, 9
compare_unchanged:
        cmp byte ptr [di], 0A5h
        ASSERT_EQ
        inc di
        loop compare_unchanged
        jmp short case_done
compare_success:
        mov bx, offset head_lba
        cmp byte ptr [si+1], 0
        je expected_ready
        mov bx, offset head_msf
        cmp byte ptr [si], 1
        je expected_ready
        mov bx, offset q_result
        cmp byte ptr [si+4], 13
        jne expected_ready
        mov bx, offset q_leadout
expected_ready:
        mov di, offset control
        mov cx, 11
compare_result:
        mov al, byte ptr [bx]
        cmp al, byte ptr [di]
        ASSERT_EQ
        inc bx
        inc di
        loop compare_result
case_done:
        add word ptr [case_ptr], 10
        cmp word ptr [case_ptr], offset cases_end
        jae tests_done
        jmp test_next
tests_done:
        mov dx, offset msg_pass
        mov ah, 09h
        int 21h
        mov ax, 4C00h
        int 21h
test_fail:
        mov dx, offset msg_fail
        mov ah, 09h
        int 21h
        mov ax, word ptr [case_ptr]
        sub ax, offset cases
        call print_hex
        mov ax, word ptr [packet+RH_STATUS]
        call print_hex
        mov ax, word ptr [calls]
        call print_hex
        mov ax, word ptr [control]
        call print_hex
        mov ax, word ptr [control+2]
        call print_hex
        mov ax, word ptr [control+4]
        call print_hex
        mov ax, word ptr [control+8]
        call print_hex
        mov ax, 4C01h
        int 21h

print_hex proc near
        mov bx, ax
        mov cx, 4
print_digit:
        push cx
        mov cl, 4
        rol bx, cl
        pop cx
        mov dl, bl
        and dl, 0Fh
        add dl, '0'
        cmp dl, '9'
        jbe print_emit
        add dl, 'A'-'9'-1
print_emit:
        mov ah, 02h
        int 21h
        loop print_digit
        mov dl, ' '
        mov ah, 02h
        int 21h
        ret
print_hex endp

fake_aspi proc far
        inc word ptr cs:[calls]
        mov si, word ptr cs:[case_ptr]
        cmp byte ptr cs:[srb+SRB_CDB], 42h
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDBLen], 10
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+2], 40h
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+3], 1
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+8], 16
        BAD_NE
        mov al, 2
        cmp byte ptr cs:[si], 1
        jne mode_ready
        mov al, byte ptr cs:[si+1]
        shl al, 1
mode_ready:
        cmp byte ptr cs:[srb+SRB_CDB+1], al
        BAD_NE
        cmp byte ptr cs:[srb+SRB_Flags], SRB_DIR_IN
        BAD_NE
        cmp word ptr cs:[srb+SRB_BufLen], 16
        BAD_NE
        cmp word ptr cs:[srb+SRB_BufPointer], offset sub_position
        BAD_NE
        mov ax, cs
        cmp word ptr cs:[srb+SRB_BufPointer+2], ax
        BAD_NE
        mov al, byte ptr cs:[si+4]
        cmp al, 1
        jne not_illegal
        jmp fake_illegal
not_illegal:
        cmp al, 2
        jne not_not_ready
        jmp fake_not_ready
not_not_ready:
        cmp al, 9
        jne fake_response
        jmp fake_success
fake_response:
        mov word ptr cs:[sub_position], 1100h ; audio playing
        mov word ptr cs:[sub_position+2], 0C00h
        mov word ptr cs:[sub_position+4], 1401h ; format 1, ADR=1/CONTROL=4
        mov word ptr cs:[sub_position+6], 0C0Ch ; binary track 12/index 12
        cmp al, 10
        jne fake_addresses
        jmp fake_success                      ; partial reply, tail poisoned
fake_addresses:
        mov word ptr cs:[sub_position+8], 0C00h
        mov word ptr cs:[sub_position+10], 3822h ; absolute 12:34:56
        mov word ptr cs:[sub_position+12], 0
        mov word ptr cs:[sub_position+14], 0201h ; relative 00:01:02
        cmp byte ptr cs:[srb+SRB_CDB+1], 0
        jne fake_faults
        mov word ptr cs:[sub_position+8], 3412h
        mov word ptr cs:[sub_position+10], 7856h
fake_faults:
        cmp al, 3
        jne fault4
        mov byte ptr cs:[sub_position+3], 11
fault4:
        cmp al, 4
        jne fault5
        mov byte ptr cs:[sub_position+4], 2
fault5:
        cmp al, 5
        jne fault6
        mov byte ptr cs:[sub_position+6], 0
fault6:
        cmp al, 6
        jne fault7
        mov byte ptr cs:[sub_position+7], 100
fault7:
        cmp al, 7
        jne fault8
        mov byte ptr cs:[sub_position+10], 60
fault8:
        cmp al, 8
        jne fault11
        mov byte ptr cs:[sub_position+15], 75
fault11:
        cmp al, 11
        jne fault12
        mov byte ptr cs:[sub_position+8], 1
fault12:
        cmp al, 12
        jne fault13
        mov byte ptr cs:[sub_position+9], 100
fault13:
        cmp al, 13
        jne fake_success
        mov byte ptr cs:[sub_position+6], 0AAh
fake_success:
        mov byte ptr cs:[srb+SRB_Status], SS_COMP
        ret
fake_illegal:
        mov al, 5
        jmp short fake_error
fake_not_ready:
        mov al, 2
fake_error:
        mov byte ptr cs:[srb+SRB_Status], SS_ERR
        mov byte ptr cs:[srb+SRB_TargStat], 2
        mov byte ptr cs:[srb+SRB_CDB+10],70h
        mov byte ptr cs:[srb+SRB_CDB+10+7],6
        mov byte ptr cs:[srb+SRB_CDB+12], al
        ret
fake_aspi endp

        include drivers/aspicda/aspicda.asm
