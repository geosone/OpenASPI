; Actual ASPICDA entry points, two memory-only audio-control targets.
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
GET macro status
        mov al, 4
        call prepare_ioctl
        SEND status
endm
SET_CHANNELS macro status
        mov al, 3
        call prepare_ioctl
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_OUT
        mov si, offset desired
        mov di, offset control+1
        mov cx, 8
        rep movsb
        SEND status
        mov si, offset desired
        call compare_control
endm

packet db 32 dup (0)
guard_before db 0A5h
control db 9 dup (0A5h)
guard_after db 0A5h
strategy_ptr dw strategy,0
interrupt_ptr dw interrupt,0
expected dw 0
step dw 0
bad db 0
test_unit db 0
sense_fault db 0                       ; 1 current, 2 mask, 3 SELECT
page_fault db 0
fixed_mask db 0
select_calls dw 0
sense_calls dw 0
calls_before dw 0
current_desc dw 8
; Audio page has an opaque 4-byte extension to test full preservation.
hardware0 db 8Eh,18,04h,5Ah,12h,34h,56h,78h
          db 81h,10h,2,20h,4,30h,8,40h,0DEh,0ADh,0BEh,0EFh
hardware1 db 8Eh,18,04h,5Ah,12h,34h,56h,78h
          db 8,50h,4,60h,2,70h,1,80h,0DEh,0ADh,0BEh,0EFh
expected0 db 0,10h,1,20h,2,30h,3,40h
expected1 db 3,50h,2,60h,1,70h,0,80h
desired db 3,1,2,2,1,3,0,4
msg_pass db 'ASPICDA audio channels/masks/preservation/error tests passed',13,10,'$'
msg_fail db 'ASPICDA audio channel regression FAILED at step $'

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
        mov al, 6
        call prepare_ioctl
        SEND 0100h
        mov ax, word ptr [control+1]
        and ax, 0100h
        cmp ax, 0100h
        ASSERT_EQ
        cmp byte ptr [unit_table+U_AUDIO_CONTROL], 1
        ASSERT_EQ
        GET 0100h
        mov si, offset expected0
        call compare_control
        mov byte ptr [test_unit], 1
        mov byte ptr [sense_fault], 1
        mov al, 6
        call prepare_ioctl
        SEND 0100h                          ; optional unsupported page != status error
        mov ax, word ptr [control+1]
        and ax, 0100h
        cmp ax, 0
        ASSERT_EQ
        cmp byte ptr [unit_table+UNIT_ENTRY+U_AUDIO_CONTROL], 2
        ASSERT_EQ
        mov byte ptr [sense_fault], 0
        GET 0100h
        mov si, offset expected1
        call compare_control
        mov byte ptr [test_unit], 0
        mov word ptr [current_desc], 0
        GET 0100h
        mov si, offset expected0
        call compare_control
        mov word ptr [current_desc], 8
        ; All malformed pages leave output untouched and never SELECT.
        mov byte ptr [page_fault], 1
