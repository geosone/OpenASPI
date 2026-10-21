; Minimal read-only SCSIMGR$ fixture for the ASPITAP DOS smoke test.

        .8086
        option casemap:none

        .model tiny
        .code
        org     0

        include common/aspi/dos_aspi.inc

driver_start:
        dd      0FFFFFFFFh
        dw      0C000h                  ; character device + IOCTL read
        dw      strategy
        dw      interrupt
        db      'SCSIMGR$'

request_ptr     dd      0

strategy proc far
        mov     word ptr cs:[request_ptr], bx
        mov     word ptr cs:[request_ptr+2], es
        ret
strategy endp

interrupt proc far
        push    ax
        push    bx
        push    cx
        push    di
        push    ds
        push    es
        push    cs
        pop     ds

        les     bx, [request_ptr]
        cmp     byte ptr es:[bx+2], 0
        je      initialize
        cmp     byte ptr es:[bx+2], 3
        jne     unsupported

        ; DOS IOCTL input packet: transfer pointer at 0Eh, byte count at 12h.
        les     di, dword ptr es:[bx+0Eh]
        mov     word ptr es:[di], offset aspi_entry
        mov     word ptr es:[di+2], cs
        les     bx, [request_ptr]
        mov     word ptr es:[bx+12h], 4
        mov     word ptr es:[bx+3], 0100h
        jmp     short request_done

initialize:
ifdef REWIND_BREAK
        ; Isolate the synthetic Ctrl-Break from DOS' normal termination
        ; behavior; ASPITAP must chain this sentinel and restore its vector.
        pushf
        cli
        push es
        xor ax, ax
        mov es, ax
        mov word ptr es:[6Ch], offset fixture_break_handler
        mov word ptr es:[6Eh], cs
        pop es
        popf
endif
        mov     word ptr es:[bx+0Eh], offset resident_end
        mov     word ptr es:[bx+10h], cs
        mov     word ptr es:[bx+3], 0100h
        jmp     short request_done

unsupported:
        mov     word ptr es:[bx+3], 8103h

request_done:
        pop     es
        pop     ds
        pop     di
        pop     cx
        pop     bx
        pop     ax
        ret
interrupt endp

ifdef REWIND_BREAK
fixture_break_handler proc far
        inc byte ptr cs:[fixture_break_count]
        iret
fixture_break_handler endp
fixture_break_count db 0
endif

; ASPI entry point: one adapter with one tape at 0:0:0.
aspi_entry proc far
        push    bp
        mov     bp, sp
        push    ax
        push    bx
        push    cx
        push    di
        push    si
        push    es

        les     bx, dword ptr [bp+6]
        mov     al, byte ptr es:[bx+SRB_Cmd]
        cmp     al, SC_HA_INQUIRY
        je      host_inquiry
        cmp     al, SC_GET_DEV_TYPE
        je      device_type
        cmp     al, SC_EXEC_SCSI_CMD
        je      execute_scsi
        mov     byte ptr es:[bx+SRB_Status], SS_INVALID_CMD
        jmp     aspi_done

host_inquiry:
ifdef BAD_INQUIRY
        mov     byte ptr es:[bx+SRB_Status], SS_ERR
        jmp     aspi_done
endif
        push    ds
        push    cs
        pop     ds
        mov     si, offset mock_identity
        mov     di, bx
        add     di, HA_ManagerId
        mov     cx, 32
        cld
        rep     movsb
        pop     ds
ifdef NO_ADAPTERS
        mov     byte ptr es:[bx+HA_Count], 0
else
        mov     byte ptr es:[bx+HA_Count], 1
endif
        mov     byte ptr es:[bx+HA_SCSI_ID], 7
        mov     byte ptr es:[bx+HA_Unique+3], 1
ifdef NO_RESIDUAL
        mov     word ptr es:[bx+HA_ExtFlags], 0
else
        mov     word ptr es:[bx+HA_ExtFlags], HA_EXT_RESIDUAL
endif
        mov     byte ptr es:[bx+SRB_Status], SS_COMP
        jmp     aspi_done

device_type:
ifdef NO_TAPE
        jmp     no_device
endif
        cmp     byte ptr es:[bx+SRB_Target], 0
        jne     no_device
        cmp     byte ptr es:[bx+SRB_Lun], 0
        jne     no_device
        mov     byte ptr es:[bx+SRB_DeviceType], ASPI_DEV_TAPE
        mov     byte ptr es:[bx+SRB_Status], SS_COMP
        jmp     aspi_done
no_device:
        mov     byte ptr es:[bx+SRB_Status], SS_NO_DEVICE
        jmp     aspi_done

execute_scsi:
        cmp     byte ptr es:[bx+SRB_CDB], 05h
        jne     execute_data
        call    execute_read_block_limits
        jmp     aspi_done
