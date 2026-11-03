; This is device ownership classification, not firmware-quirk detection.
; ASPIDSK and ASPIFDD must make the same choice to avoid claiming one device
; twice. Match only the checked vendor/product bytes and the removable bit;
; a product-name match does not imply support for optional media commands.

; Shared ASPIDSK/ASPIFDD/ASPISCAN ownership policy. Caller has already checked
; peripheral type 00h and a successful 36-byte INQUIRY in inquiry_data.
; CF clear: removable bit plus known vendor/product substring -> ASPIFDD.
; CF set: ASPIDSK. Preserve all registers. Never match revision/outside bytes.
is_fdd_model proc near
        test    byte ptr [inquiry_data+1], 80h
        jz      fdd_not_removable
        push    si
        mov     si, offset fdd_models
        call    inquiry_has_model
        pop     si
        ret
fdd_not_removable:
        stc
        ret
is_fdd_model endp

; Does the INQUIRY vendor/product (inquiry_data+8, 24 bytes, any case)
; contain one of the names at SI (each 0-terminated, the list ends with an
; empty name)? CF clear if so. Preserves all registers.
inquiry_has_model proc near
        push    ax
        push    cx
        push    si
        push    di
fdd_next_model:
        cmp     byte ptr [si], 0
        je      fdd_no
        mov     di, offset inquiry_data+8
        mov     cx, 24
fdd_try_at:
        push    si
        push    di
        push    cx
fdd_compare:
        lodsb
        or      al, al
        jz      fdd_match
        jcxz    fdd_mismatch
        mov     ah, byte ptr [di]
        cmp     ah, 'a'
        jb      fdd_upper
        cmp     ah, 'z'
        ja      fdd_upper
        sub     ah, 20h
fdd_upper:
        inc     di
        dec     cx
        cmp     al, ah
        je      fdd_compare
fdd_mismatch:
        pop     cx
        pop     di
        pop     si
        inc     di
        loop    fdd_try_at
fdd_skip_model:
        lodsb
        or      al, al
        jnz     fdd_skip_model
        jmp     fdd_next_model
fdd_match:
        pop     cx
        pop     di
        pop     si
        clc
        jmp     short fdd_done
fdd_no:
        stc
fdd_done:
        pop     di
        pop     si
        pop     cx
        pop     ax
        ret
inquiry_has_model endp

fdd_models:
        db      'ZIP', 0, 'LS-120', 0, 'LS-240', 0, 'CLIK', 0
        db      'SUPERDISK', 0, 'JAZ', 0, 'SYQUEST', 0, 'EZ135', 0
        db      'EZFLYER', 0, 'SYJET', 0, 'SPARQ', 0, 0
