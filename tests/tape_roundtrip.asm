; Destructive acceptance test for an explicitly selected virtual scratch tape.
; Host-side identity checks are mandatory; this COM cannot identify real media.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h

require_ok macro
        local ok
        jnc ok
        jmp failed
ok:
endm
require_equal macro
        local ok
        je ok
        jmp failed
ok:
endm

start:
        push cs
        pop ds
        cld
        xor cx, cx
        mov cl, byte ptr ds:[80h]
        mov si, 81h
skip_leading:
        or cx, cx
        jnz leading_character
        jmp usage
leading_character:
        cmp byte ptr [si], ' '
        je consume_leading
        cmp byte ptr [si], 9
        jne check_argument
consume_leading:
        inc si
        dec cx
        jmp skip_leading
check_argument:
        cmp cx, 8
        jae argument_length_ok
        jmp usage
argument_length_ok:
        sub cx, 8
        push cx
        mov di, offset scratch_argument
        mov cx, 8
        push ds
        pop es
        repe cmpsb
        pop cx
        je skip_trailing
        jmp usage
skip_trailing:
        jcxz arguments_ready
        lodsb
        dec cx
        cmp al, ' '
        je skip_trailing
        cmp al, 9
        je skip_trailing
        jmp usage
arguments_ready:
        mov ax, 3524h
        int 21h
        mov word ptr [old_int24], bx
        mov word ptr [old_int24+2], es
        mov dx, offset critical_error
        mov ax, 2524h
        int 21h
        mov dx, offset begin_message
        call print_message

        mov byte ptr [stage], 'O'
        call open_device
        mov byte ptr [stage], 'S'
        call check_status
        ; Newly loaded media can report UNIT ATTENTION once. Retry only TUR,
        ; never a write, and only when the reported sense key is exactly 6.
        mov byte ptr [ready_attempts], 3
ready_again:
        mov byte ptr [stage], 'T'
        mov word ptr [control], 7
        call run_mtop
        jnc ready
        call get_status
        require_ok
        cmp byte ptr [status+9], 6
        je ready_unit_attention
        jmp failed
ready_unit_attention:
        dec byte ptr [ready_attempts]
        jnz ready_again
        jmp failed
ready:
ifdef WRITE_PROTECT_TEST
        call check_write_protection
        call close_device
        call restore_int24
        mov dx, offset protect_success
        call print_message
        mov ax, 4C00h
        int 21h
endif
        mov byte ptr [stage], 'R'
        mov word ptr [control], 5
        call run_mtop
        require_ok
        mov dx, offset first_message
        call print_message
        mov word ptr [record_index], 0
        mov word ptr [record_end], 4
        mov byte ptr [stage], 'W'
        call write_records
        call close_device

        mov byte ptr [stage], 'A'
        call open_device
        mov byte ptr [stage], 'A'
        call check_status             ; do not hide an ignored close failure
        mov dx, offset append_message
        call print_message
        mov word ptr [record_index], 4
        mov word ptr [record_end], 6
        call write_records            ; append at NRMT0's close position
        call close_device

        mov byte ptr [stage], 'V'
        call open_device
        mov byte ptr [stage], 'V'
        call check_status
        mov word ptr [control], 5
        call run_mtop
        require_ok
        mov dx, offset verify_message
        call print_message
        call verify_files

        ; Repeat with an oversized buffer: five records must return short,
        ; including through legacy managers without ASPI residual support.
        mov byte ptr [stage], 'R'
        mov word ptr [control], 5
        call run_mtop
        require_ok
        mov word ptr [read_size], 4096
        mov dx, offset short_message
        call print_message
        call verify_files
        mov dx, offset newline
        call print_message
        mov dx, offset short_success
        call print_message
        call check_oversized_record
        call check_positioning
        call check_close_rewind
        call close_device
        call restore_int24
        mov dx, offset success_message
        call print_message
        mov ax, 4C00h
        int 21h

verify_files proc near
        mov word ptr [record_index], 0
        mov word ptr [record_end], 4
        mov byte ptr [stage], 'V'
        call read_records
        mov byte ptr [stage], 'F'
        call read_filemark
        mov word ptr [record_end], 6
        mov byte ptr [stage], 'v'
        call read_records
        mov byte ptr [stage], 'f'
        call read_filemark
        call read_filemark            ; two terminating marks from final close
        ret