execute_data:
ifdef BUFFERED_TEST
        ; ASPISCAN probes INQUIRY before the ordered media scenario starts.
        ; It is deliberately unsupported, not a protocol-sequence violation.
        cmp byte ptr es:[bx+SRB_CDB], 12h
        jne execute_buffered_test
        mov byte ptr es:[bx+SRB_Status], SS_ERR
        jmp aspi_done
execute_buffered_test:
        call buffered_test_command
        jmp aspi_done
endif
        cmp     byte ptr es:[bx+SRB_CDB], 08h
        je      execute_read
        cmp     byte ptr es:[bx+SRB_CDB], 0Ah
        jne     execute_control
        call    execute_write
        jmp     aspi_done
execute_control:
ifdef REWIND_TEST
        call rewind_test_control
        jmp aspi_done
endif
        cmp     byte ptr es:[bx+SRB_Flags], SRB_DIR_NONE
        jne     control_bad_scsi
        cmp     byte ptr es:[bx+SRB_CDBLen], 6
        jne     control_bad_scsi
        cmp     byte ptr es:[bx+SRB_SenseLen], 32
        jne     control_bad_scsi
        xor     ax, ax
        mov     al, byte ptr cs:[expected_index]
        cmp     al, EXPECTED_COUNT
        jae     control_bad_scsi
        mov     si, ax
        shl     si, 1
        mov     ax, si
        shl     si, 1
        add     si, ax                  ; six bytes per expected CDB
        add     si, offset expected_cdbs
        xor     di, di
        mov     cx, 6
check_cdb:
        mov     al, byte ptr cs:[si]
        cmp     al, byte ptr es:[bx+di+SRB_CDB]
        jne     control_bad_scsi
        inc     si
        inc     di
        loop    check_cdb
        inc     byte ptr cs:[expected_index]
        mov     byte ptr es:[bx+SRB_HaStat], 0
        mov     byte ptr es:[bx+SRB_TargStat], 0
        mov     byte ptr es:[bx+SRB_Status], SS_COMP
        jmp     aspi_done

control_bad_scsi:
        jmp     bad_scsi

execute_read:
        cmp     byte ptr es:[bx+SRB_CDB+1], 1
        jne     execute_variable_read
        call    execute_fixed_read
        jmp     aspi_done
execute_variable_read:
ifdef REWIND_TEST
        call rewind_test_data
        jmp aspi_done
endif
ifdef OPTION_OVERRIDES
        call    execute_option_read
        jmp     aspi_done
endif
ifdef NO_RESIDUAL
        cmp     byte ptr es:[bx+SRB_Flags], SRB_DIR_IN
else
        cmp     byte ptr es:[bx+SRB_Flags], SRB_DIR_IN or SRB_RESIDUAL
endif
        jne     read_bad_scsi
        cmp     byte ptr es:[bx+SRB_CDBLen], 6
        jne     read_bad_scsi
        cmp     byte ptr es:[bx+SRB_SenseLen], 32
        jne     read_bad_scsi
        cmp     word ptr es:[bx+SRB_BufLen], 16
        jne     read_bad_scsi
        cmp     word ptr es:[bx+SRB_BufLen+2], 0
        jne     read_bad_scsi
        xor     di, di
        mov     si, offset read_cdb
        mov     cx, 6
check_read_cdb:
        mov     al, byte ptr cs:[si]
        cmp     al, byte ptr es:[bx+di+SRB_CDB]
        jne     read_bad_scsi
        inc     si
        inc     di
        loop    check_read_cdb

        mov     al, byte ptr cs:[read_index]
        cmp     al, READ_COUNT
        jb      read_index_valid
read_bad_scsi:
        jmp     bad_scsi
read_index_valid:
        inc     byte ptr cs:[read_index]
        cmp     al, 0
        je      read_first
        cmp     al, 1
        je      read_short_ili
        cmp     al, 2
        je      read_filemark
        cmp     al, 3
        je      read_after_filemark
        cmp     al, 4
        je      read_eom
        cmp     al, 5
        je      read_descriptor_eom
        jmp     short read_negative_ili

read_first:
        mov     si, offset read_payload
        mov     cx, READ_PAYLOAD_SIZE
        call    copy_read_payload
ifndef NO_RESIDUAL
        mov     word ptr es:[bx+SRB_BufLen], 16-READ_PAYLOAD_SIZE
endif
        jmp     read_success

read_short_ili:
        mov     si, offset ili_payload
        mov     cx, ILI_PAYLOAD_SIZE
        call    copy_read_payload
ifndef NO_RESIDUAL
        mov     word ptr es:[bx+SRB_BufLen], 16-ILI_PAYLOAD_SIZE
