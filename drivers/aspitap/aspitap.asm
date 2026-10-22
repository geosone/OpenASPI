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

; DOS ASPI places autosense immediately after the actual CDB, not after
; the maximum CDB storage. Every command submitted by ASPITAP is six bytes.
TAPE_SENSE      equ     SRB_CDB + 6

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
IOCTL_MTGET16   equ     05h             ; explicit OpenASPI 16-byte ABI

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
MT_STATE_BUFFERED equ   001h
MT_STATE_REWIND equ     004h
MT_STATE_WRITTEN equ    008h
MT_STATE_READ   equ     010h
MT_STATE_EOF_NEXT equ   020h
MT_STATE_EOM_EOF equ    040h

OPT_ALLOW_SINGLE equ    001h
OPT_ALLOW_MULTIPLE equ  002h
OPT_NAME_SUFFIX  equ    004h
OPT_VERBOSE      equ    008h
OPT_WAIT_REWIND  equ    010h
OPT_BREAK_WAIT   equ    020h
OPT_BUFFERED     equ    040h
OPT_STATUS16     equ    080h
TAPE_BUFFER_SIZE equ    1024
REWIND_WAIT_TICKS equ   3277            ; about three minutes at 18.2 Hz

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

; Linked into the DOS device chain only when -b is selected.
mt_header:
        dw      offset nmt_header, 0
        dw      DEV_ATTR
        dw      strategy_mt
        dw      interrupt
mt_device_name db       'MT0     '
nmt_header:
        dd      0FFFFFFFFh
        dw      DEV_ATTR
        dw      strategy_nmt
        dw      interrupt
nmt_device_name db      'NMT0    '

request_ptr     dd      0
request_rewind  db      0
request_buffered db     0

strategy_rmt proc far
        mov     byte ptr cs:[request_buffered], 0
        mov     byte ptr cs:[request_rewind], MT_STATE_REWIND
        mov     word ptr cs:[request_ptr], bx
        mov     word ptr cs:[request_ptr+2], es
        ret
strategy_rmt endp

strategy_nrmt proc far
        mov     byte ptr cs:[request_buffered], 0
        mov     byte ptr cs:[request_rewind], 0
        mov     word ptr cs:[request_ptr], bx
        mov     word ptr cs:[request_ptr+2], es
        ret
strategy_nrmt endp

strategy_mt proc far
        mov     byte ptr cs:[request_buffered], 1
        mov     byte ptr cs:[request_rewind], MT_STATE_REWIND
        mov     word ptr cs:[request_ptr], bx
        mov     word ptr cs:[request_ptr+2], es
        ret
strategy_mt endp
strategy_nmt proc far
        mov     byte ptr cs:[request_buffered], 1
        mov     byte ptr cs:[request_rewind], 0
        mov     word ptr cs:[request_ptr], bx
        mov     word ptr cs:[request_ptr+2], es
        ret
strategy_nmt endp

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
        cmp     byte ptr [request_buffered], 0
        je      dispatch_raw_read
        call    buffered_read
        jmp     short dispatch_read_result
dispatch_raw_read:
        call    read_request
dispatch_read_result:
        jnc     read_request_success
        jmp     request_error
read_request_success:
        jmp     request_success

write_request_dispatch:
        cmp     byte ptr [request_buffered], 0
        je      dispatch_raw_write
        call    buffered_write
        jmp     short dispatch_write_result
dispatch_raw_write:
        call    write_request
dispatch_write_result:
        jnc     write_request_success
        jmp     request_error
write_request_success:
        jmp     request_success

init_request:
        cmp     byte ptr [initialization_done], 0
        jne     init_tape_ready
        call    parse_init_options
        jnc     init_options_valid
        mov     dx, offset banner_bad_options
        jmp     init_report_failure
init_options_valid:
        call    apply_device_names
        call    discover_tape
        jc      init_failed
        mov     byte ptr [initialization_done], 1
init_tape_ready:
        les     bx, [request_ptr]
        mov     word ptr es:[bx+0Eh], offset resident_end
        test    byte ptr [config_options], OPT_BUFFERED
        jz      init_resident_size_ready
        mov     word ptr es:[bx+0Eh], offset buffered_resident_end
init_resident_size_ready:
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
        mov     byte ptr [driver_error], 20
        mov     word ptr es:[bx+REQ_STATUS], 8103h
        jmp     request_done

open_request:
        cmp     byte ptr [tape_open_count], 0FFh
        jne     open_count_available
        jmp     request_error
open_count_available:
        cmp     byte ptr [tape_open_count], 0
        je      open_first_handle
        jmp     open_increment
open_first_handle:
        mov     byte ptr [mtop_performed], 0
        mov     al, byte ptr [request_buffered]
        mov     byte ptr [session_buffered], al
open_mode_ready:
        call    discard_tape_buffer
        mov     byte ptr [buffer_write_failed], 0
        and     byte ptr [device_state], MT_STATE_EOM_EOF
open_increment:
        inc     byte ptr [tape_open_count]
        jmp     request_success

close_request:
        cmp     byte ptr [tape_open_count], 0
        jne     close_decrement
        jmp     request_success
close_decrement:
        dec     byte ptr [tape_open_count]
        je      close_last_handle
        jmp     request_success
close_last_handle:
        call    flush_tape_buffer
        jc      request_error
        call    finish_written_tape
        jc      close_write_error
        cmp     byte ptr [request_rewind], 0
        je      close_complete
        call    rewind_on_close
        jnc     close_complete
        test    byte ptr [device_state], MT_STATE_WRITTEN
        jnz     close_write_error
        jmp     request_error
close_write_error:
        call    save_write_error
        jmp     request_error
close_complete:
        and     byte ptr [device_state], MT_STATE_EOM_EOF
        jmp     request_success

