; DOS-side ASPITAP compatibility smoke test.

        .8086
        option casemap:none

        .model tiny
        .code
        org     100h

fail_if_carry macro target
        local   no_error
        jnc     no_error
        jmp     target
no_error:
endm

fail_if_not_equal macro target
        local   equal
        je      equal
        jmp     target
equal:
endm

fail_if_no_carry macro target
        local   expected_error
        jc      expected_error
        jmp     target
expected_error:
endm

start:
        push    cs
        pop     ds
        mov     ax, 3524h
        int     21h
        mov     word ptr [old_int24], bx
        mov     word ptr [old_int24+2], es
        mov     dx, offset critical_error
        mov     ax, 2524h
        int     21h

        mov     byte ptr [stage], '1'
        mov     dx, offset rmt_name
        call    open_raw
        fail_if_carry failed
        mov     word ptr [handle], ax
        mov     bx, ax
        mov     byte ptr [stage], '2'
        call    get_status
        fail_if_carry failed_close
        mov     byte ptr [stage], 'D'
        cmp     byte ptr [status+0], 0
        fail_if_not_equal failed_close
        mov     byte ptr [stage], 'E'
        cmp     byte ptr [status+1], 0
        fail_if_not_equal failed_close
        mov     byte ptr [stage], 'F'
        cmp     byte ptr [status+2], 0
        fail_if_not_equal failed_close
        mov     byte ptr [stage], 'G'
        cmp     byte ptr [status+3], 80h
        fail_if_not_equal failed_close
        mov     byte ptr [stage], 'H'
        cmp     byte ptr [status+4], 06h
        fail_if_not_equal failed_close
        mov     word ptr [control], 8    ; unknown operation, before any write
        call    run_mtop
        fail_if_no_carry failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status_extended+7], 21
        fail_if_not_equal failed_close
        mov     word ptr [control], 7

        ; Open RMT0 twice. Closing the first handle must leave the tape alone;
        ; an intervening TUR proves that rewind is deferred until final close.
        mov     dx, offset rmt_name
        call    open_raw
        fail_if_carry failed_close
        mov     word ptr [handle2], ax
        mov     byte ptr [stage], 'm'
        mov     bx, word ptr [handle2]
        mov     cx, 2
        mov     dx, offset read_buffer
        mov     ah, 3Fh
        int     21h
        fail_if_no_carry failed_close2
        call    get_status
        fail_if_carry failed_close2
        cmp     byte ptr [status_extended+7], 17
        fail_if_not_equal failed_close2
        mov     byte ptr [stage], 'o'
        call    close_handle
        fail_if_carry failed_close2
        mov     ax, word ptr [handle2]
        mov     word ptr [handle], ax
        mov     word ptr [control], 7    ; MTNOP between the two closes
        mov     word ptr [control+2], 0
        mov     word ptr [control+4], 0
        call    run_mtop
        fail_if_carry failed_close
        mov     byte ptr [stage], 'c'
        call    close_handle             ; final RMT0 close must rewind
        fail_if_carry failed

        mov     byte ptr [stage], '3'
        mov     dx, offset nrmt_name
        call    open_raw
        fail_if_carry failed
        mov     word ptr [handle], ax
        mov     bx, ax
        mov     byte ptr [stage], '4'
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+4], 02h
        fail_if_not_equal failed_close

        mov     byte ptr [stage], '5'
        mov     cl, 03h                 ; ignore EOT errors
        mov     dx, offset status
        call    tape_ioctl
        fail_if_carry failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+4], 42h
        fail_if_not_equal failed_close

        mov     byte ptr [stage], '6'
        mov     cl, 04h                 ; enable EOT errors
        mov     dx, offset status
        call    tape_ioctl
        fail_if_carry failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+4], 02h
        fail_if_not_equal failed_close

        ; DOS cooked mode reduces character-device traffic to single-byte
        ; requests. Historical ASPITAPE rejects those by default.
        mov     byte ptr [stage], 's'
        mov     bx, word ptr [handle]
        mov     cx, 1
        mov     dx, offset read_buffer
        mov     ah, 3Fh
        int     21h
        fail_if_no_carry failed_close
        mov     bx, word ptr [handle]
        mov     cx, 1
        mov     dx, offset write_payload
        mov     ah, 40h
        int     21h
        fail_if_no_carry failed_close

        mov     byte ptr [stage], 'R'
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status_extended+7], 18
        fail_if_not_equal failed_close
        mov     bx, word ptr [handle]
        mov     cx, 16
        mov     dx, offset read_buffer
        mov     ah, 3Fh
        int     21h
        fail_if_carry failed_close
