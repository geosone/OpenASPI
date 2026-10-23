; Legacy category-07h status/diagnostic client. Status layout (14/16 bytes)
; is selected explicitly rather than guessed from a response. A reported saved
; write/finalization error remains distinct from this query's delivery status.
; Readiness probing is explicit; displaying cached status should not silently
; introduce a positioning or write operation. Native OTAP QUERY uses OTAPINFO.

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
STATE_WRITE_ERROR equ   0200h

start:
        push    cs
        pop     ds

        ; PSP:80h is also DOS' default DTA. Save the parsed action before any
        ; file/device call can overwrite the command tail. Resolve the device
        ; selection here as well, before opening anything.
        call    parse_options
        jnc     options_ready
        mov     dx, offset option_error
        call    print_string
        mov     ax, 4C01h
        int     21h
options_ready:

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
        cmp     byte ptr [write_failure_seen], 0
        jne     saved_failure_reported
        mov     dx, offset success_message
        call    print_string
        mov     ax, 4C00h
        int     21h

saved_failure_reported:
        mov     dx, offset saved_failure_message
        call    print_string
        mov     ax, 4C02h
        int     21h

open_failed:
        mov     word ptr [last_error], ax
        mov     dx, offset open_error
        call    print_string
        call    print_tape_name
        mov     dx, offset dos_error_suffix
        jmp     short report_error

ioctl_failed_close:
        mov     word ptr [last_error], ax
        mov     dx, offset ioctl_error
        jmp     short report_error_close

ready_failed_close:
        mov     word ptr [last_error], ax
        ; The command reached the driver even when the drive reports NOT
        ; READY (for example, an empty mhVTL drive). Preserve the DOS error,
        ; but show status before exiting. A saved write snapshot still refers
        ; to that earlier failure, not this readiness command; print its warning.
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

; Parse bounded PSP tokens before DOS may reuse its command-tail/DTA area.
; Ignore unrelated old-shell tokens, but recognize READY only as a complete
; token. DEVICE must have one colon-delimited, validated non-rewinding name.
parse_options proc near
        xor     cx, cx
        mov     cl, byte ptr [80h]
        mov     si, 81h
        cmp     cx, 127
        jbe     options_scan
        mov     cx, 127
options_scan:
        or      cx, cx
        jnz     options_scan_char
        jmp     options_done
options_scan_char:
        mov     al, byte ptr [si]
        or      al, al
        jnz     options_not_nul
        jmp     options_done
options_not_nul:
        cmp     al, 0Dh
        jne     options_not_cr
        jmp     options_done
options_not_cr:
        cmp     al, ' '
        je      options_skip_space
        cmp     al, 9
        jne     options_begin_token
options_skip_space:
        inc     si
        dec     cx
        jmp     options_scan
options_begin_token:
        mov     di, si
        xor     bx, bx
options_token:
        inc     si
        inc     bx
        dec     cx
        jz      options_token_ready
        mov     al, byte ptr [si]
        or      al, al
        jz      options_token_ready
        cmp     al, 0Dh
        je      options_token_ready
        cmp     al, ' '
        je      options_token_ready
        cmp     al, 9
        jne     options_token
options_token_ready:
        push    cx
        push    si
        mov     si, di
        mov     cx, bx
        mov     al, byte ptr [si]
        cmp     al, '/'
        je      options_strip_prefix
        cmp     al, '-'
        jne     options_match_ready
options_strip_prefix:
        inc     si
        dec     cx
options_match_ready:
        cmp     cx, 5
        jne     options_match_device
        mov     di, offset ready_word
        call    match_option_word
        jc      options_match_device
        mov     byte ptr [action], 1
        jmp     short options_next
options_match_device:
        cmp     cx, 6
        jb      options_next
        push    cx
        mov     cx, 6
        mov     di, offset device_word
        call    match_option_word
        pop     cx
        jc      options_next
        cmp     cx, 7
        jbe     options_invalid
        cmp     byte ptr [si+6], ':'
        jne     options_invalid
        cmp     byte ptr [device_selected], 0
        jne     options_invalid
        add     si, 7
        sub     cx, 7
        call    validate_tape_name
        jc      options_invalid
        mov     di, offset tape_name
