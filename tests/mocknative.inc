; Memory-only native discovery, including a private test counter command.
native_calls dw 0
native_bad dw 0
native_writes dw 0
native_marks dw 0
native_flushes dw 0
native_inquiry db 1,80h,2,2,31,0,0,0,'TESTVEND','NATIVE TAPE     ','0001'
ifdef NATIVE_FIXED_LIMITS
native_limits db 0,0,2,0,2,0 ; fixed-only 512 bytes
elseifdef NATIVE_GRANULARITY
native_limits db 2,0,80h,0,0,1 ; n-minimum must be a multiple of 4
elseifdef NATIVE_UNLIMITED
native_limits db 0,0,0,0,0,1   ; maximum not specified
else
native_limits db 0,0,80h,0,0,1 ; max=32768, min=1
endif
native_mode db 64 dup (0)
native_length dw 0

native_test_command proc near
        inc word ptr cs:[native_calls]
        cmp byte ptr es:[bx+SRB_CDB],8
        jne native_not_record
ifdef NATIVE_MEDIA_TEST
        jmp native_media_read
elseifdef NATIVE_FIXED_IO_TEST
        jmp native_fixed_read
elseifdef NATIVE_ARCHIVE_TEST
        jmp native_archive_read
else
        jmp native_record_command
endif
native_not_record:
        cmp byte ptr es:[bx+SRB_CDB],0Ah
        jne native_not_write
ifdef NATIVE_FIXED_IO_TEST
        jmp native_fixed_write
elseifdef NATIVE_ARCHIVE_TEST
        jmp native_archive_write
else
        jmp native_write_command
endif
native_not_write:
        cmp byte ptr es:[bx+SRB_CDB],10h
        jne native_not_marks
        jmp native_marks_command
native_not_marks:
ifdef NATIVE_MEDIA_TEST
        cmp byte ptr es:[bx+SRB_CDB],1Bh
        jne native_not_media
        jmp native_media_command
native_not_media:
endif
ifdef NATIVE_SPACE_TEST
        cmp byte ptr es:[bx+SRB_CDB],11h
        jne native_not_space
        jmp native_space_command
native_not_space:
endif
        cmp byte ptr es:[bx+SRB_CDB],0
        je native_test_nodata
        cmp byte ptr es:[bx+SRB_CDB],1
        jne native_test_data
native_test_nodata:
        jmp native_control_command
native_test_data:
        cmp byte ptr es:[bx+SRB_CDBLen],6
        jne native_test_bad
        cmp byte ptr es:[bx+SRB_SenseLen],32
        jne native_test_bad
ifdef NO_RESIDUAL
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN
else
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN or SRB_RESIDUAL
endif
        jne native_test_bad
        cmp byte ptr es:[bx+SRB_HaStat],0
        jne native_test_bad
        cmp byte ptr es:[bx+SRB_CDB],12h
        jne native_test_limits
        cmp word ptr es:[bx+SRB_BufLen],36
        jne native_test_bad
        cmp byte ptr es:[bx+SRB_CDB+4],36
        jne native_test_bad
ifdef NATIVE_HOST
        mov byte ptr es:[bx+SRB_HaStat],11h
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+TAPE_SENSE],70h
        mov byte ptr es:[bx+TAPE_SENSE+2],7 ; plausible stale write protection
        ret
endif
        mov si,offset native_inquiry
        mov cx,36
ifdef NATIVE_SHORT
        mov cx,12
endif
        call native_copy
ifdef NATIVE_RESIDUAL_BAD
ifdef NATIVE_RESIDUAL_HIGH
        mov word ptr es:[bx+SRB_BufLen],0
        mov word ptr es:[bx+SRB_BufLen+2],1
else
        mov word ptr es:[bx+SRB_BufLen],37
endif
endif
        ret
native_test_limits:
        cmp byte ptr es:[bx+SRB_CDB],5
        jne native_test_mode
        cmp word ptr es:[bx+SRB_BufLen],6
        jne native_test_bad
        mov si,offset native_limits
        mov cx,6
        call native_copy
        ret
