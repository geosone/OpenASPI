; Native writer state machine, separate from legacy character-device writes.
; BEGIN claims a compatible existing mode; it does not issue MODE SELECT.
; FLUSH/END write zero filemarks, FILEMARK/SETMARK write one selected mark; END
; releases only after success. ABORT releases ownership without I/O, flush,
; rollback or any promise that an uncertain tape position has been recovered.
;
; Private active/dirty/failed bits map to public native session bits. Mark dirty
; before submitting WRITE or a mark; never resubmit a possibly completed write. A proven
; short clean completion is INCOMPLETE, while failures latch the claim until
; explicit recovery. Legacy close must not append its automatic filemarks.

native_write_control proc near
        cmp byte ptr [tape_open_count],1
        NT_JUMP jne,native_wcontrol_busy
        cmp byte ptr [request_rewind],0
        NT_JUMP jne,native_wcontrol_busy
        cmp byte ptr [request_buffered],0
        NT_JUMP jne,native_wcontrol_busy
        cmp word ptr [buffer_count],0
        NT_JUMP jne,native_wcontrol_busy
        cmp word ptr [native_info+NC_OPERATION],2
        jne native_wcontrol_owned
        or ax,ax                       ; BEGIN: no legacy or native state
        NT_JUMP jnz,native_wcontrol_busy
        test byte ptr [device_state],MT_STATE_EOF_NEXT
        NT_JUMP jnz,native_wcontrol_busy
        cmp word ptr [native_info+NC_FLAGS],1
        je native_wcontrol_begin
        cmp word ptr [tape_fixed_block],0
        je native_wcontrol_begin
        mov word ptr [native_info+NC_RESULT],4
        mov word ptr [native_info+NC_DIAG],4
        jmp native_wcontrol_output
native_wcontrol_begin:
        mov ax,word ptr [native_info+NC_BLOCK]
        mov word ptr [native_writer_block],ax
        mov byte ptr [native_write_state],1
        mov word ptr [native_info+NC_COMPLETION],42h ; done, claimed; no CDB
        jmp native_wcontrol_output
native_wcontrol_owned:
        test byte ptr [native_write_state],1
        NT_JUMP jz,native_wcontrol_busy
        cmp word ptr [native_info+NC_OPERATION],6
        je native_wcontrol_abort
        test al,0Fh                     ; legacy state must still be clear
        NT_JUMP jnz,native_wcontrol_busy
        test byte ptr [native_write_state],4
        NT_JUMP jnz,native_wcontrol_busy
        cmp byte ptr [media_attention],0 ; ABORT above still releases
        NT_JUMP jne,native_wcontrol_busy
        call prepare_control_srb
        mov byte ptr [srb+SRB_CDB],SCSI_WRITE_FILEMARKS
        cmp word ptr [native_info+NC_OPERATION],17
        jne native_wcontrol_filemark
        mov byte ptr [srb+SRB_CDB+1],2 ; WSMK=1, IMMED=0
        jmp short native_wcontrol_one_mark
native_wcontrol_filemark:
        cmp word ptr [native_info+NC_OPERATION],4
        jne native_wcontrol_submit
native_wcontrol_one_mark:
        mov byte ptr [srb+SRB_CDB+4],1  ; exactly one explicitly selected mark
        or byte ptr [native_write_state],2
native_wcontrol_submit:
        ; FLUSH and END use count zero, IMMED=0: no filemarks are appended.
        mov byte ptr [native_info+NC_OPCODE],SCSI_WRITE_FILEMARKS
        mov word ptr [native_info+NC_COMPLETION],1
        call execute_control_srb
        jc native_wcontrol_failed
        or word ptr [native_info+NC_COMPLETION],2
        cmp word ptr [native_info+NC_OPERATION],5
        jne native_wcontrol_output
        mov byte ptr [native_write_state],0
        or word ptr [native_info+NC_COMPLETION],80h
        jmp short native_wcontrol_output
native_wcontrol_abort:
        and byte ptr [native_write_state],not 1
        cmp byte ptr [native_write_state],0
        je native_wcontrol_aborted
        or byte ptr [native_write_state],4 ; dirty/failed remains uncertain
native_wcontrol_aborted:
        mov word ptr [native_info+NC_COMPLETION],82h
        jmp short native_wcontrol_output
native_wcontrol_failed:
        or byte ptr [native_write_state],4
        mov word ptr [native_info+NC_RESULT],3
        mov word ptr [native_info+NC_COMPLETION],5
        call native_classify_error
        xor ah,ah
        mov word ptr [native_info+NC_DIAG],ax
        call native_record_diagnostics
        call record_driver_error
        jmp short native_wcontrol_output
native_wcontrol_busy:
        mov word ptr [native_info+NC_RESULT],2
native_wcontrol_output:
        call native_session_state
        mov word ptr [native_info+NC_SESSION],ax
        les di,dword ptr [native_argument]
        mov si,offset native_info
        mov cx,NC_SIZE
        rep movsb
        clc
        ret
native_write_control endp

