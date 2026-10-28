; Shared native record validation plus synchronous READ execution (DS=CS).
; The wire count is always bytes; FIXED converts it to whole blocks only when
; building the CDB. Check packet/data bounds, segment wrap and linear overlap
; before submission, including aliases with different segment:offset pairs.
;
; A read submits once: no speculative READY, retry, synthetic legacy EOF or
; implicit repositioning. Trust residuals only when negotiated or justified by
; current sense, bounded by the request and aligned for fixed mode. Conflicting,
; deferred or transport-failed counts leave position/count uncertain.

native_read_start dd 0
native_read_end dd 0
native_packet_start dd 0
native_read_count dw 0
native_io_operation db 0
native_io_block dw 0
native_io_flags dw 0
native_io_units dw 0

; DX:AX = linear address of ES:DI, preserving BX/CX.
native_linear proc near
        mov ax,es
        xor dx,dx
        shl ax,1
        rcl dx,1
        shl ax,1
        rcl dx,1
        shl ax,1
        rcl dx,1
        shl ax,1
        rcl dx,1
        add ax,di
        adc dx,0
        ret
native_linear endp

; AL selects READ=0 or WRITE=1. Shared validation stages the 64-byte packet
; and derives byte count versus CDB units. Reject mismatched claim mode and
; packet/data linear overlap before either caller buffer can be modified.
native_record_prepare proc near
        mov byte ptr [native_io_operation],al
        mov cx,NR_SIZE
        call native_packet
        NT_JUMP jc,native_read_bad
        xor ax,ax
        mov al,byte ptr [native_io_operation]
        cmp word ptr es:[di+NC_OPERATION],ax
        NT_JUMP jne,native_read_bad
        mov ax,word ptr es:[di+NC_FLAGS]
        cmp ax,1
        NT_JUMP ja,native_read_bad
        mov word ptr [native_io_flags],ax
        cmp word ptr es:[di+NR_BLOCK+2],0
        NT_JUMP jne,native_read_bad
        mov dx,word ptr es:[di+NR_BLOCK]
        mov word ptr [native_io_block],dx
        or ax,ax
        jz native_record_variable
        or dx,dx
        NT_JUMP jz,native_read_bad
        cmp word ptr [tape_fixed_block],0
        je native_record_mode_ok
        cmp dx,word ptr [tape_fixed_block]
        NT_JUMP jne,native_read_bad
        jmp short native_record_mode_ok
native_record_variable:
        or dx,dx
        NT_JUMP jnz,native_read_bad
native_record_mode_ok:
        cmp word ptr es:[di+NR_REQUESTED+2],0
        NT_JUMP jne,native_read_bad
        mov cx,word ptr es:[di+NR_REQUESTED]
        NT_JUMP jcxz,native_read_bad
        mov word ptr [native_read_count],cx
        mov ax,cx
        cmp word ptr [native_io_block],0
        je native_record_units_ready
        xor dx,dx
        div word ptr [native_io_block]
        or dx,dx
        NT_JUMP jnz,native_read_bad
native_record_units_ready:
        mov word ptr [native_io_units],ax
        cmp byte ptr [native_io_operation],1
        jne native_record_claim_ok
        test byte ptr [native_write_state],1
        jz native_record_claim_ok
        mov ax,word ptr [native_io_block]
        cmp ax,word ptr [native_writer_block]
        NT_JUMP jne,native_read_bad
native_record_claim_ok:
        call native_linear
        mov word ptr [native_packet_start],ax
        mov word ptr [native_packet_start+2],dx
        les di,dword ptr es:[di+NR_OFFSET]
        mov ax,es
        or ax,di
        jz native_read_bad
        mov ax,cx
        dec ax
        add ax,di
        jc native_read_bad
        call native_linear
        mov word ptr [native_read_start],ax
        mov word ptr [native_read_start+2],dx
        add ax,cx
        adc dx,0
        ; Exclusive end may equal 100000h, but may not exceed it.
        cmp dx,10h
        ja native_read_bad
        jb native_read_range
        or ax,ax
        jnz native_read_bad
native_read_range:
        mov word ptr [native_read_end],ax
        mov word ptr [native_read_end+2],dx
        ; Reject physical overlap even when different far pointers alias it.
        cmp dx,word ptr [native_packet_start+2]
        jb native_read_valid
        ja native_read_overlap_start
        cmp ax,word ptr [native_packet_start]
        jbe native_read_valid