native_test_bad:
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
native_test_mode:
        cmp byte ptr es:[bx+SRB_CDB],1Ah
        jne native_test_bad
        cmp word ptr es:[bx+SRB_BufLen],64
        jne native_test_bad
        cmp byte ptr es:[bx+SRB_CDB+4],64
        jne native_test_bad
        mov al,byte ptr es:[bx+SRB_CDB+2]
        cmp al,0Fh
        je native_test_compression
        cmp al,10h
        jne native_test_bad
        jmp short native_make_mode
native_test_compression:
ifdef NATIVE_NO_COMP
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+TAPE_SENSE],70h
        mov byte ptr es:[bx+TAPE_SENSE+2],5
        mov byte ptr es:[bx+TAPE_SENSE+7],6
        mov byte ptr es:[bx+TAPE_SENSE+12],24h
        ret
endif
native_make_mode:
        push ax
        push es
        push cs
        pop es
        mov di,offset native_mode
        mov cx,64
        xor al,al
        rep stosb
        pop es
        pop ax
        mov byte ptr cs:[native_mode+2],80h ; write protected
        mov di,offset native_mode+12
        mov byte ptr cs:[native_mode+3],8
ifndef NATIVE_ARCHIVE_TEST
        mov byte ptr cs:[native_mode+10],2  ; current block 512, with descriptor
endif
ifdef NATIVE_GRANULARITY
        mov byte ptr cs:[native_mode+11],1  ; 513 matches minimum=1, granularity=4
endif
ifdef NATIVE_NO_DESCRIPTOR
        mov byte ptr cs:[native_mode+3],0
        mov byte ptr cs:[native_mode+10],0
        mov di,offset native_mode+4
endif
ifdef NATIVE_EXTRA_PAGE
        mov byte ptr cs:[di],8
        mov byte ptr cs:[di+1],0
        add di,2
endif
        mov byte ptr cs:[di],al
        mov byte ptr cs:[di+1],14
        cmp al,0Fh
        jne native_make_config
        mov byte ptr cs:[di+2],0C0h
ifdef NATIVE_NO_DCC
        mov byte ptr cs:[di+2],0
endif
        jmp short native_make_length
native_make_config:
        mov byte ptr cs:[di+8],20h
native_make_length:
        add di,16
        sub di,offset native_mode
        mov cx,di
        mov ax,cx
        dec ax
        mov byte ptr cs:[native_mode],al
ifdef NATIVE_BAD_PAGE
        mov byte ptr cs:[native_mode+13],63
endif
ifdef NATIVE_BAD_DESCRIPTOR
        mov byte ptr cs:[native_mode+3],56
endif
        mov si,offset native_mode
        call native_copy
        ret
native_test_command endp

native_copy proc near
        mov ax,word ptr es:[bx+SRB_BufLen]
        sub ax,cx
        mov word ptr cs:[native_length],ax
        push ds
        push es
        push cs
        pop ds
        les di,dword ptr es:[bx+SRB_BufPointer]
        rep movsb
        pop es
        pop ds
ifndef NO_RESIDUAL
        mov ax,word ptr cs:[native_length]
        mov word ptr es:[bx+SRB_BufLen],ax
        mov word ptr es:[bx+SRB_BufLen+2],0
endif
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        ret
native_copy endp

native_control_command proc near
        cmp byte ptr es:[bx+SRB_CDBLen],6
        jne native_control_bad
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_NONE
        jne native_control_bad
        cmp word ptr es:[bx+SRB_BufLen],0
        jne native_control_bad
        cmp word ptr es:[bx+SRB_BufLen+2],0
        jne native_control_bad
        cmp word ptr es:[bx+SRB_BufPointer],0
        jne native_control_bad
        cmp word ptr es:[bx+SRB_BufPointer+2],0
        jne native_control_bad
        cmp byte ptr es:[bx+SRB_CDB+1],0 ; synchronous, no IMMED
        jne native_control_bad
        cmp word ptr es:[bx+SRB_CDB+2],0
        jne native_control_bad
        cmp word ptr es:[bx+SRB_CDB+4],0
        jne native_control_bad
