; Completion qualification and bounded autosense parsing are separate steps.
; Only a checked target CHECK CONDITION with no host error supplies sense for
; this command. Fixed and descriptor responses have different layouts; valid
; information/count flags are independent of decoded key/ASC/stream flags.
; Consumers must still distinguish current from deferred sense before using
; information as this transfer's residual. See docs/aspi-sense.md.

; Resident ASPITAP sense decoder; included by the driver and DOS fixture.
; Execute-SCSI success must agree at all three completion layers.
; Preserves registers, CF clear only for a clean completion.
check_tape_completion proc near
        cmp     byte ptr [srb+SRB_Status], SS_COMP
        jne     tape_completion_failed
        cmp     byte ptr [srb+SRB_HaStat], 0
        jne     tape_completion_failed
        cmp     byte ptr [srb+SRB_TargStat], 0
        jne     tape_completion_failed
        clc
        ret
tape_completion_failed:
        stc
        ret
check_tape_completion endp

; Decode into resident sense_* / last_sense_key, clearing every field first.
; DS=CS; AX/BX/CX/SI are scratch, and carry is not a validity return. Consumers
; must inspect response/valid flags and qualify command completion separately.
; This tape path expects a six-byte CDB, so TAPE_SENSE is its fixed autosense offset.
remember_sense_key proc near
        mov     byte ptr [last_sense_key], 0
        mov     byte ptr [sense_response], 0
        mov     byte ptr [sense_asc_valid], 0
        mov     byte ptr [sense_asc], 0
        mov     byte ptr [sense_ascq], 0
        mov     byte ptr [sense_flags], 0
        mov     byte ptr [sense_info_valid], 0
        mov     word ptr [sense_info_high], 0
        mov     word ptr [sense_info_low], 0
        cmp     byte ptr [srb+SRB_Cmd], SC_EXEC_SCSI_CMD
        jne     tape_sense_invalid
        cmp     byte ptr [srb+SRB_Status], SS_ERR
        jne     tape_sense_invalid
        cmp     byte ptr [srb+SRB_HaStat], 0
        jne     tape_sense_invalid
        cmp     byte ptr [srb+SRB_TargStat], 2
        jne     tape_sense_invalid
        cmp     byte ptr [srb+SRB_CDBLen], 6
        jne     tape_sense_invalid
        cmp     byte ptr [srb+SRB_SenseLen], 8
        jb      tape_sense_invalid
        cmp     byte ptr [srb+SRB_SenseLen], 32
        jbe     tape_sense_header
tape_sense_invalid:
        ret
tape_sense_header:
        mov     al, byte ptr [srb+TAPE_SENSE+0]
        cmp     al, 72h
        je      descriptor_sense
        cmp     al, 73h
        je      descriptor_sense
        and     al, 7Fh
        cmp     al, 70h
        jne     sense_not_fixed_current
        jmp     fixed_sense
sense_not_fixed_current:
        cmp     al, 71h
        jne     sense_not_fixed_deferred
        jmp     fixed_sense
sense_not_fixed_deferred:
        jmp     sense_done
descriptor_sense:
        mov     byte ptr [sense_response], al
        mov     byte ptr [sense_asc_valid], 1
        mov     al, byte ptr [srb+TAPE_SENSE+2]
        mov     byte ptr [sense_asc], al
        mov     al, byte ptr [srb+TAPE_SENSE+3]
        mov     byte ptr [sense_ascq], al
        mov     al, byte ptr [srb+TAPE_SENSE+1]
        and     al, 0Fh
        mov     byte ptr [last_sense_key], al
        xor     cx, cx
        mov     cl, byte ptr [srb+TAPE_SENSE+7]
        xor     bx, bx
        mov     bl, byte ptr [srb+SRB_SenseLen]
        sub     bx, 8
        cmp     cx, bx
        jbe     descriptor_length_ready
        mov     cx, bx
