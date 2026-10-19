; ASPITAP.SYS bootstrap driver for OpenASPI.
;
; The driver locates SCSIMGR$, claims the first ASPI sequential-access device,
; and exposes the historical RMT0/NRMT0 names. The non-destructive generic
; IOCTL interface provides status, EOT policy, spacing, rewind, unload and
; readiness operations. Variable-block reads use residual counts when the ASPI
; manager provides them and retain exact-length compatibility with older
; managers. Variable-block writes use the same ASPI residual extension and
; finalize written sessions with two filemarks on final close.

        .8086
        option casemap:none

        .model tiny
        .code
        org     0

        include common/aspi/dos_aspi.inc

DEV_ATTR        equ     08840h          ; character + open/close + generic IOCTL
REQ_COMMAND     equ     02h
REQ_STATUS      equ     03h
REQ_CATEGORY    equ     0Dh
REQ_FUNCTION    equ     0Eh
REQ_PARAMETER   equ     13h
REQ_TRANSFER    equ     0Eh
REQ_COUNT       equ     12h
REQ_INIT_ARGS   equ     12h

CMD_INIT        equ     00h
CMD_READ        equ     04h
CMD_WRITE       equ     08h
CMD_OPEN        equ     0Dh
CMD_CLOSE       equ     0Eh
CMD_GEN_IOCTL   equ     13h

IOCTL_TAPE      equ     07h
IOCTL_MTOP      equ     01h
IOCTL_MTGET     equ     02h
IOCTL_IGNORE_EOT equ    03h
IOCTL_ENABLE_EOT equ    04h

MTWEOF          equ     00h
MTFSF           equ     01h
MTBSF           equ     02h
MTFSR           equ     03h
MTBSR           equ     04h
MTREW           equ     05h
MTOFFL          equ     06h
MTNOP           equ     07h

SCSI_TUR        equ     00h
SCSI_REWIND     equ     01h
SCSI_READ_BLOCK_LIMITS equ 05h
SCSI_READ       equ     08h
SCSI_WRITE      equ     0Ah
SCSI_WRITE_FILEMARKS equ 10h
SCSI_SPACE      equ     11h
SCSI_LOAD       equ     1Bh
SPACE_BLOCKS    equ     00h
SPACE_FILEMARKS equ     01h

MT_PARAM_ASPI   equ     080h
MT_PARAM_FIXED  equ     001h
MT_STATE_REWIND equ     004h
MT_STATE_WRITTEN equ    008h
MT_STATE_READ   equ     010h
MT_STATE_EOF_NEXT equ   020h
MT_STATE_EOM_EOF equ    040h

OPT_ALLOW_SINGLE equ    001h
OPT_ALLOW_MULTIPLE equ  002h
OPT_NAME_SUFFIX  equ    004h
OPT_VERBOSE      equ    008h

SENSE_FILEMARK  equ     080h
SENSE_EOM       equ     040h
SENSE_ILI       equ     020h

driver_start:
        dw      offset nrmt_header, 0   ; second header is in this segment
        dw      DEV_ATTR
        dw      strategy_rmt
        dw      interrupt
rmt_device_name db      'RMT0    '

nrmt_header:
        dd      0FFFFFFFFh              ; end of DOS device chain
        dw      DEV_ATTR
        dw      strategy_nrmt
        dw      interrupt
nrmt_device_name db     'NRMT0   '

request_ptr     dd      0
request_rewind  db      0

strategy_rmt proc far
        mov     byte ptr cs:[request_rewind], MT_STATE_REWIND
        mov     word ptr cs:[request_ptr], bx
        mov     word ptr cs:[request_ptr+2], es
        ret
strategy_rmt endp

strategy_nrmt proc far
        mov     byte ptr cs:[request_rewind], 0
        mov     word ptr cs:[request_ptr], bx
        mov     word ptr cs:[request_ptr+2], es
        ret
strategy_nrmt endp

interrupt proc far
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es

        push    cs
        pop     ds
        cld
        les     bx, [request_ptr]
        mov     al, byte ptr es:[bx+REQ_COMMAND]
        cmp     al, CMD_INIT
        je      init_request
        cmp     al, CMD_OPEN
        jne     dispatch_close
        jmp     open_request
dispatch_close:
        cmp     al, CMD_CLOSE
        jne     dispatch_ioctl
        jmp     close_request
dispatch_ioctl:
        cmp     al, CMD_GEN_IOCTL
        jne     dispatch_read
        jmp     generic_ioctl
dispatch_read:
        cmp     al, CMD_READ
        je      read_request_dispatch
        cmp     al, CMD_WRITE
        je      write_request_dispatch
        jmp     unsupported

read_request_dispatch:
        call    read_request
        jnc     read_request_success
        jmp     request_error
read_request_success:
        jmp     request_success

write_request_dispatch:
        call    write_request
        jnc     write_request_success
        jmp     request_error
write_request_success:
        jmp     request_success

init_request:
        call    parse_init_options
        jnc     init_options_valid
        mov     dx, offset banner_bad_options
        jmp     init_report_failure
init_options_valid:
        call    apply_device_names
        call    discover_tape
        jc      init_failed

        les     bx, [request_ptr]
        mov     word ptr es:[bx+0Eh], offset resident_end
        mov     word ptr es:[bx+10h], cs
        mov     word ptr es:[bx+REQ_STATUS], 0100h

        mov     dx, offset banner_found
        mov     ah, 09h
        int     21h
        mov     al, byte ptr [tape_ha]
        call    print_hex8
        mov     dl, ':'
        call    print_char
        mov     al, byte ptr [tape_target]
        call    print_hex8
        mov     dl, ':'
        call    print_char
        mov     al, byte ptr [tape_lun]
        call    print_hex8
        mov     dx, offset banner_tail
        mov     ah, 09h
        int     21h
        jmp     request_done

init_failed:
        mov     dx, offset banner_missing
init_report_failure:
        les     bx, [request_ptr]
        mov     word ptr es:[bx+0Eh], 0
        mov     word ptr es:[bx+10h], cs
        mov     word ptr es:[bx+REQ_STATUS], 810Ch
        mov     ah, 09h
        int     21h
        jmp     request_done

unsupported:
        mov     word ptr es:[bx+REQ_STATUS], 8103h
        jmp     request_done

open_request:
        cmp     byte ptr [tape_open_count], 0FFh
        je      request_error
        cmp     byte ptr [tape_open_count], 0
        jne     open_increment
        and     byte ptr [device_state], MT_STATE_EOM_EOF