verify_files endp

ifdef WRITE_PROTECT_TEST
check_write_protection proc near
        mov byte ptr [stage], 'W'
        call prepare_read_buffer        ; known payload; host requires WP first
        mov bx, word ptr [handle]
        mov cx, 512
        mov dx, offset buffer
        mov ah, 40h
        int 21h
        jc protected_write_failed
        jmp failed                      ; a successful write is never acceptable
protected_write_failed:
        call check_protected_status
        mov word ptr [control], 7        ; successful TUR cannot erase saved error
        call run_mtop
        require_ok
        call check_protected_status
        call close_device
        call open_device
        mov byte ptr [stage], 'W'
        call check_protected_status
        call run_mtop                   ; also catches erroneous close commands
        require_ok
        call check_protected_status
        ret
check_write_protection endp

check_protected_status proc near
        call get_status
        require_ok
        cmp byte ptr [status_extended+7], 7
        require_equal
        cmp byte ptr [status+8], 2
        require_equal
        cmp byte ptr [status+9], 7       ; DATA PROTECT
        require_equal
        cmp byte ptr [status+10], 0Ah    ; original WRITE, not a later TUR/close
        require_equal
        cmp word ptr [status+12], 512
        require_equal
        test word ptr [status_extended+4], 0200h
        jnz protected_error_saved
        jmp failed
protected_error_saved:
        test word ptr [status_extended+4], 0008h ; failed write is not WRITTEN
        require_equal
        ret
check_protected_status endp
protect_success db 'OpenASPI tape write-protect verification passed', 13, 10, '$'
endif

check_oversized_record proc near
        mov byte ptr [stage], 'N'
        mov dx, offset negative_message
        call print_message
        mov word ptr [control], 5
        call run_mtop
        require_ok
        mov word ptr [control], 3      ; skip the first two records
        mov word ptr [control+2], 2
        call run_mtop
        require_ok
        call prepare_read_buffer
        mov bx, word ptr [handle]
        mov cx, 256                   ; next physical record has 4096 bytes
        mov dx, offset buffer
        mov ah, 3Fh
        int 21h
        jc oversized_record_failed
        jmp failed
oversized_record_failed:
        call get_status
        require_ok
        cmp byte ptr [status_extended+7], 31
        require_equal
        cmp byte ptr [status+8], 2     ; CHECK CONDITION, NO SENSE + negative ILI
        require_equal
        cmp byte ptr [status+9], 0
        require_equal
        cmp word ptr [status+12], 256  ; DOS accepted none of the failed read
        require_equal
        test word ptr [status_extended+4], 0040h ; must not synthesize an EOF
        require_equal
        mov cx, 256                   ; DMA may change only the requested area
        call check_read_tail

        ; The oversized physical record was consumed, never replayed. The
        ; next explicit read must return the following 63-byte record.
        mov word ptr [record_index], 3
        mov word ptr [record_end], 4
        call read_records
        mov dx, offset newline
        call print_message
        mov dx, offset negative_success
        call print_message
        ret
check_oversized_record endp

check_positioning proc near
        mov byte ptr [stage], 'P'
        mov dx, offset position_message
        call print_message
        mov word ptr [read_size], 4096
        mov ax, 5                     ; REW -> BOT
        xor dx, dx
        call move_tape
        mov ax, 1                     ; FSF 1 -> start of second file
        mov dx, 1
        call move_tape
        mov ax, 4
        call read_one_record
        mov ax, 4                     ; BSR 1 -> before the same record
        mov dx, 1
        call move_tape
        mov ax, 4
        call read_one_record
        mov ax, 3                     ; FSR 1 skips second file's final record
        mov dx, 1
        call move_tape
        call read_filemark            ; consume first terminating filemark
        mov ax, 2                     ; BSF 2 -> BOT side of inter-file mark
        mov dx, 2
        call move_tape
        call read_filemark            ; reverse file spacing stops before it
        mov ax, 4
        call read_one_record

        ; Block spacing must stop at a filemark, not silently skip into the
        ; next file. After the reported error, the next read is in file two.
        mov byte ptr [stage], 'B'
        mov ax, 5
        xor dx, dx
        call move_tape
        mov word ptr [control], 3
        mov word ptr [control+2], 6    ; first file contains only four records
        call run_mtop
        jc spacing_boundary_failed
        jmp failed
