; Scripted legacy UNIT ATTENTION fixture. The second WRITE reports a current
; power-on/reset UNIT ATTENTION (key 6, ASC 29h); a later TUR reports a possible
; medium change (28h). While latched only TUR and REWIND may reach the drive;
; any other CDB is a violation.
; SRB command F2h returns the script index (+4) and violation count (+6).
attention_index dw 0
attention_bad dw 0
attention_script:
        db 0Ah, 00h, 00h, 00h, 0Ch, 00h ; WRITE 12: accepted
        db 0Ah, 00h, 00h, 00h, 0Ch, 00h ; WRITE 12: UNIT ATTENTION 29h
        db 00h, 00h, 00h, 00h, 00h, 00h ; MTNOP: TEST UNIT READY
        db 01h, 00h, 00h, 00h, 00h, 00h ; MTREW clears the latch
        db 0Ah, 00h, 00h, 00h, 0Ch, 00h ; WRITE 12 after REWIND
        db 00h, 00h, 00h, 00h, 00h, 00h ; MTNOP: UNIT ATTENTION 28h
        db 01h, 00h, 00h, 00h, 00h, 00h ; MTREW clears it again
        db 10h, 00h, 00h, 00h, 02h, 00h ; final NRMT0 close: two filemarks
        db 11h, 01h, 0FFh, 0FFh, 0FFh, 00h ; close: backspace one filemark
ATTENTION_STEPS equ 9

attention_test_command proc near
        ; ASPISCAN probes INQUIRY before the scenario; unsupported, not counted.
        cmp byte ptr es:[bx+SRB_CDB], 12h
        jne attention_scripted
        mov byte ptr es:[bx+SRB_Status], SS_ERR
        ret
attention_scripted:
        mov ax, word ptr cs:[attention_index]
        cmp ax, ATTENTION_STEPS
        jb attention_in_script
        jmp attention_violation
attention_in_script:
        mov si, ax
        shl si, 1
        add si, ax
        shl si, 1                       ; six bytes per scripted CDB
        add si, offset attention_script
        xor di, di
        mov cx, 6
attention_compare:
        mov al, byte ptr cs:[si]
        cmp al, byte ptr es:[bx+di+SRB_CDB]
        jne attention_mismatch
        inc si
        inc di
        loop attention_compare
        cmp byte ptr es:[bx+SRB_CDBLen], 6
        jne attention_violation
        cmp byte ptr es:[bx+SRB_SenseLen], 32
        jne attention_violation
        inc word ptr cs:[attention_index]
        mov al, 29h                     ; power on, reset or bus device reset
        cmp word ptr cs:[attention_index], 2
        je attention_report
        mov al, 28h                     ; not ready to ready: medium may have changed
        cmp word ptr cs:[attention_index], 6
        je attention_report
        mov word ptr es:[bx+SRB_BufLen], 0 ; no residual when negotiated
        mov word ptr es:[bx+SRB_BufLen+2], 0
        mov byte ptr es:[bx+SRB_HaStat], 0
        mov byte ptr es:[bx+SRB_TargStat], 0
        mov byte ptr es:[bx+SRB_Status], SS_COMP
        ret
attention_report:
        ; Nothing was written: residual stays the full request length.
        mov byte ptr es:[bx+TAPE_SENSE+0], 70h
        mov byte ptr es:[bx+TAPE_SENSE+2], 06h
        mov byte ptr es:[bx+TAPE_SENSE+7], 0Ah
        mov byte ptr es:[bx+TAPE_SENSE+12], al
        mov byte ptr es:[bx+SRB_HaStat], 0
        mov byte ptr es:[bx+SRB_TargStat], 2
        mov byte ptr es:[bx+SRB_Status], SS_ERR
        ret
attention_mismatch:
attention_violation:
        inc word ptr cs:[attention_bad]
        mov byte ptr es:[bx+SRB_Status], SS_ERR
        ret
attention_test_command endp