generic_ioctl:
        cmp     byte ptr es:[bx+REQ_CATEGORY], IOCTL_TAPE
        je      ioctl_category_valid
        jmp     unsupported
ioctl_category_valid:
        mov     al, byte ptr es:[bx+REQ_FUNCTION]
        cmp     al, IOCTL_MTGET
        je      ioctl_mtget
        cmp     al, IOCTL_MTGET16
        je      ioctl_mtget16
        cmp     al, IOCTL_IGNORE_EOT
        je      ioctl_ignore_eot
        cmp     al, IOCTL_ENABLE_EOT
        je      ioctl_enable_eot
        cmp     al, IOCTL_MTOP
        je      ioctl_function_valid
        jmp     unsupported
ioctl_function_valid:
        call    ioctl_mtop
        jc      request_error
        les     bx, [request_ptr]
        les     di, dword ptr es:[bx+REQ_PARAMETER]
        cmp     word ptr es:[di], MTNOP
        je      request_success
        mov     byte ptr [mtop_performed], 20h
        jmp     short request_success

ioctl_mtget:
        test    byte ptr [config_options], OPT_STATUS16
        jnz     ioctl_mtget16
        call    fill_mtget
        jmp     short request_success

ioctl_mtget16:
        call    fill_mtget16
        jmp     short request_success

ioctl_ignore_eot:
        or      byte ptr [device_state], MT_STATE_EOM_EOF
        jmp     short request_success

ioctl_enable_eot:
        and     byte ptr [device_state], not MT_STATE_EOM_EOF
        jmp     short request_success

request_error:
        call    record_driver_error
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

; Record the cause before a buffered physical request can be retried or a
; later control command can overwrite the live SCSI diagnostic fields.
record_driver_error proc near
        push    ax
        cmp     byte ptr [driver_error], 0
        jne     record_error_done
        mov     al, byte ptr [last_sense_key]
        cmp     byte ptr [last_scsi_status], 8
        jne     record_error_not_busy
        mov     al, 22
record_error_not_busy:
        or      al, al
        jnz     record_error_known
        mov     al, 31                  ; unspecified driver error
record_error_known:
        mov     byte ptr [driver_error], al
record_error_done:
        pop     ax
        ret
record_driver_error endp

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
        cmp     byte ptr [request_buffered], 0
        je      mtget_raw_mode
        or      al, MT_STATE_BUFFERED
        jmp     short mtget_buffer_mode_ready
mtget_raw_mode:
        or      al, 2                   ; TPS_RAW in both historical ABIs
mtget_buffer_mode_ready:
        cmp     byte ptr [rewind_pending], 0
        je      mtget_state_ready
        or      al, 80h                 ; historical TPS_WIND
mtget_state_ready:
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
        cmp     byte ptr [write_error_valid], 0
        je      mtget_diagnostics_ready
        mov     ax, word ptr [write_error_status]
        mov     word ptr es:[di+8], ax
        mov     ax, word ptr [write_error_opcode]
        mov     word ptr es:[di+0Ah], ax
        mov     ax, word ptr [write_error_residual]
        mov     word ptr es:[di+0Ch], ax
mtget_diagnostics_ready:
        ret
fill_mtget endp

; IOCTL.H / MTIO.H shipped in the 1992 archive describe a different ABI
; from its manual. Reuse the legacy snapshot, then expand backwards so no
; caller-owned bytes beyond the sixteen-byte destination are touched.
fill_mtget16 proc near
        call    fill_mtget
        mov     ax, word ptr es:[di+12]
        mov     word ptr es:[di+14], ax
        mov     ax, word ptr es:[di+10]
        mov     word ptr es:[di+12], ax
        mov     ax, word ptr es:[di+8]
        mov     word ptr es:[di+10], ax
        mov     ax, word ptr es:[di+6]
        mov     word ptr es:[di+8], ax
        mov     byte ptr es:[di+6], 0    ; physical unit zero
        mov     al, byte ptr [driver_error]
        cmp     byte ptr [write_error_valid], 0
        je      mtget16_error_ready
        mov     al, byte ptr [write_error_code]
mtget16_error_ready:
        mov     byte ptr es:[di+7], al
        xor     ah, ah
        mov     al, byte ptr es:[di+4]
        and     al, 1Fh
        or      al, byte ptr [mtop_performed]
        test    byte ptr [device_state], MT_STATE_EOF_NEXT
        jz      mtget16_eof_ready
        or      al, 40h
mtget16_eof_ready:
        test    byte ptr [device_state], MT_STATE_EOM_EOF
        jz      mtget16_eot_ready
        or      al, 80h
mtget16_eot_ready:
        cmp     byte ptr [rewind_pending], 0
        je      mtget16_ready
        mov     ah, 1
mtget16_ready:
        cmp     byte ptr [write_error_valid], 0
        je      mtget16_store_state
        or      ah, 2                   ; OpenASPI latched write diagnostic
mtget16_store_state:
        mov     word ptr es:[di+4], ax
        ret
fill_mtget16 endp

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
        mov     byte ptr [driver_error], 17
        cmp     byte ptr [buffer_internal_io], 0
        jne     read_open_allowed
        cmp     byte ptr [session_buffered], 0
        jne     read_access_error
        test    byte ptr [config_options], OPT_ALLOW_MULTIPLE
        jnz     read_open_allowed
        cmp     byte ptr [tape_open_count], 1
        jne     read_access_error
read_open_allowed:
        mov     byte ptr [driver_error], 18
        cmp     word ptr [requested_bytes], 1
        jne     read_size_allowed
        test    byte ptr [config_options], OPT_ALLOW_SINGLE
        jz      read_access_error
