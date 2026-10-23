; Shared no-data medium control for block and CD drivers.
; AL = opcode (1Bh START STOP, 1Eh PREVENT ALLOW), AH = CDB byte 4.
; Leaves the raw SRB for the caller's own sense/error and state policy.
aspi_media_control proc near
        push    ax
        mov     al, SRB_DIR_NONE
        mov     cl, 6
        call    aspi_prepare
        pop     ax
        mov     byte ptr [srb+SRB_CDB], al
        mov     byte ptr [srb+SRB_CDB+4], ah
        call    call_aspi
        ret
aspi_media_control endp