; WRITE entry: AL=1 selects shared packet validation, then require the active
; compatible writer claim and exclusive raw no-rewind handle. The claim's mode
; must match each record. Packet acceptance is separate from submission; after
; submission any short/uncertain write fails without replay and retains state.
native_tape_write proc near
        mov al,1
        call native_record_prepare
        jnc native_write_header_ok
        stc
        ret
native_write_header_ok:
        test al,4Fh                     ; legacy state or FAILED/UNIT ATTENTION
        NT_JUMP jnz,native_write_busy
        cmp byte ptr [native_write_state],1
        je native_write_owner
        cmp byte ptr [native_write_state],3 ; active, already dirty
        NT_JUMP jne,native_write_busy
native_write_owner:
        cmp byte ptr [tape_open_count],1
        NT_JUMP jne,native_write_busy
        cmp byte ptr [request_rewind],0
        NT_JUMP jne,native_write_busy
        cmp byte ptr [request_buffered],0
        NT_JUMP jne,native_write_busy
        cmp word ptr [buffer_count],0
        NT_JUMP jne,native_write_busy
        cmp word ptr [native_io_block],0
        jne native_write_submit
        cmp word ptr [tape_fixed_block],0
        je native_write_submit
        mov word ptr [native_info+NC_RESULT],4
        mov word ptr [native_info+NC_DIAG],4
        jmp native_write_output
native_write_busy:
        mov word ptr [native_info+NC_RESULT],2
        jmp native_write_output
; From this point a WRITE may reach media. Mark the session dirty before
; submission and never automatically repeat it, even if completion is uncertain.
; A retry at the next tape position could duplicate or corrupt archive records.
native_write_submit:
        call prepare_control_srb
        mov byte ptr [srb+SRB_CDB],SCSI_WRITE
        mov byte ptr [srb+SRB_Flags],SRB_DIR_OUT
        test word ptr [adapter_ext_flags],HA_EXT_RESIDUAL
        jz native_write_flags
        or byte ptr [srb+SRB_Flags],SRB_RESIDUAL
native_write_flags:
        mov ax,word ptr [native_read_count]
        mov word ptr [srb+SRB_BufLen],ax
        cmp word ptr [native_io_block],0
        je native_write_variable_cdb
        mov byte ptr [srb+SRB_CDB+1],1
native_write_variable_cdb:
        mov ax,word ptr [native_io_units]
        mov byte ptr [srb+SRB_CDB+3],ah
        mov byte ptr [srb+SRB_CDB+4],al
        mov ax,word ptr [native_info+NR_OFFSET]
        mov word ptr [srb+SRB_BufPointer],ax
        mov ax,word ptr [native_info+NR_SEGMENT]
        mov word ptr [srb+SRB_BufPointer+2],ax
        mov byte ptr [native_info+NC_OPCODE],SCSI_WRITE
        mov word ptr [native_info+NC_COMPLETION],1
        or byte ptr [native_write_state],2 ; submission may have changed media
        mov byte ptr [driver_error],0
        mov ax,word ptr [native_read_count]
        mov word ptr [residual_bytes],ax
        mov al,SCSI_WRITE
        mov ah,byte ptr [srb+SRB_Flags]
        mov word ptr [last_scsi_opcode],ax
        call call_aspi
        mov al,byte ptr [srb+SRB_TargStat]
        mov byte ptr [last_scsi_status],al
        call remember_sense_key
        call check_tape_completion
        jc native_write_failed
        xor ax,ax
        test byte ptr [srb+SRB_Flags],SRB_RESIDUAL
        jz native_write_success_count
        call native_record_residual
        NT_JUMP jc,native_write_malformed
native_write_success_count:
        call native_record_count
        or ax,ax
        jnz native_write_short
        or word ptr [native_info+NC_COMPLETION],2
        jmp native_write_output
native_write_short:
        mov word ptr [native_info+NC_DIAG],5 ; valid partial count, incomplete
        jmp short native_write_error
native_write_failed:
        call native_classify_error
        xor ah,ah
        mov word ptr [native_info+NC_DIAG],ax
        call native_record_diagnostics
        call check_stream_completion
        jc native_write_error
        ; Never interpret stale/deferred sense as this record's EOM/count.
        test byte ptr [srb+SRB_Flags],SRB_RESIDUAL
        jz native_write_eom
        call native_record_residual
        jc native_write_malformed
        call native_record_count
native_write_eom:
        test byte ptr [sense_flags],SENSE_EOM
        jz native_write_error
        or word ptr [native_info+NR_STREAM],2
        jmp short native_write_error
native_write_malformed:
        mov word ptr [native_info+NC_DIAG],3
        mov word ptr [native_info+NR_ACTUAL],0
        mov word ptr [native_info+NR_STREAM],0
        mov word ptr [native_info+NC_COMPLETION],1
        mov ax,word ptr [native_read_count]
        mov word ptr [residual_bytes],ax
native_write_error:
        mov word ptr [native_info+NC_RESULT],3
        or word ptr [native_info+NC_COMPLETION],4
        or byte ptr [native_write_state],4
        call record_driver_error
native_write_output:
        call native_session_state
        mov word ptr [native_info+NC_SESSION],ax
        les di,dword ptr [native_argument]
        mov si,offset native_info
        mov cx,NR_SIZE
        rep movsb
        clc
        ret
native_tape_write endp