endif
        mov     al, 20h                 ; ILI, no-sense key
        mov     dx, 16-ILI_PAYLOAD_SIZE ; requested minus actual
        call    set_descriptor_condition
ifdef READ_BAD_RESIDUAL
        call    corrupt_read_residual
endif
        jmp     aspi_done

read_filemark:
        mov     al, 80h                 ; FILEMARK, no-sense key
        mov     dx, 16                  ; no bytes transferred
        call    set_read_condition
ifdef READ_BAD_RESIDUAL
        call    corrupt_read_residual
endif
        jmp     short aspi_done

read_after_filemark:
        mov     si, offset after_filemark_payload
        mov     cx, AFTER_FILEMARK_SIZE
        call    copy_read_payload
ifndef NO_RESIDUAL
        mov     word ptr es:[bx+SRB_BufLen], 0
endif
        jmp     short read_success

read_eom:
        mov     al, 40h                 ; EOM, no-sense key
        mov     dx, 16                  ; no bytes transferred
        call    set_read_condition
        jmp     short aspi_done

read_descriptor_eom:
        mov     al, 40h                 ; EOM in stream-command descriptor
        mov     dx, 16
        call    set_descriptor_condition
ifdef READ_BAD_RESIDUAL
        call    corrupt_read_residual
endif
        jmp     short aspi_done

read_negative_ili:
ifndef NO_RESIDUAL
        mov     word ptr es:[bx+SRB_BufLen], 16
endif
        mov     byte ptr es:[bx+SRB_CDB+16], 0F0h
        mov     byte ptr es:[bx+SRB_CDB+18], 20h
        mov     byte ptr es:[bx+SRB_CDB+19], 0FFh
        mov     byte ptr es:[bx+SRB_CDB+20], 0FFh
        mov     byte ptr es:[bx+SRB_CDB+21], 0FFh
        mov     byte ptr es:[bx+SRB_CDB+22], 0FCh ; actual is four bytes too large
        mov     byte ptr es:[bx+SRB_HaStat], 0
        mov     byte ptr es:[bx+SRB_TargStat], 2
        mov     byte ptr es:[bx+SRB_Status], SS_ERR
        jmp     short aspi_done

read_success:
        mov     word ptr es:[bx+SRB_BufLen+2], 0
        mov     byte ptr es:[bx+SRB_HaStat], 0
        mov     byte ptr es:[bx+SRB_TargStat], 0
        mov     byte ptr es:[bx+SRB_Status], SS_COMP
        jmp     short aspi_done
bad_scsi:
        mov     byte ptr es:[bx+SRB_Status], SS_ERR

aspi_done:
        pop     es
        pop     si
        pop     di
        pop     cx
        pop     bx
        pop     ax
        pop     bp
        retf
aspi_entry endp

; Validate and complete the two writes issued by the DOS test. ES:BX points
; at the SRB and remains valid when this routine returns.
execute_write proc near
        cmp     byte ptr es:[bx+SRB_CDB+1], 1
        jne     execute_variable_write
        call    execute_fixed_write
        ret
execute_variable_write:
ifdef REWIND_TEST
        call rewind_test_data
        ret
endif
ifdef OPTION_OVERRIDES
        call    execute_option_write
        ret
endif
ifdef NO_RESIDUAL
        cmp     byte ptr es:[bx+SRB_Flags], SRB_DIR_OUT
else
        cmp     byte ptr es:[bx+SRB_Flags], SRB_DIR_OUT or SRB_RESIDUAL
endif
        jne     write_validation_failed
        cmp     byte ptr es:[bx+SRB_CDBLen], 6
        jne     write_validation_failed
        cmp     byte ptr es:[bx+SRB_SenseLen], 32
        jne     write_validation_failed
        cmp     word ptr es:[bx+SRB_BufLen+2], 0
        jne     write_validation_failed
        cmp     byte ptr es:[bx+SRB_CDB+1], 0
        jne     write_validation_failed
        cmp     byte ptr es:[bx+SRB_CDB+2], 0
        jne     write_validation_failed
        cmp     byte ptr es:[bx+SRB_CDB+3], 0
        jne     write_validation_failed
        mov     ax, word ptr es:[bx+SRB_BufLen]
        cmp     byte ptr es:[bx+SRB_CDB+4], al
        jne     write_validation_failed
        cmp     byte ptr es:[bx+SRB_CDB+5], 0
        je      write_validated
write_validation_failed:
        jmp     write_bad_scsi
write_validated:

        mov     al, byte ptr cs:[write_index]
        inc     byte ptr cs:[write_index]
        cmp     al, 0
        je      write_first
        cmp     al, 1
        jne     write_bad_scsi
        cmp     word ptr es:[bx+SRB_BufLen], 2
        jne     write_bad_scsi
ifndef NO_RESIDUAL
        mov     word ptr es:[bx+SRB_BufLen], 2
