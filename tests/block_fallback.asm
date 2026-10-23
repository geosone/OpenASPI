; Execute the real resident block request core against a memory-only ASPI
; callback. No installed manager or disk is accessed. Fail WRITE AND VERIFY
; with ILLEGAL REQUEST, then require exactly the original LBA/buffer/count on
; WRITE retry and the correctly advanced second chunk. Also check hard errors.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h
        jmp test_start
        include common/aspi/dos_aspi.inc
        include common/dos/devreq.inc
        include common/dos/blkdrv.inc
msg_banner db '$'
msg_no_device db '$'
CHECK_EQUAL macro
        local equal_ok
        je equal_ok
        jmp test_fail
equal_ok:
endm
CHECK_SUCCESS macro
        local success_ok
        jnc success_ok
        jmp test_fail
success_ok:
endm
CHECK_FAILURE macro
        local failure_ok
        jc failure_ok
        jmp test_fail
failure_ok:
endm
packet db 32 dup (0)
calls dw 0
bad db 0
hard_error db 0
msg_pass db 'Block fallback LBA/buffer/count and hard-error tests passed',13,10,'$'
msg_fail db 'Block fallback regression FAILED',13,10,'$'

test_start:
        push cs
        pop ds
        push cs
        pop es
        cld
        mov word ptr [aspi_entry], offset fake_aspi
        mov word ptr [aspi_entry+2], cs
        ; Shared detector/driver policy, including lowercase and a match
        ; crossing the vendor/product boundary into revision bytes (refused).
        mov di, offset inquiry_data
        mov cx, INQUIRY_LEN
        mov al, ' '
        rep stosb
        mov byte ptr [inquiry_data+1], 80h
        call is_fdd_model                       ; generic removable stick
        jnc policy_fail
        mov byte ptr [inquiry_data+16], 'z'
        mov byte ptr [inquiry_data+17], 'i'
        mov byte ptr [inquiry_data+18], 'p'
        call is_fdd_model
        jc policy_fail
        mov byte ptr [inquiry_data+1], 0
        call is_fdd_model                       ; model alone is not enough
        jnc policy_fail
        mov byte ptr [inquiry_data+1], 80h
        mov word ptr [inquiry_data+16], '  '
        mov byte ptr [inquiry_data+18], ' '
        mov byte ptr [inquiry_data+31], 'Z'
        mov byte ptr [inquiry_data+32], 'I'
        mov byte ptr [inquiry_data+33], 'P'
        call is_fdd_model
        jnc policy_fail
        jmp short policy_ok
policy_fail:
        jmp test_fail
policy_ok:
        mov word ptr [unit_ptr], offset unit_table
        mov byte ptr [unit_table+U_FLAGS], UF_MEDIA
        mov word ptr [unit_table+U_BPB+BPB_TOTAL32+2], 2000h
        mov bx, offset packet
        mov byte ptr [packet+RH_LENGTH], 32
        mov word ptr [packet+RH_START], 0FFFFh
        mov word ptr [packet+RH_START32], 5678h
        mov word ptr [packet+RH_START32+2], 1234h
        mov word ptr [packet+RH_COUNT], 66
        mov word ptr [packet+RH_BUFFER], 0123h
        mov word ptr [packet+RH_BUFFER+2], cs
        call write_verify_request
        CHECK_SUCCESS
        cmp word ptr [calls], 5
        CHECK_EQUAL
        cmp byte ptr [bad], 0
        CHECK_EQUAL
        mov word ptr [calls], 0
        mov byte ptr [hard_error], 1
        mov word ptr [packet+RH_COUNT], 66
        mov bx, offset packet
        call write_verify_request
        CHECK_FAILURE
        cmp al, 0Bh                     ; MEDIUM ERROR must survive cleanup
        CHECK_EQUAL
        cmp word ptr [calls], 1          ; never fall back/retry this error
        CHECK_EQUAL
        cmp word ptr [packet+RH_COUNT], 0
        CHECK_EQUAL
        cmp byte ptr [bad], 0
        CHECK_EQUAL
        ; Failure of fallback WRITE must not issue VERIFY.
        mov word ptr [calls], 0
        mov byte ptr [hard_error], 2
        mov word ptr [packet+RH_COUNT], 66
        mov bx, offset packet
        call write_verify_request
        CHECK_FAILURE
        cmp al, 0
        CHECK_EQUAL
        cmp word ptr [calls], 2
        CHECK_EQUAL
        cmp word ptr [packet+RH_COUNT], 0
        CHECK_EQUAL
        ; Failed VERIFY must not report success or start the next chunk.
        mov word ptr [calls], 0
        mov byte ptr [hard_error], 3
        mov word ptr [packet+RH_COUNT], 66
        mov bx, offset packet
        call write_verify_request
        CHECK_FAILURE
        cmp al, 0Bh
        CHECK_EQUAL
        cmp word ptr [calls], 3
        CHECK_EQUAL
        cmp word ptr [packet+RH_COUNT], 0
        CHECK_EQUAL
        cmp byte ptr [bad], 0
        CHECK_EQUAL
        ; Reject logical/physical overflow and volume crossings before ASPI.
        mov word ptr [calls], 0
        mov word ptr [packet+RH_START32], 0FFF0h
        mov word ptr [packet+RH_START32+2], 0FFFFh
        mov word ptr [unit_table+U_BPB+BPB_TOTAL32], 0FFFFh
        mov word ptr [unit_table+U_BPB+BPB_TOTAL32+2], 0FFFFh
        mov word ptr [packet+RH_COUNT], 32
        call write_verify_request
        CHECK_FAILURE
        cmp al, ERR_NOT_FOUND
        CHECK_EQUAL
        cmp word ptr [calls], 0
        CHECK_EQUAL
        mov word ptr [packet+RH_START32], 1
        mov word ptr [packet+RH_START32+2], 0
        mov word ptr [unit_table+U_BPB+BPB_TOTAL32], 2
        mov word ptr [unit_table+U_BPB+BPB_TOTAL32+2], 0
        mov word ptr [packet+RH_COUNT], 2
        call write_verify_request
        CHECK_FAILURE
        cmp al, ERR_NOT_FOUND
        CHECK_EQUAL
        mov byte ptr [packet+RH_LENGTH], 1Dh
        mov word ptr [packet+RH_COUNT], 1
        call write_verify_request
        CHECK_FAILURE
        cmp al, 5
        CHECK_EQUAL
        mov byte ptr [packet+RH_LENGTH], 32
        mov word ptr [packet+RH_COUNT], 0
        call write_verify_request
        CHECK_SUCCESS
        mov word ptr [unit_table+U_START], 0FFFFh
        mov word ptr [unit_table+U_START+2], 0FFFFh
        mov word ptr [packet+RH_COUNT], 1
        call write_verify_request
        CHECK_FAILURE
        cmp al, ERR_NOT_FOUND
        CHECK_EQUAL
        mov word ptr [packet+RH_START32], 0
        mov word ptr [packet+RH_COUNT], 2
        call write_verify_request
        CHECK_FAILURE
        cmp al, ERR_NOT_FOUND
        CHECK_EQUAL
        cmp word ptr [calls], 0
        CHECK_EQUAL
        mov dx, offset msg_pass
        mov ah, 09h
        int 21h
        mov ax, 4C00h
        int 21h