native_read_overlap_start:
        mov ax,word ptr [native_packet_start]
        mov dx,word ptr [native_packet_start+2]
        add ax,NR_SIZE
        adc dx,0
        cmp word ptr [native_read_start+2],dx
        ja native_read_valid
        jb native_read_bad
        cmp word ptr [native_read_start],ax
        jae native_read_valid
native_read_bad:
        stc
        ret
native_read_valid:
        push cs
        pop es
        mov di,offset native_info
        mov cx,NR_SIZE
        xor al,al
        rep stosb
        les si,dword ptr [native_argument]
        mov ax,word ptr es:[si+NR_OFFSET]
        mov word ptr [native_info+NR_OFFSET],ax
        mov ax,word ptr es:[si+NR_SEGMENT]
        mov word ptr [native_info+NR_SEGMENT],ax
        mov ax,word ptr [native_read_count]
        mov word ptr [native_info+NR_REQUESTED],ax
        mov word ptr [native_info],544Fh
        mov word ptr [native_info+2],5041h
        mov word ptr [native_info+4],NR_SIZE
        mov word ptr [native_info+6],NT_VERSION
        xor ax,ax
        mov al,byte ptr [native_io_operation]
        mov word ptr [native_info+NC_OPERATION],ax
        mov ax,word ptr [native_io_flags]
        mov word ptr [native_info+NC_FLAGS],ax
        mov ax,word ptr [native_io_block]
        mov word ptr [native_info+NR_BLOCK],ax
        call native_session_state
        mov word ptr [native_info+NC_SESSION],ax
        clc
        ret
native_record_prepare endp

; READ entry: AL=0 selects shared packet preparation. Require one raw
; no-rewind handle, no busy session/cache and no queued legacy EOF before any
; CDB. Reject incompatible variable requests as UNSUPPORTED, not as a successful
; zero read. A benign stream result still needs current sense and a proven count.
native_tape_read proc near
        xor al,al
        call native_record_prepare
        jnc native_read_header_ok
        stc
        ret
native_read_header_ok:
        or ax,ax
        NT_JUMP jnz,native_read_busy
        cmp byte ptr [tape_open_count],1
        NT_JUMP jne,native_read_busy
        cmp byte ptr [request_rewind],0
        NT_JUMP jne,native_read_busy
        cmp byte ptr [request_buffered],0
        NT_JUMP jne,native_read_busy
        cmp word ptr [buffer_count],0
        NT_JUMP jne,native_read_busy
        test byte ptr [device_state],MT_STATE_EOF_NEXT
        NT_JUMP jnz,native_read_busy
        cmp word ptr [native_io_block],0
        jne native_read_submit
        cmp word ptr [tape_fixed_block],0
        je native_read_submit
        mov word ptr [native_info+NC_RESULT],4
        mov word ptr [native_info+NC_DIAG],4
        jmp native_read_output
native_read_busy:
        mov word ptr [native_info+NC_RESULT],2
        jmp native_read_output
native_read_submit:
        call prepare_control_srb
        mov byte ptr [srb+SRB_CDB],SCSI_READ
        mov byte ptr [srb+SRB_Flags],SRB_DIR_IN
        test word ptr [adapter_ext_flags],HA_EXT_RESIDUAL
        jz native_read_flags
        or byte ptr [srb+SRB_Flags],SRB_RESIDUAL
native_read_flags:
        mov ax,word ptr [native_read_count]
        mov word ptr [srb+SRB_BufLen],ax
        cmp word ptr [native_io_block],0
        je native_read_variable_cdb
        mov byte ptr [srb+SRB_CDB+1],1
native_read_variable_cdb:
        mov ax,word ptr [native_io_units]
        mov byte ptr [srb+SRB_CDB+3],ah
        mov byte ptr [srb+SRB_CDB+4],al
        mov ax,word ptr [native_info+NR_OFFSET]
        mov word ptr [srb+SRB_BufPointer],ax
        mov ax,word ptr [native_info+NR_SEGMENT]
        mov word ptr [srb+SRB_BufPointer+2],ax
        mov byte ptr [native_info+NC_OPCODE],SCSI_READ
        mov word ptr [native_info+NC_COMPLETION],1
        mov byte ptr [driver_error],0
        mov ax,word ptr [native_read_count]
        mov word ptr [residual_bytes],ax
        mov al,SCSI_READ
        mov ah,byte ptr [srb+SRB_Flags]
        mov word ptr [last_scsi_opcode],ax
        call call_aspi
        mov al,byte ptr [srb+SRB_TargStat]
        mov byte ptr [last_scsi_status],al
        call remember_sense_key
        call check_tape_completion
        jc native_read_failed
        xor ax,ax
        test byte ptr [srb+SRB_Flags],SRB_RESIDUAL
        jz native_read_success_count
        call native_record_residual
        NT_JUMP jc,native_read_malformed
