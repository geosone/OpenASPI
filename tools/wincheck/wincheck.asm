; WINCHECK.COM - report the Windows environment hosting this DOS program.
;
; Exit status with /WIN, /3X, /9X or /DOS: 0 = requested environment,
; 1 = another environment. /Q suppresses the report. With no selector the
; program succeeds under any Windows DOS box and reports the detected class.

        .8086
        option  casemap:none

        .model  tiny
        .code
        org     100h

ENV_DOS         equ 0
ENV_WIN3        equ 1
ENV_WIN9        equ 2

WANT_WINDOWS    equ 0
WANT_WIN3       equ 1
WANT_WIN9       equ 2
WANT_DOS        equ 3

start:
        push    cs
        pop     ds
        cld
        call    detect_environment
        call    parse_command_line
        call    report_environment
        call    result_matches
        mov     ah, 4Ch
        int     21h

; INT 2Fh/AX=1600h identifies an active Windows enhanced-mode DOS box.
; The true DOS version separates Windows 9x (DOS 7/8) from Windows 3.x.
detect_environment proc near
        mov     byte ptr [environment], ENV_DOS
        mov     ax, 1600h
        int     2Fh
        or      al, al
        jz      environment_done
        cmp     al, 80h
        je      environment_done
        mov     byte ptr [environment], ENV_WIN3
        mov     ax, 3306h
        xor     bx, bx
        int     21h
        cmp     bh, 7
        jb      environment_done
        mov     byte ptr [environment], ENV_WIN9
environment_done:
        ret
detect_environment endp

parse_command_line proc near
        mov     si, 81h
        xor     ch, ch
        mov     cl, byte ptr [80h]
argument_next:
        jcxz    argument_done
        lodsb
        dec     cx
        cmp     al, '/'
        je      argument_switch
        cmp     al, '-'
        jne     argument_next
argument_switch:
        jcxz    argument_done
        lodsb
        dec     cx
        cmp     al, 'a'
        jb      argument_upper
        cmp     al, 'z'
        ja      argument_upper
        sub     al, 20h
argument_upper:
        cmp     al, 'Q'
        jne     argument_win9
        mov     byte ptr [quiet], 1
        jmp     argument_next
argument_win9:
        cmp     al, '9'
        jne     argument_win3
        mov     byte ptr [wanted], WANT_WIN9
        jmp     argument_next
argument_win3:
        cmp     al, '3'
        jne     argument_dos
        mov     byte ptr [wanted], WANT_WIN3
        jmp     argument_next
argument_dos:
        cmp     al, 'D'
        jne     argument_windows
        mov     byte ptr [wanted], WANT_DOS
        jmp     argument_next
argument_windows:
        cmp     al, 'W'
        jne     argument_next
        mov     byte ptr [wanted], WANT_WINDOWS
        jmp     argument_next
argument_done:
        ret
parse_command_line endp

report_environment proc near
        cmp     byte ptr [quiet], 0
        jne     report_done
        mov     dx, offset msg_dos
        cmp     byte ptr [environment], ENV_DOS
        je      report_print
        mov     dx, offset msg_win3
        cmp     byte ptr [environment], ENV_WIN3
        je      report_print
        mov     dx, offset msg_win9
report_print:
        mov     ah, 09h
        int     21h
report_done:
        ret
report_environment endp

; Return AL=0 for a match, AL=1 otherwise.
result_matches proc near
        mov     al, 1
        mov     ah, byte ptr [wanted]
        cmp     ah, WANT_WINDOWS
        jne     result_exact
        cmp     byte ptr [environment], ENV_DOS
        je      result_done
        xor     al, al
        ret
result_exact:
        cmp     ah, WANT_DOS
        jne     result_not_dos
        cmp     byte ptr [environment], ENV_DOS
        jne     result_done
        xor     al, al
        ret
result_not_dos:
        cmp     ah, byte ptr [environment]
        jne     result_done
        xor     al, al
result_done:
        ret
result_matches endp

msg_dos         db 'OpenASPI environment: DOS', 13, 10, '$'
msg_win3        db 'OpenASPI environment: Windows 3.x', 13, 10, '$'
msg_win9        db 'OpenASPI environment: Windows 9x/ME', 13, 10, '$'
environment     db ENV_DOS
wanted          db WANT_WINDOWS
quiet           db 0

        end     start
