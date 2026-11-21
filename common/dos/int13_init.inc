; ASPIDSK /I13 at INIT (transient): see int13.inc.

msg_i13         db      '  INT 13h $'
msg_i13_size    db      ' (not 512-byte sectors: no INT 13h drive)', 13, 10, '$'

; The device just found (unit record DI, unit_ha/target/lun): an INT 13h
; drive when /I13 is given and there is room.  Keeps DI.
i13_add proc near
        cmp     byte ptr [opt_i13], 0
        je      i13_add_done
        cmp     byte ptr [i13_count], I13_MAX
        jae     i13_add_done
        push    di
        mov     al, byte ptr [i13_count]
        mov     ah, I13_SIZE
        mul     ah
        add     ax, offset i13_table
        mov     si, ax
        mov     al, byte ptr [di+U_HA]
        mov     byte ptr [si+I13_HA], al
        mov     al, byte ptr [di+U_TARGET]
        mov     byte ptr [si+I13_TARGET], al
        mov     al, byte ptr [di+U_LUN]
        mov     byte ptr [si+I13_LUN], al
        mov     al, byte ptr [di+U_FLAGS]
        and     al, UF_REMOVABLE
        mov     byte ptr [si+I13_FLAGS], al
        call    i13_capacity
        mov     byte ptr [capacity_fresh], 0    ; load_volume reads it again
        jnc     i13_add_take
        ; no medium in a removable device: read when it is asked for
        test    byte ptr [si+I13_FLAGS], UF_REMOVABLE
        jz      i13_add_refused
        call    block_read_capacity             ; a medium of other sectors?
        mov     byte ptr [capacity_fresh], 0
        jc      i13_add_take
i13_add_refused:
        cmp     byte ptr [di+U_SHIFT], 0
        je      i13_add_out
        call    i13_print
        mov     dx, offset msg_i13_size
        mov     ah, 09h
        int     21h
        jmp     short i13_add_out
i13_add_take:
        call    i13_print
        mov     dx, offset msg_crlf
        mov     ah, 09h
        int     21h
        inc     byte ptr [i13_count]
i13_add_out:
        pop     di
        mov     byte ptr [di+U_SHIFT], 0
i13_add_done:
        ret
i13_add endp

; "  INT 13h 82h: HA h:SCSI ID t:Lun l: VENDOR PRODUCT" without the line end
i13_print proc near
        call    print_ha_title
        mov     dx, offset msg_i13
        mov     ah, 09h
        int     21h
        push    es
        mov     ax, 40h
        mov     es, ax
        mov     al, byte ptr es:[75h]
        pop     es
        add     al, 80h
        add     al, byte ptr [i13_count]
        push    ax
        mov     cl, 4
        shr     al, cl
        call    i13_hex_digit
        pop     ax
        call    i13_hex_digit
        mov     dl, 'h'
        int     21h
        mov     dl, ':'
        int     21h
        mov     dl, ' '
        int     21h
        call    print_address
        mov     dl, ' '
        mov     ah, 02h
        int     21h
        call    print_inquiry_name
        ret
i13_print endp

; AL low nibble as a hex digit; AH = 02h afterwards
i13_hex_digit proc near
        and     al, 0Fh
        add     al, '0'
        cmp     al, '9'
        jbe     i13_hex_out
        add     al, 'A' - '9' - 1
i13_hex_out:
        mov     dl, al
        mov     ah, 02h
        int     21h
        ret
i13_hex_digit endp

; The driver stays: the drives after the BIOS hard disks, INT 13h hooked.
i13_install proc near
        cmp     byte ptr [i13_count], 0
        je      i13_install_done
        push    es
        push    bx
        mov     ax, 40h
        mov     es, ax
        mov     al, byte ptr es:[75h]
        add     al, 80h
        mov     byte ptr [i13_base], al
        mov     al, byte ptr [i13_count]
        add     byte ptr es:[75h], al
        mov     ax, 3513h
        int     21h
        mov     word ptr [i13_old], bx
        mov     word ptr [i13_old+2], es
        mov     dx, offset i13_handler
        mov     ax, 2513h
        int     21h
        pop     bx
        pop     es
i13_install_done:
        ret
i13_install endp