open_increment:
        inc     byte ptr [tape_open_count]
        jmp     short request_success

close_request:
        cmp     byte ptr [tape_open_count], 0
        je      request_success
        dec     byte ptr [tape_open_count]
        jne     request_success
        call    finish_written_tape
        jc      request_error
        cmp     byte ptr [request_rewind], 0
        je      close_complete
        call    rewind_on_close
        jc      request_error
close_complete:
        and     byte ptr [device_state], MT_STATE_EOM_EOF
        jmp     short request_success

generic_ioctl:
        cmp     byte ptr es:[bx+REQ_CATEGORY], IOCTL_TAPE
        jne     unsupported
        mov     al, byte ptr es:[bx+REQ_FUNCTION]
        cmp     al, IOCTL_MTGET
        je      ioctl_mtget
        cmp     al, IOCTL_IGNORE_EOT
        je      ioctl_ignore_eot
        cmp     al, IOCTL_ENABLE_EOT
        je      ioctl_enable_eot
        cmp     al, IOCTL_MTOP
        jne     unsupported
        call    ioctl_mtop
        jc      request_error
        jmp     short request_success

ioctl_mtget:
        call    fill_mtget
        jmp     short request_success

ioctl_ignore_eot:
        or      byte ptr [device_state], MT_STATE_EOM_EOF
        jmp     short request_success

ioctl_enable_eot:
        and     byte ptr [device_state], not MT_STATE_EOM_EOF
        jmp     short request_success

request_error:
        les     bx, [request_ptr]
        mov     word ptr es:[bx+REQ_STATUS], 810Ch
        jmp     short request_done

request_success:
        les     bx, [request_ptr]
        mov     word ptr es:[bx+REQ_STATUS], 0100h

request_done:
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
interrupt endp

; Fill the byte-exact fourteen-byte ASPITAPE mtget structure.
fill_mtget proc near
        les     bx, [request_ptr]
        les     di, dword ptr es:[bx+REQ_PARAMETER]
        mov     al, byte ptr [tape_ha]
        mov     byte ptr es:[di+0], al
        mov     al, byte ptr [tape_target]
        mov     byte ptr es:[di+1], al
        mov     al, byte ptr [tape_lun]
        mov     byte ptr es:[di+2], al
        mov     al, MT_PARAM_ASPI
        cmp     word ptr [tape_fixed_block], 0
        je      mtget_parameters_ready
        or      al, MT_PARAM_FIXED
mtget_parameters_ready:
        mov     byte ptr es:[di+3], al
        mov     al, byte ptr [device_state]
        or      al, byte ptr [request_rewind]
        mov     byte ptr es:[di+4], al
        mov     byte ptr es:[di+5], 0
        mov     ax, word ptr [tape_fixed_block]
        mov     word ptr es:[di+6], ax
        mov     al, byte ptr [last_scsi_status]
        mov     byte ptr es:[di+8], al
        mov     al, byte ptr [last_sense_key]
        mov     byte ptr es:[di+9], al
        mov     ax, word ptr [last_scsi_opcode]
        mov     word ptr es:[di+0Ah], ax
        mov     ax, word ptr [residual_bytes]
        mov     word ptr es:[di+0Ch], ax
        ret
fill_mtget endp

; Process a DOS character-device input request as one variable-length SCSI
; tape record. The manager's residual-count extension lets DOS see a short
; record's actual length; older managers can still complete exact-size reads.
read_request proc near
        les     bx, [request_ptr]
        mov     ax, word ptr es:[bx+REQ_COUNT]
        mov     word ptr [requested_bytes], ax
        mov     word ptr es:[bx+REQ_COUNT], 0
        or      ax, ax
        jnz     read_nonempty
        clc
        ret

read_nonempty:
        test    byte ptr [config_options], OPT_ALLOW_MULTIPLE
        jnz     read_open_allowed
        cmp     byte ptr [tape_open_count], 1
        jne     read_access_error
read_open_allowed:
        cmp     word ptr [requested_bytes], 1
        jne     read_size_allowed
        test    byte ptr [config_options], OPT_ALLOW_SINGLE
        jz      read_access_error
read_size_allowed:
        test    byte ptr [device_state], MT_STATE_WRITTEN
        jz      read_not_written
        call    zero_transfer_count
        stc
        ret
read_not_written:
        test    byte ptr [device_state], MT_STATE_EOF_NEXT
        jz      read_issue
        and     byte ptr [device_state], not MT_STATE_EOF_NEXT
        clc
        ret

read_access_error:
        call    zero_transfer_count
        stc
        ret

read_issue:
        call    clear_srb
        mov     byte ptr [srb+SRB_Cmd], SC_EXEC_SCSI_CMD
        mov     al, byte ptr [tape_ha]
        mov     byte ptr [srb+SRB_HaId], al
        mov     byte ptr [srb+SRB_Flags], SRB_DIR_IN
        test    word ptr [adapter_ext_flags], HA_EXT_RESIDUAL
        jz      read_flags_ready
        or      byte ptr [srb+SRB_Flags], SRB_RESIDUAL
read_flags_ready:
        mov     al, byte ptr [tape_target]
        mov     byte ptr [srb+SRB_Target], al
        mov     al, byte ptr [tape_lun]
        mov     byte ptr [srb+SRB_Lun], al
        mov     ax, word ptr [requested_bytes]
        mov     word ptr [srb+SRB_BufLen], ax
        mov     word ptr [srb+SRB_BufLen+2], 0
        les     bx, [request_ptr]
        mov     ax, word ptr es:[bx+REQ_TRANSFER]
        mov     word ptr [srb+SRB_BufPointer], ax
        mov     ax, word ptr es:[bx+REQ_TRANSFER+2]
        mov     word ptr [srb+SRB_BufPointer+2], ax
        mov     byte ptr [srb+SRB_SenseLen], 32
        mov     byte ptr [srb+SRB_CDBLen], 6
        mov     byte ptr [srb+SRB_CDB], SCSI_READ
        cmp     word ptr [tape_fixed_block], 0
        je      read_variable_length
        xor     dx, dx
        mov     ax, word ptr [requested_bytes]
        div     word ptr [tape_fixed_block]
        or      dx, dx
        jnz     read_bad_block_size
        or      byte ptr [srb+SRB_CDB+1], 1
        jmp     short read_length_ready
read_variable_length:
        mov     ax, word ptr [requested_bytes]
