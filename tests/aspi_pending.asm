; Shared client (call_aspi/aspi_result/aspi_sense) against a manager that
; returns SS_PENDING and completes from the timer interrupt: the client must
; wait with IRQs enabled even when entered with them disabled, restore the
; caller's flags, see the data and sense written before the status, and treat
; aborted, abort-failed, unknown and host-failed completions as errors.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h
        jmp start
        include common/aspi/dos_aspi.inc
        include common/aspi/aspi_client.inc

CHECK macro condition
        local good
        condition good
        jmp failed
good:
endm
; completion status, host status, target status, ticks until completion
CASE macro status, hastat, targstat, ticks
        mov byte ptr [done_status], status
        mov byte ptr [done_hastat], hastat
        mov byte ptr [done_targstat], targstat
        mov word ptr [delay], ticks
        call run_case
endm

delay           dw      0               ; timer ticks until completion
pending         db      0
done_status     db      0
done_hastat     db      0
done_targstat   db      0
completions     dw      0
old_1c          dd      0
data_buf        db      4 dup (0)
step            db      'A'
; fixed sense, UNIT ATTENTION 28h
ua_sense        db      70h, 0, 06h, 0, 0, 0, 0, 6, 0, 0, 0, 0, 28h, 0
ok db 'ASPI pending/abort completion tests passed',13,10,'$'
bad db 'ASPI pending/abort completion FAILED at step $'
newline db 13,10,'$'

start:
        push cs
        pop ds
        push cs
        pop es
        cld
        mov word ptr [aspi_entry], offset fake_aspi
        mov word ptr [aspi_entry+2], cs
        mov ax, 351Ch
        int 21h
        mov word ptr [old_1c], bx
        mov word ptr [old_1c+2], es
        push cs
        pop es
        mov dx, offset timer_hook
        mov ax, 251Ch
        int 21h
        ; A: pending, completed two ticks later; data written before status
        CASE SS_COMP, 0, 0, 2
        CHECK jnc
        cmp word ptr [data_buf], 'KO'
        CHECK je
        ; B: an immediate completion is not waited for and needs no IRQ
        inc byte ptr [step]
        CASE SS_COMP, 0, 0, 0
        CHECK jnc
        ; C: aborted by the manager: an error without sense or attention
        inc byte ptr [step]
        CASE SS_ABORTED, 0, 0, 1
        CHECK jc
        or ax, ax
        CHECK jz
        ; D: abort failed, E: unknown status, F: host failure on SS_COMP
        inc byte ptr [step]
        CASE SS_ABORT_FAIL, 0, 0, 1
        CHECK jc
        inc byte ptr [step]
        CASE 05h, 0, 0, 1
        CHECK jc
        inc byte ptr [step]
        CASE SS_COMP, 11h, 0, 1
        CHECK jc
        ; G: CHECK CONDITION with UNIT ATTENTION, sense written before status
        inc byte ptr [step]
        CASE SS_ERR, 0, 2, 2
        CHECK jc
        cmp al, 6
        CHECK je
        cmp byte ptr [aspi_attention], 0
        CHECK jne
        ; H: the same as host failure: sense present but not trusted
        inc byte ptr [step]
        mov byte ptr [aspi_attention], 0
        CASE SS_ERR, 11h, 2, 1
        CHECK jc
        or ax, ax
        CHECK jz
        cmp byte ptr [aspi_attention], 0
        CHECK je
        ; every case reached the manager exactly once
        inc byte ptr [step]
        cmp word ptr [completions], 8
        CHECK je
        call restore_timer
        mov dx, offset ok
        mov ah, 9
        int 21h
        mov ax, 4C00h
        int 21h

failed:
        call restore_timer
        mov dx, offset bad
        mov ah, 9
        int 21h
        mov dl, byte ptr [step]
        mov ah, 2
        int 21h
        mov dx, offset newline
        mov ah, 9
        int 21h
        mov ax, 4C01h
        int 21h

restore_timer proc near
        push ds
        lds dx, dword ptr cs:[old_1c]
        mov ax, 251Ch
        int 21h
        pop ds
        ret
restore_timer endp

; Submit a six-byte command with IRQs disabled, as DOS may call a driver.
; Returns the aspi_result carry/AX; fails the step if call_aspi returned
; before completion or did not restore the disabled IRQ flag.
run_case proc near
        mov word ptr [data_buf], 0
        mov al, SRB_DIR_IN
        mov cl, 6
        call aspi_prepare
        mov word ptr [srb+SRB_BufLen], 2
        mov word ptr [srb+SRB_BufPointer], offset data_buf
        mov word ptr [srb+SRB_BufPointer+2], cs
        cli
        call call_aspi
        pushf
        pop ax
        sti
        test ax, 0200h
        CHECK jz
        cmp byte ptr [srb+SRB_Status], SS_PENDING
        CHECK jne
        cmp byte ptr [pending], 0
        CHECK je
        call aspi_result
        ret
run_case endp

; Writes the reply: data, then sense, host and target status, status last.
complete_srb proc near
        push ax
        push cx
        push si
        push di
        push es
        push cs
        pop es
        inc word ptr cs:[completions]
        mov word ptr cs:[data_buf], 'KO'
        mov di, offset srb+SRB_CDB+6
        mov si, offset ua_sense
        mov cx, ASPI_SENSE_LEN
        push ds
        push cs
        pop ds
        rep movsb
        pop ds
        mov al, byte ptr cs:[done_hastat]
        mov byte ptr cs:[srb+SRB_HaStat], al
        mov al, byte ptr cs:[done_targstat]
        mov byte ptr cs:[srb+SRB_TargStat], al
        mov al, byte ptr cs:[done_status]
        mov byte ptr cs:[srb+SRB_Status], al
        mov byte ptr cs:[pending], 0
        pop es
        pop di
        pop si
        pop cx
        pop ax
        ret
complete_srb endp

fake_aspi proc far
        cmp word ptr cs:[delay], 0
        je fake_now
        mov byte ptr cs:[pending], 1            ; status stays SS_PENDING
        ret
fake_now:
        call complete_srb
        ret
fake_aspi endp

timer_hook proc far
        cmp byte ptr cs:[pending], 0
        je timer_chain
        dec word ptr cs:[delay]
        jnz timer_chain
        call complete_srb
timer_chain:
        jmp dword ptr cs:[old_1c]
timer_hook endp
        end start