endif
        mov     byte ptr es:[bx+SRB_CDB+16], 70h
        mov     byte ptr es:[bx+SRB_CDB+18], 07h ; DATA PROTECT
        mov     byte ptr es:[bx+SRB_HaStat], 0
        mov     byte ptr es:[bx+SRB_TargStat], 2
        mov     byte ptr es:[bx+SRB_Status], SS_ERR
        ret

write_first:
        cmp     word ptr es:[bx+SRB_BufLen], WRITE_PAYLOAD_SIZE
        jne     write_bad_scsi
        push    es
        mov     ax, word ptr es:[bx+SRB_BufPointer+2]
        mov     si, word ptr es:[bx+SRB_BufPointer]
        mov     es, ax
        mov     di, offset write_payload
        mov     cx, WRITE_PAYLOAD_SIZE
write_compare_payload:
        mov     al, byte ptr cs:[di]
        cmp     al, byte ptr es:[si]
        jne     write_payload_bad
        inc     si
        inc     di
        loop    write_compare_payload
        pop     es
ifndef NO_RESIDUAL
        mov     word ptr es:[bx+SRB_BufLen], 0
endif
        mov     word ptr es:[bx+SRB_BufLen+2], 0
        mov     byte ptr es:[bx+SRB_HaStat], 0
        mov     byte ptr es:[bx+SRB_TargStat], 0
        mov     byte ptr es:[bx+SRB_Status], SS_COMP
        ret
write_payload_bad:
        pop     es
write_bad_scsi:
        mov     byte ptr es:[bx+SRB_Status], SS_ERR
        ret
execute_write endp

ifdef REWIND_TEST
; This fixture rejects media access until all progress responses were polled.
rewind_test_control proc near
        cmp byte ptr es:[bx+SRB_Flags], SRB_DIR_NONE
        jne rewind_test_bad
        cmp byte ptr es:[bx+SRB_CDBLen], 6
        jne rewind_test_bad
        cmp byte ptr es:[bx+SRB_CDB], 1
        jne rewind_test_not_rewind
ifdef WAIT_CLOSE
        cmp byte ptr es:[bx+SRB_CDB+1], 0
else
        cmp byte ptr es:[bx+SRB_CDB+1], 1
endif
        jne rewind_test_bad
        inc byte ptr cs:[rewind_seen]
        jmp short rewind_test_good
rewind_test_not_rewind:
        cmp byte ptr cs:[rewind_seen], 1
        jne rewind_test_bad
        cmp byte ptr es:[bx+SRB_CDB], 0
        je rewind_test_tur
        cmp byte ptr cs:[rewind_polls], 5
        jb rewind_test_bad
        ; Written NRMT0 close must still terminate and backspace a filemark.
        cmp byte ptr es:[bx+SRB_CDB], 10h
        jne rewind_test_space
        cmp byte ptr es:[bx+SRB_CDB+4], 2
        jne rewind_test_bad
        jmp short rewind_test_good
rewind_test_space:
        cmp byte ptr es:[bx+SRB_CDB], 11h
        jne rewind_test_bad
        cmp byte ptr es:[bx+SRB_CDB+1], 1
        jne rewind_test_bad
        cmp word ptr es:[bx+SRB_CDB+2], 0FFFFh
        jne rewind_test_bad
        cmp byte ptr es:[bx+SRB_CDB+4], 0FFh
        jne rewind_test_bad
rewind_test_good:
        mov byte ptr es:[bx+SRB_Status], SS_COMP
        ret
rewind_test_bad:
        mov byte ptr es:[bx+SRB_Status], SS_ERR
        ret
rewind_test_tur:
        inc byte ptr cs:[rewind_polls]
ifdef REWIND_BREAK
        cmp byte ptr cs:[rewind_polls], 1
        jne rewind_break_already_sent
        int 1Bh
        cmp byte ptr cs:[fixture_break_count], 1
        je rewind_break_already_sent
        jmp rewind_test_bad
rewind_break_already_sent:
        cmp byte ptr cs:[rewind_polls], 1
        jne rewind_break_poll_done
        mov byte ptr es:[bx+SRB_TargStat], 8
        mov byte ptr es:[bx+SRB_Status], SS_ERR
        ret
rewind_break_poll_done:
        ; The next wait may retry after the caller handles the interruption.
        mov byte ptr es:[bx+SRB_Status], SS_COMP
        ret
endif
ifdef REWIND_TIMEOUT
        push ds
        mov ax, 40h
        mov ds, ax
        pushf
        cli
        add word ptr ds:[6Ch], 3277     ; accelerate three minutes of BIOS time
        adc word ptr ds:[6Eh], 0
        popf
        pop ds
        mov byte ptr es:[bx+SRB_TargStat], 8
        mov byte ptr es:[bx+SRB_Status], SS_ERR
        ret
