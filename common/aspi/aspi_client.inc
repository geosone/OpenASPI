; ASPI client helpers shared by ASPIDSK, ASPIFDD and ASPICDA.
;
; Include after dos_aspi.inc inside the resident code of a driver.  The
; helpers use DS = CS and keep their data (SRB, manager entry, scan state)
; in the resident part, so they can be called by the request handlers.
;
;   aspi_open        finds SCSIMGR$ and reads its entry point (init only)
;   aspi_scan_first  starts an enumeration of host/target/LUN
;   aspi_scan_next   next device: CF clear, scan_ha/target/lun/type set
;   aspi_inquiry     INQUIRY (36 bytes into inquiry_data) of scan_* device
;   aspi_prepare     clears the SRB for SC_EXEC_SCSI_CMD on unit_ha/...
;   call_aspi        submits the SRB and waits for its completion

ASPI_SENSE_LEN          equ     14
INQUIRY_LEN             equ     36

aspi_entry      dd      0
srb             db      ASPI_SRB_SIZE dup (0)

; the device of the current request (set by the driver from its unit table)
unit_ha         db      0
unit_target     db      0
unit_lun        db      0

; Submit the SRB.  DOS can enter a driver with IRQs disabled, and managers
; may complete through their hardware IRQ: enable them while waiting.  The
; manager owns command timeouts, so a pending SRB is never given up.
call_aspi proc near
        pushf
        sti
        push    bx                              ; managers need not keep
        push    cx                              ; the registers
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        push    cs
        mov     ax, offset srb
        push    ax
        call    dword ptr cs:[aspi_entry]
        add     sp, 4
        pop     es
        pop     ds
call_aspi_wait:
        cmp     byte ptr cs:[srb+SRB_Status], SS_PENDING
        je      call_aspi_wait
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
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

; An execute-SCSI SRB for unit_ha/unit_target/unit_lun with AL = flags
; (direction) and CL = CDB length.  The caller fills the CDB, the buffer
; pointer and length, then calls call_aspi.
aspi_prepare proc near
        call    clear_srb
        mov     byte ptr [srb+SRB_Cmd], SC_EXEC_SCSI_CMD
        mov     byte ptr [srb+SRB_Flags], al
        mov     byte ptr [srb+SRB_CDBLen], cl
        mov     byte ptr [srb+SRB_SenseLen], ASPI_SENSE_LEN
        mov     al, byte ptr [unit_ha]
        mov     byte ptr [srb+SRB_HaId], al
        mov     al, byte ptr [unit_target]
        mov     byte ptr [srb+SRB_Target], al
        mov     al, byte ptr [unit_lun]
        mov     byte ptr [srb+SRB_Lun], al
        ret
aspi_prepare endp

; CF clear when the command completed without error.  AL = sense key of a
; CHECK CONDITION (0 if none).  Sense follows the actual CDB in the SRB.
aspi_result proc near
        xor     al, al
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        je      aspi_result_ok
        cmp     byte ptr [srb+SRB_TargStat], 02h        ; CHECK CONDITION
        jne     aspi_result_fail
        push    bx
        mov     bl, byte ptr [srb+SRB_CDBLen]
        xor     bh, bh
        mov     al, byte ptr [srb+bx+SRB_CDB+2]
        and     al, 0Fh
        pop     bx
aspi_result_fail:
        stc
        ret
aspi_result_ok:
        clc
        ret
aspi_result endp

; AL = SCSI sense key -> AL = DOS driver error code (devreq.inc)
sense_to_doserr proc near
        cmp     al, 02h                         ; NOT READY
        jne     sense_not_medium
        mov     al, 02h
        ret
sense_not_medium:
        cmp     al, 03h                         ; MEDIUM ERROR
        jne     sense_not_illegal
        mov     al, 0Bh
        ret
sense_not_illegal:
        cmp     al, 05h                         ; ILLEGAL REQUEST
        jne     sense_not_attention
        mov     al, 08h
        ret
sense_not_attention:
        cmp     al, 06h                         ; UNIT ATTENTION
        jne     sense_not_protect
        mov     al, 0Fh
        ret
sense_not_protect:
        cmp     al, 07h                         ; DATA PROTECT
        jne     sense_general
        xor     al, al
        ret
sense_general:
        mov     al, 0Ch
        ret
sense_to_doserr endp
