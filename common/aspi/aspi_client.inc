; Resident transport boundary: one shared SRB, synchronous submission, no
; reentrant calls. The caller selects unit_ha/target/lun before preparation.
; Completion status, host status and target status must agree before success;
; a sense key alone never authorizes a retry or an unsupported-CDB fallback.
; Initialization/enumeration code is separate in aspi_init.inc so DOS can reclaim
; it; these helpers and their buffers must remain below resident_end.

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
; Set by aspi_sense on checked current UNIT ATTENTION (key 6, 70h/72h). Drivers
; clear it when a DOS request starts and transfer it to the selected unit when
; the request ends, so a change consumed by any command is not lost.
aspi_attention  db      0

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

; Reset the whole resident SRB backing store, including CDB/sense/workspace.
; A new command must not inherit status, direction or sense from the previous
; one. ES:DI and AX/CX are saved because callers may still hold DOS packet data.
; Only call after the manager no longer owns a pending SRB.
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
; CHECK CONDITION (0 if unavailable). AH is unspecified. Sense follows the
; actual CDB in the DOS SRB, unlike the separate Win32 sense array.
aspi_result proc near
        xor     ax, ax
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        jne     aspi_result_error
        cmp     byte ptr [srb+SRB_HaStat], 0
        jne     aspi_result_fail
        cmp     byte ptr [srb+SRB_TargStat], 0
        je      aspi_result_ok
        jmp     short aspi_result_fail
aspi_result_error:
        call    aspi_sense
aspi_result_fail:
        stc
        ret
aspi_result_ok:
        clc
        ret
aspi_result endp

; CF clear: checked autosense, AL = key, AH = ASC (zero if unavailable).
; CF set: no trustworthy autosense, AX = 0. All other registers preserved.
; Fixed responses need their eight-byte header; ASC also needs byte 12
; within both the allocation and the additional-length field. Descriptor
; responses carry key/ASC in the header. No descriptor traversal is needed.
; SenseLen is an allocation, not proof of the actual transfer length. The
; zeroed SRB prevents reuse; DOS ASPI cannot prove every short transfer.
; Current key 6 also sets aspi_attention; nothing here clears it.
aspi_sense proc near
        push    bx
        xor     ax, ax
        cmp     byte ptr [srb+SRB_Cmd], SC_EXEC_SCSI_CMD
        jne     aspi_sense_invalid
        cmp     byte ptr [srb+SRB_Status], SS_ERR
        jne     aspi_sense_invalid
        cmp     byte ptr [srb+SRB_HaStat], 0
        jne     aspi_sense_invalid
        cmp     byte ptr [srb+SRB_TargStat], 2
        jne     aspi_sense_invalid
        cmp     byte ptr [srb+SRB_SenseLen], 8
        jb      aspi_sense_invalid
        cmp     byte ptr [srb+SRB_SenseLen], ASPI_SENSE_LEN
        ja      aspi_sense_invalid
        mov     bl, byte ptr [srb+SRB_CDBLen]
        xor     bh, bh
        cmp     bl, 6
        je      aspi_sense_address
        cmp     bl, 10
        je      aspi_sense_address
        cmp     bl, 12
        je      aspi_sense_address
        cmp     bl, 16
        jne     aspi_sense_invalid
aspi_sense_address:
        mov     al, byte ptr [srb+bx+SRB_CDB]
        cmp     al, 72h
        je      aspi_sense_descriptor
        cmp     al, 73h
        je      aspi_sense_descriptor
        and     al, 7Fh                  ; VALID bit belongs to fixed sense
        cmp     al, 70h
        je      aspi_sense_fixed
        cmp     al, 71h
        jne     aspi_sense_invalid
aspi_sense_fixed:
        xor     ah, ah
        cmp     byte ptr [srb+SRB_SenseLen], 13
        jb      aspi_sense_key
        cmp     byte ptr [srb+bx+SRB_CDB+7], 5
        jb      aspi_sense_key
        mov     ah, byte ptr [srb+bx+SRB_CDB+12]
aspi_sense_key:
        mov     al, byte ptr [srb+bx+SRB_CDB+2]
        and     al, 0Fh
        jmp     short aspi_sense_valid
aspi_sense_descriptor:
        mov     ah, byte ptr [srb+bx+SRB_CDB+2]
        mov     al, byte ptr [srb+bx+SRB_CDB+1]
        and     al, 0Fh
aspi_sense_valid:
        call    aspi_note_attention
        pop     bx
        clc
        ret
aspi_sense_invalid:
        xor     ax, ax
        pop     bx
        stc
        ret
aspi_sense endp

; AL = checked key, BX = CDB length (sense base). Set aspi_attention only for
; current UNIT ATTENTION; deferred sense does not describe this command.
aspi_note_attention proc near
        cmp     al, 06h
        jne     aspi_attention_done
        push    ax
        mov     al, byte ptr [srb+bx+SRB_CDB]
        cmp     al, 72h
        je      aspi_attention_current
        and     al, 7Fh
        cmp     al, 70h
        jne     aspi_attention_restore
aspi_attention_current:
        mov     byte ptr [aspi_attention], 1
aspi_attention_restore:
        pop     ax
aspi_attention_done:
        ret
aspi_note_attention endp

; AL = SCSI sense key -> AL = DOS driver error code (devreq.inc)
; Lossy mapping from a qualified key (or zero/unavailable) to DOS error AL.
; It does NOT return completion in carry: DATA PROTECT deliberately yields AL=0,
; a valid write-protection error when the caller sets DOS ERROR. General errors
; remain general; use original sense/ASC for unsupported-opcode or rescue policy.
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
