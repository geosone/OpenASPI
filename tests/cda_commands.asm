; Real ASPICDA strategy/interrupt and resident code, memory-only ASPI.
; No installed ASPI manager or medium is accessed by this fixture.
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
calls dw 0
bad db 0
case_ptr dw 0
strategy_ptr dw strategy, 0
interrupt_ptr dw interrupt, 0
msg_pass db 'ASPICDA seek/prefetch/address/play tests passed',13,10,'$'
msg_fail db 'ASPICDA command regression FAILED',13,10,'$'
msg_position db 'ASPICDA installed seek/prefetch boundary tests passed',13,10,'$'
volume_packet db 8, 4 dup (0)
last_sector dd 0
position_command db 83h

; command, mode, packet length, fault (capacity=1, seek=2, sentinel=3),
; start DWORD, play count DWORD, status WORD, call count WORD,
; expected decoded LBA DWORD (seek), or start MSF packed DWORD (play).
cases:
        db 83h,0,24,0
        dd 12345678h,0
        dw 0100h,2
        dd 12345678h
        db 82h,0,24,0
        dd 0,0
        dw 0100h,2
        dd 0
        db 83h,0,24,0
        dd 12345679h,0
        dw 8108h,1
        dd 0
        db 83h,1,24,0
        dd 00000200h,0                 ; 00:02:00 => LBA zero
        dw 0100h,2
        dd 0
        db 82h,1,24,0
        dd 00010201h,0                 ; 01:02:01 => LBA 4501
        dw 0100h,2
        dd 4501
        db 83h,2,24,0                  ; invalid addressing mode
        dd 0,0
        dw 8108h,0
        dd 0
        db 83h,1,24,0                  ; invalid frames
        dd 0000024Bh,0
        dw 8108h,0
        dd 0
        db 83h,1,24,0                  ; invalid seconds
        dd 00003C00h,0
        dw 8108h,0
        dd 0
        db 83h,1,24,0                  ; invalid minutes
        dd 00630200h,0
        dw 8108h,0
        dd 0
        db 83h,1,24,0                  ; reserved MSF byte
        dd 01000200h,0
        dw 8108h,0
        dd 0
        db 83h,1,24,0                  ; before logical sector zero
        dd 0000014Ah,0
        dw 8108h,0
        dd 0
        db 83h,0,23,0                  ; short request
        dd 0,0
        dw 8105h,0
        dd 0
        db 83h,0,24,1                  ; NOT READY from capacity
        dd 12345678h,0
        dw 8102h,1
        dd 0
        db 83h,0,24,2                  ; ILLEGAL REQUEST from SEEK
        dd 12345678h,0
        dw 8108h,2
        dd 12345678h
        db 83h,0,24,3                  ; capacity(16) sentinel unsupported
        dd 0,0
        dw 8108h,1
        dd 0
        db 84h,0,22,0                  ; distinct PLAY start offset
        dd 75,75
        dw 0100h,1
        dd 00000300h                  ; start 00:03:00, end 00:04:00
        db 84h,1,22,0
        dd 00000300h,75
        dw 0100h,1
        dd 00000300h
        db 84h,0,22,0                  ; 32-bit endpoint overflow
        dd 0FFFFFFF0h,32
        dw 8108h,0
        dd 0
        db 84h,0,22,0                  ; outside CD MSF conversion range
        dd 449849,1
        dw 8108h,0
        dd 0
        db 84h,0,21,0
        dd 0,75
        dw 8105h,0
        dd 0
        db 80h,2,25,0                  ; READ LONG shares checked decoder
        dd 0,0
        dw 8108h,0
        dd 0
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
        ; Independent packet cases must not share an active PLAY.
        mov byte ptr [unit_table+U_AUDIO_STATE], 0
        mov byte ptr [unit_table+U_AUDIO_RANGE], 0
        mov di, offset packet
        mov cx, 32
        xor al, al
        rep stosb
        mov word ptr [calls], 0
        mov byte ptr [bad], 0
        mov si, word ptr [case_ptr]
        mov al, byte ptr [si]
        mov byte ptr [packet+RH_COMMAND], al
        mov al, byte ptr [si+1]
        mov byte ptr [packet+RH_CD_ADDRMODE], al
        mov al, byte ptr [si+2]
        mov byte ptr [packet+RH_LENGTH], al
        mov di, offset packet+RH_CD_START
        cmp byte ptr [si], CMD_PLAY_AUDIO
        jne packet_start
        mov di, offset packet+RH_CD_PLAYSTART
packet_start:
        mov ax, word ptr [si+4]
        mov word ptr [di], ax
        mov ax, word ptr [si+6]
        mov word ptr [di+2], ax
        cmp byte ptr [si], CMD_PLAY_AUDIO
        jne packet_ready
        mov ax, word ptr [si+8]
        mov word ptr [packet+RH_CD_PLAYCOUNT], ax
        mov ax, word ptr [si+10]
        mov word ptr [packet+RH_CD_PLAYCOUNT+2], ax
packet_ready:
        mov bx, offset packet
        call dword ptr [strategy_ptr]
        call dword ptr [interrupt_ptr]
        mov si, word ptr [case_ptr]
        mov ax, word ptr [packet+RH_STATUS]
        cmp ax, word ptr [si+12]
        ASSERT_EQ
        mov ax, word ptr [calls]
        cmp ax, word ptr [si+14]
        ASSERT_EQ
        cmp byte ptr [bad], 0
        ASSERT_EQ
        add word ptr [case_ptr], 20
        cmp word ptr [case_ptr], offset cases_end
        jae tests_done
        jmp test_next