ifdef NO_RESIDUAL
        cmp     ax, 16
else
        cmp     ax, 12
endif
        fail_if_not_equal failed_close
        push    ds
        pop     es
        mov     si, offset expected_payload
        mov     di, offset read_buffer
        mov     cx, READ_EXPECTED_SIZE
        repe    cmpsb
        fail_if_not_equal failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+4], 12h
        fail_if_not_equal failed_close
ifdef NO_RESIDUAL
        cmp     word ptr [status+0Ah], 0808h
else
        cmp     word ptr [status+0Ah], 0C08h
endif
        fail_if_not_equal failed_close
ifdef NO_RESIDUAL
        cmp     word ptr [status+0Ch], 0
else
        cmp     word ptr [status+0Ch], 4
endif
        fail_if_not_equal failed_close

        ; A short variable record may arrive as CHECK CONDITION with a
        ; positive ILI information value instead of a manager residual.
        mov     byte ptr [stage], 'q'
        mov     bx, word ptr [handle]
        mov     cx, 16
        mov     dx, offset read_buffer
        mov     ah, 3Fh
        int     21h
        fail_if_carry failed_close
        cmp     ax, ILI_EXPECTED_SIZE
        fail_if_not_equal failed_close
        push    ds
        pop     es
        mov     si, offset ili_expected_payload
        mov     di, offset read_buffer
        mov     cx, ILI_EXPECTED_SIZE
        repe    cmpsb
        fail_if_not_equal failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+4], 12h
        fail_if_not_equal failed_close
        cmp     byte ptr [status+8], 2
        fail_if_not_equal failed_close
        cmp     byte ptr [status+9], 0
        fail_if_not_equal failed_close
ifdef NO_RESIDUAL
        cmp     word ptr [status+0Ah], 0808h
else
        cmp     word ptr [status+0Ah], 0C08h