test_fail:
        mov dx, offset msg_fail
        mov ah, 09h
        int 21h
        mov ax, 4C01h
        int 21h

BAD_IF_NOT_EQUAL macro
        local expected
        je expected
        jmp fake_bad
expected:
endm
fake_aspi proc far
        inc word ptr cs:[calls]
        cmp word ptr cs:[srb+SRB_CDB+2], 3412h
        BAD_IF_NOT_EQUAL
        cmp byte ptr cs:[srb+SRB_CDB+7], 0
        BAD_IF_NOT_EQUAL
        mov ax, cs
        cmp word ptr cs:[calls], 4
        jae fake_tail
        cmp word ptr cs:[srb+SRB_CDB+4], 7856h
        BAD_IF_NOT_EQUAL
        cmp byte ptr cs:[srb+SRB_CDB+8], 64
        BAD_IF_NOT_EQUAL
        jmp short fake_buffer
fake_tail:
        cmp word ptr cs:[srb+SRB_CDB+4], 0B856h
        BAD_IF_NOT_EQUAL
        cmp byte ptr cs:[srb+SRB_CDB+8], 2
        BAD_IF_NOT_EQUAL
        add ax, 0800h
fake_buffer:
        cmp word ptr cs:[calls], 3
        je fake_verify
        cmp word ptr cs:[calls], 5
        je fake_verify
        cmp word ptr cs:[srb+SRB_BufPointer], 0123h
        BAD_IF_NOT_EQUAL
        cmp word ptr cs:[srb+SRB_BufPointer+2], ax
        BAD_IF_NOT_EQUAL
        cmp word ptr cs:[calls], 1
        jne fake_write
        cmp byte ptr cs:[srb+SRB_CDB], 2Eh
        BAD_IF_NOT_EQUAL
        mov byte ptr cs:[srb+SRB_Status], SS_ERR
        mov byte ptr cs:[srb+SRB_TargStat], 2
        mov byte ptr cs:[srb+SRB_CDB+10+2], 5
        cmp byte ptr cs:[hard_error], 1
        jne fake_done
        mov byte ptr cs:[srb+SRB_CDB+10+2], 3
        jmp short fake_done
fake_write:
        cmp byte ptr cs:[srb+SRB_CDB], 2Ah
        BAD_IF_NOT_EQUAL
        cmp byte ptr cs:[hard_error], 2
        jne fake_success
        mov byte ptr cs:[srb+SRB_Status], SS_ERR
        mov byte ptr cs:[srb+SRB_TargStat], 2
        mov byte ptr cs:[srb+SRB_CDB+10+2], 7
        jmp short fake_done
fake_verify:
        cmp byte ptr cs:[srb+SRB_CDB], 2Fh
        BAD_IF_NOT_EQUAL
        cmp byte ptr cs:[srb+SRB_Flags], SRB_DIR_NONE
        BAD_IF_NOT_EQUAL
        cmp word ptr cs:[srb+SRB_BufLen], 0
        BAD_IF_NOT_EQUAL
        cmp word ptr cs:[srb+SRB_BufLen+2], 0
        BAD_IF_NOT_EQUAL
        cmp word ptr cs:[srb+SRB_BufPointer], 0
        BAD_IF_NOT_EQUAL
        cmp word ptr cs:[srb+SRB_BufPointer+2], 0
        BAD_IF_NOT_EQUAL
        cmp byte ptr cs:[hard_error], 3
        je fake_bad_verify
fake_success:
        mov byte ptr cs:[srb+SRB_Status], SS_COMP
fake_done:
        ret
fake_bad_verify:
        mov byte ptr cs:[srb+SRB_Status], SS_ERR
        mov byte ptr cs:[srb+SRB_TargStat], 2
        mov byte ptr cs:[srb+SRB_CDB+10+2], 3
        ret
fake_bad:
        mov byte ptr cs:[bad], 1
        mov byte ptr cs:[srb+SRB_Status], SS_ERR
        mov byte ptr cs:[srb+SRB_TargStat], 2
        mov byte ptr cs:[srb+SRB_CDB+10+2], 3
        ret
fake_aspi endp
        end test_start
