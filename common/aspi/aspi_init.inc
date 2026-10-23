; Initialization only: DOS services discover the manager, then ASPI queries
; walk host/target/LUN addresses. A successful INQUIRY supplies identification,
; not permission to claim a device; each driver's ownership policy decides that.
; Do not call these routines from resident request handlers after INIT returns:
; DOS may already have reused their code and discovery buffers.

; ASPI client initialization shared by ASPIDSK, ASPIFDD and ASPICDA.
;
; Include in the transient part of a driver (after its resident end): it is
; used only while DOS initializes the driver.  Needs aspi_client.inc.
;
;   aspi_open        finds SCSIMGR$ and reads its entry point; CF on failure
;   aspi_scan_first  starts an enumeration of every host/target/LUN
;   aspi_scan_next   next device: CF clear and scan_ha/target/lun/type set,
;                    CF set at the end
;   aspi_inquiry     INQUIRY of the scan_* device into inquiry_data; CF on
;                    failure.  inquiry_data+1 bit 7 is the removable bit.

aspi_manager_name db    'SCSIMGR$', 0

scan_ha         db      0
scan_target     db      0
scan_lun        db      0
scan_type       db      0
scan_adapters   db      0
scan_targets    db      0
scan_own_id     db      0
inquiry_data    db      INQUIRY_LEN dup (0)

; Open SCSIMGR$ only to retrieve its FAR manager entry point, then close the
; DOS handle while retaining IOCTL carry. Query adapter count through that entry;
; CF clear means a non-null entry and at least one advertised adapter, not a
; discovered or claimed storage device. DS=CS; init-time DOS services are used.
aspi_open proc near
        mov     ax, 3D00h
        mov     dx, offset aspi_manager_name
        int     21h
        jc      aspi_open_done
        mov     bx, ax
        mov     ax, 4402h                       ; IOCTL read: entry point
        mov     dx, offset aspi_entry
        mov     cx, 4
        int     21h
        pushf
        mov     ah, 3Eh
        int     21h
        popf
        jc      aspi_open_done
        mov     ax, word ptr [aspi_entry]
        or      ax, word ptr [aspi_entry+2]
        jnz     aspi_open_count
        stc
        ret
aspi_open_count:
        call    clear_srb
        mov     byte ptr [srb+SRB_Cmd], SC_HA_INQUIRY
        call    call_aspi
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        jne     aspi_open_fail
        mov     al, byte ptr [srb+HA_Count]
        mov     byte ptr [scan_adapters], al
        or      al, al
        jnz     aspi_open_ok
aspi_open_fail:
        stc
        ret
aspi_open_ok:
        clc
aspi_open_done:
        ret
aspi_open endp

; Reset only enumeration state; the first aspi_scan_next loads adapter zero.
; This is not a returned candidate and does not clear registered DOS units.
aspi_scan_first proc near
        mov     byte ptr [scan_ha], 0
        mov     byte ptr [scan_target], 0FFh    ; aspi_scan_next starts at 0
        mov     byte ptr [scan_lun], 7
        mov     byte ptr [scan_targets], 0
        ret
aspi_scan_first endp

; Enumeration state is scan_*, separate from runtime unit_*. GET DEVICE TYPE
; finds candidates; INQUIRY and driver-specific ownership policy still qualify
; them. Skip the adapter's own target ID and advance LUN/target/adapter at the
; respective bounds; end-of-scan carry does not designate an installed DOS unit.
aspi_scan_next proc near
scan_next_lun:
        inc     byte ptr [scan_lun]
        cmp     byte ptr [scan_lun], 8
        jb      scan_query
        mov     byte ptr [scan_lun], 0
scan_next_target:
        inc     byte ptr [scan_target]
        mov     al, byte ptr [scan_target]
        cmp     al, byte ptr [scan_targets]
        jb      scan_target_ok
        ; next adapter (the first time: adapter 0)
        cmp     byte ptr [scan_targets], 0
        je      scan_adapter
        inc     byte ptr [scan_ha]
scan_adapter:
        mov     al, byte ptr [scan_ha]
        cmp     al, byte ptr [scan_adapters]
        jb      scan_adapter_inquiry
        stc
        ret
; Load this adapter's initiator ID and bounded target count (default eight).
; A failed adapter inquiry follows the limited failure path below, not a valid
; advertisement of a full target range. These are manager addresses, not drive
; letters, and the initiator's own target is excluded from candidate probing.
scan_adapter_inquiry:
        call    clear_srb
        mov     byte ptr [srb+SRB_Cmd], SC_HA_INQUIRY
        mov     al, byte ptr [scan_ha]
        mov     byte ptr [srb+SRB_HaId], al
        call    call_aspi
        mov     al, byte ptr [srb+HA_SCSI_ID]
        mov     byte ptr [scan_own_id], al
        mov     al, byte ptr [srb+HA_Unique+3]  ; targets per adapter, 0 = 8
        or      al, al
        jz      scan_eight
        cmp     al, 32
        jbe     scan_targets_ready
scan_eight:
        mov     al, 8
scan_targets_ready:
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        je      scan_adapter_ok
        mov     al, 1                           ; skip a failing adapter
        mov     byte ptr [scan_own_id], 0FFh
scan_adapter_ok:
        mov     byte ptr [scan_targets], al
        mov     byte ptr [scan_target], 0
scan_target_ok:
        mov     al, byte ptr [scan_target]
        cmp     al, byte ptr [scan_own_id]
        je      scan_next_target
scan_query:
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
        je      scan_found
; Current block/CD enumeration stops this target after a failed GET DEVICE
; TYPE at a LUN. It does not promise exhaustive discovery of higher sparse LUNs;
; ASPITAP's independent discovery loop instead advances through all eight LUNs.
        ; no device: the other LUNs of this target are not asked
        mov     byte ptr [scan_lun], 7
        jmp     scan_next_lun
scan_found:
        mov     al, byte ptr [srb+SRB_DeviceType]
        and     al, 1Fh
        mov     byte ptr [scan_type], al
        clc
        ret
aspi_scan_next endp

; Copy scan_* into runtime unit_* and read 36-byte standard identity. This
; selects the shared SRB address as a side effect; callers retain scan_* if they
; need to continue discovery. Carry reports checked completion, not ownership
; or proof that the drive currently contains a mountable filesystem.
aspi_inquiry proc near
        mov     al, byte ptr [scan_ha]
        mov     byte ptr [unit_ha], al
        mov     al, byte ptr [scan_target]
        mov     byte ptr [unit_target], al
        mov     al, byte ptr [scan_lun]
        mov     byte ptr [unit_lun], al
        mov     al, SRB_DIR_IN
        mov     cl, 6
        call    aspi_prepare
        mov     byte ptr [srb+SRB_CDB], 12h     ; INQUIRY
        mov     byte ptr [srb+SRB_CDB+4], INQUIRY_LEN
        mov     word ptr [srb+SRB_BufLen], INQUIRY_LEN
        mov     word ptr [srb+SRB_BufPointer], offset inquiry_data
        mov     word ptr [srb+SRB_BufPointer+2], cs
        call    call_aspi
        jmp     aspi_result
aspi_inquiry endp

; Print the vendor and product of inquiry_data (24 characters).
print_inquiry_name proc near
        push    si
        mov     si, offset inquiry_data+8
        mov     cx, 24
print_inquiry_loop:
        lodsb
        cmp     al, ' '
        jae     print_inquiry_char
        mov     al, ' '
print_inquiry_char:
        mov     dl, al
        mov     ah, 02h
        int     21h
        loop    print_inquiry_loop
        pop     si
        ret
print_inquiry_name endp
