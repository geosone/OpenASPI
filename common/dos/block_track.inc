; Generic block track operations use zero-based sector numbers in CHS packets.
; READ/WRITE addresses are physical-device absolute, VERIFY volume-relative.
; Do not add the partition offset twice. Validate geometry, arithmetic overflow,
; track bounds, access/session ownership and far-buffer bounds before I/O.
; Shared scratch state and SRB require DS=CS and serialized driver requests.
; See docs/block-track.md for the DOS-facing packet contract.

; Generic IOCTL minors: WRITE=41h, READ=61h, VERIFY=62h.
track_packet db 13 dup (0)
track_argument dd 0
track_minor db 0
track_remaining dw 0
track_lba dd 0
track_buffer dd 0

; As in PB_CHECK, condition describes the accepted case, not failure.
; The short condition skips a near JMP on success; both paths stay 8086 code.
TR_CHECK macro condition, failure
        local okay
        condition okay
        jmp failure
okay:
endm

; Input: ES:BX request and unit_ptr, DS=CS. The parameter pointer is saved
; because ES:BP will also be used for other work. Copy only the packet prefix
; required by READ/WRITE, single-track VERIFY or multi-track VERIFY.
; CF/AL report the DOS result; VERIFY additionally has a defined result byte.
ioctl_track proc near
        mov al,byte ptr es:[bx+RH_IOCTL_MINOR]
        mov byte ptr [track_minor],al
        les bp,dword ptr es:[bx+RH_IOCTL_PARAM]
        mov word ptr [track_argument],bp
        mov word ptr [track_argument+2],es
        mov ax,es
        or ax,bp
        TR_CHECK jnz,track_bad_packet
        mov cx,13
        cmp byte ptr [track_minor],62h
        jne track_rw_packet
        cmp bp,0FFFBh                  ; single-track verify needs five bytes
        TR_CHECK jbe,track_bad_packet
        mov al,byte ptr es:[bp]
        test al,0FEh
        TR_CHECK jz,track_bad_packet
        mov cx,5
        test al,1
        jz track_copy_packet
        mov cx,7
        cmp bp,0FFF9h
        TR_CHECK jbe,track_bad_packet
        jmp short track_copy_packet
track_rw_packet:
        cmp bp,0FFF3h
        TR_CHECK jbe,track_bad_packet
        cmp byte ptr es:[bp],0
        TR_CHECK je,track_bad_packet
track_copy_packet:
        push ds
        push es
        pop ds
        push cs
        pop es
        mov si,bp
        mov di,offset track_packet
        rep movsb
        pop ds
        cmp byte ptr [track_minor],62h
        je track_verify_packet
        mov ax,word ptr [track_packet+7]
        mov word ptr [track_remaining],ax
        or ax,ax
        TR_CHECK jnz,track_complete     ; zero sectors: no command or buffer use
        ; Validate the entire contiguous real-mode buffer before any transfer.
        mov ax,word ptr [track_packet+11]
        mov cx,16
        mul cx
        add ax,word ptr [track_packet+9]
        adc dx,0
        mov bx,ax
        mov si,dx
        or ax,dx
        TR_CHECK jnz,track_bad_packet
        mov ax,word ptr [track_remaining]
        mov cx,512
        mul cx
        add ax,bx
        adc dx,si
        TR_CHECK jnc,track_bad_packet
        cmp dx,10h
        TR_CHECK jbe,track_bad_packet
        jb track_buffer_valid
        or ax,ax
        TR_CHECK jz,track_bad_packet
track_buffer_valid:
        ; Normalize so each <=32-KiB command remains inside a segment.
        mov ax,word ptr [track_packet+9]
        mov cl,4
        shr ax,cl
        add ax,word ptr [track_packet+11]
        TR_CHECK jnc,track_bad_packet
        mov word ptr [track_buffer+2],ax
        mov ax,word ptr [track_packet+9]
        and ax,0Fh
        mov word ptr [track_buffer],ax
        jmp short track_preflight
track_verify_packet:
        test byte ptr [track_packet],1
        jz track_preflight
        cmp word ptr [track_packet+5],0
        TR_CHECK jne,track_complete     ; zero tracks: no VERIFY(10) count zero