; CX is bytes remaining, bounded by min(additional_length, allocation-8).
; Each iteration requires the two-byte descriptor header, then its entire body.
; A truncated/unknown optional descriptor must not turn zero-filled fields into
; valid residual/stream information. Unknown complete descriptors are skipped.
descriptor_length_ready:
        mov     si, offset srb+TAPE_SENSE+8
descriptor_loop:
        cmp     cx, 2
        jae     descriptor_header_ready
        jmp     sense_done
descriptor_header_ready:
        xor     bx, bx
        mov     bl, byte ptr [si+1]
        add     bx, 2
        cmp     bx, cx
        jbe     descriptor_size_ready
        jmp     sense_done
descriptor_size_ready:
        cmp     byte ptr [si], 0
        je      descriptor_information
        cmp     byte ptr [si], 4
        je      descriptor_stream
        jmp     short descriptor_next

; Information descriptor: require VALID and a complete 64-bit field. The
; resident result is only 32 bits, so nonzero upper four bytes are not truncated.
; The lower bytes are big-endian; build high/low WORDs explicitly. A valid field
; still needs current-command and units/range checks before use as a residual.
descriptor_information:
        cmp     byte ptr [si+1], 0Ah
        jb      descriptor_next
        test    byte ptr [si+2], 80h
        jz      descriptor_next
        cmp     word ptr [si+4], 0
        jne     descriptor_next
        cmp     word ptr [si+6], 0
        jne     descriptor_next
        mov     ah, byte ptr [si+8]
        mov     al, byte ptr [si+9]
        mov     word ptr [sense_info_high], ax
        mov     ah, byte ptr [si+10]
        mov     al, byte ptr [si+11]
        mov     word ptr [sense_info_low], ax
        mov     byte ptr [sense_info_valid], 1
        jmp     short descriptor_next

; Stream flags live in descriptor type 04h, not the sense-key byte used by
; fixed format. Merge only FILEMARK/EOM/ILI; none alone proves successful I/O.
; The caller evaluates coexistence of flags and any hard sense key.
descriptor_stream:
        cmp     byte ptr [si+1], 2
        jb      descriptor_next
        mov     al, byte ptr [si+3]
        and     al, SENSE_FILEMARK or SENSE_EOM or SENSE_ILI
        or      byte ptr [sense_flags], al

descriptor_next:
        add     si, bx
        sub     cx, bx
        jmp     descriptor_loop
fixed_sense:
        mov     byte ptr [sense_response], al
        cmp     byte ptr [srb+SRB_SenseLen], 14
        jb      fixed_sense_information
        cmp     byte ptr [srb+TAPE_SENSE+7], 6
        jb      fixed_sense_information
        mov     byte ptr [sense_asc_valid], 1
        mov     al, byte ptr [srb+TAPE_SENSE+12]
        mov     byte ptr [sense_asc], al
        mov     al, byte ptr [srb+TAPE_SENSE+13]
        mov     byte ptr [sense_ascq], al
; Fixed VALID qualifies the four-byte INFORMATION field, not the entire
; reply. ASC/ASCQ have their own length validity. Preserve the raw 32-bit value;
; signed/positive residual interpretation and block-to-byte conversion belong
; to the command consumer, not this generic decode step.
fixed_sense_information:
        mov     al, byte ptr [srb+TAPE_SENSE+0]
        test    al, 80h
        jz      fixed_sense_flags
        mov     byte ptr [sense_info_valid], 1
        mov     ah, byte ptr [srb+TAPE_SENSE+3]
        mov     al, byte ptr [srb+TAPE_SENSE+4]
        mov     word ptr [sense_info_high], ax
        mov     ah, byte ptr [srb+TAPE_SENSE+5]
        mov     al, byte ptr [srb+TAPE_SENSE+6]
        mov     word ptr [sense_info_low], ax
fixed_sense_flags:
        mov     al, byte ptr [srb+TAPE_SENSE+2]
        mov     ah, al
        and     ah, SENSE_FILEMARK or SENSE_EOM or SENSE_ILI
        mov     byte ptr [sense_flags], ah
        and     al, 0Fh
        mov     byte ptr [last_sense_key], al
sense_done:
        ret
remember_sense_key endp