read_size_allowed:
        mov     byte ptr [driver_error], 0
        ; Reject incomplete fixed-block requests before polling rewind or
        ; consuming a deferred EOF. Neither operation belongs to bad input.
        cmp     word ptr [tape_fixed_block], 0
        je      read_request_size_valid
        mov     ax, word ptr [requested_bytes]
        xor     dx, dx
        div     word ptr [tape_fixed_block]
        or      dx, dx
        jz      read_request_size_valid
        jmp     read_bad_block_size
read_request_size_valid:
        call    wait_for_rewind
        jc      read_access_error
        test    byte ptr [device_state], MT_STATE_WRITTEN
        jz      read_not_written
        mov     byte ptr [driver_error], 19
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
        mov     byte ptr [driver_error], 31 ; input error, not stale SCSI sense
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
        ; A malformed manager residual is not an EOF/ILI/EOM completion.
        ; Never let otherwise plausible sense turn an unknown length into
        ; success or queue an artificial filemark for the next read.
        jmp     read_bad_residual
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
; A zero-byte driver write request marks the session written without a data
; CDB; some DOS kernels suppress zero-byte API writes before driver dispatch.
write_request proc near
        mov     byte ptr [driver_error], 17
        les     bx, [request_ptr]
        mov     ax, word ptr es:[bx+REQ_COUNT]
        mov     word ptr [requested_bytes], ax
        mov     word ptr es:[bx+REQ_COUNT], 0
        cmp     byte ptr [buffer_internal_io], 0
        jne     write_open_exclusive
        cmp     byte ptr [session_buffered], 0
        je      write_mode_allowed
        jmp     write_access_error
write_mode_allowed:
        test    byte ptr [config_options], OPT_ALLOW_MULTIPLE
        jnz     write_open_exclusive
        cmp     byte ptr [tape_open_count], 1
        je      write_open_exclusive
        jmp     write_access_error
write_open_exclusive:
        mov     byte ptr [driver_error], 0
        ; Bad input must not poll or consume a pending close rewind.
        mov     ax, word ptr [requested_bytes]
        or      ax, ax
        jz      write_request_size_valid
        cmp     ax, 1
        jne     write_check_fixed_size
        test    byte ptr [config_options], OPT_ALLOW_SINGLE
        jnz     write_check_fixed_size
        mov     byte ptr [driver_error], 18
        jmp     write_access_error
write_check_fixed_size:
        cmp     word ptr [tape_fixed_block], 0
        je      write_request_size_valid
        xor     dx, dx
        div     word ptr [tape_fixed_block]
        or      dx, dx
        jz      write_request_size_valid
        jmp     write_bad_block_size
write_request_size_valid:
        call    wait_for_rewind
        jnc     write_rewind_ready
        jmp     write_access_error
write_rewind_ready:
        mov     ax, word ptr [requested_bytes]
        or      ax, ax
        jnz     write_issue
        and     byte ptr [device_state], not MT_STATE_EOF_NEXT
        or      byte ptr [device_state], MT_STATE_WRITTEN
        clc
        ret

write_issue:
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
        ; Buffered acceptance, short transfers and ignored CHECK CONDITION
        ; are not proof that a later physical record was fully written.
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        jne     write_incomplete
        cmp     word ptr [residual_bytes], 0
        jne     write_incomplete
        mov     byte ptr [write_error_valid], 0
        jmp     short write_success_state
write_incomplete:
        call    save_raw_write_error
write_success_state:
        and     byte ptr [device_state], not MT_STATE_EOF_NEXT
        or      byte ptr [device_state], MT_STATE_WRITTEN
        ; DOS may loop a successful short character-device write and submit
        ; the remainder as another tape record. Fail raw short writes so the
        ; caller, not DOS, chooses recovery. Keep the actual residual in status.
        cmp     byte ptr [buffer_internal_io], 0
        jne     write_complete
        cmp     word ptr [residual_bytes], 0
        je      write_complete
        stc
        ret
write_complete:
        clc
        ret

write_bad_block_size:
        mov     byte ptr [driver_error], 31 ; input error, not stale SCSI sense
        call    zero_transfer_count
        stc
        ret

write_scsi_failed:
        call    remember_sense_key
        test    byte ptr [srb+SRB_Flags], SRB_RESIDUAL
        jz      write_zero_failed
        call    finish_transfer_count
        jc      write_zero_failed
        call    check_stream_completion
        jc      write_condition_error
        ; Ignore-EOT never suppresses a real media/hardware sense key.
        cmp     byte ptr [last_sense_key], 1 ; NO SENSE / RECOVERED ERROR only
        ja      write_condition_error
        test    byte ptr [sense_flags], SENSE_EOM
        jz      write_condition_error
        test    byte ptr [device_state], MT_STATE_EOM_EOF
        jnz     write_success
        jmp     short write_condition_error
write_zero_failed:
        call    zero_transfer_count
write_condition_error:
        call    save_raw_write_error
        stc
        ret
write_bad_residual:
        call    zero_transfer_count
        call    save_raw_write_error
        stc
        ret
write_access_error:
        call    zero_transfer_count
        stc
        ret
write_request endp

; Snapshot only after a physical raw WRITE was submitted, not for bad sizes,
; single-byte/mixed-mode guards or a failed pre-write readiness barrier.
; Buffered requests retain their separate all-or-nothing record handling.
save_raw_write_error proc near
        cmp     byte ptr [buffer_internal_io], 0
        jne     raw_write_error_done
        call    save_write_error
raw_write_error_done:
        ret
save_raw_write_error endp

; The buffered aliases reuse the raw request handlers with a resident private
; request packet. Cache state belongs to the single physical tape session.
buffered_read proc near
        call    begin_buffer_request
        cmp     word ptr [buffer_left], 0
        jne     buffered_read_nonempty
        jmp     buffer_success
buffered_read_nonempty:
        call    check_buffer_access
        jnc     buffered_read_access_ok
        jmp     buffer_error
