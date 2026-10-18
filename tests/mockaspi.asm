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
        mov     byte ptr es:[bx+HA_Count], 1
        mov     byte ptr es:[bx+HA_SCSI_ID], 7
        mov     byte ptr es:[bx+HA_Unique+3], 1
        mov     byte ptr es:[bx+SRB_Status], SS_COMP
        jmp     aspi_done

device_type:
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
        cmp     byte ptr es:[bx+SRB_Flags], SRB_DIR_NONE
        jne     bad_scsi
        cmp     byte ptr es:[bx+SRB_CDBLen], 6
        jne     bad_scsi
        cmp     byte ptr es:[bx+SRB_SenseLen], 32
        jne     bad_scsi
        xor     ax, ax
        mov     al, byte ptr cs:[expected_index]
        cmp     al, EXPECTED_COUNT
        jae     bad_scsi
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
        jne     bad_scsi
        inc     si
        inc     di
        loop    check_cdb
        inc     byte ptr cs:[expected_index]
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

EXPECTED_COUNT equ     7
expected_index db      0
expected_cdbs:
        db      00h, 00h, 00h, 00h, 00h, 00h ; MTNOP / TEST UNIT READY
        db      11h, 01h, 00h, 00h, 03h, 00h ; MTFSF 3
        db      11h, 01h, 0FFh, 0FFh, 0FDh, 00h ; MTBSF 3
        db      11h, 00h, 00h, 00h, 04h, 00h ; MTFSR 4
        db      11h, 00h, 0FFh, 0FFh, 0FCh, 00h ; MTBSR 4
        db      01h, 00h, 00h, 00h, 00h, 00h ; MTREW
        db      1Bh, 00h, 00h, 00h, 00h, 00h ; MTOFFL

resident_end label byte

        end     driver_start
