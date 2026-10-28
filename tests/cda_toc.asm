; Actual ASPICDA TOC/capacity handlers against memory-only ASPI: a short or
; untouched READ TOC or READ CAPACITY reply must not reuse an earlier disc's
; data, and malformed TOC headers fail instead of being searched.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h
        jmp test_start
ASPICDA_TEST equ 1
DRIVER_ENTRY textequ <test_start>
        include common/aspi/dos_aspi.inc
        include common/dos/devreq.inc

CHECK_EQ macro
        local good
        je good
        jmp failed
good:
endm
; control code, count, expected status
QUERY macro code, count, status
        mov byte ptr [control], code
        mov word ptr [packet+RH_COUNT], count
        call submit
        cmp word ptr [packet+RH_STATUS], status
        CHECK_EQ
        inc word ptr [step]
endm
; TOC reply source and bytes the fake manager writes
REPLY macro source, written
        mov word ptr [toc_src], offset source
        mov word ptr [toc_len], written
endm

packet db 32 dup (0)
control db 16 dup (0)
strategy_ptr dw offset strategy,0
interrupt_ptr dw offset interrupt,0
step dw 0
toc_src dw 0
toc_len dw 0
cap_len dw 8
; disc A: tracks 1 and 2, lead-out at 10:00:00
toc_a   db 0, 26, 1, 2
        db 0, 14h, 1, 0, 0, 0, 2, 0
        db 0, 14h, 2, 0, 0, 5, 0, 0
        db 0, 14h, 0AAh, 0, 0, 10, 0, 0
; disc B claims the same two tracks, but only track 1 is transferred
toc_b   db 0, 26, 1, 2
        db 0, 10h, 1, 0, 0, 0, 2, 0
toc_odd db 0, 25, 1, 2                  ; not whole descriptors
toc_rev db 0, 26, 2, 1                  ; first > last
toc_big db 3, 0, 1, 2                   ; longer than the buffer
cap_a   db 0, 0, 0, 0FFh, 0, 0, 8, 0    ; last LBA 255, 2048 bytes
ok db 'ASPICDA TOC/capacity short-reply tests passed',13,10,'$'
failure db 'ASPICDA TOC/capacity FAILED step $'

test_start:
        push cs
        pop ds
        push cs
        pop es
        mov word ptr [strategy_ptr+2], cs
        mov word ptr [interrupt_ptr+2], cs
        mov word ptr [aspi_entry], offset fake_aspi
        mov word ptr [aspi_entry+2], cs
        mov byte ptr [unit_count], 1
        mov byte ptr [packet+RH_LENGTH], 32
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_IN
        mov word ptr [packet+RH_BUFFER], offset control
        mov word ptr [packet+RH_BUFFER+2], cs
        ; disc A: disk and track information
        REPLY toc_a, 28
        QUERY 10, 7, ST_DONE
        cmp word ptr [control+1], 0201h
        CHECK_EQ
        cmp byte ptr [control+5], 10            ; lead-out minutes
        CHECK_EQ
        mov byte ptr [control+1], 2
        QUERY 11, 7, ST_DONE
        cmp byte ptr [control+4], 5             ; track 2 at 05:00
        CHECK_EQ
        ; disc B, short: track 2 must not come from disc A
        REPLY toc_b, 12
        mov byte ptr [control+1], 2
        QUERY 11, 7, ST_DONE or ST_ERROR or ERR_NOT_FOUND
        mov byte ptr [control+1], 1
        QUERY 11, 7, ST_DONE
        cmp byte ptr [control+6], 01h           ; disc B's CONTROL 0, ADR 1
        CHECK_EQ
        ; untouched reply and malformed headers
        REPLY toc_a, 0
        QUERY 10, 7, ST_DONE or ST_ERROR or ERR_GENERAL
        REPLY toc_odd, 4
        QUERY 10, 7, ST_DONE or ST_ERROR or ERR_GENERAL
        REPLY toc_rev, 4
        QUERY 10, 7, ST_DONE or ST_ERROR or ERR_GENERAL
        REPLY toc_big, 4
        QUERY 10, 7, ST_DONE or ST_ERROR or ERR_GENERAL
        ; capacity: a full reply, then an untouched one
        QUERY 8, 5, ST_DONE
        cmp word ptr [control+1], 256
        CHECK_EQ
        mov word ptr [cap_len], 0
        QUERY 8, 5, ST_DONE or ST_ERROR or ERR_NOT_FOUND
        mov dx, offset ok
        mov ah, 9
        int 21h
        mov ax, 4C00h
        int 21h
failed:
        mov dx, offset failure
        mov ah, 9
        int 21h
        mov ax, word ptr [step]
        aam
        add ax, 3030h
        push ax
        mov dl, ah
        mov ah, 2
        int 21h
        pop dx
        mov ah, 2
        int 21h
        mov ax, 4C01h
        int 21h

submit proc near
        push cs
        pop es
        mov bx, offset packet
        call dword ptr [strategy_ptr]
        call dword ptr [interrupt_ptr]
        ret
submit endp

fake_aspi proc far
        push si
        push di
        push cx
        push es
        mov byte ptr cs:[srb+SRB_Status], SS_COMP
        les di, dword ptr cs:[srb+SRB_BufPointer]
        cmp byte ptr cs:[srb+SRB_CDB], 43h
        je fake_toc
        cmp byte ptr cs:[srb+SRB_CDB], 25h
        jne fake_done
        mov si, offset cap_a
        mov cx, word ptr cs:[cap_len]
        jmp short fake_copy
fake_toc:
        mov si, word ptr cs:[toc_src]
        mov cx, word ptr cs:[toc_len]
fake_copy:
        rep movsb
fake_done:
        pop es
        pop cx
        pop di
        pop si
        ret
fake_aspi endp
        include drivers/aspicda/aspicda.asm
