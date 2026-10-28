; Standard INQUIRY reply qualification, shared by the drivers' aspi_inquiry
; (aspi_init.inc) and ASPISCAN, so both classify a device the same way.
; The includer defines inquiry_data (INQUIRY_LEN bytes) and the srb.
;
; A successful status does not prove 36 bytes arrived. The buffer is poisoned
; first (an untouched reply has qualifier 7), the manager's residual count is
; used when the request asked for it, and the reply is cut to its own
; additional length. Fewer than five bytes, a nonzero qualifier or a type other
; than GET DEVICE TYPE's fails. Missing bytes read as zero (header) or blanks
; (identification), and identification bytes are forced to printable ASCII.
; Without residual support a truncated transfer whose header claims 36 bytes
; cannot be detected; its unwritten identification bytes still read as blanks.

ifndef INQUIRY_LEN
INQUIRY_LEN     equ     36
endif

; Fill inquiry_data with 0FFh before the command. Preserves all registers.
inquiry_poison proc near
        push    ax
        push    cx
        push    di
        push    es
        push    cs
        pop     es
        mov     di, offset inquiry_data
        mov     cx, INQUIRY_LEN
        mov     al, 0FFh
        rep     stosb
        pop     es
        pop     di
        pop     cx
        pop     ax
        ret
inquiry_poison endp

; After an INQUIRY that completed without error. AL = peripheral type from
; GET DEVICE TYPE. CF clear: inquiry_data is qualified; CF set: reject it.
; Destroys AX, CX, DI.
inquiry_qualify proc near
        mov     ah, al
        mov     cx, INQUIRY_LEN
        test    byte ptr [srb+SRB_Flags], SRB_RESIDUAL
        jz      inquiry_header
        cmp     word ptr [srb+SRB_BufLen+2], 0
        jne     inquiry_bad
        sub     cx, word ptr [srb+SRB_BufLen]   ; bytes actually transferred
        jb      inquiry_bad
inquiry_header:
        cmp     cx, 5
        jb      inquiry_bad
        cmp     ah, byte ptr [inquiry_data]     ; qualifier 0, same type
        jne     inquiry_bad
        mov     al, byte ptr [inquiry_data+4]   ; additional length
        xor     ah, ah
        add     ax, 5
        cmp     ax, cx
        jae     inquiry_cut
        mov     cx, ax
inquiry_cut:
        mov     di, offset inquiry_data
        add     di, cx
inquiry_blank:
        cmp     cx, INQUIRY_LEN
        jae     inquiry_ascii
        xor     al, al
        cmp     cx, 8
        jb      inquiry_fill
        mov     al, ' '
inquiry_fill:
        mov     byte ptr [di], al
        inc     di
        inc     cx
        jmp     short inquiry_blank
inquiry_ascii:
        mov     di, offset inquiry_data+8
        mov     cx, INQUIRY_LEN-8
inquiry_ascii_next:
        cmp     byte ptr [di], ' '
        jb      inquiry_ascii_fix
        cmp     byte ptr [di], 7Eh
        jbe     inquiry_ascii_ok
inquiry_ascii_fix:
        mov     byte ptr [di], ' '
inquiry_ascii_ok:
        inc     di
        loop    inquiry_ascii_next
        clc
        ret
inquiry_bad:
        stc
        ret
inquiry_qualify endp
