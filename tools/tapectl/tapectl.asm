; Non-destructive ASPITAPE-compatible status utility for DOS.

        .8086
        option casemap:none

        .model tiny
        .code
        org     100h

IOCTL_TAPE      equ     07h
IOCTL_MTOP      equ     01h
IOCTL_MTGET     equ     02h
MTNOP           equ     07h

start:
        push    cs
        pop     ds

        ; PSP:80h is also DOS' default DTA. Save the parsed action before any
        ; file/device call can overwrite the command tail.
        call    parse_action
        mov     byte ptr [action], al

        mov     dx, offset tape_name
        call    open_raw
        jc      open_failed
        mov     word ptr [handle], ax

        call    get_status
        jc      ioctl_failed_close
        call    print_status

        cmp     byte ptr [action], 0
        je      status_passed

        call    test_ready
        jc      ready_failed_close
        mov     dx, offset ready_message
        call    print_string
        call    get_status
        jc      ioctl_failed_close
        call    print_status

status_passed:
        call    close_handle
        mov     dx, offset success_message
        call    print_string
        mov     ax, 4C00h
        int     21h

open_failed:
        mov     word ptr [last_error], ax
        mov     dx, offset open_error
        jmp     short report_error

ioctl_failed_close:
        mov     word ptr [last_error], ax
        mov     dx, offset ioctl_error
        jmp     short report_error_close

ready_failed_close:
        mov     word ptr [last_error], ax
        ; The command reached the driver even when the drive reports NOT
        ; READY (for example, an empty mhVTL drive). Preserve the DOS error,
        ; but show the recorded SCSI status and sense key before exiting.
        call    get_status
        jc      ready_failed_report
        call    print_status
ready_failed_report:
        mov     dx, offset ready_error

report_error_close:
        push    dx
        call    close_handle
        pop     dx
report_error:
        call    print_string
        mov     ax, word ptr [last_error]
        call    print_hex16
        call    print_newline
        mov     ax, 4C01h
        int     21h

; Return AL=1 when READY occurs in the command tail, otherwise AL=0. Some old
; command interpreters leave their own /P tail or redirection text in a child
; PSP, so unrelated tokens are deliberately ignored.
parse_action proc near
        xor     cx, cx
        mov     cl, byte ptr [80h]
        mov     si, 81h
        cmp     cx, 127
        jbe     parse_scan
        mov     cx, 127
parse_scan:
        jcxz    parse_none
        mov     al, byte ptr [si]
        or      al, al
        jz      parse_none
        cmp     al, 0Dh
        je      parse_none
        and     al, 0DFh
        cmp     al, 'R'
        je      parse_ready_candidate
        inc     si
        dec     cx
        jmp     short parse_scan
parse_ready_candidate:
        cmp     cx, 5
        jb      parse_none
        push    cx
        push    si
        mov     di, offset ready_word
        mov     bx, 5
parse_ready_loop:
        mov     al, byte ptr [si]
        and     al, 0DFh
        cmp     al, byte ptr [di]
        jne     parse_ready_mismatch
        inc     si
        inc     di
        dec     bx
        jnz     parse_ready_loop
        pop     si
        pop     cx
        mov     al, 1
        ret
parse_ready_mismatch:
        pop     si
        pop     cx
        inc     si
        dec     cx
        jmp     short parse_scan
parse_none:
        xor     al, al
        ret
parse_action endp

open_raw proc near
        mov     ax, 3D00h
        int     21h
        jc      open_done
        mov     bx, ax
        mov     ax, 4400h
        int     21h
        jc      open_raw_failed
        or      dl, 20h
        xor     dh, dh
        mov     ax, 4401h
        int     21h
        jc      open_raw_failed
        mov     ax, bx
        clc
open_done:
        ret
open_raw_failed:
        push    ax
        mov     ah, 3Eh
        int     21h
        pop     ax
        stc
        ret
open_raw endp

close_handle proc near
        mov     bx, word ptr [handle]
        mov     ah, 3Eh
        int     21h
        ret
close_handle endp

get_status proc near
        mov     bx, word ptr [handle]
        mov     ch, IOCTL_TAPE
        mov     cl, IOCTL_MTGET
        mov     dx, offset status
        mov     ax, 440Ch
        int     21h
        ret
get_status endp

test_ready proc near
        mov     bx, word ptr [handle]
        mov     ch, IOCTL_TAPE
        mov     cl, IOCTL_MTOP
        mov     dx, offset control
        mov     ax, 440Ch
        int     21h
        ret
test_ready endp

print_status proc near
        mov     dx, offset address_message
        call    print_string
        mov     al, byte ptr [status+0]
        call    print_hex8
        mov     dl, ':'
        call    print_char
        mov     al, byte ptr [status+1]
        call    print_hex8
        mov     dl, ':'
        call    print_char
        mov     al, byte ptr [status+2]
        call    print_hex8

        mov     dx, offset flags_message
        call    print_string
        mov     al, byte ptr [status+4]
        call    print_hex8

        mov     dx, offset scsi_message
        call    print_string
        mov     al, byte ptr [status+8]
        call    print_hex8

        mov     dx, offset sense_message
        call    print_string
        mov     al, byte ptr [status+9]
        call    print_hex8

        mov     dx, offset opcode_message
        call    print_string
        mov     ax, word ptr [status+0Ah]
        call    print_hex16

        mov     dx, offset residual_message
        call    print_string
        mov     ax, word ptr [status+0Ch]
        call    print_hex16
        jmp     short print_newline
print_status endp

print_hex16 proc near
        push    ax
        mov     al, ah
        call    print_hex8
        pop     ax
        call    print_hex8
        ret
print_hex16 endp

print_hex8 proc near
        push    ax
        push    bx
        push    cx
        push    dx
        mov     ch, al
        mov     cl, 4
        shr     al, cl
        and     al, 0Fh
        xor     bh, bh
        mov     bl, al
        mov     dl, byte ptr [hex_digits+bx]
        call    print_char
        mov     al, ch
        and     al, 0Fh
        mov     bl, al
        mov     dl, byte ptr [hex_digits+bx]
        call    print_char
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
print_hex8 endp

print_char proc near
        mov     ah, 02h
        int     21h
        ret
print_char endp

print_string proc near
        mov     ah, 09h
        int     21h
        ret
print_string endp

print_newline proc near
        mov     dx, offset newline
        jmp     short print_string
print_newline endp

tape_name        db      'NRMT0', 0
ready_word       db      'READY'
action           db      0
handle           dw      0
last_error       dw      0
control:
        dw      MTNOP
        dd      1
status           db      14 dup (0)

address_message  db      'NRMT0 ASPI address $'
flags_message    db      ' flags=$'
scsi_message     db      ' SCSI=$'
sense_message    db      ' sense=$'
opcode_message   db      ' opcode=$'
residual_message db      ' residual=$'
ready_message    db      'TEST UNIT READY completed', 13, 10, '$'
success_message  db      'OpenASPI TAPECTL status passed', 13, 10, '$'
open_error       db      'Cannot open NRMT0, DOS error $'
ioctl_error      db      'Cannot read ASPITAPE status, DOS error $'
ready_error      db      'TEST UNIT READY failed, DOS error $'
newline          db      13, 10, '$'
hex_digits       db      '0123456789ABCDEF'

        end     start
