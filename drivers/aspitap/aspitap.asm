; ASPITAP.SYS bootstrap driver for OpenASPI.
;
; The driver locates SCSIMGR$, claims the first ASPI sequential-access device,
; and exposes the historical RMT0/NRMT0 names.  The non-destructive generic
; IOCTL interface provides status, EOT policy, spacing, rewind, unload and
; readiness operations. Variable-block reads use residual counts when the ASPI
; manager provides them and retain exact-length compatibility with older
; managers. Data writes remain disabled.

        .8086
        option casemap:none

        .model tiny
        .code
        org     0

        include common/aspi/dos_aspi.inc

DEV_ATTR        equ     08040h          ; character device + generic IOCTL
REQ_COMMAND     equ     02h
REQ_STATUS      equ     03h
REQ_CATEGORY    equ     0Dh
REQ_FUNCTION    equ     0Eh
REQ_PARAMETER   equ     13h
REQ_TRANSFER    equ     0Eh
REQ_COUNT       equ     12h

CMD_INIT        equ     00h
CMD_READ        equ     04h
CMD_WRITE       equ     08h
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
SCSI_READ       equ     08h
SCSI_SPACE      equ     11h
SCSI_LOAD       equ     1Bh
SPACE_BLOCKS    equ     00h
SPACE_FILEMARKS equ     01h

MT_PARAM_ASPI   equ     080h
MT_STATE_REWIND equ     004h
MT_STATE_READ   equ     010h
MT_STATE_EOM_EOF equ    040h

driver_start:
        dw      offset nrmt_header, 0   ; second header is in this segment
        dw      DEV_ATTR
        dw      strategy_rmt
        dw      interrupt
        db      'RMT0    '

nrmt_header:
        dd      0FFFFFFFFh              ; end of DOS device chain
        dw      DEV_ATTR
        dw      strategy_nrmt
        dw      interrupt
        db      'NRMT0   '

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
        cmp     al, CMD_GEN_IOCTL
        je      generic_ioctl
        cmp     al, CMD_READ
        je      read_request_dispatch
        cmp     al, CMD_WRITE
        je      unsupported
        jmp     short unsupported

read_request_dispatch:
        call    read_request
        jnc     read_request_success
        jmp     request_error
read_request_success:
        jmp     request_success

init_request:
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
        jmp     short request_done

init_failed:
        les     bx, [request_ptr]
        mov     word ptr es:[bx+0Eh], 0
        mov     word ptr es:[bx+10h], cs
        mov     word ptr es:[bx+REQ_STATUS], 810Ch
        mov     dx, offset banner_missing
        mov     ah, 09h
        int     21h
        jmp     short request_done

unsupported:
        mov     word ptr es:[bx+REQ_STATUS], 8103h
        jmp     short request_done

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
        mov     byte ptr es:[di+3], MT_PARAM_ASPI
        mov     al, byte ptr [device_state]
        or      al, byte ptr [request_rewind]
        mov     byte ptr es:[di+4], al
        mov     byte ptr es:[di+5], 0
        mov     word ptr es:[di+6], 0
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
        mov     ax, word ptr [requested_bytes]
        mov     byte ptr [srb+SRB_CDB+3], ah
        mov     byte ptr [srb+SRB_CDB+4], al

        xor     ax, ax
        mov     al, byte ptr [srb+SRB_CDB]
        mov     ah, byte ptr [srb+SRB_Flags]
        mov     word ptr [last_scsi_opcode], ax
        call    call_aspi

        mov     al, byte ptr [srb+SRB_TargStat]
        mov     byte ptr [last_scsi_status], al
        mov     byte ptr [last_sense_key], 0
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        jne     read_scsi_failed
        call    finish_read_count
        jc      read_bad_residual
        or      byte ptr [device_state], MT_STATE_READ
        clc
        ret

read_bad_residual:
        call    zero_read_count
        jmp     short read_remember_sense
read_scsi_failed:
        test    byte ptr [srb+SRB_Flags], SRB_RESIDUAL
        jz      read_error_without_residual
        call    finish_read_count
        jnc     read_remember_sense
read_error_without_residual:
        call    zero_read_count
read_remember_sense:
        call    remember_sense_key
        stc
        ret
read_request endp

zero_read_count proc near
        les     bx, [request_ptr]
        mov     word ptr es:[bx+REQ_COUNT], 0
        mov     ax, word ptr [requested_bytes]
        mov     word ptr [residual_bytes], ax
        ret
zero_read_count endp