spacing_boundary_failed:
        call get_status
        require_ok
        cmp byte ptr [status_extended+7], 31
        require_equal
        cmp byte ptr [status+8], 2
        require_equal
        cmp byte ptr [status+9], 0
        require_equal
        test word ptr [status_extended+4], 0040h
        require_equal
        mov ax, 4
        call read_one_record
        mov ax, 5                     ; leave successful tests at known BOT
        xor dx, dx
        call move_tape
        mov dx, offset newline
        call print_message
        mov dx, offset position_success
        call print_message
        ret
check_positioning endp

; AX = mtop operation, DX = unsigned 16-bit magnitude (encoded by driver).
move_tape proc near
        mov word ptr [control], ax
        mov word ptr [control+2], dx
        mov word ptr [control+4], 0
        call run_mtop
        require_ok
        call check_status
        ret
move_tape endp

; AX = expected record index in the existing deterministic data pattern.
read_one_record proc near
        mov word ptr [record_index], ax
        inc ax
        mov word ptr [record_end], ax
        call read_records
        ret
read_one_record endp

check_close_rewind proc near
        mov byte ptr [stage], 'C'
        mov dx, offset close_message
        call print_message
        mov ax, 0                     ; positioning phase left NRMT0 at BOT
        call read_one_record
        call close_device
        call open_device              ; NRMT0 close/open must retain position
        mov byte ptr [stage], 'C'
        call check_status
        test word ptr [status_extended+4], 0100h
        require_equal
        mov ax, 1
        call read_one_record
        call close_device

        mov dx, offset rewind_name
        call open_named_device        ; opening RMT0 itself must not rewind
        mov byte ptr [stage], 'C'
        call check_status
        mov ax, 2
        call read_one_record
        call close_device             ; final RMT0 close initiates rewind
        call open_device
        mov byte ptr [stage], 'C'
        call check_close_status
        mov ax, 0                     ; pending rewind must finish before READ
        call read_one_record
        call check_status
        test word ptr [status_extended+4], 0100h
        require_equal
        call close_device

        mov byte ptr [stage], 'c'
        mov dx, offset rewind_name
        call open_named_device
        mov byte ptr [stage], 'c'
        call check_status
        call close_device             ; even an untouched RMT0 handle rewinds
        call open_device
        mov byte ptr [stage], 'c'
        call check_close_status
        mov ax, 0
        call read_one_record
        call check_status
        test word ptr [status_extended+4], 0100h
        require_equal
        ; A nonfinal RMT0 close must not rewind an existing NRMT0 session.
        mov ax, word ptr [handle]
        mov word ptr [retained_handle], ax
        mov dx, offset rewind_name
        call open_named_device
        call close_device
        mov ax, word ptr [retained_handle]
        mov word ptr [handle], ax
        mov byte ptr [stage], 'L'
        call check_status
        test word ptr [status_extended+4], 0100h
        require_equal
        mov ax, 1                     ; original NRMT0 position was after record 0
        call read_one_record
        mov ax, 5                     ; leave successful acceptance runs at BOT
        xor dx, dx
        call move_tape
        mov dx, offset newline
        call print_message
        mov dx, offset close_success
        call print_message
        ret
check_close_rewind endp

check_close_status proc near
        call check_status
ifdef IMMEDIATE_CLOSE
        test word ptr [status_extended+4], 0100h
        jnz close_pending_expected
        jmp failed
close_pending_expected:
else
        test word ptr [status_extended+4], 0100h
        require_equal
endif
        ret
check_close_status endp

write_records proc near
write_next:
        call record_parameters
        push ds
        pop es
        mov di, offset buffer
        push cx
fill_next:
        stosb
        inc al
        loop fill_next
        pop cx
        push cx
        mov bx, word ptr [handle]
        mov dx, offset buffer
        mov ah, 40h
        int 21h
        require_ok
        pop cx
        cmp ax, cx
        require_equal
        call check_status
        inc word ptr [record_index]
        mov ax, word ptr [record_index]
        cmp ax, word ptr [record_end]
        jb write_next
        ret
write_records endp