read_length_ready:
        mov     byte ptr [srb+SRB_CDB+3], ah
        mov     byte ptr [srb+SRB_CDB+4], al

        xor     ax, ax
        mov     al, byte ptr [srb+SRB_CDB]
        mov     ah, byte ptr [srb+SRB_Flags]
        mov     dl, byte ptr [srb+SRB_CDB+1]
        and     dl, 7
        or      ah, dl
        mov     word ptr [last_scsi_opcode], ax
        call    call_aspi

        mov     al, byte ptr [srb+SRB_TargStat]
        mov     byte ptr [last_scsi_status], al
        mov     byte ptr [last_sense_key], 0
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        jne     read_scsi_failed
        call    finish_transfer_count
        jc      read_bad_residual
        or      byte ptr [device_state], MT_STATE_READ
        clc
        ret

read_bad_block_size:
        call    zero_transfer_count
        stc
        ret

read_bad_residual:
        call    zero_transfer_count
        stc
        ret
read_scsi_failed:
        call    remember_sense_key
        test    byte ptr [srb+SRB_Flags], SRB_RESIDUAL
        jz      read_count_from_sense
        call    finish_transfer_count
        jnc     read_classify_sense
        jmp     short read_zero_failed
read_count_from_sense:
        call    finish_read_sense_count
        jnc     read_classify_sense
read_zero_failed:
        call    zero_transfer_count
read_classify_sense:
        call    classify_read_sense
        jc      read_condition_error
        or      byte ptr [device_state], MT_STATE_READ
        clc
        ret
read_condition_error:
        stc
        ret
read_request endp

; Process one DOS output request as one variable-length SCSI tape record.
; A zero-byte DOS write marks the session written without issuing a data CDB.
write_request proc near
        les     bx, [request_ptr]
        mov     ax, word ptr es:[bx+REQ_COUNT]
        mov     word ptr [requested_bytes], ax
        mov     word ptr es:[bx+REQ_COUNT], 0
        test    byte ptr [config_options], OPT_ALLOW_MULTIPLE
        jnz     write_open_exclusive
        cmp     byte ptr [tape_open_count], 1
        je      write_open_exclusive
        jmp     write_access_error
write_open_exclusive:
        or      ax, ax
        jnz     write_issue
        and     byte ptr [device_state], not MT_STATE_EOF_NEXT
        or      byte ptr [device_state], MT_STATE_WRITTEN
        clc
        ret

write_issue:
        cmp     word ptr [requested_bytes], 1
        jne     write_size_allowed
        test    byte ptr [config_options], OPT_ALLOW_SINGLE
        jnz     write_size_allowed
        jmp     write_access_error
write_size_allowed:
        call    clear_srb
        mov     byte ptr [srb+SRB_Cmd], SC_EXEC_SCSI_CMD
        mov     al, byte ptr [tape_ha]
        mov     byte ptr [srb+SRB_HaId], al
        mov     byte ptr [srb+SRB_Flags], SRB_DIR_OUT
        test    word ptr [adapter_ext_flags], HA_EXT_RESIDUAL
        jz      write_flags_ready
        or      byte ptr [srb+SRB_Flags], SRB_RESIDUAL
write_flags_ready:
        mov     al, byte ptr [tape_target]
        mov     byte ptr [srb+SRB_Target], al
        mov     al, byte ptr [tape_lun]
        mov     byte ptr [srb+SRB_Lun], al
        mov     ax, word ptr [requested_bytes]
        mov     word ptr [srb+SRB_BufLen], ax
        mov     word ptr [srb+SRB_BufLen+2], 0
        les     bx, [request_ptr]
        mov     ax, word ptr es:[bx+REQ_TRANSFER]
        mov     word ptr [srb+SRB_BufPointer], ax
        mov     ax, word ptr es:[bx+REQ_TRANSFER+2]
        mov     word ptr [srb+SRB_BufPointer+2], ax
        mov     byte ptr [srb+SRB_SenseLen], 32
        mov     byte ptr [srb+SRB_CDBLen], 6
        mov     byte ptr [srb+SRB_CDB], SCSI_WRITE
        cmp     word ptr [tape_fixed_block], 0
        je      write_variable_length
        xor     dx, dx
        mov     ax, word ptr [requested_bytes]
        div     word ptr [tape_fixed_block]
        or      dx, dx
        jnz     write_bad_block_size
        or      byte ptr [srb+SRB_CDB+1], 1
        jmp     short write_length_ready
write_variable_length:
        mov     ax, word ptr [requested_bytes]
write_length_ready:
        mov     byte ptr [srb+SRB_CDB+3], ah
        mov     byte ptr [srb+SRB_CDB+4], al

        xor     ax, ax
        mov     al, byte ptr [srb+SRB_CDB]
        mov     ah, byte ptr [srb+SRB_Flags]
        mov     dl, byte ptr [srb+SRB_CDB+1]
        and     dl, 7
        or      ah, dl
        mov     word ptr [last_scsi_opcode], ax
        call    call_aspi

        mov     al, byte ptr [srb+SRB_TargStat]
        mov     byte ptr [last_scsi_status], al
        mov     byte ptr [last_sense_key], 0
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        jne     write_scsi_failed
        call    finish_transfer_count
        jc      write_bad_residual
write_success:
        and     byte ptr [device_state], not MT_STATE_EOF_NEXT
        or      byte ptr [device_state], MT_STATE_WRITTEN
        clc
        ret

write_bad_block_size:
        call    zero_transfer_count
        stc
        ret

write_scsi_failed:
        call    remember_sense_key
        test    byte ptr [srb+SRB_Flags], SRB_RESIDUAL
        jz      write_zero_failed
        call    finish_transfer_count
        jc      write_zero_failed
        test    byte ptr [sense_flags], SENSE_EOM
        jz      write_condition_error
        test    byte ptr [device_state], MT_STATE_EOM_EOF
        jnz     write_success
        jmp     short write_condition_error
write_zero_failed:
        call    zero_transfer_count
write_condition_error:
        stc
        ret
write_bad_residual:
        call    zero_transfer_count
        stc
        ret
write_access_error:
        call    zero_transfer_count
        stc
        ret
write_request endp

zero_transfer_count proc near
        les     bx, [request_ptr]
        mov     word ptr es:[bx+REQ_COUNT], 0
        mov     ax, word ptr [requested_bytes]
        mov     word ptr [residual_bytes], ax
        ret
zero_transfer_count endp