endif
ifdef WAIT_CLOSE
        jmp short rewind_test_good
else
ifdef REWIND_ERROR
        mov byte ptr es:[bx+SRB_CDB+16], 70h
        mov byte ptr es:[bx+SRB_CDB+18], 2
        mov byte ptr es:[bx+SRB_CDB+28], 3Ah ; no media: do not retry
else
        cmp byte ptr cs:[rewind_polls], 1
        jne rewind_test_sense
ifdef REWIND_MIDNIGHT
        push ds
        mov ax, 40h
        mov ds, ax
        pushf
        cli
        mov word ptr ds:[6Ch], 0
        mov word ptr ds:[6Eh], 0
        popf
        pop ds
endif
        mov byte ptr es:[bx+SRB_TargStat], 8 ; BUSY, without sense
        mov byte ptr es:[bx+SRB_Status], SS_ERR
        ret
rewind_test_sense:
        cmp byte ptr cs:[rewind_polls], 2
        jne rewind_test_descriptor
        mov byte ptr es:[bx+SRB_CDB+16], 70h
        mov byte ptr es:[bx+SRB_CDB+18], 2
        mov byte ptr es:[bx+SRB_CDB+28], 4
        mov byte ptr es:[bx+SRB_CDB+29], 1 ; becoming ready
        jmp short rewind_test_condition
rewind_test_descriptor:
        cmp byte ptr cs:[rewind_polls], 3
        jne rewind_test_progress
        mov byte ptr es:[bx+SRB_CDB+16], 72h
        mov byte ptr es:[bx+SRB_CDB+17], 2
        mov byte ptr es:[bx+SRB_CDB+18], 4
        mov byte ptr es:[bx+SRB_CDB+19], 7 ; operation in progress
        jmp short rewind_test_condition
rewind_test_progress:
        cmp byte ptr cs:[rewind_polls], 4
        je rewind_test_report_progress
        jmp rewind_test_good
rewind_test_report_progress:
        mov byte ptr es:[bx+SRB_CDB+16], 70h
        mov byte ptr es:[bx+SRB_CDB+29], 1Ah ; no-sense rewind progress
endif
rewind_test_condition:
        mov byte ptr es:[bx+SRB_TargStat], 2
        mov byte ptr es:[bx+SRB_Status], SS_ERR
        ret
endif
rewind_test_control endp

rewind_test_data proc near
        cmp byte ptr cs:[rewind_polls], 5
        jb rewind_test_data_bad
        cmp word ptr es:[bx+SRB_BufLen], 2
        jne rewind_test_data_bad
        cmp byte ptr es:[bx+SRB_CDB+4], 2
        jne rewind_test_data_bad
        mov word ptr es:[bx+SRB_BufLen], 0
        mov byte ptr es:[bx+SRB_Status], SS_COMP
        ret
rewind_test_data_bad:
        mov byte ptr es:[bx+SRB_Status], SS_ERR
        ret
rewind_test_data endp
rewind_seen db 0
rewind_polls db 0
endif

ifdef OPTION_OVERRIDES
execute_option_read proc near
        cmp     byte ptr es:[bx+SRB_Flags], SRB_DIR_IN or SRB_RESIDUAL
        jne     option_read_bad
        cmp     byte ptr es:[bx+SRB_CDBLen], 6
        jne     option_read_bad
        cmp     byte ptr es:[bx+SRB_SenseLen], 32
        jne     option_read_bad
        cmp     word ptr es:[bx+SRB_BufLen+2], 0
        jne     option_read_bad
        mov     al, byte ptr cs:[read_index]
        inc     byte ptr cs:[read_index]
        or      al, al
        jnz     option_read_one
        cmp     word ptr es:[bx+SRB_BufLen], 2
        jne     option_read_bad
        jmp     short option_read_complete
option_read_one:
        cmp     al, 1
        jne     option_read_bad
        cmp     word ptr es:[bx+SRB_BufLen], 1
        jne     option_read_bad
option_read_complete:
        mov     word ptr es:[bx+SRB_BufLen], 0
        mov     word ptr es:[bx+SRB_BufLen+2], 0
        mov     byte ptr es:[bx+SRB_HaStat], 0
        mov     byte ptr es:[bx+SRB_TargStat], 0
        mov     byte ptr es:[bx+SRB_Status], SS_COMP
        ret
option_read_bad:
        mov     byte ptr es:[bx+SRB_Status], SS_ERR
        ret
execute_option_read endp