endif
        fail_if_not_equal failed_close
        cmp     word ptr [status+0Ch], 4
        fail_if_not_equal failed_close

        ; A filemark is reported as exactly one zero-byte read. The following
        ; read must return the first record in the next tape file.
        mov     byte ptr [stage], 'f'
        mov     bx, word ptr [handle]
        mov     cx, 16
        mov     dx, offset read_buffer
        mov     ah, 3Fh
        int     21h
        fail_if_carry failed_close
        or      ax, ax
        fail_if_not_equal failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+8], 2
        fail_if_not_equal failed_close
        cmp     word ptr [status+0Ch], 16
        fail_if_not_equal failed_close

        mov     byte ptr [stage], 'a'
        mov     bx, word ptr [handle]
        mov     cx, 16
        mov     dx, offset read_buffer
        mov     ah, 3Fh
        int     21h
        fail_if_carry failed_close
        cmp     ax, AFTER_FILEMARK_SIZE
        fail_if_not_equal failed_close
        push    ds
        pop     es
        mov     si, offset after_filemark_payload
        mov     di, offset read_buffer
        mov     cx, AFTER_FILEMARK_SIZE
        repe    cmpsb
        fail_if_not_equal failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+8], 0
        fail_if_not_equal failed_close
        cmp     word ptr [status+0Ch], 0
        fail_if_not_equal failed_close

        ; EOM remains an error in the default mode.
        mov     byte ptr [stage], 'e'
        mov     bx, word ptr [handle]
        mov     cx, 16
        mov     dx, offset read_buffer
        mov     ah, 3Fh
        int     21h
        fail_if_no_carry failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+8], 2
        fail_if_not_equal failed_close
        cmp     word ptr [status+0Ch], 16
        fail_if_not_equal failed_close

        ; With ignore-EOT selected, the same EOM condition becomes EOF.
        mov     byte ptr [stage], 'i'
        mov     cl, 03h
        mov     dx, offset status
        call    tape_ioctl
        fail_if_carry failed_close
        mov     bx, word ptr [handle]
        mov     cx, 16
        mov     dx, offset read_buffer
        mov     ah, 3Fh
        int     21h
        fail_if_carry failed_close
        or      ax, ax
        fail_if_not_equal failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+4], 52h
        fail_if_not_equal failed_close
        cmp     byte ptr [status+8], 2
        fail_if_not_equal failed_close

        mov     byte ptr [stage], 't'
        mov     cl, 04h
        mov     dx, offset status
        call    tape_ioctl
        fail_if_carry failed_close

        ; Negative ILI means the record did not fit and must stay an error.
        mov     byte ptr [stage], 'n'
        mov     bx, word ptr [handle]
        mov     cx, 16
        mov     dx, offset read_buffer
        mov     ah, 3Fh
        int     21h
        fail_if_no_carry failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+4], 12h
        fail_if_not_equal failed_close
        cmp     byte ptr [status+8], 2
        fail_if_not_equal failed_close
        cmp     word ptr [status+0Ch], 16
        fail_if_not_equal failed_close

        mov     byte ptr [stage], 'Z'
        mov     bx, word ptr [handle]
        xor     cx, cx
        mov     dx, offset read_buffer
        mov     ah, 3Fh
        int     21h
        fail_if_carry failed_close
        or      ax, ax
        fail_if_not_equal failed_close

        mov     byte ptr [stage], 'W'
        mov     bx, word ptr [handle]
        mov     cx, WRITE_PAYLOAD_SIZE
        mov     dx, offset write_payload
        mov     ah, 40h
        int     21h
        fail_if_carry failed_close
        cmp     ax, WRITE_PAYLOAD_SIZE
        fail_if_not_equal failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+4], 1Ah
        fail_if_not_equal failed_close
ifdef NO_RESIDUAL
        cmp     word ptr [status+0Ah], 100Ah
else
        cmp     word ptr [status+0Ah], 140Ah
endif
        fail_if_not_equal failed_close
        cmp     word ptr [status+0Ch], 0
        fail_if_not_equal failed_close

        ; Historical ASPITAPE permits a read-then-write session, but rejects
        ; every read after the first successful write.
        mov     byte ptr [stage], 'd'
        mov     bx, word ptr [handle]
        mov     cx, 16
        mov     dx, offset read_buffer
        mov     ah, 3Fh
        int     21h
        fail_if_no_carry failed_close

        ; A DATA PROTECT condition must remain a failed DOS write and expose
        ; the SCSI sense key through mtget.
        mov     byte ptr [stage], 'p'
        mov     bx, word ptr [handle]
        mov     cx, 2
        mov     dx, offset write_payload
        mov     ah, 40h
        int     21h
        fail_if_no_carry failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status+4], 1Ah
        fail_if_not_equal failed_close
        cmp     byte ptr [status+8], 2
        fail_if_not_equal failed_close
        cmp     byte ptr [status+9], 7
        fail_if_not_equal failed_close
        cmp     word ptr [status+0Ch], 2
        fail_if_not_equal failed_close

        mov     byte ptr [stage], '7'
        mov     cl, 01h                 ; mtop: MTNOP
        mov     dx, offset control
        call    tape_ioctl
        fail_if_carry failed_close
        call    get_status
        fail_if_carry failed_close
ifdef NO_RESIDUAL
        cmp     word ptr [status+0Ah], 100Ah
