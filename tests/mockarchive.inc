; Memory-only archive medium: records persist across DOS opens and REWIND.
; Resident pool stays within this tiny driver's segment; no host devices.
AM_JUMP macro condition,target
        local yes,no
        condition yes
        jmp short no
yes:
        jmp target
no:
endm
archive_records dw 0
archive_used dw 0
archive_cursor dw 0
archive_offset dw 0
archive_amount dw 0
archive_sense_flags db 0
ifdef NATIVE_ARCHIVE_FIXED
archive_progress dw 0
archive_request dw 0
endif
archive_lengths dw 64 dup (0)

native_archive_bad proc near
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        stc
        ret
native_archive_bad endp
native_archive_header proc near
        cmp byte ptr es:[bx+SRB_CDBLen],6
        jne archive_header_bad
ifdef NATIVE_ARCHIVE_FIXED
        cmp byte ptr es:[bx+SRB_CDB+1],1
else
        cmp byte ptr es:[bx+SRB_CDB+1],0
endif
        jne archive_header_bad
        cmp byte ptr es:[bx+SRB_CDB+2],0
        jne archive_header_bad
        cmp byte ptr es:[bx+SRB_CDB+5],0
        jne archive_header_bad
        cmp word ptr es:[bx+SRB_BufLen+2],0
        jne archive_header_bad
        mov ax,word ptr es:[bx+SRB_BufLen]
        or ax,ax
        jz archive_header_bad
        cmp ax,32768
        ja archive_header_bad
        mov dh,byte ptr es:[bx+SRB_CDB+3]
        mov dl,byte ptr es:[bx+SRB_CDB+4]
ifdef NATIVE_ARCHIVE_FIXED
        mov cx,ax                       ; buffer bytes versus CDB blocks
        mov ax,dx
        mov dx,NATIVE_ARCHIVE_FIXED
        mul dx
        or dx,dx
        jne archive_header_bad
        cmp ax,cx
        jne archive_header_bad
        mov ax,cx
else
        cmp ax,dx
        jne archive_header_bad
endif
        clc
        ret
archive_header_bad:
        stc
        ret
native_archive_header endp
native_archive_write proc near
        call native_archive_header
        AM_JUMP jc,native_archive_bad
ifdef NO_RESIDUAL
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_OUT
else
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_OUT or SRB_RESIDUAL
endif
        AM_JUMP jne,native_archive_bad
        mov dx,word ptr cs:[archive_cursor]
        cmp dx,word ptr cs:[archive_records]
        AM_JUMP jne,native_archive_bad
        cmp dx,63
        AM_JUMP jae,native_archive_bad
        inc word ptr cs:[native_writes]
ifdef ARCHIVE_WRITE_SHORT
        cmp word ptr cs:[native_writes],1
        jne archive_write_full
ifdef NATIVE_ARCHIVE_FIXED
        sub ax,NATIVE_ARCHIVE_FIXED
else
        dec ax
endif
archive_write_full:
endif
        mov word ptr cs:[archive_amount],ax
        add ax,word ptr cs:[archive_used]
        AM_JUMP jc,native_archive_bad
        cmp ax,49152
        AM_JUMP ja,native_archive_bad
        mov di,offset archive_media
        add di,word ptr cs:[archive_used]
        mov cx,word ptr cs:[archive_amount]
        push ds
        push es
        lds si,dword ptr es:[bx+SRB_BufPointer]
        push cs
        pop es
        rep movsb
        pop es
        pop ds
        mov di,word ptr cs:[archive_records]
        shl di,1
        mov ax,word ptr cs:[archive_amount]
        mov word ptr cs:[di+archive_lengths],ax
        add word ptr cs:[archive_used],ax
        inc word ptr cs:[archive_records]
        inc word ptr cs:[archive_cursor]
        mov ax,word ptr cs:[archive_used]
        mov word ptr cs:[archive_offset],ax