fault_loop:
        GET 810Ch
        call check_unchanged
        inc byte ptr [page_fault]
        cmp byte ptr [page_fault], 9
        jb fault_loop
        mov byte ptr [page_fault], 0
        mov byte ptr [hardware0+8], 83h     ; mixed source, not a DOS index
        GET 8103h
        call check_unchanged
        mov byte ptr [hardware0+8], 80h     ; muted route, volume immaterial
        GET 0100h
        cmp word ptr [control+1], 0
        ASSERT_EQ
        mov byte ptr [hardware0+8], 81h
        mov byte ptr [sense_fault], 1
        GET 8108h
        call check_unchanged
        SET_CHANNELS 8108h
        mov byte ptr [sense_fault], 0
        cmp word ptr [select_calls], 0
        ASSERT_EQ
        mov byte ptr [sense_fault], 2
        SET_CHANNELS 8108h
        mov byte ptr [sense_fault], 0
        GET 0100h
        mov si, offset expected0
        call compare_control
        mov byte ptr [page_fault], 10      ; current/mask page-size mismatch
        SET_CHANNELS 810Ch
        mov byte ptr [page_fault], 0
        mov byte ptr [fixed_mask], 1       ; volumes cannot be changed
        SET_CHANNELS 8103h
        mov byte ptr [fixed_mask], 0
        cmp word ptr [select_calls], 0
        ASSERT_EQ
        mov byte ptr [sense_fault], 3
        SET_CHANNELS 8108h                 ; SELECT failed: no software echo
        mov byte ptr [sense_fault], 0
        GET 0100h
        mov si, offset expected0
        call compare_control
        SET_CHANNELS 0100h
        GET 0100h
        mov si, offset desired
        call compare_control
        mov byte ptr [test_unit], 1
        GET 0100h
        mov si, offset expected1
        call compare_control
        mov byte ptr [test_unit], 0
        ; Silent hardware port with fixed, nonzero volume: GET -> SET must
        ; retain the pair, not unmute it or fail by changing its fixed bits.
        mov byte ptr [hardware0+8], 80h
        mov byte ptr [hardware0+9], 10h
        GET 0100h
        mov si, offset control+1
        mov di, offset desired
        mov cx, 8
        rep movsb
        mov byte ptr [fixed_mask], 1
        SET_CHANNELS 0100h
        cmp word ptr [hardware0+8], 1080h
        ASSERT_EQ
        mov byte ptr [fixed_mask], 0
        GET 0100h
        mov si, offset desired
        call compare_control
        mov byte ptr [unit_table+U_AUDIO_STATE], 1
        GET 0300h                         ; controls do not disrupt playback
        SET_CHANNELS 0300h
        cmp byte ptr [unit_table+U_AUDIO_STATE], 1
        ASSERT_EQ
        mov byte ptr [unit_table+U_AUDIO_STATE], 0
        mov ax, word ptr [sense_calls]
        mov word ptr [calls_before], ax
        mov byte ptr [desired], 4          ; invalid input channel
        SET_CHANNELS 8103h
        mov byte ptr [desired], 0
        mov al, 3
        call prepare_ioctl
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_OUT
        mov word ptr [packet+RH_COUNT], 8
        SEND 8105h
        call check_unchanged
        mov al, 4
        call prepare_ioctl
        mov word ptr [packet+RH_COUNT], 8
        SEND 8105h
        call check_unchanged
        mov al, 3
        call prepare_ioctl
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_OUT
        mov byte ptr [packet+RH_LENGTH], 19
        SEND 8105h
        call check_unchanged
        mov al, 3
        call prepare_ioctl
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_OUT
        mov word ptr [packet+RH_BUFFER], 0
        mov word ptr [packet+RH_BUFFER+2], 0
        SEND 8105h
        call check_unchanged
        mov al, 3
        call prepare_ioctl
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_OUT
        mov word ptr [packet+RH_BUFFER], 0FFFAh
        mov ax, cs
        sub ax, 100h                     ; alias away from COM stack at FFFE
        mov word ptr [packet+RH_BUFFER+2], ax
        mov es, ax
        mov byte ptr es:[0FFFAh], 3
        mov byte ptr es:[0FFFBh], 0A5h
        push cs
        pop es
        SEND 8105h
        call check_unchanged
        mov ax, word ptr [packet+RH_BUFFER+2]
        mov es, ax
        cmp byte ptr es:[0FFFBh], 0A5h
        push cs
        pop es
        ASSERT_EQ
        mov ax, word ptr [sense_calls]
        cmp ax, word ptr [calls_before]
        ASSERT_EQ
        ; An entirely fixed page is readable, but not a control capability.
        mov byte ptr [test_unit], 1
        mov byte ptr [fixed_mask], 2
        mov byte ptr [unit_table+UNIT_ENTRY+U_AUDIO_CONTROL], 0
        mov al, 6
        call prepare_ioctl
        SEND 0100h
        cmp byte ptr [unit_table+UNIT_ENTRY+U_AUDIO_CONTROL], 2
        ASSERT_EQ
        mov si, offset expected1
        mov di, offset desired
        mov cx, 8
        rep movsb
        SET_CHANNELS 0100h                 ; unchanged fixed values are valid
        mov al, 6
        call prepare_ioctl
        SEND 0100h
        mov ax, word ptr [control+1]
        and ax, 0100h
        cmp ax, 0                          ; no false capability from a no-op SET
        ASSERT_EQ
        GET 0100h
        mov si, offset expected1
        call compare_control
        mov dx, offset msg_pass
        mov ah, 09h
        int 21h
        mov ax, 4C00h
        int 21h

