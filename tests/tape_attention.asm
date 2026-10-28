; Legacy UNIT ATTENTION latch through the installed driver and mockattention.inc.
; A reset reported by one WRITE must stop later writes, reads, filemarks, SPACE
; and implicit close marks without any CDB, until an explicit MTREW succeeds.

        .8086
        option casemap:none
        .model tiny
        .code
        org     100h
        include common/aspi/dos_aspi.inc

CFCHECK macro condition
        local good
        condition good
        jmp failed
good:
endm
EQCHECK macro
        local good
        je good
        jmp failed
good:
endm

start:
        push    cs
        pop     ds
        cld
        mov     ax, 3524h
        int     21h
        mov     word ptr [old_int24], bx
        mov     word ptr [old_int24+2], es
        mov     dx, offset critical_error
        mov     ax, 2524h
        int     21h
        mov     dx, offset manager_name
        mov     ax, 3D00h
        int     21h
        CFCHECK jnc
        mov     bx, ax
        mov     dx, offset entry
        mov     cx, 4
        mov     ax, 4402h
        int     21h
        CFCHECK jnc
        mov     ah, 3Eh
        int     21h

        mov     byte ptr [stage], '1'
        call    open_tape
        CFCHECK jnc
        call    write_record             ; accepted
        CFCHECK jnc
        cmp     ax, 12
        EQCHECK
        mov     byte ptr [stage], '2'
        call    write_record             ; device reports UNIT ATTENTION 29h
        CFCHECK jc
        mov     ax, 0406h                ; saved write error 6, latch set
        call    expect_status
        mov     byte ptr [stage], '3'
        call    write_record             ; latched: no CDB
        CFCHECK jc
        mov     ax, 0406h                ; the original cause stays visible
        call    expect_status
        mov     byte ptr [stage], '4'
        mov     dx, offset read_buffer
        mov     cx, 12
        mov     bx, word ptr [handle]
        mov     ah, 3Fh
        int     21h
        CFCHECK jc
        mov     byte ptr [stage], '5'
        mov     word ptr [control], 0    ; MTWEOF 1
        call    run_mtop
        CFCHECK jc
        mov     byte ptr [stage], '6'
        mov     word ptr [control], 1    ; MTFSF 1
        call    run_mtop
        CFCHECK jc
        mov     byte ptr [stage], '7'
        mov     word ptr [control], 7    ; MTNOP may still inspect readiness
        call    run_mtop
        CFCHECK jnc
        mov     byte ptr [stage], '8'
        call    close_handle             ; must not append close filemarks
        call    open_tape                ; latch survives close/open
        CFCHECK jnc
        call    write_record
        CFCHECK jc
        mov     ax, 0418h                ; refused close finalization was saved
        call    expect_status
        mov     byte ptr [stage], '9'
        mov     word ptr [control], 5    ; MTREW clears the latch
        call    run_mtop
        CFCHECK jnc
        mov     ax, 0018h                ; saved write error remains until a write
        call    expect_status
        mov     byte ptr [stage], 'A'
        call    write_record
        CFCHECK jnc
        cmp     ax, 12
        EQCHECK
        mov     byte ptr [stage], 'B'
        mov     word ptr [control], 7    ; MTNOP reports UNIT ATTENTION 28h
        call    run_mtop
        CFCHECK jc
        mov     ax, 0406h
        call    expect_status
        mov     byte ptr [stage], 'C'
        mov     word ptr [control], 3    ; MTFSR 1: refused, no CDB
        call    run_mtop
        CFCHECK jc
        mov     ax, 0418h                ; driver error 24
        call    expect_status
        mov     byte ptr [stage], 'D'
        call    write_record
        CFCHECK jc
        mov     ax, 0418h
        call    expect_status
        mov     byte ptr [stage], 'E'
        mov     word ptr [control], 5
        call    run_mtop
        CFCHECK jnc
        mov     ax, 0000h
        call    expect_status
        mov     byte ptr [stage], 'F'
        call    close_handle             ; now the usual close marks
        CFCHECK jnc
        mov     byte ptr [stage], 'G'
        mov     byte ptr [test_srb], 0F2h
        push    cs
        mov     dx, offset test_srb
        push    dx
        call    dword ptr [entry]
        add     sp, 4
        cmp     word ptr [test_srb+6], 0
        EQCHECK
        cmp     word ptr [test_srb+4], 9
        EQCHECK

        call    restore_int24
        mov     dx, offset success_message
        mov     ah, 09h
        int     21h
        mov     ax, 4C00h
        int     21h

failed:
        call    restore_int24
        mov     dx, offset failure_message
        mov     ah, 09h
        int     21h
        mov     dl, byte ptr [stage]
        mov     ah, 02h
        int     21h
        mov     dl, ' '
        mov     ah, 02h
        int     21h
        mov     al, byte ptr [status+7]  ; last driver error seen
        call    print_hex
        mov     dx, offset newline
        mov     ah, 09h
        int     21h
        mov     ax, 4C01h
        int     21h

print_hex proc near
        push    ax
        mov     cl, 4
        shr     al, cl
        call    print_nibble
        pop     ax
print_nibble:
        and     al, 0Fh
        add     al, '0'
        cmp     al, '9'
        jbe     nibble_ready
        add     al, 7
nibble_ready:
        mov     dl, al
        mov     ah, 02h
        int     21h
        ret
print_hex endp

; AL = expected driver error byte, AH = expected 0400h attention bit (4 or 0)
; in the explicit 16-byte status snapshot.
expect_status proc near
        push    ax
        mov     bx, word ptr [handle]
        mov     cx, 0705h
        mov     dx, offset status
        mov     ax, 440Ch
        int     21h
        pop     ax
        CFCHECK jnc
        cmp     byte ptr [status+7], al
        EQCHECK
        mov     al, byte ptr [status+5]
        and     al, 4
        cmp     al, ah
        EQCHECK
        ret
expect_status endp

write_record proc near
        mov     bx, word ptr [handle]
        mov     cx, 12
        mov     dx, offset write_payload
        mov     ah, 40h
        int     21h
        ret
write_record endp

open_tape proc near
        mov     dx, offset tape_name
        mov     ax, 3D02h
        int     21h
        jc      open_done
        mov     word ptr [handle], ax
        mov     bx, ax
        mov     ax, 4400h
        int     21h
        jc      open_done
        or      dl, 20h                  ; raw mode
        xor     dh, dh
        mov     ax, 4401h
        int     21h
open_done:
        ret
open_tape endp

close_handle proc near
        mov     bx, word ptr [handle]
        mov     ah, 3Eh
        int     21h
        ret
close_handle endp

run_mtop proc near
        mov     bx, word ptr [handle]
        mov     cx, 0701h
        mov     dx, offset control
        mov     ax, 440Ch
        int     21h
        ret
run_mtop endp

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
        mov     al, 3                    ; fail; never prompt or retry
        iret
critical_error endp

tape_name       db      'NRMT0', 0
manager_name    db      'SCSIMGR$', 0
entry           dd      0
old_int24       dd      0
handle          dw      0
stage           db      '0'
control:
        dw      7
        dd      1
status          db      18 dup (0)
test_srb        db      ASPI_SRB_SIZE dup (0)
write_payload   db      'WRITE-RECORD'
read_buffer     db      16 dup (0)
success_message db      'OpenASPI tape unit attention test passed', 13, 10, '$'
failure_message db      'OpenASPI tape unit attention test FAILED at stage $'
newline         db      13, 10, '$'

        end     start