tests_done:
        mov dx, offset msg_pass
        mov ah, 09h
        int 21h
        ; Also exercise the installed driver through SHSUCDX on R:. Only
        ; the disposable QEMU CD image is positioned; no media is written.
        mov di, offset packet
        mov cx, 32
        xor al, al
        rep stosb
        mov byte ptr [packet+RH_LENGTH], 20
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_IN
        mov word ptr [packet+RH_BUFFER], offset volume_packet
        mov word ptr [packet+RH_BUFFER+2], cs
        mov word ptr [packet+RH_COUNT], 5
        call installed_request
        cmp word ptr [packet+RH_STATUS], ST_DONE
        ASSERT_EQ
        mov ax, word ptr [volume_packet+1]
        mov dx, word ptr [volume_packet+3]
        sub ax, 1
        sbb dx, 0
        mov word ptr [last_sector], ax
        mov word ptr [last_sector+2], dx
position_next:
        mov byte ptr [packet+RH_LENGTH], 24
        mov al, byte ptr [position_command]
        mov byte ptr [packet+RH_COMMAND], al
        mov word ptr [packet+RH_CD_START], 0
        mov word ptr [packet+RH_CD_START+2], 0
        call installed_request
        cmp word ptr [packet+RH_STATUS], ST_DONE
        ASSERT_EQ
        mov ax, word ptr [last_sector]
        mov dx, word ptr [last_sector+2]
        mov word ptr [packet+RH_CD_START], ax
        mov word ptr [packet+RH_CD_START+2], dx
        call installed_request
        cmp word ptr [packet+RH_STATUS], ST_DONE
        ASSERT_EQ
        add word ptr [packet+RH_CD_START], 1
        adc word ptr [packet+RH_CD_START+2], 0
        call installed_request
        cmp word ptr [packet+RH_STATUS], 8108h
        ASSERT_EQ
        dec byte ptr [position_command]
        cmp byte ptr [position_command], 82h
        je position_next
        mov dx, offset msg_position
        mov ah, 09h
        int 21h
        mov ax, 4C00h
        int 21h
test_fail:
        mov dx, offset msg_fail
        mov ah, 09h
        int 21h
        mov ax, 4C01h
        int 21h

installed_request proc near
        mov word ptr [packet+RH_STATUS], 0FFFFh
        mov bx, offset packet
        mov cx, 'R'-'A'
        mov ax, 1510h
        int 2Fh
        ret
installed_request endp

fake_aspi proc far
        inc word ptr cs:[calls]
        mov si, word ptr cs:[case_ptr]
        cmp byte ptr cs:[srb+SRB_Cmd], SC_EXEC_SCSI_CMD
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDBLen], 10
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB], 25h
        jne fake_position
        jmp fake_capacity
fake_position:
        cmp byte ptr cs:[srb+SRB_Flags], SRB_DIR_NONE
        BAD_NE
        mov ax, word ptr cs:[srb+SRB_BufLen]
        or ax, word ptr cs:[srb+SRB_BufLen+2]
        or ax, word ptr cs:[srb+SRB_BufPointer]
        or ax, word ptr cs:[srb+SRB_BufPointer+2]
        cmp ax, 0
        BAD_NE
        cmp byte ptr cs:[si], CMD_PLAY_AUDIO
        je fake_play
        cmp byte ptr cs:[srb+SRB_CDB], 2Bh
        BAD_NE
        mov ax, word ptr cs:[srb+SRB_CDB+2]
        xchg al, ah
        cmp ax, word ptr cs:[si+18]
        BAD_NE
        mov ax, word ptr cs:[srb+SRB_CDB+4]
        xchg al, ah
        cmp ax, word ptr cs:[si+16]
        BAD_NE
        cmp byte ptr cs:[si+3], 2
        jne fake_position_ok
        jmp fake_illegal
fake_position_ok:
        jmp fake_success
fake_play:
        cmp byte ptr cs:[srb+SRB_CDB], 47h
        BAD_NE
        mov al, byte ptr cs:[srb+SRB_CDB+3]
        cmp al, byte ptr cs:[si+18]
        BAD_NE
        mov al, byte ptr cs:[srb+SRB_CDB+4]
        cmp al, byte ptr cs:[si+17]
        BAD_NE
        mov al, byte ptr cs:[srb+SRB_CDB+5]
        cmp al, byte ptr cs:[si+16]
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+6], 0
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+7], 4
        BAD_NE
        cmp byte ptr cs:[srb+SRB_CDB+8], 0
        BAD_NE
        jmp fake_success
fake_capacity:
        cmp word ptr cs:[calls], 1
        BAD_NE
        cmp byte ptr cs:[srb+SRB_Flags], SRB_DIR_IN
        BAD_NE
        cmp word ptr cs:[srb+SRB_BufLen], 8
        BAD_NE
        cmp word ptr cs:[srb+SRB_BufPointer], offset capacity_data
        BAD_NE
        mov ax, cs
        cmp word ptr cs:[srb+SRB_BufPointer+2], ax
        BAD_NE
        cmp byte ptr cs:[si+3], 1
        je fake_not_ready
        mov word ptr cs:[capacity_data], 3412h
        mov word ptr cs:[capacity_data+2], 7856h
        cmp byte ptr cs:[si+3], 3
        jne fake_success
        mov word ptr cs:[capacity_data], 0FFFFh
        mov word ptr cs:[capacity_data+2], 0FFFFh
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