buffered_read_access_ok:
        test    byte ptr [device_state], MT_STATE_WRITTEN
        jz      buffered_read_not_written
        mov     byte ptr [driver_error], 19
        jmp     buffer_error
buffered_read_not_written:
        call    wait_for_rewind
        jnc     buffered_read_loop
        jmp     buffer_error
buffered_read_loop:
        mov     ax, word ptr [buffer_count]
        sub     ax, word ptr [buffer_cursor]
        jnz     buffered_read_copy
        call    discard_tape_buffer
        ; Deliver a filemark only after all cached bytes preceding it.
        test    byte ptr [device_state], MT_STATE_EOF_NEXT
        jz      buffered_read_refill
        cmp     word ptr [buffer_done], 0
        je      buffered_read_refill
        jmp     buffer_success
buffered_read_refill:
        mov     byte ptr [buffer_direction], 0
        call    buffer_physical_io
        jnc     buffered_read_filled
        jmp     buffer_error
buffered_read_filled:
        mov     ax, word ptr [buffer_packet+REQ_COUNT]
        mov     word ptr [buffer_count], ax
        mov     byte ptr [buffer_kind], 1
        or      ax, ax
        jnz     buffered_read_copy
        cmp     word ptr [buffer_done], 0
        je      buffered_read_eof
        or      byte ptr [device_state], MT_STATE_EOF_NEXT
buffered_read_eof:
        jmp     buffer_success
buffered_read_copy:
        cmp     ax, word ptr [buffer_left]
        jbe     buffered_read_chunk_ready
        mov     ax, word ptr [buffer_left]
buffered_read_chunk_ready:
        mov     word ptr [buffer_chunk], ax
        mov     cx, ax
        mov     si, offset tape_buffer
        add     si, word ptr [buffer_cursor]
        mov     es, word ptr [buffer_user_segment]
        mov     di, word ptr [buffer_user_offset]
        rep     movsb
        mov     ax, word ptr [buffer_chunk]
        add     word ptr [buffer_cursor], ax
        call    advance_buffer_request
        cmp     word ptr [buffer_left], 0
        jne     buffered_read_loop
        jmp     buffer_success
buffered_read endp

buffered_write proc near
        call    begin_buffer_request
        call    check_buffer_access
        jnc     buffered_write_access_ok
        jmp     buffer_error
buffered_write_access_ok:
        call    wait_for_rewind
        jnc     buffered_write_ready
        jmp     buffer_error
buffered_write_ready:
        cmp     byte ptr [buffer_kind], 1
        jne     buffered_write_mode_ready
        call    discard_tape_buffer
buffered_write_mode_ready:
        cmp     word ptr [buffer_left], 0
        jne     buffered_write_loop
        or      byte ptr [device_state], MT_STATE_WRITTEN
        and     byte ptr [device_state], not MT_STATE_EOF_NEXT
        jmp     buffer_success
buffered_write_loop:
        mov     byte ptr [buffer_kind], 2
        mov     ax, TAPE_BUFFER_SIZE
        sub     ax, word ptr [buffer_count]
        cmp     ax, word ptr [buffer_left]
        jbe     buffered_write_chunk_ready
        mov     ax, word ptr [buffer_left]
buffered_write_chunk_ready:
        mov     word ptr [buffer_chunk], ax
        mov     cx, ax
        mov     si, word ptr [buffer_user_offset]
        mov     di, offset tape_buffer
        add     di, word ptr [buffer_count]
        mov     ax, word ptr [buffer_user_segment]
        push    ds
        push    cs
        pop     es
        mov     ds, ax
        rep     movsb
        pop     ds
        mov     ax, word ptr [buffer_chunk]
        add     word ptr [buffer_count], ax
        cmp     word ptr [buffer_count], TAPE_BUFFER_SIZE
        jne     buffered_write_accepted
        call    write_buffer_record
        jnc     buffered_write_accepted
        jmp     buffer_error
buffered_write_accepted:
        or      byte ptr [device_state], MT_STATE_WRITTEN
        and     byte ptr [device_state], not MT_STATE_EOF_NEXT
        call    advance_buffer_request
        cmp     word ptr [buffer_left], 0
        jne     buffered_write_loop
        jmp     buffer_success
buffered_write endp

begin_buffer_request proc near
        les     bx, [request_ptr]
        mov     ax, word ptr es:[bx+REQ_COUNT]
        mov     word ptr [buffer_left], ax
        mov     word ptr [buffer_done], 0
        mov     word ptr es:[bx+REQ_COUNT], 0
        mov     ax, word ptr es:[bx+REQ_TRANSFER]
        mov     dx, word ptr es:[bx+REQ_TRANSFER+2]
        mov     bx, ax
        and     bx, 0Fh
        mov     word ptr [buffer_user_offset], bx
        mov     cl, 4
        shr     ax, cl
        add     dx, ax
        mov     word ptr [buffer_user_segment], dx
        ret
begin_buffer_request endp

check_buffer_access proc near
        cmp     byte ptr [buffer_write_failed], 0
        je      buffer_access_not_latched
        mov     al, byte ptr [write_error_code]
        mov     byte ptr [driver_error], al
        stc
        ret
buffer_access_not_latched:
        mov     byte ptr [driver_error], 17
        mov     al, byte ptr [request_buffered]
        cmp     al, byte ptr [session_buffered]
        jne     buffer_access_error
        test    byte ptr [config_options], OPT_ALLOW_MULTIPLE
        jnz     buffer_check_single
        cmp     byte ptr [tape_open_count], 1
        jne     buffer_access_error
buffer_check_single:
        mov     byte ptr [driver_error], 18
        cmp     word ptr [buffer_left], 1
        jne     buffer_access_ok
        test    byte ptr [config_options], OPT_ALLOW_SINGLE
        jz      buffer_access_error