ifdef NATIVE_MEDIA_TEST
        cmp byte ptr cs:[native_media_loaded],0
        jne native_control_loaded
        jmp native_media_notready
native_control_loaded:
endif
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        cmp byte ptr es:[bx+SRB_CDB],1
        jne native_control_return
ifdef NATIVE_CONTROL_FAULT
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+TAPE_SENSE],70h
        mov byte ptr es:[bx+TAPE_SENSE+2],2
        mov byte ptr es:[bx+TAPE_SENSE+7],6
        mov byte ptr es:[bx+TAPE_SENSE+12],3Ah
if NATIVE_CONTROL_FAULT eq 1
        mov byte ptr es:[bx+SRB_HaStat],11h
        mov byte ptr es:[bx+TAPE_SENSE+2],7
elseif NATIVE_CONTROL_FAULT eq 3
        mov byte ptr es:[bx+TAPE_SENSE],71h
elseif NATIVE_CONTROL_FAULT eq 4
        mov byte ptr es:[bx+TAPE_SENSE+2],5
        mov byte ptr es:[bx+TAPE_SENSE+12],20h
elseif NATIVE_CONTROL_FAULT eq 5
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        mov byte ptr es:[bx+SRB_HaStat],11h
endif
endif
native_control_return:
ifdef NATIVE_ARCHIVE_TEST
        cmp byte ptr es:[bx+SRB_CDB],1
        jne native_archive_not_rewind
        cmp byte ptr es:[bx+SRB_Status],SS_COMP
        jne native_archive_not_rewind
        mov word ptr cs:[archive_cursor],0
        mov word ptr cs:[archive_offset],0
ifdef NATIVE_ARCHIVE_FIXED
        mov word ptr cs:[archive_progress],0
endif
native_archive_not_rewind:
endif
        ret
native_control_bad:
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
native_control_command endp

; Memory-only record source. No real medium and no writes.
native_record_command proc near
        cmp byte ptr es:[bx+SRB_CDBLen],6
        jne native_record_bad
        cmp byte ptr es:[bx+SRB_CDB+1],0
        jne native_record_bad
        cmp byte ptr es:[bx+SRB_CDB+2],0
        jne native_record_bad
        cmp word ptr es:[bx+SRB_CDB+3],0800h ; 8-byte request, big endian
        jne native_record_bad
        cmp byte ptr es:[bx+SRB_CDB+5],0
        jne native_record_bad
        cmp word ptr es:[bx+SRB_BufLen],8
        jne native_record_bad
        cmp word ptr es:[bx+SRB_BufLen+2],0
        jne native_record_bad
ifdef NO_RESIDUAL
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN
else
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN or SRB_RESIDUAL
endif
        jne native_record_bad
        jmp short native_record_data
native_record_bad:
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
native_record_data:
        mov si,offset native_record_bytes
        mov cx,8
ifdef NATIVE_READ_CASE
if NATIVE_READ_CASE eq 1 or NATIVE_READ_CASE eq 3 or NATIVE_READ_CASE eq 8 or NATIVE_READ_CASE eq 10
        mov cx,4
elseif NATIVE_READ_CASE eq 2 or NATIVE_READ_CASE eq 4 or NATIVE_READ_CASE eq 11 or NATIVE_READ_CASE eq 12
        xor cx,cx
endif
endif
        call native_copy
ifdef NATIVE_READ_CASE
if NATIVE_READ_CASE eq 6
        mov word ptr es:[bx+SRB_BufLen],9
elseif NATIVE_READ_CASE ne 12
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+TAPE_SENSE],0F0h
        mov byte ptr es:[bx+TAPE_SENSE+7],6