prepare_ioctl proc near
        push ax
        mov di, offset packet
        mov cx, 32
        xor al, al
        rep stosb
        mov di, offset guard_before
        mov cx, 11
        mov al, 0A5h
        rep stosb
        pop ax
        mov byte ptr [control], al
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_IN
        mov byte ptr [packet+RH_LENGTH], 20
        mov al, byte ptr [test_unit]
        mov byte ptr [packet+RH_UNIT], al
        mov word ptr [packet+RH_COUNT], 9
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
compare_control proc near
        mov di, offset control+1
        mov cx, 8
compare_next:
        mov al, byte ptr [si]
        cmp al, byte ptr [di]
        ASSERT_EQ
        inc si
        inc di
        loop compare_next
        ret
compare_control endp
check_unchanged proc near
        mov di, offset control+1
        mov cx, 8
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
        mov al, byte ptr cs:[srb+SRB_Target]
        cmp al, byte ptr cs:[test_unit]
        BAD_NE
        mov bp, offset hardware0
        or al, al
        jz fake_target_ready
        mov bp, offset hardware1
fake_target_ready:
        cmp byte ptr cs:[srb+SRB_CDBLen], 10
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB], 5Ah
        je fake_sense
        jmp fake_select
fake_sense:
        inc word ptr cs:[sense_calls]
        cmp byte ptr cs:[srb+SRB_Flags], SRB_DIR_IN
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+1], 8
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+8], AUDIO_MODE_SIZE
        BAD_NE
        cmp word ptr cs:[srb+SRB_BufLen], AUDIO_MODE_SIZE
        BAD_NE
        cmp word ptr cs:[srb+SRB_BufPointer], offset audio_mode
        BAD_NE
        mov ax, cs
        cmp word ptr cs:[srb+SRB_BufPointer+2], ax
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+2], 0Eh
        je fake_current
        cmp byte ptr cs:[srb+SRB_CDB+2], 4Eh
        BAD_NE
        cmp byte ptr cs:[sense_fault], 2
        jne fake_mask_ok
        jmp fake_error
fake_mask_ok:
        xor bx, bx                        ; mask deliberately has no descriptor
        jmp short fake_fill
fake_current:
        cmp byte ptr cs:[sense_fault], 1
        jne fake_current_ok
        jmp fake_error
fake_current_ok:
        mov bx, word ptr cs:[current_desc]
fake_fill:
        cmp byte ptr cs:[page_fault], 1
        jne fake_fill_response
        jmp fake_success                  ; no returned bytes, poison retained
fake_fill_response:
        push cs
        pop es
        mov di, offset audio_mode
        mov cx, AUDIO_MODE_SIZE
        xor al, al
        rep stosb
        mov ax, bx
        add ax, 26                        ; header + descriptor + 20 - 2
        xchg al, ah
        mov word ptr cs:[audio_mode], ax
        mov word ptr cs:[audio_mode+2], 0BBAAh
        mov ax, bx
        xchg al, ah
        mov word ptr cs:[audio_mode+6], ax
        mov di, offset audio_mode+8
        add di, bx
        mov bx, di                        ; page address
        mov si, bp
        mov cx, 20
        rep movsb
        cmp byte ptr cs:[srb+SRB_CDB+2], 4Eh
        jne fake_faults
        mov di, bx
        add di, 8
        mov cx, 4