buffer_access_ok:
        mov     byte ptr [driver_error], 0
        cmp     word ptr [tape_fixed_block], 0
        je      buffer_block_size_ok
        mov     ax, TAPE_BUFFER_SIZE
        xor     dx, dx
        div     word ptr [tape_fixed_block]
        or      dx, dx
        jnz     buffer_access_error
buffer_block_size_ok:
        clc
        ret
buffer_access_error:
        stc
        ret
check_buffer_access endp

advance_buffer_request proc near
        mov     ax, word ptr [buffer_chunk]
        sub     word ptr [buffer_left], ax
        add     word ptr [buffer_done], ax
        add     ax, word ptr [buffer_user_offset]
        mov     bx, ax
        and     bx, 0Fh
        mov     word ptr [buffer_user_offset], bx
        mov     cl, 4
        shr     ax, cl
        add     word ptr [buffer_user_segment], ax
        ret
advance_buffer_request endp

buffer_success:
        les     bx, [request_ptr]
        mov     ax, word ptr [buffer_done]
        mov     word ptr es:[bx+REQ_COUNT], ax
        clc
        ret
buffer_error:
        les     bx, [request_ptr]
        mov     ax, word ptr [buffer_done]
        mov     word ptr es:[bx+REQ_COUNT], ax
        stc
        ret

discard_tape_buffer proc near
        mov     byte ptr [buffer_kind], 0
        mov     word ptr [buffer_count], 0
        mov     word ptr [buffer_cursor], 0
        ret
discard_tape_buffer endp

buffer_physical_io proc near
        push    word ptr [request_ptr+2]
        push    word ptr [request_ptr]
        mov     word ptr [request_ptr], offset buffer_packet
        mov     word ptr [request_ptr+2], cs
        mov     word ptr [buffer_packet+REQ_COUNT], TAPE_BUFFER_SIZE
        mov     word ptr [buffer_packet+REQ_TRANSFER], offset tape_buffer
        mov     word ptr [buffer_packet+REQ_TRANSFER+2], cs
        mov     byte ptr [buffer_internal_io], 1
        cmp     byte ptr [buffer_direction], 0
        jne     buffer_physical_write
        call    read_request
        jmp     short buffer_physical_done
buffer_physical_write:
        call    write_request
buffer_physical_done:
        pushf
        mov     byte ptr [buffer_internal_io], 0
        pop     ax
        pop     word ptr [request_ptr]
        pop     word ptr [request_ptr+2]
        push    ax
        popf
        ret
buffer_physical_io endp

; A failed or partial physical write is never replayed automatically: the
; drive may have consumed a record. Latch the error through the final close.
write_buffer_record proc near
        mov     byte ptr [buffer_direction], 1
        call    buffer_physical_io
        jc      write_buffer_failed
        cmp     word ptr [buffer_packet+REQ_COUNT], TAPE_BUFFER_SIZE
        jne     write_buffer_failed
        call    discard_tape_buffer
        clc
        ret
write_buffer_failed:
        call    save_write_error
        mov     byte ptr [buffer_write_failed], 1
        stc
        ret
write_buffer_record endp

; Shared by data flush and written-session finalization. DOS may ignore a
; close error, so failed filemarks/positioning need the same durable status.
save_write_error proc near
        call    record_driver_error
        mov     al, byte ptr [driver_error]
        mov     byte ptr [write_error_code], al
        mov     al, byte ptr [last_scsi_status]
        mov     byte ptr [write_error_status], al
        mov     al, byte ptr [last_sense_key]
        mov     byte ptr [write_error_status+1], al
        mov     ax, word ptr [last_scsi_opcode]
        mov     word ptr [write_error_opcode], ax
        mov     ax, word ptr [residual_bytes]
        mov     word ptr [write_error_residual], ax
        mov     byte ptr [write_error_valid], 1
        ret
save_write_error endp

flush_tape_buffer proc near
        cmp     byte ptr [session_buffered], 0
        je      flush_buffer_done
        cmp     byte ptr [buffer_write_failed], 0
        jne     flush_buffer_failed
        cmp     byte ptr [buffer_kind], 2
        jne     flush_buffer_done
        cmp     word ptr [buffer_count], 0
        je      flush_buffer_done
        push    cs
        pop     es
        mov     di, offset tape_buffer
        add     di, word ptr [buffer_count]
        mov     cx, TAPE_BUFFER_SIZE
        sub     cx, word ptr [buffer_count]
        xor     al, al
        rep     stosb
        jmp     write_buffer_record
flush_buffer_done:
        clc
        ret
flush_buffer_failed:
        mov     al, byte ptr [write_error_code]
        mov     byte ptr [driver_error], al
        stc
        ret
flush_tape_buffer endp

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
        ; FIXED transfers cannot complete a fraction of a physical block.
        cmp     word ptr [tape_fixed_block], 0
        je      finish_read_apply
        push    ax
        xor     dx, dx
        div     word ptr [tape_fixed_block]
        pop     ax
        or      dx, dx
        jz      finish_read_apply
        mov     byte ptr [driver_error], 31 ; malformed fixed-block residual
        jmp     short finish_read_invalid
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

; Sense flags describe a stream condition only for an ordinary target CHECK
; CONDITION. Stale sense must never hide host errors or aborted/BUSY results.
; No registers are changed; CF is clear only for that completion envelope.
check_stream_completion proc near
        cmp     byte ptr [srb+SRB_Status], SS_ERR
        jne     stream_completion_error
        cmp     byte ptr [srb+SRB_HaStat], 0
        jne     stream_completion_error
        cmp     byte ptr [srb+SRB_TargStat], 2
        jne     stream_completion_error
        ; Deferred sense describes an earlier command, not this transfer.
        cmp     byte ptr [sense_response], 70h
        je      stream_completion_current
        cmp     byte ptr [sense_response], 72h
        jne     stream_completion_error