; Convert ASPI's returned residual count to the DOS request's transferred
; byte count. Reject a manager result that cannot fit this 16-bit DOS request
; or that exceeds the original buffer length.
finish_transfer_count proc near
        test    byte ptr [srb+SRB_Flags], SRB_RESIDUAL
        jnz     finish_read_residual
        xor     ax, ax
        jmp     short finish_read_apply
finish_read_residual:
        cmp     word ptr [srb+SRB_BufLen+2], 0
        jne     finish_read_invalid
        mov     ax, word ptr [srb+SRB_BufLen]
        cmp     ax, word ptr [requested_bytes]
        ja      finish_read_invalid
finish_read_apply:
        mov     word ptr [residual_bytes], ax
        mov     dx, word ptr [requested_bytes]
        sub     dx, ax
        les     bx, [request_ptr]
        mov     word ptr es:[bx+REQ_COUNT], dx
        clc
        ret
finish_read_invalid:
        stc
        ret
finish_transfer_count endp

; Fixed-format tape sense reports the requested-minus-actual byte count in its
; signed information field. A positive 16-bit value therefore recovers short
; variable records for managers without ASPI residual support.
finish_read_sense_count proc near
        cmp     byte ptr [sense_info_valid], 0
        je      finish_sense_invalid
        cmp     word ptr [sense_info_high], 0
        jne     finish_sense_invalid
        mov     ax, word ptr [sense_info_low]
        cmp     word ptr [tape_fixed_block], 0
        je      finish_sense_bytes_ready
        mul     word ptr [tape_fixed_block]
        or      dx, dx
        jnz     finish_sense_invalid
finish_sense_bytes_ready:
        cmp     ax, word ptr [requested_bytes]
        ja      finish_sense_invalid
        mov     word ptr [residual_bytes], ax
        mov     dx, word ptr [requested_bytes]
        sub     dx, ax
        les     bx, [request_ptr]
        mov     word ptr es:[bx+REQ_COUNT], dx
        clc
        ret
finish_sense_invalid:
        stc
        ret
finish_read_sense_count endp

; FILEMARK and a positive ILI are normal variable-block read completions. EOM
; is an EOF only when the caller selected the documented ignore-EOT policy.
classify_read_sense proc near
        test    byte ptr [sense_flags], SENSE_FILEMARK
        jnz     read_sense_filemark
        test    byte ptr [sense_flags], SENSE_ILI
        jnz     read_sense_ili
        test    byte ptr [sense_flags], SENSE_EOM
        jnz     read_sense_eom
        stc
        ret

read_sense_filemark:
        les     bx, [request_ptr]
        cmp     word ptr es:[bx+REQ_COUNT], 0
        je      read_sense_success
        or      byte ptr [device_state], MT_STATE_EOF_NEXT
        jmp     short read_sense_success

read_sense_ili:
        cmp     word ptr [tape_fixed_block], 0
        jne     read_sense_error
        cmp     byte ptr [sense_info_valid], 0
        je      read_sense_error
        cmp     word ptr [sense_info_high], 0
        jne     read_sense_error
        mov     ax, word ptr [sense_info_low]
        cmp     ax, word ptr [requested_bytes]
        ja      read_sense_error
        jmp     short read_sense_success

read_sense_eom:
        test    byte ptr [device_state], MT_STATE_EOM_EOF
        jz      read_sense_error
read_sense_success:
        clc
        ret
read_sense_error:
        stc
        ret
classify_read_sense endp

rewind_on_close proc near
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_REWIND
        call    execute_control_srb
        ret
rewind_on_close endp

; Match the historical close contract after a write: terminate the tape file
; with two filemarks. A no-rewind close then spaces backward over one filemark
; so the next writer can append at the expected position.
finish_written_tape proc near
        test    byte ptr [device_state], MT_STATE_WRITTEN
        jnz     finish_tape_write_marks
        clc
        ret
finish_tape_write_marks:
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_WRITE_FILEMARKS
        mov     byte ptr [srb+SRB_CDB+4], 2
        call    execute_control_srb
        jc      finish_tape_done
        cmp     byte ptr [request_rewind], 0
        jne     finish_tape_done
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_SPACE
        mov     byte ptr [srb+SRB_CDB+1], SPACE_FILEMARKS
        mov     byte ptr [srb+SRB_CDB+2], 0FFh
        mov     byte ptr [srb+SRB_CDB+3], 0FFh
        mov     byte ptr [srb+SRB_CDB+4], 0FFh
        call    execute_control_srb
finish_tape_done:
        ret
finish_written_tape endp

; Translate the documented ASPITAPE mtop operations to six-byte sequential-
; access CDBs.  The four-byte count in mtop must fit the signed or unsigned
; 24-bit field used by the corresponding SCSI command.
ioctl_mtop proc near
        les     bx, [request_ptr]
        les     di, dword ptr es:[bx+REQ_PARAMETER]
        mov     ax, word ptr es:[di]
        cmp     ax, MTNOP
        jbe     mtop_operation_valid
        stc
        ret
mtop_operation_valid:
        shl     ax, 1
        mov     si, ax
        jmp     word ptr cs:[si+mtop_operations]

mtop_operations:
        dw      mtop_write_filemarks
        dw      mtop_forward_filemarks
        dw      mtop_backward_filemarks
        dw      mtop_forward_records
        dw      mtop_backward_records
        dw      mtop_rewind
        dw      mtop_offline
        dw      mtop_nop

mtop_nop:
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_TUR
        jmp     execute_control_srb

mtop_write_filemarks:
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_WRITE_FILEMARKS
        call    encode_forward_count
        jc      mtop_write_filemarks_done
        call    execute_control_srb
        jc      mtop_write_filemarks_done
        or      byte ptr [device_state], MT_STATE_WRITTEN
mtop_write_filemarks_done:
        ret

mtop_forward_filemarks:
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_SPACE
        mov     byte ptr [srb+SRB_CDB+1], SPACE_FILEMARKS
        call    encode_forward_count
        jnc     mtop_fsf_ready
        stc
        ret
mtop_fsf_ready:
        jmp     execute_control_srb

mtop_backward_filemarks:
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_SPACE
        mov     byte ptr [srb+SRB_CDB+1], SPACE_FILEMARKS
        call    encode_backward_count
        jnc     mtop_bsf_ready
        stc
        ret
mtop_bsf_ready:
        jmp     execute_control_srb

mtop_forward_records:
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_SPACE
        mov     byte ptr [srb+SRB_CDB+1], SPACE_BLOCKS
        call    encode_forward_count
        jnc     mtop_fsr_ready
        stc
        ret