ifndef NO_RESIDUAL
        mov ax,word ptr es:[bx+SRB_BufLen]
        sub ax,word ptr cs:[archive_amount]
        mov word ptr es:[bx+SRB_BufLen],ax
endif
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        ret
native_archive_write endp
native_archive_mark proc near
        mov di,word ptr cs:[archive_records]
        cmp di,64
        AM_JUMP jae,native_archive_bad
        shl di,1
        mov word ptr cs:[di+archive_lengths],0FFFFh
        inc word ptr cs:[archive_records]
        inc word ptr cs:[archive_cursor]
        clc
        ret
native_archive_mark endp
native_archive_read proc near
        call native_archive_header
        AM_JUMP jc,native_archive_bad
ifdef NO_RESIDUAL
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN
else
        cmp byte ptr es:[bx+SRB_Flags],SRB_DIR_IN or SRB_RESIDUAL
endif
        AM_JUMP jne,native_archive_bad
ifdef NATIVE_ARCHIVE_FIXED
        jmp native_archive_read_fixed
endif
        mov di,word ptr cs:[archive_cursor]
        cmp di,word ptr cs:[archive_records]
        AM_JUMP jae,native_archive_bad
        shl di,1
        mov cx,word ptr cs:[di+archive_lengths]
        mov byte ptr cs:[archive_sense_flags],20h ; ordinary positive ILI
        cmp cx,0FFFFh
        je archive_read_mark
        cmp cx,ax
        AM_JUMP ja,native_archive_bad
        mov si,offset archive_media
        add si,word ptr cs:[archive_offset]
        add word ptr cs:[archive_offset],cx
        inc word ptr cs:[archive_cursor]
ifdef ARCHIVE_COMBINED_MARK
        mov di,word ptr cs:[archive_cursor]
        cmp di,word ptr cs:[archive_records]
        jae archive_read_no_combined
        shl di,1
        cmp word ptr cs:[di+archive_lengths],0FFFFh
        jne archive_read_no_combined
        or byte ptr cs:[archive_sense_flags],80h
        inc word ptr cs:[archive_cursor]
archive_read_no_combined:
endif
        call native_copy
ifdef ARCHIVE_CORRUPT
        push es
        les di,dword ptr es:[bx+SRB_BufPointer]
        xor byte ptr es:[di],1
        pop es
endif
ifdef ARCHIVE_READ_HARD
        mov byte ptr cs:[archive_sense_flags],3
endif
        jmp short archive_read_sense
archive_read_mark:
        inc word ptr cs:[archive_cursor]
        xor cx,cx
        mov si,offset archive_media
        call native_copy
        mov byte ptr cs:[archive_sense_flags],80h
ifdef ARCHIVE_EOM
        mov byte ptr cs:[archive_sense_flags],40h
endif
ifdef ARCHIVE_EOD
        mov byte ptr cs:[archive_sense_flags],8
        mov byte ptr es:[bx+TAPE_SENSE+13],5
endif
archive_read_sense::
ifdef NATIVE_ARCHIVE_FIXED
        cmp byte ptr cs:[archive_sense_flags],0
        je archive_read_done
endif
        ; Exact-length ordinary data completes cleanly; CHECK CONDITION is
        ; reserved for a length difference, stream condition or injected fault.
        cmp byte ptr cs:[archive_sense_flags],20h
        jne archive_read_check
        cmp word ptr cs:[native_length],0
        je archive_read_done
archive_read_check:
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+TAPE_SENSE],0F0h
        mov byte ptr es:[bx+TAPE_SENSE+7],6
        mov al,byte ptr cs:[archive_sense_flags]
        mov byte ptr es:[bx+TAPE_SENSE+2],al
        mov ax,word ptr cs:[native_length]
ifdef NATIVE_ARCHIVE_FIXED
        xor dx,dx
        mov cx,NATIVE_ARCHIVE_FIXED
        div cx                          ; sense residual blocks, ASPI bytes
endif
        mov byte ptr es:[bx+TAPE_SENSE+5],ah
        mov byte ptr es:[bx+TAPE_SENSE+6],al
