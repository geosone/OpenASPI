; ASPISCAN.COM - read-only ASPI for DOS adapter and device inventory.
;
; Opens SCSIMGR$, obtains the ASPI entry point, enumerates host/target/LUN
; addresses and issues only the SCSI INQUIRY command to devices reported by
; SC_GET_DEV_TYPE.  Exit status: 0 = at least one tape, 1 = no tape,
; 2 = manager/adapter error.

        .8086
        option  casemap:none

        .model  tiny
        .code
        org     100h

        include common/aspi/dos_aspi.inc

start:
        push    cs
        pop     ds
        push    cs
        pop     es
        cld

        mov     dx, offset msg_title
        call    print_string
        call    open_manager
        jnc     manager_open
        mov     dx, offset msg_no_manager
        call    print_string
        mov     ax, 4C02h
        int     21h

manager_open:
        call    clear_srb
        mov     byte ptr [srb+SRB_Cmd], SC_HA_INQUIRY
        call    call_aspi
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        je      have_adapters
        mov     dx, offset msg_bad_manager
        call    print_string
        mov     ax, 4C02h
        int     21h

have_adapters:
        mov     al, byte ptr [srb+HA_Count]
        mov     byte ptr [adapter_count], al
        or      al, al
        jnz     adapter_first
        mov     dx, offset msg_no_adapters
        call    print_string
        mov     ax, 4C02h
        int     21h

adapter_first:
        mov     byte ptr [adapter], 0

adapter_loop:
        call    clear_srb
        mov     byte ptr [srb+SRB_Cmd], SC_HA_INQUIRY
        mov     al, byte ptr [adapter]
        mov     byte ptr [srb+SRB_HaId], al
        call    call_aspi
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        jne     adapter_next

        mov     al, byte ptr [srb+HA_SCSI_ID]
        mov     byte ptr [adapter_scsi_id], al
        mov     al, byte ptr [srb+HA_Unique+3]
        or      al, al
        jz      default_targets
        cmp     al, 32
        jbe     targets_known
default_targets:
        mov     al, 8
targets_known:
        mov     byte ptr [target_count], al

        mov     dx, offset msg_adapter
        call    print_string
        mov     al, byte ptr [adapter]
        call    print_hex8
        mov     dx, offset msg_manager
        call    print_string
        mov     si, offset srb+HA_ManagerId
        mov     cx, 16
        call    print_fixed
        mov     dx, offset msg_ident
        call    print_string
        mov     si, offset srb+HA_Identifier
        mov     cx, 16
        call    print_fixed
        call    print_quote_crlf

        mov     byte ptr [target], 0
target_loop:
        mov     al, byte ptr [target]
        cmp     al, byte ptr [adapter_scsi_id]
        je      target_next
        mov     byte ptr [lun], 0
lun_loop:
        call    probe_device
        inc     byte ptr [lun]
        cmp     byte ptr [lun], 8
        jb      lun_loop
target_next:
        inc     byte ptr [target]
        mov     al, byte ptr [target]
        cmp     al, byte ptr [target_count]
        jb      target_loop

adapter_next:
        inc     byte ptr [adapter]
        mov     al, byte ptr [adapter]
        cmp     al, byte ptr [adapter_count]
        jae     scan_finished
        jmp     adapter_loop

scan_finished:
        cmp     byte ptr [device_count], 0
        jne     report_tapes
        mov     dx, offset msg_no_devices
        call    print_string
report_tapes:
        mov     dx, offset msg_summary
        call    print_string
        mov     al, byte ptr [device_count]
        call    print_hex8
        mov     dx, offset msg_summary_tapes
        call    print_string
        mov     al, byte ptr [tape_count]
        call    print_hex8
        call    print_crlf
        call    report_driver
        cmp     byte ptr [tape_count], 0
        jne     exit_success
        mov     ax, 4C01h
        int     21h
exit_success:
        mov     ax, 4C00h
        int     21h

; Open SCSIMGR$ and obtain its four-byte far entry point.  CF reports failure.
open_manager proc near
        mov     ax, 3D00h
        mov     dx, offset manager_name
        int     21h
        jc      open_done
        mov     bx, ax
        mov     ax, 4402h
        mov     dx, offset aspi_entry
        mov     cx, 4
        int     21h
        pushf
        mov     ah, 3Eh
        int     21h
        popf
        jc      open_done
        cmp     word ptr [aspi_entry], 0
        jne     open_ok
        cmp     word ptr [aspi_entry+2], 0
        jne     open_ok
        stc
        ret
open_ok:
        clc
open_done:
        ret
open_manager endp

; Query one address and print its standard INQUIRY identity.
probe_device proc near
        call    clear_srb
        mov     byte ptr [srb+SRB_Cmd], SC_GET_DEV_TYPE
        mov     al, byte ptr [adapter]
        mov     byte ptr [srb+SRB_HaId], al
        mov     al, byte ptr [target]
        mov     byte ptr [srb+SRB_Target], al
        mov     al, byte ptr [lun]
        mov     byte ptr [srb+SRB_Lun], al
        call    call_aspi
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        je      device_present
        jmp     probe_done
device_present:
        mov     al, byte ptr [srb+SRB_DeviceType]
        and     al, 1Fh
        mov     byte ptr [device_type], al
        inc     byte ptr [device_count]
        cmp     al, ASPI_DEV_TAPE
        jne     run_inquiry
        inc     byte ptr [tape_count]