read_records proc near
read_next:
        mov dl, '.'
        mov ah, 02h
        int 21h
        call record_parameters
        push cx
        call prepare_read_buffer
        cmp word ptr [read_size], 0
        je read_size_ready
        mov cx, word ptr [read_size]
read_size_ready:
        mov bx, word ptr [handle]
        mov dx, offset buffer
        mov ah, 3Fh
        int 21h
        require_ok
        pop cx
        cmp ax, cx
        require_equal
        call record_parameters
        mov si, offset buffer
compare_next:
        cmp byte ptr [si], al
        require_equal
        inc si
        inc al
        loop compare_next
        call record_parameters
        call check_read_tail
        call check_status
        call record_parameters
        mov ax, word ptr [read_size]
        or ax, ax
        jz read_residual_ready          ; exact-size pass expects zero residual
        sub ax, cx
read_residual_ready:
        cmp word ptr [status+12], ax
        require_equal
        inc word ptr [record_index]
        mov ax, word ptr [record_index]
        cmp ax, word ptr [record_end]
        jb read_next
        ret
read_records endp

prepare_read_buffer proc near
        push ax
        push cx
        push di
        push es
        push ds
        pop es
        mov di, offset buffer
        mov cx, 4112                  ; data plus trailing sixteen-byte guard
        mov al, 0A5h
        rep stosb
        pop es
        pop di
        pop cx
        pop ax
        ret
prepare_read_buffer endp

; CX = returned payload length. Every byte after it must remain untouched.
check_read_tail proc near
        mov si, offset buffer
        add si, cx
        mov ax, 4112
        sub ax, cx
        mov cx, ax
check_tail_next:
        cmp byte ptr [si], 0A5h
        require_equal
        inc si
        loop check_tail_next
        ret
check_read_tail endp

record_parameters proc near
        mov bx, word ptr [record_index]
        shl bx, 1
        mov cx, word ptr [record_lengths+bx]
        mov ax, word ptr [record_index]
        mov ah, 17
        mul ah                        ; reproducible byte ramp for each record
        ret
record_parameters endp

read_filemark proc near
        mov dl, '|'
        mov ah, 02h
        int 21h
        call prepare_read_buffer
        mov bx, word ptr [handle]
        mov cx, 4096
        mov dx, offset buffer
        mov ah, 3Fh
        int 21h
        require_ok
        or ax, ax
        require_equal
        xor cx, cx
        call check_read_tail
        call check_status
        cmp word ptr [status+12], 4096
        require_equal
        ret
read_filemark endp

open_device proc near
        mov dx, offset tape_name
        jmp open_named_device
open_device endp

; DX names a tape alias; the character-device/raw-mode checks are shared.
open_named_device proc near
        mov ax, 3D02h
        int 21h
        require_ok
        mov word ptr [handle], ax
        mov bx, ax
        mov byte ptr [stage], 'D'
        mov ax, 4400h
        int 21h
        require_ok
        test dl, 80h                  ; never write an ordinary NRMT0 file
        jnz device_is_character
        jmp failed
device_is_character:
        or dl, 20h
        xor dh, dh
        mov byte ptr [stage], 'd'
        mov ax, 4401h
        int 21h
        require_ok
        ret
open_named_device endp

close_device proc near
        mov bx, word ptr [handle]
        mov ah, 3Eh
        int 21h
        mov word ptr [handle], 0FFFFh
        require_ok
        ret
close_device endp

check_status proc near
        call get_status
        require_ok
        mov byte ptr [status_phase], 1
        test word ptr [status_extended+4], 0200h
        require_equal
        mov byte ptr [status_phase], 2
        cmp byte ptr [status_extended+7], 0
        require_equal
        mov byte ptr [status_phase], 3
        test byte ptr [status+3], 1    ; this acceptance scenario is variable mode
        jz status_variable
        jmp failed
status_variable:
        ret
check_status endp

get_status proc near
        jmp checked_mtget
get_status endp
run_mtop proc near
        mov bx, word ptr [handle]
        mov cx, 0701h
        mov dx, offset control
        mov ax, 440Ch
        int 21h
        ret
run_mtop endp
print_message proc near
        mov ah, 09h
        int 21h
        ret
print_message endp
restore_int24 proc near
        push ds
        mov dx, word ptr [old_int24]
        mov ax, word ptr [old_int24+2]
        mov ds, ax
        mov ax, 2524h
        int 21h
        pop ds
        ret