track_preflight:
        mov di,word ptr [unit_ptr]
        call block_read_capacity
        TR_CHECK jnc,track_device_failed
        mov al,byte ptr [di+U_FLAGS]
        and al,UF_MEDIA or UF_BPB_OVERRIDE
        cmp al,UF_MEDIA or UF_BPB_OVERRIDE
        je track_geometry
        test byte ptr [di+U_FLAGS],UF_REMOVABLE
        jnz track_refresh
        test byte ptr [di+U_FLAGS],UF_MEDIA
        jnz track_geometry
track_refresh:
        call load_volume
        TR_CHECK jnc,track_device_failed
track_geometry:
        cmp word ptr [di+U_BPB+BPB_BYTES],512
        TR_CHECK je,track_geometry_bad
        mov cx,word ptr [di+U_BPB+BPB_HEADS]
        or cx,cx
        TR_CHECK jnz,track_geometry_bad
        cmp cx,256
        TR_CHECK jbe,track_geometry_bad
        cmp word ptr [track_packet+1],cx
        TR_CHECK jb,track_range_bad
        mov bx,word ptr [di+U_BPB+BPB_SPT]
        or bx,bx
        TR_CHECK jnz,track_geometry_bad
        cmp bx,63
        TR_CHECK jbe,track_geometry_bad
        cmp byte ptr [track_minor],62h
        jne track_rw_sector
        mov ax,1
        test byte ptr [track_packet],1
        jz track_verify_count
        mov ax,word ptr [track_packet+5]
track_verify_count:
        mul bx
        or dx,dx
        TR_CHECK jz,track_range_bad
        cmp ax,255
        TR_CHECK jbe,track_range_bad
        mov word ptr [track_remaining],ax
        jmp short track_chs
track_rw_sector:
        cmp word ptr [track_packet+5],bx
        TR_CHECK jb,track_range_bad
track_chs:
; CHS multiplication is a 32-bit result assembled with 16-bit MULs. Preserve
; the high half of cylinder*heads+head and multiply both halves by sectors/track;
; reject carry beyond 32 bits rather than wrapping onto another part of media.
        ; (cylinder * heads + head) * sectors/track.
        mov ax,word ptr [track_packet+3]
        mul cx
        add ax,word ptr [track_packet+1]
        adc dx,0
        TR_CHECK jnc,track_range_bad
        mov si,dx
        mul bx
        mov cx,ax
        mov bp,dx
        mov ax,si
        mul bx
        or dx,dx
        TR_CHECK jz,track_range_bad
        add ax,bp
        TR_CHECK jnc,track_range_bad
        mov dx,ax
        mov ax,cx
        cmp byte ptr [track_minor],62h
        je track_sector_ready
        add ax,word ptr [track_packet+5]
        adc dx,0
        TR_CHECK jnc,track_range_bad
track_sector_ready:
        cmp byte ptr [track_minor],62h
        jne track_physical_lba
        ; VERIFY covers only this volume, then translates once to physical LBA.
        mov word ptr [track_lba],ax
        mov word ptr [track_lba+2],dx
        mov cx,word ptr [di+U_BPB+BPB_TOTAL16]
        xor si,si
        or cx,cx
        jnz track_volume_limit
        mov cx,word ptr [di+U_BPB+BPB_TOTAL32]
        mov si,word ptr [di+U_BPB+BPB_TOTAL32+2]
track_volume_limit:
        add ax,word ptr [track_remaining]
        adc dx,0
        TR_CHECK jnc,track_range_bad
        cmp dx,si
        TR_CHECK jbe,track_range_bad
        jb track_volume_valid
        cmp ax,cx
        TR_CHECK jbe,track_range_bad
track_volume_valid:
        mov ax,word ptr [track_lba]
        mov dx,word ptr [track_lba+2]
        add ax,word ptr [di+U_START]
        adc dx,word ptr [di+U_START+2]
        TR_CHECK jnc,track_range_bad
track_physical_lba:
        mov word ptr [track_lba],ax
        mov word ptr [track_lba+2],dx
        add ax,word ptr [track_remaining]
        adc dx,0
        TR_CHECK jnc,track_range_bad
        cmp dx,word ptr [di+U_CAPACITY+2]
        TR_CHECK jbe,track_range_bad
        jb track_transfer
        cmp ax,word ptr [di+U_CAPACITY]
        TR_CHECK jbe,track_range_bad