execute_option_write proc near
        cmp     byte ptr es:[bx+SRB_Flags], SRB_DIR_OUT or SRB_RESIDUAL
        jne     option_write_bad
        cmp     byte ptr es:[bx+SRB_CDBLen], 6
        jne     option_write_bad
        cmp     byte ptr es:[bx+SRB_SenseLen], 32
        jne     option_write_bad
        cmp     word ptr es:[bx+SRB_BufLen], 1
        jne     option_write_bad
        cmp     word ptr es:[bx+SRB_BufLen+2], 0
        jne     option_write_bad
        cmp     byte ptr es:[bx+SRB_CDB+4], 1
        jne     option_write_bad
        mov     word ptr es:[bx+SRB_BufLen], 0
        mov     byte ptr es:[bx+SRB_HaStat], 0
        mov     byte ptr es:[bx+SRB_TargStat], 0
        mov     byte ptr es:[bx+SRB_Status], SS_COMP
        ret
option_write_bad:
        mov     byte ptr es:[bx+SRB_Status], SS_ERR
        ret
execute_option_write endp
endif

execute_fixed_read proc near
ifdef NO_RESIDUAL
        cmp     byte ptr es:[bx+SRB_Flags], SRB_DIR_IN
else
        cmp     byte ptr es:[bx+SRB_Flags], SRB_DIR_IN or SRB_RESIDUAL
endif
        jne     fixed_read_bad
        cmp     byte ptr es:[bx+SRB_CDBLen], 6
        jne     fixed_read_bad
        cmp     byte ptr es:[bx+SRB_SenseLen], 32
        jne     fixed_read_bad
        cmp     word ptr es:[bx+SRB_BufLen], 1024
        jne     fixed_read_bad
        cmp     word ptr es:[bx+SRB_BufLen+2], 0
        jne     fixed_read_bad
        cmp     byte ptr es:[bx+SRB_CDB+2], 0
        jne     fixed_read_bad
        cmp     byte ptr es:[bx+SRB_CDB+3], 0
        jne     fixed_read_bad
        cmp     byte ptr es:[bx+SRB_CDB+4], 1
        jne     fixed_read_bad
        cmp     byte ptr es:[bx+SRB_CDB+5], 0
        jne     fixed_read_bad

        push    es
        mov     ax, word ptr es:[bx+SRB_BufPointer+2]
        mov     di, word ptr es:[bx+SRB_BufPointer]
        mov     es, ax
        mov     al, 5Ah
        mov     cx, 1024
        rep     stosb
        pop     es
ifndef NO_RESIDUAL
        mov     word ptr es:[bx+SRB_BufLen], 0
endif
        mov     word ptr es:[bx+SRB_BufLen+2], 0
        mov     byte ptr es:[bx+SRB_HaStat], 0
        mov     byte ptr es:[bx+SRB_TargStat], 0
        mov     byte ptr es:[bx+SRB_Status], SS_COMP
        ret
fixed_read_bad:
        mov     byte ptr es:[bx+SRB_Status], SS_ERR
        ret
execute_fixed_read endp

execute_fixed_write proc near
ifdef NO_RESIDUAL
        cmp     byte ptr es:[bx+SRB_Flags], SRB_DIR_OUT
else
        cmp     byte ptr es:[bx+SRB_Flags], SRB_DIR_OUT or SRB_RESIDUAL
endif
        jne     fixed_write_bad
        cmp     byte ptr es:[bx+SRB_CDBLen], 6
        jne     fixed_write_bad
        cmp     byte ptr es:[bx+SRB_SenseLen], 32
        jne     fixed_write_bad
        cmp     word ptr es:[bx+SRB_BufLen], 1024
        jne     fixed_write_bad
        cmp     word ptr es:[bx+SRB_BufLen+2], 0
        jne     fixed_write_bad
        cmp     byte ptr es:[bx+SRB_CDB+2], 0
        jne     fixed_write_bad
        cmp     byte ptr es:[bx+SRB_CDB+3], 0
        jne     fixed_write_bad
        cmp     byte ptr es:[bx+SRB_CDB+4], 1
        jne     fixed_write_bad
        cmp     byte ptr es:[bx+SRB_CDB+5], 0
        jne     fixed_write_bad

        push    es
        mov     ax, word ptr es:[bx+SRB_BufPointer+2]
        mov     si, word ptr es:[bx+SRB_BufPointer]
        mov     es, ax
        mov     cx, 1024
fixed_write_compare:
        cmp     byte ptr es:[si], 0A5h
        jne     fixed_write_payload_bad
        inc     si
        loop    fixed_write_compare
        pop     es
ifndef NO_RESIDUAL
        mov     word ptr es:[bx+SRB_BufLen], 0
endif
        mov     word ptr es:[bx+SRB_BufLen+2], 0
        mov     byte ptr es:[bx+SRB_HaStat], 0
        mov     byte ptr es:[bx+SRB_TargStat], 0
        mov     byte ptr es:[bx+SRB_Status], SS_COMP
        ret