; Convert ASPI's returned residual count to the DOS request's transferred
; byte count. Reject a manager result that cannot fit this 16-bit DOS request
; or that exceeds the original buffer length.
finish_read_count proc near
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
finish_read_count endp

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
        dw      mtop_unsupported
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
        jmp     short mtop_execute

mtop_forward_filemarks:
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_SPACE
        mov     byte ptr [srb+SRB_CDB+1], SPACE_FILEMARKS
        call    encode_forward_count
        jnc     mtop_fsf_ready
        stc
        ret
mtop_fsf_ready:
        jmp     short mtop_execute

mtop_backward_filemarks:
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_SPACE
        mov     byte ptr [srb+SRB_CDB+1], SPACE_FILEMARKS
        call    encode_backward_count
        jnc     mtop_bsf_ready
        stc
        ret
mtop_bsf_ready:
        jmp     short mtop_execute

mtop_forward_records:
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_SPACE
        mov     byte ptr [srb+SRB_CDB+1], SPACE_BLOCKS
        call    encode_forward_count
        jnc     mtop_fsr_ready
        stc
        ret
mtop_fsr_ready:
        jmp     short mtop_execute

mtop_backward_records:
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_SPACE
        mov     byte ptr [srb+SRB_CDB+1], SPACE_BLOCKS
        call    encode_backward_count
        jnc     mtop_bsr_ready
        stc
        ret
mtop_bsr_ready:
        jmp     short mtop_execute

mtop_rewind:
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_REWIND
        jmp     short mtop_execute

mtop_offline:
        call    prepare_control_srb
        mov     byte ptr [srb+SRB_CDB], SCSI_LOAD

mtop_execute:
        xor     ax, ax
        mov     al, byte ptr [srb+SRB_CDB]
        mov     ah, byte ptr [srb+SRB_Flags]
        mov     word ptr [last_scsi_opcode], ax
        mov     word ptr [residual_bytes], 0
        call    call_aspi

        mov     al, byte ptr [srb+SRB_TargStat]
        mov     byte ptr [last_scsi_status], al
        mov     byte ptr [last_sense_key], 0
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        je      mtop_complete
        call    remember_sense_key
        stc
        ret
mtop_complete:
        clc
        ret
mtop_unsupported:
        stc
        ret
ioctl_mtop endp

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
        mov     al, byte ptr [srb+SRB_CDB+16]
        and     al, 7Fh
        cmp     al, 70h
        je      fixed_sense
        cmp     al, 71h
        je      fixed_sense
        cmp     al, 72h
        je      descriptor_sense
        cmp     al, 73h
        jne     sense_done
descriptor_sense:
        mov     al, byte ptr [srb+SRB_CDB+17]
        and     al, 0Fh
        mov     byte ptr [last_sense_key], al
        ret
fixed_sense:
        mov     al, byte ptr [srb+SRB_CDB+18]
        and     al, 0Fh
        mov     byte ptr [last_sense_key], al
sense_done:
        ret
remember_sense_key endp

; Locate SCSIMGR$, query each adapter and find the first peripheral type 01h.
; CF is clear with tape_ha:tape_target:tape_lun filled in.
discover_tape proc near
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
        call    clear_srb
        mov     byte ptr [srb+SRB_Cmd], SC_HA_INQUIRY
        call    call_aspi
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        je      adapter_count_ready
        jmp     discovery_failed
adapter_count_ready:
        mov     al, byte ptr [srb+HA_Count]
        mov     byte ptr [adapter_count], al
        or      al, al
        jnz     begin_adapter_scan
        jmp     discovery_failed
begin_adapter_scan:
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
        stc
        ret
discover_tape endp

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

manager_name        db  'SCSIMGR$', 0
banner_found        db  'OpenASPI ASPITAP: tape found at $'
banner_tail         db  '; RMT0 and NRMT0 ready (read-only)', 13, 10, '$'
banner_missing      db  'OpenASPI ASPITAP: no ASPI tape; not installed', 13, 10, '$'

aspi_entry          dd  0
adapter_count       db  0
adapter_scsi_id     db  0
adapter_ext_flags   dw  0
target_count        db  8
scan_ha             db  0
scan_target         db  0
scan_lun            db  0
tape_ha             db  0
tape_target         db  0
tape_lun            db  0
device_state        db  0
last_scsi_status    db  0
last_sense_key      db  0
last_scsi_opcode    dw  0
residual_bytes      dw  0
requested_bytes     dw  0
srb                  db  ASPI_SRB_SIZE dup (0)

resident_end label byte

        end     driver_start