fake_mask_pair:
        mov word ptr es:[di], 0FF0Fh
        cmp byte ptr cs:[fixed_mask], 0
        je fake_mask_next
        mov byte ptr es:[di+1], 0
fake_mask_next:
        cmp byte ptr cs:[fixed_mask], 2
        jne fake_mask_advance
        mov byte ptr es:[di], 0
fake_mask_advance:
        add di, 2
        loop fake_mask_pair
        cmp byte ptr cs:[page_fault], 10
        jne fake_faults
        mov byte ptr cs:[bx+1], 14
fake_faults:
        mov al, byte ptr cs:[page_fault]
        cmp al, 2
        jne fault3
        mov word ptr cs:[audio_mode], 1500h
fault3:
        cmp al, 3
        jne fault4
        mov word ptr cs:[audio_mode], 0FFFFh
fault4:
        cmp al, 4
        jne fault5
        mov word ptr cs:[audio_mode+6], 0FFFFh
fault5:
        cmp al, 5
        jne fault6
        mov byte ptr cs:[bx], 0Dh
fault6:
        cmp al, 6
        jne fault7
        mov byte ptr cs:[bx], 4Eh
fault7:
        cmp al, 7
        jne fault8
        mov byte ptr cs:[bx+1], 13
fault8:
        cmp al, 8
        jne fake_response_done
        mov byte ptr cs:[bx+1], 60
fake_response_done:
        jmp fake_success
fake_select:
        inc word ptr cs:[select_calls]
        cmp byte ptr cs:[srb+SRB_CDB], 55h
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+1], 10h
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+8], 28
        BAD_NE
        cmp byte ptr cs:[srb+SRB_Flags], SRB_DIR_OUT
        BAD_NE
        cmp word ptr cs:[srb+SRB_BufLen], 28
        BAD_NE
        cmp word ptr cs:[srb+SRB_BufPointer], offset audio_select
        BAD_NE
        mov ax, cs
        cmp word ptr cs:[srb+SRB_BufPointer+2], ax
        BAD_NE
        mov si, offset audio_select
        mov cx, 8
fake_zero_header:
        cmp byte ptr cs:[si], 0
        BAD_NE
        inc si
        loop fake_zero_header
        cmp byte ptr cs:[si], 0Eh          ; PS cleared
        BAD_NE
        xor bx, bx
fake_preserve:
        cmp bx, 8
        jb fake_compare_field
        cmp bx, 16
        jb fake_preserve_next
fake_compare_field:
        mov al, byte ptr cs:[si+bx]
        mov di, bp
        add di, bx
        mov ah, byte ptr cs:[di]
        or bx, bx
        jnz fake_not_page_code
        and ah, 7Fh
fake_not_page_code:
        cmp al, ah
        BAD_NE
fake_preserve_next:
        inc bx
        cmp bx, 20
        jb fake_preserve
        mov bx, offset audio_select+16
        mov di, bp
        add di, 8
        mov cx, 4
fake_reserved:
        mov al, byte ptr cs:[bx]
        xor al, byte ptr cs:[di]
        and al, 0F0h
        cmp al, 0
        BAD_NE
        add bx, 2
        add di, 2
        loop fake_reserved
        cmp byte ptr cs:[sense_fault], 3
        je fake_error
        push cs
        pop es
        mov di, bp
        mov si, offset audio_select+8
        mov cx, 20
        rep movsb                         ; hardware changes only after success
fake_success:
        mov byte ptr cs:[srb+SRB_Status], SS_COMP
        ret
fake_error:
        mov byte ptr cs:[srb+SRB_Status], SS_ERR
        mov byte ptr cs:[srb+SRB_TargStat], 2
        mov byte ptr cs:[srb+SRB_CDB+10],70h
        mov byte ptr cs:[srb+SRB_CDB+10+7],6
        mov byte ptr cs:[srb+SRB_CDB+12], 5
        ret
fake_aspi endp

        include drivers/aspicda/aspicda.asm