else
        cmp     word ptr [status+0Ah], 140Ah
endif
        fail_if_not_equal failed_close
        cmp     byte ptr [status+8], 2
        fail_if_not_equal failed_close
        cmp     byte ptr [status+9], 7
        fail_if_not_equal failed_close

        mov     byte ptr [stage], '8'
        mov     word ptr [control], 0    ; MTWEOF
        mov     word ptr [control+2], 2
        mov     word ptr [control+4], 0
        call    run_mtop
        fail_if_carry failed_close
        call    get_status
        fail_if_carry failed_close
        mov     al, byte ptr [status_extended+4]
        and     al, 20h
        cmp     al, 20h
        fail_if_not_equal failed_close

        mov     byte ptr [stage], '9'
        mov     word ptr [control], 1    ; MTFSF
        mov     word ptr [control+2], 3
        mov     word ptr [control+4], 0
        call    run_mtop
        fail_if_carry failed_close

        mov     byte ptr [stage], 'I'
        mov     word ptr [control], 2    ; MTBSF
        call    run_mtop
        fail_if_carry failed_close

        mov     byte ptr [stage], 'J'
        mov     word ptr [control], 3    ; MTFSR
        mov     word ptr [control+2], 4
        mov     word ptr [control+4], 0
        call    run_mtop
        fail_if_carry failed_close

        mov     byte ptr [stage], 'K'
        mov     word ptr [control], 4    ; MTBSR
        call    run_mtop
        fail_if_carry failed_close

        mov     byte ptr [stage], 'L'
        mov     word ptr [control], 5    ; MTREW
        mov     word ptr [control+2], 1
        mov     word ptr [control+4], 0
        call    run_mtop
        fail_if_carry failed_close

        mov     byte ptr [stage], 'M'
        mov     word ptr [control], 6    ; MTOFFL
        call    run_mtop
        fail_if_carry failed_close

        ; Exact signed SPACE limits and the distinct unsigned filemark limit.
        ; The mock compares all six CDB bytes, not only successful return codes.
        mov     byte ptr [stage], 'B'
        mov     word ptr [control], 0
        mov     word ptr [control+2], 0FFFFh
        mov     word ptr [control+4], 00FFh
        call    run_mtop               ; MTWEOF 16777215 remains valid
        fail_if_carry failed_close
        mov     word ptr [control], 1
        mov     word ptr [control+4], 007Fh
        call    run_mtop               ; MTFSF 8388607
        fail_if_carry failed_close
        mov     word ptr [control], 3
        call    run_mtop               ; MTFSR 8388607
        fail_if_carry failed_close
        mov     word ptr [control], 2
        mov     word ptr [control+2], 0
        mov     word ptr [control+4], 0080h
        call    run_mtop               ; MTBSF 8388608 -> -8388608
        fail_if_carry failed_close
        mov     word ptr [control], 4
        call    run_mtop               ; MTBSR 8388608 -> -8388608
        fail_if_carry failed_close

        mov     byte ptr [stage], 'N'
        mov     word ptr [control], 1
        call    run_mtop               ; +8388608 must not become backward
        fail_if_no_carry failed_close
        mov     word ptr [control], 3
        call    run_mtop
        fail_if_no_carry failed_close
        mov     word ptr [control+2], 0FFFFh
        mov     word ptr [control+4], 00FFh
        call    run_mtop               ; 16777215 must not become -1
        fail_if_no_carry failed_close
        mov     word ptr [control], 1
        call    run_mtop
        fail_if_no_carry failed_close

        mov     word ptr [control], 1    ; count too large for SPACE
        mov     word ptr [control+2], 0
        mov     word ptr [control+4], 0100h
        call    run_mtop
        fail_if_no_carry failed_close

        mov     byte ptr [stage], 'O'
        mov     word ptr [control], 2    ; magnitude too large for SPACE
        mov     word ptr [control+2], 1
        mov     word ptr [control+4], 0080h
        call    run_mtop
        fail_if_no_carry failed_close

        mov     byte ptr [stage], 'P'
        mov     word ptr [control], 8    ; undefined tape operation
        call    run_mtop
        fail_if_no_carry failed_close
        call    get_status
        fail_if_carry failed_close
        cmp     byte ptr [status_extended+7], 7
        fail_if_not_equal failed_close
