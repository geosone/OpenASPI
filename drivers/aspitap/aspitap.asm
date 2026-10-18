; ASPITAP.SYS bootstrap driver for OpenASPI.
;
; The driver now locates SCSIMGR$ and claims the first ASPI sequential-access
; device during INIT.  It deliberately rejects runtime I/O until the compatible
; raw read and generic-IOCTL paths are implemented.

        .8086
        option casemap:none

        .model tiny
        .code
        org     0

        include common/aspi/dos_aspi.inc

driver_start:
        dd      0FFFFFFFFh              ; end of DOS device chain
        dw      08000h                  ; character device, no I/O yet
        dw      strategy
        dw      interrupt
        db      'RMT0    '

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
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es

        les     bx, cs:[request_ptr]
        cmp     byte ptr es:[bx+2], 0   ; INIT request?
        jne     unsupported

        push    cs
        pop     ds
        cld
        call    discover_tape
        jc      init_failed

        les     bx, cs:[request_ptr]
        mov     word ptr es:[bx+0Eh], offset resident_end
        mov     word ptr es:[bx+10h], cs
        mov     word ptr es:[bx+3], 0100h

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
        les     bx, cs:[request_ptr]
        mov     word ptr es:[bx+0Eh], 0
        mov     word ptr es:[bx+10h], cs
        mov     word ptr es:[bx+3], 810Ch ; done + error + general failure
        mov     dx, offset banner_missing
        mov     ah, 09h
        int     21h
        jmp     short request_done

unsupported:
        mov     word ptr es:[bx+3], 8103h ; done + error + unknown command

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
banner_tail         db  '; runtime I/O not enabled yet', 13, 10, '$'
banner_missing      db  'OpenASPI ASPITAP: no ASPI tape; not installed', 13, 10, '$'

aspi_entry          dd  0
adapter_count       db  0
adapter_scsi_id     db  0
target_count        db  8
scan_ha             db  0
scan_target         db  0
scan_lun            db  0
tape_ha             db  0
tape_target         db  0
tape_lun            db  0
srb                  db  ASPI_SRB_SIZE dup (0)

resident_end label byte

        end     driver_start
