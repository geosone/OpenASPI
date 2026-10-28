; Shared INQUIRY qualification (aspi_inquiry) against a memory-only manager:
; short, untouched and contradictory replies must not expose stale bytes.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h
        jmp start
        include common/aspi/dos_aspi.inc
        include common/aspi/aspi_client.inc
        include common/aspi/aspi_init.inc

CHECK macro condition
        local good
        condition good
        jmp failed
good:
endm
; length written, residual (dword), source, expected carry (0/1)
CASE macro written, resid_lo, resid_hi, source, carry
        mov word ptr [fake_len], written
        mov word ptr [fake_resid], resid_lo
        mov word ptr [fake_resid+2], resid_hi
        mov word ptr [fake_src], offset source
        call run_case
        mov al, carry
        call expect_carry
endm
EXPECT_BYTES macro offs, source, count
        mov si, offset source
        mov di, offset inquiry_data+offs
        mov cx, count
        call compare
endm

fake_len        dw      0
fake_resid      dd      0
fake_src        dw      0
fake_flags      db      0
step            db      'A'
; CD-ROM, removable, SCSI-2, additional length 31
reply_cd        db      05h, 80h, 02h, 02h, 31, 0, 0, 0
                db      'OPENASPI', 'TEST CD-ROM     ', '1.00'
reply_disk      db      00h, 00h, 02h, 02h, 31, 0, 0, 0
                db      'OPENASPI', 'TEST DISK       ', '1.00'
reply_qual      db      25h, 80h, 02h, 02h, 31, 0, 0, 0
                db      'OPENASPI', 'NOT CONNECTED   ', '1.00'
; additional length 3: only eight bytes belong to the reply
reply_short     db      05h, 80h, 02h, 02h, 3, 0, 0, 0
                db      'ZZZZZZZZ', 'ZZZZZZZZZZZZZZZZ', 'ZZZZ'
reply_ctl       db      05h, 80h, 02h, 02h, 31, 0, 0, 0
                db      'OPEN', 01h, 'ASP', 'TEST', 0FFh, 'CD-ROM     ', '1.00'
blanks          db      28 dup (' ')
vendor_fixed    db      'OPEN ASPTEST CD-ROM     '
ok db 'INQUIRY completion/length/stale-byte validation passed',13,10,'$'
bad db 'INQUIRY validation FAILED at step $'
newline db 13,10,'$'

start:
        push cs
        pop ds
        push cs
        pop es
        cld
        mov word ptr [aspi_entry], offset fake_aspi
        mov word ptr [aspi_entry+2], cs
        mov byte ptr [scan_type], 05h
        ; A: a complete reply without residual support
        mov word ptr [scan_ext_flags], 0
        CASE 36, 0, 0, reply_cd, 0
        test byte ptr [fake_flags], SRB_RESIDUAL
        CHECK jz
        EXPECT_BYTES 0, reply_cd, 36
        ; B: success but nothing written (untouched buffer)
        inc byte ptr [step]
        CASE 0, 0, 0, reply_cd, 1
        ; C: another device type than GET DEVICE TYPE, D: qualifier 1
        inc byte ptr [step]
        CASE 36, 0, 0, reply_disk, 1
        inc byte ptr [step]
        CASE 36, 0, 0, reply_qual, 1
        ; E: the reply's own length cuts off bytes the device wrote anyway
        inc byte ptr [step]
        CASE 36, 0, 0, reply_short, 0
        EXPECT_BYTES 8, blanks, 28
        ; F: control characters in the identification read as blanks
        inc byte ptr [step]
        CASE 36, 0, 0, reply_ctl, 0
        EXPECT_BYTES 8, vendor_fixed, 24
        ; G: residual support: 20 of 36 bytes arrived, the rest is blank
        inc byte ptr [step]
        mov word ptr [scan_ext_flags], HA_EXT_RESIDUAL
        CASE 20, 16, 0, reply_cd, 0
        test byte ptr [fake_flags], SRB_RESIDUAL
        CHECK jnz
        EXPECT_BYTES 0, reply_cd, 20
        EXPECT_BYTES 20, blanks, 16
        ; H: fewer than five bytes, I: residual above the request,
        ; J: residual with a high word
        inc byte ptr [step]
        CASE 4, 32, 0, reply_cd, 1
        inc byte ptr [step]
        CASE 36, 37, 0, reply_cd, 1
        inc byte ptr [step]
        CASE 36, 0, 1, reply_cd, 1
        ; K: a full transfer with residual 0
        inc byte ptr [step]
        CASE 36, 0, 0, reply_cd, 0
        EXPECT_BYTES 0, reply_cd, 36
        mov dx, offset ok
        mov ah, 9
        int 21h
        mov ax, 4C00h
        int 21h

failed:
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

run_case proc near
        call aspi_inquiry
        mov al, 0
        adc al, 0
        mov byte ptr [case_carry], al
        ret
run_case endp

expect_carry proc near
        cmp al, byte ptr [case_carry]
        CHECK je
        ret
expect_carry endp

compare proc near
        push ds
        pop es
        repe cmpsb
        CHECK je
        ret
compare endp

case_carry db 0

fake_aspi proc far
        push bp
        mov bp, sp
        push si
        push di
        push cx
        push es
        les di, dword ptr [bp+6]                ; the SRB
        mov al, byte ptr es:[di+SRB_Flags]
        mov byte ptr cs:[fake_flags], al
        mov byte ptr es:[di+SRB_Status], SS_COMP
        test al, SRB_RESIDUAL
        jz fake_copy
        mov ax, word ptr cs:[fake_resid]
        mov word ptr es:[di+SRB_BufLen], ax
        mov ax, word ptr cs:[fake_resid+2]
        mov word ptr es:[di+SRB_BufLen+2], ax
fake_copy:
        les di, dword ptr es:[di+SRB_BufPointer]
        mov si, word ptr cs:[fake_src]
        mov cx, word ptr cs:[fake_len]
        rep movsb
        pop es
        pop cx
        pop di
        pop si
        pop bp
        ret
fake_aspi endp
        end start