mtop_fsr_ready:
        jmp     execute_control_srb

mtop_backward_records:
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_SPACE
        mov     byte ptr [srb+SRB_CDB+1], SPACE_BLOCKS
        call    encode_backward_count
        jnc     mtop_bsr_ready
        stc
        ret
mtop_bsr_ready:
        jmp     execute_control_srb

mtop_rewind:
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_REWIND
        jmp     execute_control_srb

mtop_offline:
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_LOAD
        jmp     execute_control_srb

mtop_unsupported:
        stc
        ret
ioctl_mtop endp

execute_control_srb proc near
        xor     ax, ax
        mov     al, byte ptr [srb+SRB_CDB]
        mov     ah, byte ptr [srb+SRB_Flags]
        mov     dl, byte ptr [srb+SRB_CDB+1]
        and     dl, 7
        or      ah, dl
        mov     word ptr [last_scsi_opcode], ax
        mov     word ptr [residual_bytes], 0
        call    call_aspi

        mov     al, byte ptr [srb+SRB_TargStat]
        mov     byte ptr [last_scsi_status], al
        mov     byte ptr [last_sense_key], 0
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        je      control_complete
        call    remember_sense_key
        stc
        ret
control_complete:
        cmp     byte ptr [srb+SRB_CDB], SCSI_TUR
        je      control_success
        and     byte ptr [device_state], not MT_STATE_EOF_NEXT
control_success:
        clc
        ret
execute_control_srb endp

prepare_control_srb proc near
        call    clear_srb
        mov     byte ptr [srb+SRB_Cmd], SC_EXEC_SCSI_CMD
        mov     al, byte ptr [tape_ha]
        mov     byte ptr [srb+SRB_HaId], al
        mov     byte ptr [srb+SRB_Flags], SRB_DIR_NONE
        mov     al, byte ptr [tape_target]
        mov     byte ptr [srb+SRB_Target], al
        mov     al, byte ptr [tape_lun]
        mov     byte ptr [srb+SRB_Lun], al
        mov     byte ptr [srb+SRB_SenseLen], 32
        mov     byte ptr [srb+SRB_CDBLen], 6
        ret
prepare_control_srb endp

; Encode an unsigned count from mtop.count into CDB bytes 2..4.
encode_forward_count proc near
        mov     ax, word ptr es:[di+2]
        mov     dx, word ptr es:[di+4]
        cmp     dx, 00FFh
        ja      forward_count_invalid
        mov     byte ptr [srb+SRB_CDB+2], dl
        mov     byte ptr [srb+SRB_CDB+3], ah
        mov     byte ptr [srb+SRB_CDB+4], al
        clc
        ret
forward_count_invalid:
        stc
        ret
encode_forward_count endp

; Encode -mtop.count as a signed 24-bit SPACE count.
encode_backward_count proc near
        mov     ax, word ptr es:[di+2]
        mov     dx, word ptr es:[di+4]
        cmp     dx, 0080h
        ja      backward_count_invalid
        jb      backward_count_valid
        or      ax, ax                  ; 00800000h is the largest magnitude
        jnz     backward_count_invalid
backward_count_valid:
        neg     ax
        adc     dx, 0
        neg     dx
        mov     byte ptr [srb+SRB_CDB+2], dl
        mov     byte ptr [srb+SRB_CDB+3], ah
        mov     byte ptr [srb+SRB_CDB+4], al
        clc
        ret
backward_count_invalid:
        stc
        ret
encode_backward_count endp

remember_sense_key proc near
        mov     byte ptr [sense_flags], 0
        mov     byte ptr [sense_info_valid], 0
        mov     word ptr [sense_info_high], 0
        mov     word ptr [sense_info_low], 0
        mov     al, byte ptr [srb+SRB_CDB+16]
        and     al, 7Fh
        cmp     al, 70h
        jne     sense_not_fixed_current
        jmp     fixed_sense
sense_not_fixed_current:
        cmp     al, 71h
        jne     sense_not_fixed_deferred
        jmp     fixed_sense
sense_not_fixed_deferred:
        cmp     al, 72h
        je      descriptor_sense
        cmp     al, 73h
        je      descriptor_sense
        jmp     sense_done
descriptor_sense:
        mov     al, byte ptr [srb+SRB_CDB+17]
        and     al, 0Fh
        mov     byte ptr [last_sense_key], al
        xor     cx, cx
        mov     cl, byte ptr [srb+SRB_CDB+23]
        cmp     cx, 24
        jbe     descriptor_length_ready
        mov     cx, 24
descriptor_length_ready:
        mov     si, offset srb+SRB_CDB+24
descriptor_loop:
        cmp     cx, 2
        jae     descriptor_header_ready
        jmp     sense_done
descriptor_header_ready:
        xor     bx, bx
        mov     bl, byte ptr [si+1]
        add     bx, 2
        cmp     bx, cx
        jbe     descriptor_size_ready
        jmp     sense_done
descriptor_size_ready:
        cmp     byte ptr [si], 0
        je      descriptor_information
        cmp     byte ptr [si], 4
        je      descriptor_stream
        jmp     short descriptor_next

descriptor_information:
        cmp     byte ptr [si+1], 0Ah
        jb      descriptor_next
        test    byte ptr [si+2], 80h
        jz      descriptor_next
        cmp     word ptr [si+4], 0
        jne     descriptor_next
        cmp     word ptr [si+6], 0
        jne     descriptor_next
        mov     ah, byte ptr [si+8]
        mov     al, byte ptr [si+9]
        mov     word ptr [sense_info_high], ax
        mov     ah, byte ptr [si+10]
        mov     al, byte ptr [si+11]
        mov     word ptr [sense_info_low], ax
        mov     byte ptr [sense_info_valid], 1
        jmp     short descriptor_next

descriptor_stream:
        cmp     byte ptr [si+1], 2
        jb      descriptor_next
        mov     al, byte ptr [si+3]
        and     al, SENSE_FILEMARK or SENSE_EOM or SENSE_ILI
        or      byte ptr [sense_flags], al

descriptor_next:
        add     si, bx
        sub     cx, bx
        jmp     descriptor_loop
fixed_sense:
        mov     al, byte ptr [srb+SRB_CDB+16]
        test    al, 80h
        jz      fixed_sense_flags
        mov     byte ptr [sense_info_valid], 1
        mov     ah, byte ptr [srb+SRB_CDB+19]
        mov     al, byte ptr [srb+SRB_CDB+20]
        mov     word ptr [sense_info_high], ax
        mov     ah, byte ptr [srb+SRB_CDB+21]
        mov     al, byte ptr [srb+SRB_CDB+22]
        mov     word ptr [sense_info_low], ax