if NATIVE_READ_CASE eq 1 or NATIVE_READ_CASE eq 3 or NATIVE_READ_CASE eq 8 or NATIVE_READ_CASE eq 10
        mov byte ptr es:[bx+TAPE_SENSE+6],4
elseif NATIVE_READ_CASE eq 2 or NATIVE_READ_CASE eq 4 or NATIVE_READ_CASE eq 11
        mov byte ptr es:[bx+TAPE_SENSE+6],8
endif
if NATIVE_READ_CASE eq 1 or NATIVE_READ_CASE eq 8 or NATIVE_READ_CASE eq 9
        mov byte ptr es:[bx+TAPE_SENSE+2],20h
elseif NATIVE_READ_CASE eq 2 or NATIVE_READ_CASE eq 3
        mov byte ptr es:[bx+TAPE_SENSE+2],80h
elseif NATIVE_READ_CASE eq 4
        mov byte ptr es:[bx+TAPE_SENSE+2],40h
elseif NATIVE_READ_CASE eq 10
        mov byte ptr es:[bx+TAPE_SENSE+2],3 ; medium error with partial bytes
elseif NATIVE_READ_CASE eq 11
        mov byte ptr es:[bx+TAPE_SENSE+2],8
        mov byte ptr es:[bx+TAPE_SENSE+13],5
endif
if NATIVE_READ_CASE eq 5
        mov byte ptr es:[bx+SRB_HaStat],11h
        mov byte ptr es:[bx+TAPE_SENSE+2],80h ; plausible stale FILEMARK
elseif NATIVE_READ_CASE eq 7
        mov byte ptr es:[bx+TAPE_SENSE],0F1h
        mov byte ptr es:[bx+TAPE_SENSE+2],80h
elseif NATIVE_READ_CASE eq 8
        mov byte ptr es:[bx+TAPE_SENSE+6],3 ; contradicts actual residual 4
elseif NATIVE_READ_CASE eq 9
        mov word ptr es:[bx+TAPE_SENSE+3],0FFFFh
        mov word ptr es:[bx+TAPE_SENSE+5],0FCFFh ; signed -4
endif
endif
endif
        ret
native_record_command endp
native_record_bytes db 'RECORD01'

native_write_command proc near
        cmp byte ptr es:[bx+SRB_CDBLen],6
        jne native_write_bad
        cmp byte ptr es:[bx+SRB_CDB+1],0
        jne native_write_bad
        cmp byte ptr es:[bx+SRB_CDB+2],0
        jne native_write_bad
        cmp word ptr es:[bx+SRB_CDB+3],0800h
        jne native_write_bad
        cmp byte ptr es:[bx+SRB_CDB+5],0
        jne native_write_bad
        cmp word ptr es:[bx+SRB_BufLen],8
        jne native_write_bad
        cmp word ptr es:[bx+SRB_BufLen+2],0
        jne native_write_bad
ifdef NO_RESIDUAL
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_OUT
else
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_OUT or SRB_RESIDUAL
endif
        jne native_write_bad
        push ds
        push es
        push bx
        lds si,dword ptr es:[bx+SRB_BufPointer]
        push cs
        pop es
        mov di,offset native_record_bytes
        mov cx,8
        repe cmpsb
        pop bx
        pop es
        pop ds
        jne native_write_bad
        inc word ptr cs:[native_writes]
        mov byte ptr es:[bx+SRB_Status],SS_COMP
ifndef NO_RESIDUAL
        mov word ptr es:[bx+SRB_BufLen],0
endif
        jmp short native_write_reply
native_write_bad:
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
native_write_reply:
ifdef NATIVE_WRITE_CASE
if NATIVE_WRITE_CASE eq 1
        mov word ptr es:[bx+SRB_BufLen],4
elseif NATIVE_WRITE_CASE eq 5
        mov word ptr es:[bx+SRB_BufLen+2],1
else
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+TAPE_SENSE],70h
        mov byte ptr es:[bx+TAPE_SENSE+2],7
        mov byte ptr es:[bx+TAPE_SENSE+7],6
        mov byte ptr es:[bx+TAPE_SENSE+12],27h