fixed_write_payload_bad:
        pop     es
fixed_write_bad:
        mov     byte ptr es:[bx+SRB_Status], SS_ERR
        ret
execute_fixed_write endp

execute_read_block_limits proc near
ifdef NO_RESIDUAL
        cmp     byte ptr es:[bx+SRB_Flags], SRB_DIR_IN
else
        cmp     byte ptr es:[bx+SRB_Flags], SRB_DIR_IN or SRB_RESIDUAL
endif
        jne     block_limits_bad
        cmp     byte ptr es:[bx+SRB_CDBLen], 6
        jne     block_limits_bad
        cmp     byte ptr es:[bx+SRB_SenseLen], 32
        jne     block_limits_bad
        cmp     word ptr es:[bx+SRB_BufLen], 6
        jne     block_limits_bad
        cmp     word ptr es:[bx+SRB_BufLen+2], 0
        jne     block_limits_bad

        push    ds
        push    es
        push    bx
        mov     ax, word ptr es:[bx+SRB_BufPointer+2]
        mov     di, word ptr es:[bx+SRB_BufPointer]
        mov     es, ax
        push    cs
        pop     ds
        mov     si, offset block_limits_response
        mov     cx, 6
        rep     movsb
        pop     bx
        pop     es
        pop     ds
ifndef NO_RESIDUAL
        mov     word ptr es:[bx+SRB_BufLen], 0
endif
        mov     word ptr es:[bx+SRB_BufLen+2], 0
        mov     byte ptr es:[bx+SRB_HaStat], 0
        mov     byte ptr es:[bx+SRB_TargStat], 0
        mov     byte ptr es:[bx+SRB_Status], SS_COMP
        ret
block_limits_bad:
        mov     byte ptr es:[bx+SRB_Status], SS_ERR
        ret
execute_read_block_limits endp

; Copy CX bytes from CS:SI to the caller's transfer buffer while preserving
; the SRB pointer in ES:BX.
copy_read_payload proc near
        push    ds
        push    es
        push    bx
        mov     ax, word ptr es:[bx+SRB_BufPointer+2]
        mov     di, word ptr es:[bx+SRB_BufPointer]
        mov     es, ax
        push    cs
        pop     ds
        rep     movsb
        pop     bx
        pop     es
        pop     ds
        ret
copy_read_payload endp

ifdef READ_BAD_RESIDUAL
; Sense remains plausible: it must never mask the manager's invalid length.
corrupt_read_residual proc near
ifdef READ_BAD_RESIDUAL_HIGH
        mov     word ptr es:[bx+SRB_BufLen], 0
        mov     word ptr es:[bx+SRB_BufLen+2], 1
else
        mov     word ptr es:[bx+SRB_BufLen], 17
endif
        ret
corrupt_read_residual endp
endif

; Return fixed-format CHECK CONDITION sense. AL contains FILEMARK/EOM/ILI and
; DX contains the positive requested-minus-actual information value.
set_read_condition proc near
ifndef NO_RESIDUAL
        mov     word ptr es:[bx+SRB_BufLen], dx
endif
        mov     word ptr es:[bx+SRB_BufLen+2], 0
        mov     byte ptr es:[bx+SRB_CDB+16], 0F0h
        mov     byte ptr es:[bx+SRB_CDB+18], al
        mov     byte ptr es:[bx+SRB_CDB+19], 0
        mov     byte ptr es:[bx+SRB_CDB+20], 0
        mov     byte ptr es:[bx+SRB_CDB+21], dh
        mov     byte ptr es:[bx+SRB_CDB+22], dl
        mov     byte ptr es:[bx+SRB_HaStat], 0
        mov     byte ptr es:[bx+SRB_TargStat], 2
        mov     byte ptr es:[bx+SRB_Status], SS_ERR
        ret
set_read_condition endp

; Return descriptor-format CHECK CONDITION sense. AL contains the stream
; FILEMARK/EOM/ILI bits and DX contains requested-minus-actual bytes.
set_descriptor_condition proc near
ifndef NO_RESIDUAL
        mov     word ptr es:[bx+SRB_BufLen], dx