stream_completion_current:
        clc
        ret
stream_completion_error:
        stc
        ret
check_stream_completion endp

; FILEMARK and a positive ILI are normal variable-block read completions. EOM
; is an EOF only when the caller selected the documented ignore-EOT policy.
classify_read_sense proc near
        call    check_stream_completion
        jc      read_sense_error
        ; Stream flags do not override a hard error reported by the drive.
        cmp     byte ptr [last_sense_key], 1 ; NO SENSE / RECOVERED ERROR only
        ja      read_sense_error
        ; Flags may coexist. Validate every restriction before any flag can
        ; turn the response into success or queue a deferred filemark.
        test    byte ptr [sense_flags], SENSE_EOM
        jz      read_check_ili
        test    byte ptr [device_state], MT_STATE_EOM_EOF
        jz      read_sense_error
read_check_ili:
        test    byte ptr [sense_flags], SENSE_ILI
        jz      read_check_filemark
        cmp     word ptr [tape_fixed_block], 0
        jne     read_sense_error
        cmp     byte ptr [sense_info_valid], 0
        je      read_sense_error
        cmp     word ptr [sense_info_high], 0
        jne     read_sense_error
        mov     ax, word ptr [sense_info_low]
        cmp     ax, word ptr [requested_bytes]
        ja      read_sense_error
        ; Both counts describe requested-minus-actual bytes for variable
        ; records. A valid-looking but contradictory residual is not data.
        cmp     ax, word ptr [residual_bytes]
        jne     read_sense_length_error
read_check_filemark:
        test    byte ptr [sense_flags], SENSE_FILEMARK
        jnz     read_sense_filemark
        test    byte ptr [sense_flags], SENSE_ILI or SENSE_EOM
        jnz     read_sense_success
        stc
        ret

read_sense_filemark:
        les     bx, [request_ptr]
        cmp     word ptr es:[bx+REQ_COUNT], 0
        je      read_sense_success
        or      byte ptr [device_state], MT_STATE_EOF_NEXT
read_sense_success:
        clc
        ret
read_sense_length_error:
        call    zero_transfer_count
        mov     byte ptr [driver_error], 31 ; contradictory completion lengths
read_sense_error:
        stc
        ret
classify_read_sense endp

rewind_on_close proc near
        call    wait_for_rewind
        jc      rewind_close_done
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_REWIND
        test    byte ptr [config_options], OPT_WAIT_REWIND
        jnz     rewind_close_issue
        mov     byte ptr [srb+SRB_CDB+1], 1 ; IMMED: return when rewind starts
rewind_close_issue:
        call    execute_control_srb
        jc      rewind_close_done
        test    byte ptr [config_options], OPT_WAIT_REWIND
        jnz     rewind_close_done
        mov     byte ptr [rewind_pending], 1
rewind_close_done:
        ret
rewind_on_close endp

; Reopening and status queries do not wait for an immediate close rewind.
; Media commands wait up to three minutes, polling once per BIOS tick. Only
; BUSY and recognized rewind/becoming-ready sense are retried; media/transport
; errors return immediately. Keep pending set on error so no later request
; can skip the readiness barrier.
wait_for_rewind proc near
        cmp     byte ptr [rewind_pending], 0
        jne     rewind_wait_start
        clc
        ret
rewind_wait_start:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    es
        mov     byte ptr [break_requested], 0
        call    install_break_hook
        call    read_bios_ticks
        mov     word ptr [rewind_start_low], ax
        mov     word ptr [rewind_start_high], dx
        mov     word ptr [rewind_poll_low], ax
        mov     word ptr [rewind_poll_high], dx
rewind_poll:
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_TUR
        call    execute_control_srb
        jc      rewind_not_ready
        mov     byte ptr [rewind_pending], 0
        clc
        jmp     rewind_wait_done
rewind_not_ready:
        cmp     byte ptr [srb+SRB_HaStat], 0
        je      rewind_transport_ok
        jmp     rewind_wait_error
rewind_transport_ok:
        cmp     byte ptr [srb+SRB_Status], SS_ERR
        je      rewind_status_valid
        jmp     rewind_wait_error
rewind_status_valid:
        cmp     byte ptr [srb+SRB_TargStat], 8 ; SCSI BUSY
        je      rewind_wait_tick
        cmp     byte ptr [srb+SRB_TargStat], 2
        je      rewind_check_sense
        jmp     rewind_wait_error
rewind_check_sense:
        mov     al, byte ptr [srb+TAPE_SENSE+0]
        and     al, 7Fh
        mov     si, offset srb+TAPE_SENSE+12 ; fixed sense ASC/ASCQ
        cmp     al, 70h
        je      rewind_check_progress
        mov     si, offset srb+TAPE_SENSE+2 ; descriptor sense ASC/ASCQ
        cmp     al, 72h
        jne     rewind_wait_error
rewind_check_progress:
        cmp     byte ptr [last_sense_key], 2
        jne     rewind_check_no_sense
        cmp     byte ptr [si], 4
        jne     rewind_wait_error
        cmp     byte ptr [si+1], 1        ; becoming ready
        je      rewind_wait_tick
        cmp     byte ptr [si+1], 7        ; operation in progress
        je      rewind_wait_tick
        jmp     short rewind_wait_error
rewind_check_no_sense:
        cmp     byte ptr [last_sense_key], 0
        jne     rewind_wait_error
        cmp     word ptr [si], 1A00h     ; rewind operation in progress
        jne     rewind_wait_error