if NATIVE_WRITE_CASE eq 2 or NATIVE_WRITE_CASE eq 7
        mov byte ptr es:[bx+SRB_HaStat],11h
        mov byte ptr es:[bx+TAPE_SENSE+2],40h
if NATIVE_WRITE_CASE eq 7
        mov byte ptr es:[bx+SRB_Status],SS_COMP
endif
elseif NATIVE_WRITE_CASE eq 4 or NATIVE_WRITE_CASE eq 9
        mov byte ptr es:[bx+TAPE_SENSE+2],40h
        mov byte ptr es:[bx+TAPE_SENSE+12],0
ifndef NO_RESIDUAL
if NATIVE_WRITE_CASE eq 4
        mov word ptr es:[bx+SRB_BufLen],4
endif
endif
elseif NATIVE_WRITE_CASE eq 6
        mov byte ptr es:[bx+TAPE_SENSE],71h
elseif NATIVE_WRITE_CASE eq 8
        mov byte ptr es:[bx+TAPE_SENSE+2],3
        mov byte ptr es:[bx+TAPE_SENSE+12],0Ch
ifndef NO_RESIDUAL
        mov word ptr es:[bx+SRB_BufLen],4
endif
endif
endif
endif
        ret
native_write_command endp

native_marks_command proc near
        cmp byte ptr es:[bx+SRB_CDBLen],6
        jne native_marks_bad
        cmp byte ptr es:[bx+SRB_CDB+1],0 ; no IMMED or setmarks
        jne native_marks_bad
        cmp word ptr es:[bx+SRB_CDB+2],0
        jne native_marks_bad
        cmp byte ptr es:[bx+SRB_CDB+4],1
        ja native_marks_bad
        cmp byte ptr es:[bx+SRB_CDB+5],0
        jne native_marks_bad
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_NONE
        jne native_marks_bad
        cmp word ptr es:[bx+SRB_BufLen],0
        jne native_marks_bad
        cmp word ptr es:[bx+SRB_BufLen+2],0
        jne native_marks_bad
        cmp word ptr es:[bx+SRB_BufPointer],0
        jne native_marks_bad
        cmp word ptr es:[bx+SRB_BufPointer+2],0
        jne native_marks_bad
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        cmp byte ptr es:[bx+SRB_CDB+4],0
        je native_marks_zero
        inc word ptr cs:[native_marks]
ifdef NATIVE_ARCHIVE_TEST
        call native_archive_mark
        jnc native_archive_mark_ready
        ret
native_archive_mark_ready:
endif
ifdef NATIVE_FINISH_FAULT
if NATIVE_FINISH_FAULT eq 2
        jmp short native_marks_fault
endif
endif
        ret
native_marks_zero:
        inc word ptr cs:[native_flushes]
ifdef NATIVE_FINISH_FAULT
if NATIVE_FINISH_FAULT eq 1
        jmp short native_marks_fault
elseif NATIVE_FINISH_FAULT eq 3
        cmp word ptr cs:[native_flushes],2
        je native_marks_fault
endif
endif
        ret
native_marks_bad:
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
ifdef NATIVE_FINISH_FAULT
native_marks_fault:
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+TAPE_SENSE],70h
        mov byte ptr es:[bx+TAPE_SENSE+2],3
        mov byte ptr es:[bx+TAPE_SENSE+7],6
        mov byte ptr es:[bx+TAPE_SENSE+12],0Ch
        ret
endif
native_marks_command endp

ifdef NATIVE_ARCHIVE_TEST
        include tests/mockarchive.inc
endif

ifdef NATIVE_FIXED_IO_TEST
        include tests/mockfixednative.inc
endif

ifdef NATIVE_SPACE_TEST
        include tests/mockspace.inc
endif

ifdef NATIVE_MEDIA_TEST
        include tests/mockmedia.inc
endif