endif
        mov     word ptr es:[bx+SRB_BufLen+2], 0
        mov     byte ptr es:[bx+SRB_CDB+16], 72h
        mov     byte ptr es:[bx+SRB_CDB+17], 00h
        mov     byte ptr es:[bx+SRB_CDB+18], 00h
        mov     byte ptr es:[bx+SRB_CDB+19], 00h
        mov     byte ptr es:[bx+SRB_CDB+23], 16
        mov     byte ptr es:[bx+SRB_CDB+24], 00h
        mov     byte ptr es:[bx+SRB_CDB+25], 0Ah
        mov     byte ptr es:[bx+SRB_CDB+26], 80h
        mov     byte ptr es:[bx+SRB_CDB+27], 00h
        mov     word ptr es:[bx+SRB_CDB+28], 0
        mov     word ptr es:[bx+SRB_CDB+30], 0
        mov     word ptr es:[bx+SRB_CDB+32], 0
        mov     byte ptr es:[bx+SRB_CDB+34], dh
        mov     byte ptr es:[bx+SRB_CDB+35], dl
        mov     byte ptr es:[bx+SRB_CDB+36], 04h
        mov     byte ptr es:[bx+SRB_CDB+37], 02h
        mov     byte ptr es:[bx+SRB_CDB+38], 00h
        mov     byte ptr es:[bx+SRB_CDB+39], al
        mov     byte ptr es:[bx+SRB_HaStat], 0
        mov     byte ptr es:[bx+SRB_TargStat], 2
        mov     byte ptr es:[bx+SRB_Status], SS_ERR
        ret
set_descriptor_condition endp

ifdef OPTION_OVERRIDES
EXPECTED_COUNT equ     3
else
ifdef FIXED_BLOCK
EXPECTED_COUNT equ     2
else
EXPECTED_COUNT equ     17
endif
endif
READ_COUNT     equ     7
; '$' must be printed literally; the control byte must be sanitized.
mock_identity  db      'MOCK', '$', 1, 'ASPI', 6 dup (' ')
               db      'MOCK TAPE HA', 4 dup (' ')
expected_index db      0
read_index     db      0
write_index    db      0
read_cdb       db      08h, 00h, 00h, 00h, 10h, 00h
ifdef NO_RESIDUAL
READ_PAYLOAD_SIZE equ  16
read_payload   db      '0123456789ABCDEF'
else
READ_PAYLOAD_SIZE equ  12
read_payload   db      'TAPE-READ-OK'
endif
ILI_PAYLOAD_SIZE equ   12
ili_payload    db      'ILI-READ-OK!'
AFTER_FILEMARK_SIZE equ 16
after_filemark_payload db 'AFTER-FILEMARK!!'
WRITE_PAYLOAD_SIZE equ 12
write_payload  db      'WRITE-RECORD'
ifdef FIXED_BLOCK
block_limits_response db 00h, 00h, 04h, 00h, 04h, 00h
else
block_limits_response db 00h, 00h, 0FFh, 0FFh, 00h, 01h
endif
expected_cdbs:
ifdef OPTION_OVERRIDES
        db      01h, 00h, 00h, 00h, 00h, 00h ; RST0$ close: rewind
        db      10h, 00h, 00h, 00h, 02h, 00h ; close: two filemarks
        db      11h, 01h, 0FFh, 0FFh, 0FFh, 00h ; close: backspace one
else
ifdef FIXED_BLOCK
        db      10h, 00h, 00h, 00h, 02h, 00h ; close: two filemarks
        db      11h, 01h, 0FFh, 0FFh, 0FFh, 00h ; close: backspace one
else
        db      00h, 00h, 00h, 00h, 00h, 00h ; MTNOP between RMT0 closes
        db      01h, 00h, 00h, 00h, 00h, 00h ; final RMT0 close rewinds
        db      00h, 00h, 00h, 00h, 00h, 00h ; MTNOP / TEST UNIT READY
        db      10h, 00h, 00h, 00h, 02h, 00h ; MTWEOF 2
        db      11h, 01h, 00h, 00h, 03h, 00h ; MTFSF 3
        db      11h, 01h, 0FFh, 0FFh, 0FDh, 00h ; MTBSF 3
        db      11h, 00h, 00h, 00h, 04h, 00h ; MTFSR 4
        db      11h, 00h, 0FFh, 0FFh, 0FCh, 00h ; MTBSR 4
        db      01h, 00h, 00h, 00h, 00h, 00h ; MTREW
        db      1Bh, 00h, 00h, 00h, 00h, 00h ; MTOFFL
        db      10h, 00h, 0FFh, 0FFh, 0FFh, 00h ; MTWEOF unsigned maximum
        db      11h, 01h, 7Fh, 0FFh, 0FFh, 00h ; MTFSF signed maximum
        db      11h, 00h, 7Fh, 0FFh, 0FFh, 00h ; MTFSR signed maximum
        db      11h, 01h, 80h, 00h, 00h, 00h ; MTBSF signed minimum
        db      11h, 00h, 80h, 00h, 00h, 00h ; MTBSR signed minimum
        db      10h, 00h, 00h, 00h, 02h, 00h ; close: two filemarks
        db      11h, 01h, 0FFh, 0FFh, 0FFh, 00h ; close: backspace one
endif
endif

ifdef BUFFERED_TEST
        include tests/mockbuffered.inc
endif
resident_end label byte

        end     driver_start