run_inquiry:
        call    scsi_inquiry
        mov     dx, offset msg_device
        call    print_string
        mov     al, byte ptr [adapter]
        call    print_hex8
        mov     dl, ':'
        call    print_char
        mov     al, byte ptr [target]
        call    print_hex8
        mov     dl, ':'
        call    print_char
        mov     al, byte ptr [lun]
        call    print_hex8
        mov     dx, offset msg_type
        call    print_string
        mov     al, byte ptr [device_type]
        call    print_hex8
        cmp     byte ptr [device_type], ASPI_DEV_TAPE
        jne     print_identity
        mov     dx, offset msg_tape
        call    print_string
print_identity:
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        jne     inquiry_failed
        mov     dx, offset msg_vendor
        call    print_string
        mov     si, offset inquiry_data+8
        mov     cx, 8
        call    print_fixed
        mov     dx, offset msg_product
        call    print_string
        mov     si, offset inquiry_data+16
        mov     cx, 16
        call    print_fixed
        call    print_quote_crlf
        ret
inquiry_failed:
        mov     dx, offset msg_inquiry_failed
        call    print_string
probe_done:
        ret
probe_device endp

; Issue the read-only six-byte SCSI INQUIRY command.
scsi_inquiry proc near
        call    clear_srb
        mov     di, offset inquiry_data
        mov     cx, 36
        xor     al, al
        rep     stosb
        mov     byte ptr [srb+SRB_Cmd], SC_EXEC_SCSI_CMD
        mov     byte ptr [srb+SRB_Flags], SRB_DIR_IN
        mov     al, byte ptr [adapter]
        mov     byte ptr [srb+SRB_HaId], al
        mov     al, byte ptr [target]
        mov     byte ptr [srb+SRB_Target], al
        mov     al, byte ptr [lun]
        mov     byte ptr [srb+SRB_Lun], al
        mov     word ptr [srb+SRB_BufLen], 36
        mov     word ptr [srb+SRB_BufLen+2], 0
        mov     word ptr [srb+SRB_BufPointer], offset inquiry_data
        mov     word ptr [srb+SRB_BufPointer+2], cs
        mov     byte ptr [srb+SRB_SenseLen], 18
        mov     byte ptr [srb+SRB_CDBLen], 6
        mov     byte ptr [srb+SRB_CDB], 12h
        mov     byte ptr [srb+SRB_CDB+4], 36
        call    call_aspi
        ret
scsi_inquiry endp

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
aspi_wait:
        cmp     byte ptr [srb+SRB_Status], SS_PENDING
        jne     aspi_done
        loop    aspi_wait
aspi_done:
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

; Report whether the ASPITAP character device remained installed.
report_driver proc near
        mov     ax, 3D00h
        mov     dx, offset tape_driver_name
        int     21h
        jc      driver_absent
        mov     bx, ax
        mov     ah, 3Eh
        int     21h
        mov     dx, offset msg_driver_present
        jmp     print_string
driver_absent:
        mov     dx, offset msg_driver_absent
        jmp     print_string
report_driver endp

print_string proc near
        mov     ah, 09h
        int     21h
        ret
print_string endp

print_char proc near
        mov     ah, 02h
        int     21h
        ret
print_char endp

print_crlf proc near
        mov     dx, offset msg_crlf
        jmp     print_string
print_crlf endp

print_quote_crlf proc near
        mov     dx, offset msg_quote_crlf
        jmp     print_string
print_quote_crlf endp

print_hex8 proc near
        push    ax
        push    bx
        push    dx
        mov     bl, al
        mov     cl, 4
        shr     al, cl
        call    print_nibble
        mov     al, bl
        and     al, 0Fh
        call    print_nibble
        pop     dx
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

; Print CX fixed-width bytes, replacing controls with a dot.
print_fixed proc near
fixed_next:
        lodsb
        cmp     al, 20h
        jae     fixed_print
        mov     al, '.'
fixed_print:
        mov     dl, al
        call    print_char
        loop    fixed_next
        ret
print_fixed endp

manager_name        db  'SCSIMGR$', 0
tape_driver_name    db  'RMT0', 0
msg_title           db  'OpenASPI DOS device scan', 13, 10, '$'
msg_no_manager      db  'SCSIMGR$ not found', 13, 10, '$'
msg_bad_manager     db  'ASPI host adapter inquiry failed', 13, 10, '$'
msg_no_adapters     db  'No ASPI host adapters', 13, 10, '$'
msg_no_devices      db  'No ASPI devices', 13, 10, '$'
msg_adapter         db  'HA $'
msg_manager         db  ' manager="$'
msg_ident           db  '" adapter="$'
msg_device          db  '  device $'
msg_type            db  ' type=$'
msg_tape            db  ' TAPE$'
msg_vendor          db  ' vendor="$'
msg_product         db  '" product="$'
msg_inquiry_failed  db  ' INQUIRY failed', 13, 10, '$'
msg_summary         db  'Devices: $'
msg_summary_tapes   db  '  tapes: $'
msg_driver_present  db  'ASPITAP RMT0 resident', 13, 10, '$'
msg_driver_absent   db  'ASPITAP RMT0 absent', 13, 10, '$'
msg_crlf            db  13, 10, '$'
msg_quote_crlf      db  '"', 13, 10, '$'

aspi_entry          dd  0
adapter_count       db  0
adapter             db  0
adapter_scsi_id     db  0
target_count        db  8
target              db  0
lun                 db  0
device_type         db  0
device_count        db  0
tape_count          db  0
srb                 db  ASPI_SRB_SIZE dup (0)
inquiry_data        db  36 dup (0)

        end     start
