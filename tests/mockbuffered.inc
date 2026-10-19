; Ordered, payload-validating SCSI fixture for the software-buffered aliases.
buffered_test_command proc near
        cmp byte ptr cs:[buffer_protocol_error], 0
        je buffered_protocol_ready
        jmp buffered_bad
buffered_protocol_ready:
        xor ax, ax
        mov al, byte ptr cs:[buffer_event]
        cmp al, BUFFER_EVENT_COUNT
        jb buffered_event_in_range
        jmp buffered_bad
buffered_event_in_range:
        mov si, ax
        mov al, byte ptr cs:[si+buffer_events]
        cmp al, byte ptr es:[bx+SRB_CDB]
        je buffered_opcode_ok
        jmp buffered_bad
buffered_opcode_ok:
        cmp byte ptr es:[bx+SRB_CDBLen], 6
        jne buffered_bad
        cmp byte ptr es:[bx+SRB_SenseLen], 32
        jne buffered_bad
        inc byte ptr cs:[buffer_event]
        cmp al, 8
        je buffered_data
        cmp al, 0Ah
        je buffered_data
        cmp byte ptr es:[bx+SRB_Flags], SRB_DIR_NONE
        jne buffered_bad
        cmp al, 10h
        jne buffered_control_not_marks
        cmp byte ptr es:[bx+SRB_CDB+4], 2
        jne buffered_bad
buffered_control_not_marks:
        cmp al, 11h
        jne buffered_good
ifdef BUFFER_DISCARD
        cmp byte ptr cs:[buffer_event], 1
else
        cmp byte ptr cs:[buffer_event], 9
endif
        jne buffered_backspace
        cmp byte ptr es:[bx+SRB_CDB+1], 0
        jne buffered_bad
        cmp byte ptr es:[bx+SRB_CDB+4], 1
        jne buffered_bad
        jmp short buffered_good
buffered_backspace:
        cmp byte ptr es:[bx+SRB_CDB+1], 1
        jne buffered_bad
        cmp word ptr es:[bx+SRB_CDB+2], 0FFFFh
        jne buffered_bad
        cmp byte ptr es:[bx+SRB_CDB+4], 0FFh
        jne buffered_bad
buffered_good:
        mov byte ptr es:[bx+SRB_Status], SS_COMP
        ret
buffered_bad:
        mov byte ptr cs:[buffer_protocol_error], 1
        mov byte ptr es:[bx+SRB_Status], SS_ERR
        ret
buffered_data:
        cmp word ptr es:[bx+SRB_BufLen], 1024
        jne buffered_bad
        cmp word ptr es:[bx+SRB_BufLen+2], 0
        jne buffered_bad
ifdef FIXED_BLOCK
        cmp byte ptr es:[bx+SRB_CDB+1], 1
        jne buffered_bad
        cmp word ptr es:[bx+SRB_CDB+3], 0100h ; one block, big endian
else
        cmp byte ptr es:[bx+SRB_CDB+1], 0
        jne buffered_bad
        cmp word ptr es:[bx+SRB_CDB+3], 0004h ; 1024 bytes, big endian
endif
        jne buffered_bad
        cmp byte ptr es:[bx+SRB_CDB], 0Ah
        je buffered_write_data
        jmp buffered_read_data
buffered_write_data:
ifdef NO_RESIDUAL
        cmp byte ptr es:[bx+SRB_Flags], SRB_DIR_OUT
else
        cmp byte ptr es:[bx+SRB_Flags], SRB_DIR_OUT or SRB_RESIDUAL
endif
        je buffered_write_flags_ok
        jmp buffered_bad
buffered_write_flags_ok:
        push es
        mov si, word ptr es:[bx+SRB_BufPointer]
        mov ax, word ptr es:[bx+SRB_BufPointer+2]
        mov es, ax
ifdef BUFFER_WRITE_ERROR
        mov cx, 1024
        mov al, 'Z'
        call buffered_compare
        jc buffered_payload_bad
else
ifdef BUFFER_CLOSE_ERROR
        mov cx, 3
        mov al, 'Z'
        call buffered_compare
        jc buffered_payload_bad
        mov cx, 1021
        xor al, al
        call buffered_compare
        jc buffered_payload_bad
else
        cmp byte ptr cs:[buffer_event], 11
        jne buffered_tail_payload
        mov cx, 600
        mov al, 'Q'
        call buffered_compare
        jc buffered_payload_bad
        mov cx, 424
        mov al, 'R'
        call buffered_compare
        jc buffered_payload_bad
        jmp short buffered_payload_ok
