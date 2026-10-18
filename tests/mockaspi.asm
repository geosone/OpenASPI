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
ifdef NO_RESIDUAL
        mov     word ptr es:[bx+HA_ExtFlags], 0
else
        mov     word ptr es:[bx+HA_ExtFlags], HA_EXT_RESIDUAL
endif
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
        cmp     byte ptr es:[bx+SRB_CDB], 08h
        je      execute_read
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
        je      read_eom
        jmp     short read_negative_ili

read_first:
        mov     si, offset read_payload
        mov     cx, READ_PAYLOAD_SIZE
        call    copy_read_payload
ifndef NO_RESIDUAL
        mov     word ptr es:[bx+SRB_BufLen], 16-READ_PAYLOAD_SIZE
endif
        jmp     short read_success

read_short_ili:
        mov     si, offset ili_payload
        mov     cx, ILI_PAYLOAD_SIZE
        call    copy_read_payload
ifndef NO_RESIDUAL
        mov     word ptr es:[bx+SRB_BufLen], 16-ILI_PAYLOAD_SIZE
endif
        mov     al, 20h                 ; ILI, no-sense key
        mov     dx, 16-ILI_PAYLOAD_SIZE ; requested minus actual
        call    set_read_condition
        jmp     short aspi_done

read_filemark:
        mov     al, 80h                 ; FILEMARK, no-sense key
        mov     dx, 16                  ; no bytes transferred
        call    set_read_condition
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

EXPECTED_COUNT equ     9
READ_COUNT     equ     7
expected_index db      0
read_index     db      0
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
expected_cdbs:
        db      00h, 00h, 00h, 00h, 00h, 00h ; MTNOP between RMT0 closes
        db      01h, 00h, 00h, 00h, 00h, 00h ; final RMT0 close rewinds
        db      00h, 00h, 00h, 00h, 00h, 00h ; MTNOP / TEST UNIT READY
        db      11h, 01h, 00h, 00h, 03h, 00h ; MTFSF 3
        db      11h, 01h, 0FFh, 0FFh, 0FDh, 00h ; MTBSF 3
        db      11h, 00h, 00h, 00h, 04h, 00h ; MTFSR 4
        db      11h, 00h, 0FFh, 0FFh, 0FCh, 00h ; MTBSR 4
        db      01h, 00h, 00h, 00h, 00h, 00h ; MTREW
        db      1Bh, 00h, 00h, 00h, 00h, 00h ; MTOFFL

resident_end label byte

        end     driver_start