native_read_success_count:
        call native_record_count
        jmp native_read_complete
native_read_failed:
        mov word ptr [native_info+NC_RESULT],3
        mov word ptr [native_info+NC_COMPLETION],5
        call native_classify_error
        xor ah,ah
        mov word ptr [native_info+NC_DIAG],ax
        call native_record_diagnostics
        call check_stream_completion
        NT_JUMP jc,native_read_output
        ; Only current target sense can qualify transfer counts/stream flags.
        test byte ptr [srb+SRB_Flags],SRB_RESIDUAL
        jz native_read_sense_count
        call native_record_residual
        NT_JUMP jc,native_read_malformed
        call native_record_count
        jmp short native_read_stream
native_read_sense_count:
        call native_record_sense_residual
        jc native_read_stream
        call native_record_count
native_read_stream:
        cmp word ptr [native_io_block],0
        je native_read_stream_flags
        cmp byte ptr [sense_info_valid],0
        je native_read_stream_flags
        call native_record_sense_residual
        NT_JUMP jc,native_read_malformed
        test word ptr [native_info+NC_COMPLETION],20h
        jz native_read_stream_flags
        cmp ax,word ptr [residual_bytes]
        NT_JUMP jne,native_read_malformed
native_read_stream_flags:
        xor ax,ax
        ; SCSI's mark bit covers both filemarks and setmarks. Only bounded,
        ; current target sense reaches here; ASC/ASCQ 00/03 selects SETMARK.
        ; A missing mandatory mark bit is contradictory, not an ordinary EOF.
        cmp byte ptr [sense_asc_valid],0
        je native_read_filemark_bit
        cmp byte ptr [sense_asc],0
        jne native_read_filemark_bit
        cmp byte ptr [sense_ascq],3
        jne native_read_filemark_bit
        test byte ptr [sense_flags],SENSE_FILEMARK
        NT_JUMP jz,native_read_malformed
        cmp byte ptr [sense_info_valid],0
        je native_read_setmark_flag
        call native_record_sense_residual
        NT_JUMP jc,native_read_malformed
        test word ptr [native_info+NC_COMPLETION],20h
        jz native_read_setmark_flag
        cmp ax,word ptr [residual_bytes]
        NT_JUMP jne,native_read_malformed
native_read_setmark_flag:
        xor ax,ax
        or al,40h
        jmp short native_read_no_filemark
native_read_filemark_bit:
        test byte ptr [sense_flags],SENSE_FILEMARK
        jz native_read_no_filemark
        or al,1
native_read_no_filemark:
        test byte ptr [sense_flags],SENSE_EOM
        jz native_read_no_eom
        or al,2
native_read_no_eom:
        test byte ptr [sense_flags],SENSE_ILI
        jz native_read_no_ili
        or al,4
native_read_no_ili:
        or word ptr [native_info+NR_STREAM],ax
        cmp byte ptr [last_sense_key],1
        jbe native_read_benign
        ; BLANK CHECK / end-of-data is distinct from filemark and EOM.
        cmp byte ptr [last_sense_key],8
        NT_JUMP jne,native_read_output
        cmp byte ptr [sense_asc_valid],0
        NT_JUMP je,native_read_output
        cmp byte ptr [sense_asc],0
        NT_JUMP jne,native_read_output
        cmp byte ptr [sense_ascq],5
        NT_JUMP jne,native_read_output
        or ax,ax
        NT_JUMP jnz,native_read_output
        cmp word ptr [native_info+NR_ACTUAL],0
        NT_JUMP jne,native_read_output
        or word ptr [native_info+NR_STREAM],20h
        jmp short native_read_benign_count
native_read_benign:
        or ax,ax
        NT_JUMP jz,native_read_output
        test al,4
        jz native_read_benign_count
        cmp word ptr [native_io_block],0
        NT_JUMP jne,native_read_output
        cmp byte ptr [sense_info_valid],0
        NT_JUMP je,native_read_malformed
        test word ptr [sense_info_high],8000h
        jz native_read_positive_ili
        or word ptr [native_info+NR_STREAM],10h ; record larger than buffer
        jmp native_read_output