archive_read_done:
        ret
native_archive_read endp
ifdef NATIVE_ARCHIVE_FIXED
; Fixed tape is a sequence of physical blocks, independent of write SRB chunks.
; Fill reads across stored chunks, retaining an intra-chunk cursor. Only marks
; delimit tape files; a short clean chunk is not a variable-record ILI.
native_archive_read_fixed proc near
        mov word ptr cs:[archive_request],ax
        mov word ptr cs:[archive_amount],0
        mov byte ptr cs:[archive_sense_flags],0
archive_fixed_fill:
        mov di,word ptr cs:[archive_cursor]
        cmp di,word ptr cs:[archive_records]
        AM_JUMP jae,native_archive_bad
        shl di,1
        mov dx,word ptr cs:[di+archive_lengths]
        cmp dx,0FFFFh
        je archive_fixed_mark
        sub dx,word ptr cs:[archive_progress]
        AM_JUMP jbe,native_archive_bad
        mov ax,word ptr cs:[archive_request]
        sub ax,word ptr cs:[archive_amount]
        cmp ax,dx
        jbe archive_fixed_take
        mov ax,dx
archive_fixed_take:
        add word ptr cs:[archive_progress],ax
        add word ptr cs:[archive_amount],ax
        mov ax,word ptr cs:[archive_progress]
        cmp ax,word ptr cs:[di+archive_lengths]
        jne archive_fixed_more
        inc word ptr cs:[archive_cursor]
        mov word ptr cs:[archive_progress],0
archive_fixed_more:
        mov ax,word ptr cs:[archive_amount]
        cmp ax,word ptr cs:[archive_request]
        je archive_fixed_filled
        jmp archive_fixed_fill
archive_fixed_mark:
        inc word ptr cs:[archive_cursor]
        mov byte ptr cs:[archive_sense_flags],80h
        jmp short archive_fixed_copy
archive_fixed_filled:
ifdef ARCHIVE_COMBINED_MARK
        mov di,word ptr cs:[archive_cursor]
        cmp di,word ptr cs:[archive_records]
        jae archive_fixed_copy
        cmp word ptr cs:[archive_progress],0
        jne archive_fixed_copy
        shl di,1
        cmp word ptr cs:[di+archive_lengths],0FFFFh
        jne archive_fixed_copy
        inc word ptr cs:[archive_cursor]
        mov byte ptr cs:[archive_sense_flags],80h
endif
archive_fixed_copy:
        mov si,offset archive_media
        add si,word ptr cs:[archive_offset]
        mov cx,word ptr cs:[archive_amount]
        add word ptr cs:[archive_offset],cx
        call native_copy
ifdef ARCHIVE_CORRUPT
        push es
        les di,dword ptr es:[bx+SRB_BufPointer]
        xor byte ptr es:[di],1
        pop es
endif
ifdef ARCHIVE_PADDING_BAD
        ; The first OTB1 label is 144 bytes, followed by physical padding.
        cmp word ptr cs:[archive_offset],NATIVE_ARCHIVE_FIXED
        jne archive_fixed_padding_done
        push es
        les di,dword ptr es:[bx+SRB_BufPointer]
        mov byte ptr es:[di+144],1
        pop es
archive_fixed_padding_done:
endif
ifdef ARCHIVE_READ_HARD
        mov byte ptr cs:[archive_sense_flags],3
endif
ifdef ARCHIVE_EOM
        test byte ptr cs:[archive_sense_flags],80h
        jz archive_fixed_eom_done
        mov byte ptr cs:[archive_sense_flags],40h
archive_fixed_eom_done:
endif
ifdef ARCHIVE_EOD
        test byte ptr cs:[archive_sense_flags],80h
        jz archive_fixed_eod_done
        mov byte ptr cs:[archive_sense_flags],8
        mov byte ptr es:[bx+TAPE_SENSE+13],5
archive_fixed_eod_done:
endif
        jmp archive_read_sense
native_archive_read_fixed endp
endif
archive_media db 49152 dup (0)