ifdef NO_RESIDUAL
        cmp     word ptr [status+0Ah], 100Ah
else
        cmp     word ptr [status+0Ah], 140Ah
endif
        fail_if_not_equal failed_close
        cmp     byte ptr [status+8], 2
        fail_if_not_equal failed_close
        cmp     byte ptr [status+9], 7
        fail_if_not_equal failed_close

        call    close_handle
        call    restore_int24
        mov     dx, offset success_message
        mov     ah, 09h
        int     21h
        mov     ax, 4C00h
        int     21h

failed_close:
        call    close_handle
        jmp     short failed
failed_close2:
        mov     bx, word ptr [handle2]
        mov     ah, 3Eh
        int     21h
failed:
        call    restore_int24
        mov     dx, offset failure_message
        mov     ah, 09h
        int     21h
        mov     dl, byte ptr [stage]
        mov     ah, 02h
        int     21h
        mov     dx, offset newline
        mov     ah, 09h
        int     21h
        mov     ax, 4C01h
        int     21h

open_raw proc near
        mov     ax, 3D02h
        int     21h
        jc      open_done
        mov     byte ptr [stage], 'A'
        mov     bx, ax
        mov     ax, 4400h
        int     21h
        jc      open_failed
        mov     byte ptr [stage], 'B'
        or      dl, 20h
        xor     dh, dh
        mov     ax, 4401h
        int     21h
        jc      open_failed
        mov     byte ptr [stage], 'C'
        mov     ax, bx
        clc
open_done:
        ret
open_failed:
        mov     ah, 3Eh
        int     21h
        stc
        ret
open_raw endp

close_handle proc near
        mov     bx, word ptr [handle]
        mov     ah, 3Eh
        int     21h
        ret
close_handle endp

restore_int24 proc near
        push    ds
        mov     dx, word ptr cs:[old_int24]
        mov     ax, word ptr cs:[old_int24+2]
        mov     ds, ax
        mov     ax, 2524h
        int     21h
        pop     ds
        ret
restore_int24 endp

critical_error proc far
        mov     al, 3                   ; fail the request; never prompt/retry
        iret
critical_error endp

get_status proc near
        jmp     checked_mtget
get_status endp

run_mtop proc near
        mov     cl, 01h
        mov     dx, offset control
        jmp     short tape_ioctl
run_mtop endp

tape_ioctl proc near
        mov     bx, word ptr [handle]
        mov     ch, 07h
        mov     ax, 440Ch
        int     21h
        ret
tape_ioctl endp

rmt_name        db      'RMT0', 0
nrmt_name       db      'NRMT0', 0
handle          dw      0
handle2         dw      0
old_int24       dd      0
stage           db      '?'
control:
        dw      7                       ; MTNOP
        dd      1
        include tests/tape_status.inc
status          db      18 dup (0)
ifdef NO_RESIDUAL
READ_EXPECTED_SIZE equ  16
expected_payload db     '0123456789ABCDEF'
else
READ_EXPECTED_SIZE equ  12
expected_payload db     'TAPE-READ-OK'
endif
ILI_EXPECTED_SIZE equ  12
ili_expected_payload db 'ILI-READ-OK!'
AFTER_FILEMARK_SIZE equ 16
after_filemark_payload db 'AFTER-FILEMARK!!'
WRITE_PAYLOAD_SIZE equ 12
write_payload   db      'WRITE-RECORD'
read_buffer     db      16 dup (0)
success_message db      'OpenASPI tape IOCTL smoke test passed', 13, 10, '$'
failure_message db      'OpenASPI tape IOCTL smoke test FAILED at stage $'
newline         db      13, 10, '$'

        end     start