buffered_tail_payload:
        mov cx, 276
        mov al, 'R'
        call buffered_compare
        jc buffered_payload_bad
        mov cx, 748
        xor al, al
        call buffered_compare
        jc buffered_payload_bad
endif
endif
buffered_payload_ok:
        pop es
ifdef BUFFER_ERROR
ifdef BUFFER_RECOVERY
        cmp byte ptr cs:[buffer_event], 1
        jne buffered_recovered_write
endif
ifdef BUFFER_SHORT_WRITE
        mov word ptr es:[bx+SRB_BufLen], 512
        jmp buffered_good
else
        mov byte ptr es:[bx+SRB_CDB+16], 70h
        mov byte ptr es:[bx+SRB_CDB+18], 7 ; DATA PROTECT
        mov byte ptr es:[bx+SRB_TargStat], 2
        mov byte ptr es:[bx+SRB_Status], SS_ERR
        ret
endif
ifdef BUFFER_RECOVERY
buffered_recovered_write:
        mov word ptr es:[bx+SRB_BufLen], 0
        jmp buffered_good
endif
else
ifndef NO_RESIDUAL
        mov word ptr es:[bx+SRB_BufLen], 0
endif
        jmp buffered_good
endif
buffered_payload_bad:
        pop es
        jmp buffered_bad

buffered_read_data:
ifdef NO_RESIDUAL
        cmp byte ptr es:[bx+SRB_Flags], SRB_DIR_IN
else
        cmp byte ptr es:[bx+SRB_Flags], SRB_DIR_IN or SRB_RESIDUAL
endif
        je buffered_read_flags_ok
        jmp buffered_bad
buffered_read_flags_ok:
        cmp byte ptr cs:[buffer_event], 5
        je buffered_filemark
        push es
        mov di, word ptr es:[bx+SRB_BufPointer]
        mov ax, word ptr es:[bx+SRB_BufPointer+2]
        mov es, ax
        mov cx, 1024
        mov al, 'A'
        cmp byte ptr cs:[buffer_event], 2
        je buffered_fill
        mov al, 'B'
        cmp byte ptr cs:[buffer_event], 3
        je buffered_fill
        mov al, 'C'
        cmp byte ptr cs:[buffer_event], 6
        je buffered_fill
        mov al, 'X'
        cmp byte ptr cs:[buffer_event], 7
        jne buffered_read_later
ifdef FIXED_BLOCK
        mov cx, 1024
else
        mov cx, 12
endif
        jmp short buffered_fill
buffered_read_later:
        mov al, 'D'
        cmp byte ptr cs:[buffer_event], 8
        je buffered_fill
        mov al, 'E'
buffered_fill:
        rep stosb
        pop es
        cmp byte ptr cs:[buffer_event], 7
        je buffered_data_filemark
ifndef NO_RESIDUAL
        mov word ptr es:[bx+SRB_BufLen], 0
endif
        jmp buffered_good
buffered_filemark:
        mov dx, 1024
        jmp short buffered_mark_sense
buffered_data_filemark:
ifdef FIXED_BLOCK
        mov dx, 0
else
        mov dx, 1012
endif
buffered_mark_sense:
        mov al, 80h
ifdef FIXED_BLOCK
        ; Fixed sense information is in blocks, while ASPI residual is bytes.
        push dx
        cmp dx, 0
        je buffered_fixed_info_ready
        mov dx, 1
buffered_fixed_info_ready:
        call set_read_condition
        pop dx
ifndef NO_RESIDUAL
        mov word ptr es:[bx+SRB_BufLen], dx
endif
else
        call set_read_condition
endif
        ret
buffered_test_command endp

buffered_compare proc near
buffered_compare_next:
        cmp byte ptr es:[si], al
        jne buffered_compare_bad
        inc si
        loop buffered_compare_next
        clc
        ret
buffered_compare_bad:
        stc
        ret
buffered_compare endp

buffer_event db 0
buffer_protocol_error db 0
buffer_events:
ifdef BUFFER_DISCARD
        db 11h, 10h, 11h, 00h
BUFFER_EVENT_COUNT equ 4
else
ifdef BUFFER_ERROR
ifdef BUFFER_WRITE_ERROR
        db 0Ah, 00h, 00h
ifdef BUFFER_RECOVERY
        db 0Ah, 10h, 11h, 00h
BUFFER_EVENT_COUNT equ 7
else
BUFFER_EVENT_COUNT equ 3
endif
else
        db 0Ah, 00h
BUFFER_EVENT_COUNT equ 2
endif
else
        db 01h, 08h, 08h, 00h, 08h, 08h, 08h, 08h
        db 11h, 08h, 0Ah, 00h, 0Ah, 10h, 11h, 00h
BUFFER_EVENT_COUNT equ 16
endif
endif