fixed_sense_flags:
        mov     al, byte ptr [srb+SRB_CDB+18]
        mov     ah, al
        and     ah, SENSE_FILEMARK or SENSE_EOM or SENSE_ILI
        mov     byte ptr [sense_flags], ah
        and     al, 0Fh
        mov     byte ptr [last_sense_key], al
sense_done:
        ret
remember_sense_key endp

; Locate SCSIMGR$, query each adapter and find the first peripheral type 01h.
; CF is clear with tape_ha:tape_target:tape_lun filled in.
discover_tape proc near
        mov     word ptr [discovery_reason], offset msg_no_manager
        mov     ax, 3D00h
        mov     dx, offset manager_name
        int     21h
        jnc     manager_opened
        jmp     discovery_failed
manager_opened:
        mov     bx, ax
        mov     ax, 4402h
        mov     dx, offset aspi_entry
        mov     cx, 4
        int     21h
        pushf
        mov     ah, 3Eh
        int     21h
        popf
        jnc     manager_entry_read
        jmp     discovery_failed
manager_entry_read:
        cmp     word ptr [aspi_entry], 0
        jne     query_adapters
        cmp     word ptr [aspi_entry+2], 0
        jne     query_adapters
        jmp     discovery_failed

query_adapters:
        mov     word ptr [discovery_reason], offset msg_bad_inquiry
        call    clear_srb
        mov     byte ptr [srb+SRB_Cmd], SC_HA_INQUIRY
        call    call_aspi
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        je      adapter_count_ready
        jmp     discovery_failed
adapter_count_ready:
        mov     word ptr [discovery_reason], offset msg_no_adapters
        mov     al, byte ptr [srb+HA_Count]
        mov     byte ptr [adapter_count], al
        call    report_adapter_count
        or      al, al
        jnz     begin_adapter_scan
        jmp     discovery_failed
begin_adapter_scan:
        mov     word ptr [discovery_reason], offset msg_no_tape
        mov     byte ptr [scan_ha], 0

scan_adapter:
        call    clear_srb
        mov     byte ptr [srb+SRB_Cmd], SC_HA_INQUIRY
        mov     al, byte ptr [scan_ha]
        mov     byte ptr [srb+SRB_HaId], al
        call    call_aspi
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        je      adapter_inquiry_ready
        jmp     next_adapter
adapter_inquiry_ready:
        call    report_adapter
        mov     ax, word ptr [srb+HA_ExtFlags]
        mov     word ptr [adapter_ext_flags], ax
        mov     al, byte ptr [srb+HA_SCSI_ID]
        mov     byte ptr [adapter_scsi_id], al
        mov     al, byte ptr [srb+HA_Unique+3]
        or      al, al
        jz      use_eight_targets
        cmp     al, 32
        jbe     target_limit_ready
use_eight_targets:
        mov     al, 8
target_limit_ready:
        mov     byte ptr [target_count], al
        mov     byte ptr [scan_target], 0

scan_target_loop:
        mov     al, byte ptr [scan_target]
        cmp     al, byte ptr [adapter_scsi_id]
        je      next_target
        mov     byte ptr [scan_lun], 0
scan_lun_loop:
        call    clear_srb
        mov     byte ptr [srb+SRB_Cmd], SC_GET_DEV_TYPE
        mov     al, byte ptr [scan_ha]
        mov     byte ptr [srb+SRB_HaId], al
        mov     al, byte ptr [scan_target]
        mov     byte ptr [srb+SRB_Target], al
        mov     al, byte ptr [scan_lun]
        mov     byte ptr [srb+SRB_Lun], al
        call    call_aspi
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        jne     next_lun
        mov     al, byte ptr [srb+SRB_DeviceType]
        and     al, 1Fh
        cmp     al, ASPI_DEV_TAPE
        jne     next_lun
        mov     al, byte ptr [scan_ha]
        mov     byte ptr [tape_ha], al
        mov     al, byte ptr [scan_target]
        mov     byte ptr [tape_target], al
        mov     al, byte ptr [scan_lun]
        mov     byte ptr [tape_lun], al
        call    detect_block_limits
        call    report_tape
        clc
        ret

next_lun:
        inc     byte ptr [scan_lun]
        cmp     byte ptr [scan_lun], 8
        jb      scan_lun_loop
next_target:
        inc     byte ptr [scan_target]
        mov     al, byte ptr [scan_target]
        cmp     al, byte ptr [target_count]
        jb      scan_target_loop
next_adapter:
        inc     byte ptr [scan_ha]
        mov     al, byte ptr [scan_ha]
        cmp     al, byte ptr [adapter_count]
        jae     discovery_failed
        jmp     scan_adapter

discovery_failed:
        test    byte ptr [config_options], OPT_VERBOSE
        jz      discovery_failure_done
        mov     dx, word ptr [discovery_reason]
        mov     ah, 09h
        int     21h
discovery_failure_done:
        stc
        ret
discover_tape endp

; Parse the historical safety overrides from the CONFIG.SYS argument tail.
; DOS supplies a far pointer in the initialization request. Both '-' and '/'
; prefixes and upper/lower case are accepted; option clusters are permitted.
parse_init_options proc near
        mov     byte ptr [config_options], 0
        mov     byte ptr [config_name_letter], 'M'
        les     bx, [request_ptr]
        les     si, dword ptr es:[bx+REQ_INIT_ARGS]
        mov     ax, es
        or      ax, si
        jnz     init_options_scan
        jmp     init_options_done
init_options_scan:
        mov     al, byte ptr es:[si]
        or      al, al
        jnz     init_options_scan_cr
        jmp     init_options_done
init_options_scan_cr:
        cmp     al, 0Dh
        jne     init_options_scan_lf
        jmp     init_options_done
init_options_scan_lf:
        cmp     al, 0Ah
        jne     init_options_scan_prefix
        jmp     init_options_done
init_options_scan_prefix:
        cmp     al, ' '
        je      init_options_whitespace
        cmp     al, 9
        je      init_options_whitespace
        cmp     al, '-'
        je      init_options_prefix
        cmp     al, '/'
        je      init_options_prefix
        ; DOS may include the driver pathname before the arguments. Skip
        ; that whole token so a '-' within a pathname is not an option.