rewind_wait_tick:
        cmp     byte ptr [break_requested], 0
        jne     rewind_wait_interrupted
        call    read_bios_ticks
        cmp     ax, word ptr [rewind_poll_low]
        jne     rewind_tick_changed
        cmp     dx, word ptr [rewind_poll_high]
        je      rewind_wait_tick
rewind_tick_changed:
        mov     word ptr [rewind_poll_low], ax
        mov     word ptr [rewind_poll_high], dx
        sub     ax, word ptr [rewind_start_low]
        sbb     dx, word ptr [rewind_start_high]
        jnc     rewind_elapsed_ready
        add     ax, 00B0h               ; BIOS resets at 001800B0h midnight
        adc     dx, 0018h
rewind_elapsed_ready:
        or      dx, dx
        jnz     rewind_wait_timeout
        cmp     ax, REWIND_WAIT_TICKS
        jae     rewind_wait_timeout
        jmp     rewind_poll
rewind_wait_timeout:
        mov     byte ptr [driver_error], 16
        jmp     short rewind_wait_error
rewind_wait_interrupted:
        mov     byte ptr [driver_error], 23
rewind_wait_error:
        stc
rewind_wait_done:
        pushf
        call    restore_break_hook
        popf
        pop     es
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
wait_for_rewind endp

; DOS device requests may run inside DOS itself. Change INT 1Bh directly
; under CLI, avoiding a nested DOS vector service. Hook only while a pending
; rewind is being polled; preserve and chain the previous Ctrl-Break handler.
install_break_hook proc near
        test    byte ptr [config_options], OPT_BREAK_WAIT
        jz      install_break_done
        cmp     byte ptr [break_hook_installed], 0
        jne     install_break_done
        pushf
        cli
        push    ax
        push    es
        xor     ax, ax
        mov     es, ax
        mov     ax, word ptr es:[6Ch]
        mov     word ptr [old_break_vector], ax
        mov     ax, word ptr es:[6Eh]
        mov     word ptr [old_break_vector+2], ax
        mov     word ptr es:[6Ch], offset tape_break_handler
        mov     word ptr es:[6Eh], cs
        mov     byte ptr [break_hook_installed], 1
        pop     es
        pop     ax
        popf
install_break_done:
        ret
install_break_hook endp

restore_break_hook proc near
        cmp     byte ptr [break_hook_installed], 0
        je      restore_break_done
        pushf
        cli
        push    ax
        push    es
        xor     ax, ax
        mov     es, ax
        ; A TSR may have chained above us from an interrupt. Keep our
        ; resident link intact in that case and do not hook ourselves twice.
        cmp     word ptr es:[6Ch], offset tape_break_handler
        jne     restore_break_owned_elsewhere
        mov     ax, cs
        cmp     word ptr es:[6Eh], ax
        jne     restore_break_owned_elsewhere
        mov     ax, word ptr [old_break_vector]
        mov     word ptr es:[6Ch], ax
        mov     ax, word ptr [old_break_vector+2]
        mov     word ptr es:[6Eh], ax
        mov     byte ptr [break_hook_installed], 0
restore_break_owned_elsewhere:
        pop     es
        pop     ax
        popf
restore_break_done:
        ret
restore_break_hook endp

tape_break_handler proc far
        mov     byte ptr cs:[break_requested], 1
        jmp     dword ptr cs:[old_break_vector]
tape_break_handler endp

; Read the BIOS data area atomically without consuming its midnight flag.
; Return DX:AX ticks; preserve the caller's interrupt-enable state.
read_bios_ticks proc near
        pushf
        cli
        push    es
        mov     ax, 40h
        mov     es, ax
        mov     ax, word ptr es:[6Ch]
        mov     dx, word ptr es:[6Eh]
        pop     es
        popf
        ret
read_bios_ticks endp

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
        mov     byte ptr [driver_error], 0
        les     bx, [request_ptr]
        les     di, dword ptr es:[bx+REQ_PARAMETER]
        mov     ax, word ptr es:[di]
        cmp     ax, MTNOP
        jbe     mtop_operation_valid
        mov     byte ptr [driver_error], 21
        stc
        ret
mtop_operation_valid:
        ; Reject malformed requests before the readiness barrier.  Otherwise
        ; even an invalid count can poll the drive or consume a pending rewind.
        ; The encoders touch only the scratch SRB, rebuilt by the handlers.
        cmp     ax, MTREW
        jae     mtop_count_valid
        push    ax
        cmp     ax, MTBSF
        je      mtop_check_backward
        cmp     ax, MTBSR
        je      mtop_check_backward
        or      ax, ax                  ; WRITE FILEMARKS is unsigned
        jz      mtop_check_filemarks
        call    encode_forward_space_count
        jmp     short mtop_count_checked
mtop_check_filemarks:
        call    encode_forward_count
        jmp     short mtop_count_checked
mtop_check_backward:
        call    encode_backward_count
mtop_count_checked:
        pop     ax
        jnc     mtop_count_valid
        ret
mtop_count_valid:
        call    wait_for_rewind
        jnc     mtop_rewind_ready
        ret
mtop_rewind_ready:
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
        jnc     mtop_write_filemarks_complete
        call    save_write_error
        stc
        ret
mtop_write_filemarks_complete:
        or      byte ptr [device_state], MT_STATE_WRITTEN
mtop_write_filemarks_done:
        ret

mtop_forward_filemarks:
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_SPACE
        mov     byte ptr [srb+SRB_CDB+1], SPACE_FILEMARKS
        call    encode_forward_space_count
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
        call    encode_forward_space_count
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
        cmp     byte ptr [srb+SRB_CDB], SCSI_TUR
        je      control_buffer_ready
        call    discard_tape_buffer
control_buffer_ready:
        mov     byte ptr [driver_error], 0
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