; The entire LBA span and any data buffer were checked before this loop.
; VERIFY uses BYTCHK=0 (no transfer buffer); READ/WRITE split into sector chunks.
; Only completed chunks advance the physical LBA and buffer segment. A WRITE
; invalidates cached media unless an explicit logical BPB override is active.
track_transfer:
        mov cx,word ptr [track_remaining]
        cmp cx,CHUNK_SECTORS
        jbe track_chunk_ready
        mov cx,CHUNK_SECTORS
track_chunk_ready:
        mov byte ptr [xfer_opcode],28h
        cmp byte ptr [track_minor],61h
        je track_chunk_buffer
        mov byte ptr [xfer_opcode],2Ah
        cmp byte ptr [track_minor],41h
        je track_chunk_buffer
        mov byte ptr [xfer_opcode],2Fh  ; VERIFY, BYTCHK=0, no buffer or payload
track_chunk_buffer:
        mov ax,word ptr [track_buffer]
        mov word ptr [xfer_buffer],ax
        mov ax,word ptr [track_buffer+2]
        mov word ptr [xfer_buffer+2],ax
        mov ax,word ptr [track_lba]
        mov dx,word ptr [track_lba+2]
        call xfer_sectors
        TR_CHECK jnc,track_device_failed
        cmp byte ptr [track_minor],41h
        jne track_chunk_done
        mov di,word ptr [unit_ptr]
        test byte ptr [di+U_FLAGS],UF_BPB_OVERRIDE
        jnz track_chunk_done
        and byte ptr [di+U_FLAGS],not UF_MEDIA
track_chunk_done:
        sub word ptr [track_remaining],cx
        jz track_complete
        add word ptr [track_lba],cx
        adc word ptr [track_lba+2],0
        mov ax,cx
        mov cl,5
        shl ax,cl
        add word ptr [track_buffer+2],ax
        jmp track_transfer
track_complete:
        cmp byte ptr [track_minor],62h
        jne track_success
        les bp,dword ptr [track_argument]
        mov byte ptr es:[bp],0
track_success:
        clc
        ret
track_bad_packet:
        mov al,ERR_UNKNOWN_CMD
        stc
        ret
track_geometry_bad:
        mov al,ERR_UNKNOWN_MEDIA
        mov ah,2
        call track_verify_result
        stc
        ret
track_range_bad:
        mov al,ERR_NOT_FOUND
        mov ah,2
        call track_verify_result
        stc
        ret
track_device_failed:
        cmp byte ptr [track_minor],62h
        jne track_invalidate
        cmp al,ERR_NOT_READY
        jne track_verify_opcode
        mov ah,3
        call track_verify_result
        jmp short track_invalidate
track_verify_opcode:
        ; Distinguish an unsupported VERIFY opcode from an invalid LBA or
        ; field. No read fallback or guessed success after ILLEGAL REQUEST.
        cmp byte ptr [srb+SRB_CDB],2Fh
        jne track_invalidate
        cmp byte ptr [srb+SRB_CDBLen],10
        jne track_invalidate
        push ax
        call aspi_sense
        cmp ax,2005h
        pop ax
        jne track_invalidate
        mov al,ERR_UNKNOWN_CMD
        mov ah,1
        call track_verify_result
; A failed device preflight/transfer makes cached media/override untrusted.
; This is distinct from malformed input, which returns without device access.
; For VERIFY, preserve the DOS carry/error even when a result byte is supplied.
track_invalidate:
        mov di,word ptr [unit_ptr]
        and byte ptr [di+U_FLAGS],not (UF_MEDIA or UF_BPB_OVERRIDE)
        stc
        ret
ioctl_track endp

; A valid VERIFY packet returns its defined capability/media result byte.
; Other errors keep the input byte; CF and DOS status remain authoritative.
track_verify_result proc near
        cmp byte ptr [track_minor],62h
        jne track_verify_result_done
        les bp,dword ptr [track_argument]
        mov byte ptr es:[bp],ah
track_verify_result_done:
        ret
track_verify_result endp