init_options_skip_path:
        inc     si
        mov     al, byte ptr es:[si]
        or      al, al
        jz      init_options_path_done
        cmp     al, 0Dh
        je      init_options_path_done
        cmp     al, 0Ah
        je      init_options_path_done
        cmp     al, ' '
        je      init_options_scan
        cmp     al, 9
        jne     init_options_skip_path
        jmp     short init_options_scan
init_options_path_done:
        clc
        ret
init_options_whitespace:
        inc     si
        jmp     short init_options_scan
init_options_prefix:
        inc     si
        mov     al, byte ptr es:[si]
        cmp     al, ' '
        ja      init_options_cluster
        stc
        ret
init_options_cluster:
        mov     al, byte ptr es:[si]
        or      al, al
        jnz     init_options_cluster_cr
        jmp     init_options_done
init_options_cluster_cr:
        cmp     al, 0Dh
        jne     init_options_cluster_lf
        jmp     init_options_done
init_options_cluster_lf:
        cmp     al, 0Ah
        jne     init_options_cluster_space
        jmp     init_options_done
init_options_cluster_space:
        cmp     al, ' '
        jne     init_option_skip_tab
        jmp     init_options_scan
init_option_skip_tab:
        cmp     al, 9
        jne     init_option_skip_dash
        jmp     init_options_scan
init_option_skip_dash:
        cmp     al, '-'
        jne     init_option_skip_slash
        jmp     init_options_prefix
init_option_skip_slash:
        cmp     al, '/'
        jne     init_option_skip_next
        jmp     init_options_prefix
init_option_skip_next:
        cmp     al, '$'
        jne     init_option_letter
        or      byte ptr [config_options], OPT_NAME_SUFFIX
        jmp     short init_option_next
init_option_letter:
        and     al, 0DFh
        cmp     al, 'S'
        jne     init_option_not_single
        or      byte ptr [config_options], OPT_ALLOW_SINGLE
        jmp     short init_option_next
init_option_not_single:
        cmp     al, 'M'
        jne     init_option_not_multiple
        or      byte ptr [config_options], OPT_ALLOW_MULTIPLE
        jmp     short init_option_next
init_option_not_multiple:
        cmp     al, 'V'
        je      init_option_verbose
        cmp     al, 'D'
        jne     init_option_not_verbose
init_option_verbose:
        or      byte ptr [config_options], OPT_VERBOSE
        jmp     short init_option_next
init_option_not_verbose:
        cmp     al, 'T'
        jne     init_options_invalid
        inc     si
        mov     al, byte ptr es:[si]
        and     al, 0DFh
        cmp     al, 'A'
        jb      init_options_invalid
        cmp     al, 'Z'
        ja      init_options_invalid
        mov     byte ptr [config_name_letter], al
init_option_next:
        inc     si
        jmp     short init_options_cluster
init_options_invalid:
        stc
        ret
init_options_done:
        clc
        ret
parse_init_options endp

; Apply the historical -tX base-letter replacement and -$ collision suffix
; before DOS links the resident character-device headers into its name table.
apply_device_names proc near
        mov     al, byte ptr [config_name_letter]
        mov     byte ptr [rmt_device_name+1], al
        mov     byte ptr [nrmt_device_name+2], al
        test    byte ptr [config_options], OPT_NAME_SUFFIX
        jz      device_names_done
        mov     byte ptr [rmt_device_name+4], '$'
        mov     byte ptr [nrmt_device_name+5], '$'
device_names_done:
        ret
apply_device_names endp

; READ BLOCK LIMITS distinguishes drives which require a single fixed block
; size from variable-block drives. Version 1 of the ASPITAPE status ABI can
; report only a 16-bit size, so larger or ambiguous limits remain variable.
detect_block_limits proc near
        mov     word ptr [tape_fixed_block], 0
        call    clear_srb
        mov     byte ptr [srb+SRB_Cmd], SC_EXEC_SCSI_CMD
        mov     al, byte ptr [tape_ha]
        mov     byte ptr [srb+SRB_HaId], al
        mov     byte ptr [srb+SRB_Flags], SRB_DIR_IN
        test    word ptr [adapter_ext_flags], HA_EXT_RESIDUAL
        jz      block_limits_flags_ready
        or      byte ptr [srb+SRB_Flags], SRB_RESIDUAL
block_limits_flags_ready:
        mov     al, byte ptr [tape_target]
        mov     byte ptr [srb+SRB_Target], al
        mov     al, byte ptr [tape_lun]
        mov     byte ptr [srb+SRB_Lun], al
        mov     word ptr [srb+SRB_BufLen], 6
        mov     word ptr [srb+SRB_BufLen+2], 0
        mov     word ptr [srb+SRB_BufPointer], offset block_limits
        mov     word ptr [srb+SRB_BufPointer+2], cs
        mov     byte ptr [srb+SRB_SenseLen], 32
        mov     byte ptr [srb+SRB_CDBLen], 6
        mov     byte ptr [srb+SRB_CDB], SCSI_READ_BLOCK_LIMITS
        call    call_aspi
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        jne     block_limits_done
        cmp     byte ptr [block_limits+1], 0
        jne     block_limits_done
        mov     ah, byte ptr [block_limits+2]
        mov     al, byte ptr [block_limits+3]
        mov     dh, byte ptr [block_limits+4]
        mov     dl, byte ptr [block_limits+5]
        cmp     ax, dx
        jne     block_limits_done
        or      ax, ax
        jz      block_limits_done
        mov     word ptr [tape_fixed_block], ax
block_limits_done:
        ret
detect_block_limits endp

call_aspi proc near
        push    ds
        push    es
        push    cs
        mov     ax, offset srb
        push    ax
        call    dword ptr cs:[aspi_entry]
        add     sp, 4
        pop     es
        pop     ds
        mov     cx, 0FFFFh
wait_aspi:
        cmp     byte ptr [srb+SRB_Status], SS_PENDING
        jne     aspi_complete
        loop    wait_aspi
aspi_complete:
        ret
call_aspi endp

clear_srb proc near
        push    ax
        push    cx
        push    di
        push    es
        push    cs
        pop     es
        mov     di, offset srb
        mov     cx, ASPI_SRB_SIZE
        xor     al, al
        rep     stosb
        pop     es
        pop     di
        pop     cx
        pop     ax
        ret
clear_srb endp

print_char proc near
        mov     ah, 02h
        int     21h
        ret
print_char endp