; SPACE uses a signed 24-bit count even for forward movement.  Values with
; bit 23 set would silently send a backward SPACE instead of rejecting it.
encode_forward_space_count proc near
        cmp     word ptr es:[di+4], 007Fh
        jbe     forward_space_count_valid
        stc
        ret
forward_space_count_valid:
        jmp     encode_forward_count
encode_forward_space_count endp

; Encode an unsigned WRITE FILEMARKS count into CDB bytes 2..4.
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
        mov     al, byte ptr [srb+TAPE_SENSE+0]
        and     al, 7Fh
        mov     byte ptr [sense_response], al
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
        mov     al, byte ptr [srb+TAPE_SENSE+1]
        and     al, 0Fh
        mov     byte ptr [last_sense_key], al
        xor     cx, cx
        mov     cl, byte ptr [srb+TAPE_SENSE+7]
        cmp     cx, 24
        jbe     descriptor_length_ready
        mov     cx, 24
descriptor_length_ready:
        mov     si, offset srb+TAPE_SENSE+8
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
        mov     al, byte ptr [srb+TAPE_SENSE+0]
        test    al, 80h
        jz      fixed_sense_flags
        mov     byte ptr [sense_info_valid], 1
        mov     ah, byte ptr [srb+TAPE_SENSE+3]
        mov     al, byte ptr [srb+TAPE_SENSE+4]
        mov     word ptr [sense_info_high], ax
        mov     ah, byte ptr [srb+TAPE_SENSE+5]
        mov     al, byte ptr [srb+TAPE_SENSE+6]
        mov     word ptr [sense_info_low], ax
fixed_sense_flags:
        mov     al, byte ptr [srb+TAPE_SENSE+2]
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
        cmp     al, '2'
        jne     init_option_not_status16
        or      byte ptr [config_options], OPT_STATUS16
        jmp     short init_option_next
init_option_not_status16:
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
        cmp     al, 'W'
        jne     init_option_not_wait
        or      byte ptr [config_options], OPT_WAIT_REWIND
        jmp     short init_option_next
init_option_not_wait:
        cmp     al, 'I'
        jne     init_option_not_break
        or      byte ptr [config_options], OPT_BREAK_WAIT
        jmp     short init_option_next
init_option_not_break:
        cmp     al, 'B'
        jne     init_option_not_buffered
        or      byte ptr [config_options], OPT_BUFFERED
        jmp     short init_option_next
init_option_not_buffered:
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
        jmp     init_options_cluster
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
        mov     byte ptr [mt_device_name], al
        mov     byte ptr [nmt_device_name+1], al
        test    byte ptr [config_options], OPT_BUFFERED
        jz      device_buffer_names_ready
        mov     word ptr [nrmt_header], offset mt_header
        mov     word ptr [nrmt_header+2], cs
        mov     word ptr [mt_header+2], cs
device_buffer_names_ready:
        test    byte ptr [config_options], OPT_NAME_SUFFIX
        jz      device_names_done
        mov     byte ptr [rmt_device_name+4], '$'
        mov     byte ptr [nrmt_device_name+5], '$'
        mov     byte ptr [mt_device_name+3], '$'
        mov     byte ptr [nmt_device_name+4], '$'
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
        ; DOS can enter a character driver with IRQs disabled. Real ASPI
        ; managers may complete asynchronously, through their hardware IRQ.
        ; The manager owns command timeouts: never reuse a pending SRB just
        ; because a CPU-speed-dependent polling budget has expired.
        pushf
        sti
        push    ds
        push    es
        push    cs
        mov     ax, offset srb
        push    ax
        call    dword ptr cs:[aspi_entry]
        add     sp, 4
        pop     es
        pop     ds
wait_aspi:
        cmp     byte ptr [srb+SRB_Status], SS_PENDING
        jne     aspi_complete
        jmp     wait_aspi
aspi_complete:
        popf
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
        jnz     report_tape_verbose
        jmp     report_tape_done
report_tape_verbose:
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
        test    byte ptr [config_options], OPT_BUFFERED
        jz      report_names_done
        mov     dl, ' '
        call    print_char
        mov     si, offset mt_device_name
        mov     cx, 8
        call    print_fixed
        mov     dl, ' '
        call    print_char
        mov     si, offset nmt_device_name
        mov     cx, 8
        call    print_fixed
report_names_done:
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
initialization_done db  0
config_name_letter  db  'M'
rewind_pending      db  0
rewind_start_low    dw  0
rewind_start_high   dw  0
rewind_poll_low     dw  0
rewind_poll_high    dw  0
break_requested     db  0
old_break_vector    dd  0
break_hook_installed db 0
device_state        db  0
tape_open_count     db  0
last_scsi_status    db  0
last_sense_key      db  0
driver_error        db  0
mtop_performed      db  0
last_scsi_opcode    dw  0
residual_bytes      dw  0
requested_bytes     dw  0
sense_flags         db  0
sense_response      db  0
sense_info_valid    db  0
sense_info_high     dw  0
sense_info_low      dw  0
block_limits        db  6 dup (0)
srb                  db  ASPI_SRB_SIZE dup (0)

session_buffered    db  0
buffer_internal_io  db  0
buffer_write_failed db  0
write_error_valid   db  0
write_error_code    db  0
write_error_status  dw  0               ; SCSI status byte, sense-key byte
write_error_opcode  dw  0
write_error_residual dw 0
buffer_kind         db  0               ; 0 empty, 1 read cache, 2 write cache
buffer_count        dw  0
buffer_cursor       dw  0
buffer_left         dw  0
buffer_done         dw  0
buffer_chunk        dw  0
buffer_user_offset  dw  0
buffer_user_segment dw  0
buffer_direction    db  0
buffer_packet       db  24 dup (0)

resident_end label byte
tape_buffer         db  TAPE_BUFFER_SIZE dup (0)
buffered_resident_end label byte

        end     driver_start
