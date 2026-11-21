; Device lines of the INIT scan for ASPIDSK, ASPIFDD and ASPICDA, in the style
; of the SCSI vendors' ASPIDISK/ASPICD drivers. Transient, after aspi_init.inc:
;   Host Adapter #0  EUSBASPI  USB Mass Storage
;   HA 0:SCSI ID 0:Lun 1: VENDOR PRODUCT ...
; The longest fixed part ("HA 12:SCSI ID 31:Lun 7: " and 8 + 1 + 16 name
; characters) is 49 columns; what a driver adds must keep a line below 80.
; They need the driver's print_digit (AL, decimal) and msg_crlf.

msg_ha_title    db      'Host Adapter #$'
msg_addr_ha     db      'HA $'
msg_addr_id     db      ':SCSI ID $'
msg_addr_lun    db      ':Lun $'

; Title of scan_ha before its first line; once per adapter. Keeps all but AX.
print_ha_title proc near
        mov     al, byte ptr [scan_ha]
        cmp     al, byte ptr [title_ha]
        je      ha_title_done
        mov     byte ptr [title_ha], al
        push    dx
        push    si
        push    cx
        mov     dx, offset msg_ha_title
        mov     ah, 09h
        int     21h
        mov     al, byte ptr [scan_ha]
        call    print_digit
        mov     si, offset scan_ha_name
        call    print_two_blanks
        mov     cx, 16
        call    print_field
        add     si, 16
        call    print_two_blanks
        mov     cx, 16
        call    print_field
        mov     dx, offset msg_crlf
        mov     ah, 09h
        int     21h
        pop     cx
        pop     si
        pop     dx
ha_title_done:
        ret
print_ha_title endp

print_two_blanks proc near
        mov     dl, ' '
        mov     ah, 02h
        int     21h
        int     21h
        ret
print_two_blanks endp

; "HA h:SCSI ID t:Lun l:" of scan_*. Keeps all but AX and DX.
print_address proc near
        mov     dx, offset msg_addr_ha
        mov     ah, 09h
        int     21h
        mov     al, byte ptr [scan_ha]
        call    print_digit
        mov     dx, offset msg_addr_id
        mov     ah, 09h
        int     21h
        mov     al, byte ptr [scan_target]
        call    print_digit
        mov     dx, offset msg_addr_lun
        mov     ah, 09h
        int     21h
        mov     al, byte ptr [scan_lun]
        call    print_digit
        mov     dl, ':'
        mov     ah, 02h
        int     21h
        ret
print_address endp

; CX characters at SI without the trailing blanks; control characters print
; as blanks. Keeps all but AX and DX.
print_field proc near
        push    si
        push    cx
        push    bx
        mov     bx, cx
field_trim:
        or      bx, bx
        jz      field_done
        cmp     byte ptr [si+bx-1], ' '
        ja      field_print
        dec     bx
        jmp     short field_trim
field_print:
        mov     cx, bx
field_char:
        lodsb
        cmp     al, ' '
        jae     field_out
        mov     al, ' '
field_out:
        mov     dl, al
        mov     ah, 02h
        int     21h
        loop    field_char
field_done:
        pop     bx
        pop     cx
        pop     si
        ret
print_field endp

; Vendor (8) and product (16) at SI as "VENDOR PRODUCT". Keeps all but AX, DX.
print_vendor_product proc near
        push    cx
        mov     cx, 8
        call    print_field
        mov     dl, ' '
        mov     ah, 02h
        int     21h
        add     si, 8
        mov     cx, 16
        call    print_field
        sub     si, 8
        pop     cx
        ret
print_vendor_product endp

; The vendor and product of inquiry_data. Keeps all but AX and DX.
print_inquiry_name proc near
        push    si
        mov     si, offset inquiry_data+8
        call    print_vendor_product
        pop     si
        ret
print_inquiry_name endp