native_read_positive_ili:
        cmp word ptr [sense_info_high],0
        NT_JUMP jne,native_read_malformed
        mov ax,word ptr [sense_info_low]
        cmp ax,word ptr [native_read_count]
        NT_JUMP ja,native_read_malformed
        test word ptr [native_info+NC_COMPLETION],20h
        jz native_read_benign_count
        cmp ax,word ptr [residual_bytes]
        NT_JUMP jne,native_read_malformed
native_read_benign_count:
        test word ptr [native_info+NC_COMPLETION],20h
        jz native_read_output
        mov word ptr [native_info+NC_RESULT],5
native_read_complete:
        and word ptr [native_info+NC_COMPLETION],not 4
        or word ptr [native_info+NC_COMPLETION],2
        or byte ptr [device_state],MT_STATE_READ
        jmp short native_read_output
native_read_malformed:
        mov word ptr [native_info+NC_RESULT],3
        mov word ptr [native_info+NC_DIAG],3
        mov word ptr [native_info+NC_COMPLETION],5
        mov word ptr [native_info+NR_ACTUAL],0
        mov word ptr [native_info+NR_STREAM],0
        mov ax,word ptr [native_read_count]
        mov word ptr [residual_bytes],ax
native_read_output:
        cmp word ptr [native_info+NC_RESULT],3
        jne native_read_copy
        call record_driver_error
native_read_copy:
        les di,dword ptr [native_argument]
        mov si,offset native_info
        mov cx,NR_SIZE
        rep movsb
        clc
        ret
native_tape_read endp

; AX=requested-minus-actual. Only negotiated, bounded residuals qualify.
native_record_residual proc near
        cmp word ptr [srb+SRB_BufLen+2],0
        jne native_record_invalid
        mov ax,word ptr [srb+SRB_BufLen]
        cmp ax,word ptr [native_read_count]
        ja native_record_invalid
        cmp word ptr [native_io_block],0
        je native_record_residual_ok
        push ax
        xor dx,dx
        div word ptr [native_io_block]
        pop ax
        or dx,dx
        jnz native_record_invalid
native_record_residual_ok:
        clc
        ret
native_record_invalid:
        stc
        ret
native_record_residual endp
; AX is an already validated residual in BYTES. Publish requested-residual,
; COUNT_VALID (20h), and SHORT (08h) only after residual provenance/range checks;
; a stored zero without COUNT_VALID must continue to mean unknown.
native_record_count proc near
        mov word ptr [residual_bytes],ax
        mov dx,word ptr [native_read_count]
        sub dx,ax
        mov word ptr [native_info+NR_ACTUAL],dx
        or word ptr [native_info+NC_COMPLETION],20h
        or ax,ax
        jz native_record_count_done
        or word ptr [native_info+NR_STREAM],8
native_record_count_done:
        ret
native_record_count endp
; Copy already decoded diagnostics into the shared CONTROL/record prefix.
; This does not validate sense or establish count/position: callers classify
; completion first, then publish the separate completion and stream facts.
; AX is scratch; DS=CS and native_info is the resident output staging packet.
native_record_diagnostics proc near
        mov al,byte ptr [srb+SRB_HaStat]
        mov byte ptr [native_info+NC_HOST],al
        mov al,byte ptr [srb+SRB_TargStat]
        mov byte ptr [native_info+NC_TARGET],al
        mov al,byte ptr [last_sense_key]
        mov byte ptr [native_info+NC_KEY],al
        mov al,byte ptr [sense_response]
        mov byte ptr [native_info+NC_RESPONSE],al
        mov al,byte ptr [sense_asc]
        mov byte ptr [native_info+NC_ASC],al
        mov al,byte ptr [sense_ascq]
        mov byte ptr [native_info+NC_ASCQ],al
        ret
native_record_diagnostics endp

; Current sequential-access sense INFORMATION is residual blocks in FIXED mode,
; residual bytes in variable mode. Bound the multiplication before publishing.
native_record_sense_residual proc near
        cmp byte ptr [sense_info_valid],0
        je native_sense_residual_bad
        cmp word ptr [sense_info_high],0
        jne native_sense_residual_bad
        mov ax,word ptr [sense_info_low]
        cmp word ptr [native_io_block],0
        je native_sense_residual_range
        mul word ptr [native_io_block]
        or dx,dx
        jnz native_sense_residual_bad
native_sense_residual_range:
        cmp ax,word ptr [native_read_count]
        ja native_sense_residual_bad
        clc
        ret
native_sense_residual_bad:
        stc
        ret
native_record_sense_residual endp