options_copy_name:
        mov     al, byte ptr [si]
        inc     si
        cmp     al, 'a'
        jb      options_copy_char
        cmp     al, 'z'
        ja      options_copy_char
        sub     al, 20h
options_copy_char:
        mov     byte ptr [di], al
        inc     di
        loop    options_copy_name
        mov     byte ptr [di], 0
        mov     byte ptr [device_selected], 1
options_next:
        pop     si
        pop     cx
        jmp     options_scan
options_invalid:
        pop     si
        pop     cx
        stc
        ret
options_done:
        clc
        ret
parse_options endp

; Compare exactly CX option letters without consuming the caller's token.
match_option_word proc near
        push    si
        push    di
        push    cx
match_option_next:
        mov     al, byte ptr [si]
        and     al, 0DFh
        cmp     al, byte ptr [di]
        jne     match_option_bad
        inc     si
        inc     di
        loop    match_option_next
        clc
        jmp     short match_option_done
match_option_bad:
        stc
match_option_done:
        pop     cx
        pop     di
        pop     si
        ret
match_option_word endp

; Allow N?T0..3 or NR?T0..3, optionally followed by '$'. No paths,
; rewind-on-close aliases, wildcards or other DOS devices are accepted.
; Keep CX (the actual copy length) and SI unchanged, including on failure.
validate_tape_name proc near
        push    cx
        cmp     cx, 4
        jb      tape_name_bad
        cmp     cx, 6
        ja      tape_name_bad
        mov     di, si
        add     di, cx
        cmp     byte ptr [di-1], '$'
        jne     tape_name_base
        dec     cx
tape_name_base:
        mov     al, byte ptr [si]
        and     al, 0DFh
        cmp     al, 'N'
        jne     tape_name_bad
        mov     di, si
        inc     di
        cmp     cx, 4
        je      tape_name_letter
        cmp     cx, 5
        jne     tape_name_bad
        mov     al, byte ptr [di]
        and     al, 0DFh
        cmp     al, 'R'
        jne     tape_name_bad
        inc     di
tape_name_letter:
        mov     al, byte ptr [di]
        and     al, 0DFh
        cmp     al, 'A'
        jb      tape_name_bad
        cmp     al, 'Z'
        ja      tape_name_bad
        mov     al, byte ptr [di+1]
        and     al, 0DFh
        cmp     al, 'T'
        jne     tape_name_bad
        cmp     byte ptr [di+2], '0'
        jb      tape_name_bad
        cmp     byte ptr [di+2], '3'
        ja      tape_name_bad
        clc
        pop     cx
        ret
tape_name_bad:
        stc
        pop     cx
        ret
validate_tape_name endp

; Input DS:DX validated no-rewind alias; return AX handle with carry clear.
; After open, require a character device and set DOS raw mode. If either check
; fails, close the acquired handle while preserving the original error in AX;
; an ordinary file of the same name must not receive tape control requests.
open_raw proc near
        mov     ax, 3D00h
        int     21h
        jc      open_done
        mov     bx, ax
        mov     ax, 4400h
        int     21h
        jc      open_raw_failed
        test    dl, 80h                ; reject an ordinary file with this name
        jnz     open_character_device
        mov     dx, offset nondevice_error
        call    print_string
        mov     ax, 1
        jmp     short open_raw_failed
open_character_device:
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