restore_int24 endp
critical_error proc far
        mov al, 3
        iret
critical_error endp
failed:
        ; No command or data retry here. DOS handles process-exit closes.
        mov word ptr [failure_ax], ax
        cmp word ptr [handle], 0FFFFh
        je failure_status_ready
        call get_status
failure_status_ready:
        call restore_int24
        mov dx, offset failure_message
        call print_message
        mov dl, byte ptr [stage]
        mov ah, 02h
        int 21h
        mov dx, offset newline
        call print_message
        mov dx, offset diagnostic_message
        call print_message
        mov al, byte ptr [status_extended+7]
        call print_hex_byte
        mov al, byte ptr [status+3]
        call print_hex_byte
        mov al, byte ptr [status_phase]
        call print_hex_byte
        mov dl, ' '
        mov ah, 02h
        int 21h
        mov al, byte ptr [status+8]
        call print_hex_byte
        mov al, byte ptr [status+9]
        call print_hex_byte
        mov al, byte ptr [status+10]
        call print_hex_byte
        mov al, byte ptr [status+11]
        call print_hex_byte
        mov al, byte ptr [status+12]
        call print_hex_byte
        mov al, byte ptr [failure_ax+1]
        call print_hex_byte
        mov al, byte ptr [failure_ax]
        call print_hex_byte
        mov dx, offset newline
        call print_message
        mov ax, 4C01h
        int 21h
usage:
        mov dx, offset usage_message
        call print_message
        mov ax, 4C02h
        int 21h

print_hex_byte proc near
        push ax
        push cx
        mov cl, 4
        shr al, cl
        call print_hex_digit
        pop cx
        pop ax
        and al, 0Fh
print_hex_digit:
        and al, 0Fh
        add al, '0'
        cmp al, '9'
        jbe hex_digit_ready
        add al, 7
hex_digit_ready:
        mov dl, al
        mov ah, 02h
        int 21h
        ret
print_hex_byte endp

scratch_argument db '/SCRATCH'
tape_name db 'NRMT0', 0
rewind_name db 'RMT0', 0
handle dw 0FFFFh
retained_handle dw 0FFFFh
old_int24 dd 0
stage db '?'
ready_attempts db 0
status_phase db 0
failure_ax dw 0
record_index dw 0
record_end dw 0
read_size dw 0
record_lengths dw 512, 1024, 4096, 63, 2048, 511
control dw 7
        dd 0
        include tests/tape_status.inc
status db 18 dup (0)
buffer db 4096 dup (0)
buffer_guard db 16 dup (0)
begin_message db 'OpenASPI virtual scratch tape acceptance test', 13, 10, '$'
first_message db 'Writing four variable records in first file', 13, 10, '$'
append_message db 'Appending two variable records in second file', 13, 10, '$'
verify_message db 'Rewinding and comparing all six records and filemarks', 13, 10, '$'
short_message db 13, 10, 'Repeating reads with guarded 4096-byte buffers', 13, 10, '$'
short_success db 'OpenASPI tape short-record verification passed: 6 records, guarded buffers', 13, 10, '$'
negative_message db 'Rejecting a 4096-byte record in a guarded 256-byte buffer', 13, 10, '$'
negative_success db 'OpenASPI tape oversized-record rejection passed', 13, 10, '$'
position_message db 'Checking forward/backward record and filemark positioning', 13, 10, '$'
position_success db 'OpenASPI tape positioning verification passed', 13, 10, '$'
close_message db 'Checking RMT0/NRMT0 close and reopen positions', 13, 10, '$'
ifdef IMMEDIATE_CLOSE
close_success db 'OpenASPI tape close-rewind verification passed: immediate', 13, 10, '$'
else
close_success db 'OpenASPI tape close-rewind verification passed: synchronous', 13, 10, '$'
endif
success_message db 'OpenASPI tape roundtrip passed: 8254 bytes, 6 records, 2 files', 13, 10, '$'
failure_message db 'OpenASPI tape roundtrip FAILED at stage $'
diagnostic_message db 'Hex: driver/parameter/check SCSI/sense/opcode/residual-low/DOS-AX: $'
usage_message db 'Virtual scratch media only: TAPERW /SCRATCH', 13, 10, '$'
newline db 13, 10, '$'
        end start