print_hex8 proc near
        push    ax
        push    bx
        push    cx
        push    dx
        mov     bl, al
        mov     cl, 4
        shr     al, cl
        call    print_nibble
        mov     al, bl
        and     al, 0Fh
        call    print_nibble
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
print_hex8 endp

print_nibble proc near
        and     al, 0Fh
        add     al, '0'
        cmp     al, '9'
        jbe     nibble_ready
        add     al, 7
nibble_ready:
        mov     dl, al
        call    print_char
        ret
print_nibble endp

; Optional initialization diagnostics. Preserve the discovery registers and
; never issue extra ASPI commands merely to produce verbose output.
report_adapter_count proc near
        push    ax
        push    dx
        test    byte ptr [config_options], OPT_VERBOSE
        jz      report_count_done
        mov     dx, offset msg_adapter_count
        mov     ah, 09h
        int     21h
        mov     al, byte ptr [adapter_count]
        call    print_hex8
        mov     dx, offset msg_crlf
        mov     ah, 09h
        int     21h
report_count_done:
        pop     dx
        pop     ax
        ret
report_adapter_count endp

report_adapter proc near
        push    ax
        push    cx
        push    dx
        push    si
        test    byte ptr [config_options], OPT_VERBOSE
        jz      report_adapter_done
        mov     dx, offset msg_adapter
        mov     ah, 09h
        int     21h
        mov     al, byte ptr [scan_ha]
        call    print_hex8
        mov     dx, offset msg_extensions
        mov     ah, 09h
        int     21h
        mov     ax, word ptr [srb+HA_ExtFlags]
        call    print_hex16
        mov     dx, offset msg_manager
        mov     ah, 09h
        int     21h
        mov     si, offset srb+HA_ManagerId
        mov     cx, 16
        call    print_fixed
        mov     dx, offset msg_identity
        mov     ah, 09h
        int     21h
        mov     si, offset srb+HA_Identifier
        mov     cx, 16
        call    print_fixed
        mov     dx, offset msg_quote_crlf
        mov     ah, 09h
        int     21h
report_adapter_done:
        pop     si
        pop     dx
        pop     cx
        pop     ax
        ret
report_adapter endp

report_tape proc near
        push    ax
        push    cx
        push    dx
        push    si
        test    byte ptr [config_options], OPT_VERBOSE
        jz      report_tape_done
        mov     dx, offset msg_tape
        mov     ah, 09h
        int     21h
        mov     al, byte ptr [tape_ha]
        call    print_hex8
        mov     dl, ':'
        call    print_char
        mov     al, byte ptr [tape_target]
        call    print_hex8
        mov     dl, ':'
        call    print_char
        mov     al, byte ptr [tape_lun]
        call    print_hex8
        cmp     word ptr [tape_fixed_block], 0
        je      report_variable
        mov     dx, offset msg_fixed
        mov     ah, 09h
        int     21h
        mov     ax, word ptr [tape_fixed_block]
        call    print_hex16
        mov     dx, offset msg_hex_bytes
        jmp     short report_block_text
report_variable:
        mov     dx, offset msg_variable
report_block_text:
        mov     ah, 09h
        int     21h
        mov     dx, offset msg_names
        mov     ah, 09h
        int     21h
        mov     si, offset rmt_device_name
        mov     cx, 8
        call    print_fixed
        mov     dl, ' '
        call    print_char
        mov     si, offset nrmt_device_name
        mov     cx, 8
        call    print_fixed
        mov     dx, offset msg_crlf
        mov     ah, 09h
        int     21h
report_tape_done:
        pop     si
        pop     dx
        pop     cx
        pop     ax
        ret
report_tape endp

print_hex16 proc near
        push    ax
        mov     al, ah
        call    print_hex8
        pop     ax
        call    print_hex8
        ret
print_hex16 endp

; ASPI identity fields are fixed-width bytes, not DOS '$'-terminated strings.
; Replace nonprintable bytes so manager data cannot control the console.
print_fixed proc near
fixed_next:
        lodsb
        cmp     al, 20h
        jb      fixed_unprintable
        cmp     al, 7Eh
        jbe     fixed_print
fixed_unprintable:
        mov     al, '.'
fixed_print:
        mov     dl, al
        call    print_char
        loop    fixed_next
        ret
print_fixed endp

manager_name        db  'SCSIMGR$', 0
banner_found        db  'OpenASPI ASPITAP: tape found at $'
banner_tail         db  '; tape device names ready', 13, 10, '$'
banner_missing      db  'OpenASPI ASPITAP: no ASPI tape; not installed', 13, 10, '$'
banner_bad_options  db  'OpenASPI ASPITAP: invalid or unsupported option; not installed', 13, 10, '$'
msg_adapter_count   db  'ASPITAP: adapters=$'
msg_adapter         db  'ASPITAP: HA $'
msg_extensions      db  ' extensions=$'
msg_manager         db  ' manager="$'
msg_identity        db  '" adapter="$'
msg_quote_crlf      db  '"', 13, 10, '$'
msg_tape            db  'ASPITAP: tape $'
msg_fixed           db  ' fixed block=$'
msg_hex_bytes       db  'h bytes', 13, 10, '$'
msg_variable        db  ' variable blocks', 13, 10, '$'
msg_names           db  'ASPITAP: names=$'
msg_crlf            db  13, 10, '$'
msg_no_manager      db  'ASPITAP: ASPI manager unavailable or entry point invalid', 13, 10, '$'
msg_bad_inquiry     db  'ASPITAP: host adapter inquiry failed', 13, 10, '$'
msg_no_adapters     db  'ASPITAP: manager reports no host adapters', 13, 10, '$'
msg_no_tape         db  'ASPITAP: no sequential-access device found', 13, 10, '$'

aspi_entry          dd  0
adapter_count       db  0
discovery_reason    dw  0
adapter_scsi_id     db  0
adapter_ext_flags   dw  0
target_count        db  8
scan_ha             db  0
scan_target         db  0
scan_lun            db  0
tape_ha             db  0
tape_target         db  0
tape_lun            db  0
tape_fixed_block    dw  0
config_options      db  0
config_name_letter  db  'M'
device_state        db  0
tape_open_count     db  0
last_scsi_status    db  0
last_sense_key      db  0
last_scsi_opcode    dw  0
residual_bytes      dw  0
requested_bytes     dw  0
sense_flags         db  0
sense_info_valid    db  0
sense_info_high     dw  0
sense_info_low      dw  0
block_limits        db  6 dup (0)
srb                  db  ASPI_SRB_SIZE dup (0)

resident_end label byte

        end     driver_start