; Try explicit function 0705h, then the historical 0702h 14-byte contract on
; failure. Normalize status/opcode/residual into the display's common slots while
; saving the 16-bit state/error separately. This is not length autodetection:
; a third-party 0702h using a different layout needs an explicit compatibility
; choice, not an assumption that our larger backing buffer reveals its ABI.
get_status proc near
        mov     bx, word ptr [handle]
        mov     cx, 0705h              ; explicit sixteen-byte ABI first
        mov     dx, offset status
        mov     ax, 440Ch
        int     21h
        jc      get_status_legacy
        mov     ax, word ptr [status+4]
        mov     word ptr [status_flags], ax
        mov     al, byte ptr [status+7]
        mov     byte ptr [status_error], al
        ; Normalize common fields for the existing display code.
        mov     ax, word ptr [status+10]
        mov     word ptr [status+8], ax
        mov     ax, word ptr [status+12]
        mov     word ptr [status+10], ax
        mov     ax, word ptr [status+14]
        mov     word ptr [status+12], ax
        clc
        ret
get_status_legacy:
        mov     byte ptr [status_error], 0
        mov     bx, word ptr [handle]
        mov     ch, IOCTL_TAPE
        mov     cl, IOCTL_MTGET
        mov     dx, offset status
        mov     ax, 440Ch
        int     21h
        jc      get_status_done
        xor     ah, ah
        mov     al, byte ptr [status+4]
        mov     word ptr [status_flags], ax
get_status_done:
        ret
get_status endp

; Explicit legacy MTNOP readiness request, distinct from cached status.
; A failure is this probe's DOS result, not proof that a saved write diagnostic
; belongs to the probe. The caller preserves AX before querying status again.
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
        call    print_tape_name
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
        mov     ax, word ptr [status_flags]
        call    print_hex16
        mov     dx, offset driver_error_message
        call    print_string
        mov     al, byte ptr [status_error]
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
        call    print_newline
        test    word ptr [status_flags], STATE_WRITE_ERROR
        jz      print_status_done
        mov     byte ptr [write_failure_seen], 1
        mov     dx, offset write_warning
        call    print_string
        mov     dx, offset recovery_warning
        call    print_string
print_status_done:
        ret
print_status endp

; DOS function 09h terminates at '$'; names must instead use a zero-terminated
; character loop so collision-avoiding device suffixes are printed intact.
print_tape_name proc near
        push    ax
        push    dx
        push    si
        mov     si, offset tape_name
print_name_next:
        mov     al, byte ptr [si]
        inc     si
        or      al, al
        jz      print_name_done
        mov     dl, al
        call    print_char
        jmp     short print_name_next
print_name_done:
        pop     si
        pop     dx
        pop     ax
        ret
print_tape_name endp

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

tape_name        db      'NRMT0', 0, 2 dup (0)
ready_word       db      'READY'
device_word      db      'DEVICE'
device_selected db      0
action           db      0
handle           dw      0
last_error       dw      0
control:
        dw      MTNOP
        dd      1
status           db      16 dup (0)
status_flags     dw      0
status_error     db      0
write_failure_seen db    0

address_message  db      ' ASPI address $'
flags_message    db      ' flags=$'
driver_error_message db  ' driver-error=$'
scsi_message     db      ' SCSI=$'
sense_message    db      ' sense=$'
opcode_message   db      ' opcode=$'
residual_message db      ' residual=$'
ready_message    db      'TEST UNIT READY completed', 13, 10, '$'
success_message  db      'OpenASPI TAPECTL status passed', 13, 10, '$'
saved_failure_message db 'OpenASPI TAPECTL saved write failure reported', 13, 10, '$'
write_warning    db      'WARNING: saved tape write/finalization failure.', 13, 10, '$'
recovery_warning db      'Readiness does not confirm backup success; application recovery is required.', 13, 10, '$'
open_error       db      'Cannot open $'
dos_error_suffix db      ', DOS error $'
nondevice_error  db      'Selected name is not a DOS character device.', 13, 10, '$'
option_error    db      'Invalid device selection. Use /DEVICE:NRMT0 or /DEVICE:NMT0 (non-rewinding names).', 13, 10, '$'
ioctl_error      db      'Cannot read ASPITAPE status, DOS error $'
ready_error      db      'TEST UNIT READY failed, DOS error $'
newline          db      13, 10, '$'
hex_digits       db      '0123456789ABCDEF'

        end     start
