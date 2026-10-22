; Real-manager scratch qualification, included by tape_roundtrip.asm.
; Uses its raw-device open checks, status ABI checks and guarded buffer.
check_buffered_roundtrip proc near
        mov byte ptr [stage], 'K'
        mov dx, offset buffered_message
        call print_message
        call close_device              ; previous phase left raw NRMT0 at BOT
        mov dx, offset buffered_name
        call open_named_device
        call check_buffered_status
        mov word ptr [stream_index], 0
        mov word ptr [stream_offset], 0
buffered_write_next:
        call prepare_read_buffer
        mov bx, word ptr [stream_index]
        mov cx, word ptr [stream_requests+bx]
        push cx
        push ds
        pop es
        mov di, offset buffer
stream_fill_next:
        mov ax, word ptr [stream_offset]
        mov al, ah                     ; distinguish physical records/positions
        xor al, 5Ch
        stosb
        inc word ptr [stream_offset]
        loop stream_fill_next
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
        call check_read_tail           ; no write may overrun its input
        call check_buffered_status
        mov ax, 7                      ; TUR must not discard partial writes
        xor dx, dx
        call move_tape
        add word ptr [stream_index], 2
        cmp word ptr [stream_index], 6
        jb buffered_write_next
        call close_device              ; flush 452 bytes plus 572 zero padding

        ; Verify physical record boundaries and padding independently through
        ; raw NRMT0: exactly three 1024-byte records must precede the marks.
        call open_device
        mov byte ptr [stage], 'k'
        call check_status
        test byte ptr [status+4], 1
        require_equal
        mov ax, 5
        xor dx, dx
        call move_tape
        mov word ptr [stream_offset], 0
buffered_raw_next:
        mov cx, 1024
        mov word ptr [stream_expected], cx
        call read_stream_chunk
        cmp word ptr [stream_offset], 3072
        jb buffered_raw_next
        call read_filemark
        call read_filemark
        mov ax, 5
        xor dx, dx
        call move_tape
        call close_device

        ; Now split and combine those physical records through NMT0. The
        ; final 1900-byte request must stop short at the first filemark.
        mov dx, offset buffered_name
        call open_named_device
        mov byte ptr [stage], 'K'
        call check_buffered_status
        mov word ptr [stream_offset], 0
        mov word ptr [stream_index], 0
buffered_read_next:
        mov bx, word ptr [stream_index]
        mov ax, word ptr [stream_returns+bx]
        mov word ptr [stream_expected], ax
        mov cx, word ptr [stream_reads+bx]
        call read_stream_chunk
        call check_buffered_status
        mov ax, 7                      ; TUR must retain unread cache and EOF
        xor dx, dx
        call move_tape
        add word ptr [stream_index], 2
        cmp word ptr [stream_index], 6
        jb buffered_read_next
        ; mtget describes the last command, not an aggregate buffered request.
        ; TUR above left residual zero; synthetic EOF submits no new command.
        mov word ptr [filemark_residual], 0
        call read_filemark             ; deferred EOF after the short data
        mov word ptr [filemark_residual], 1024 ; next EOF is a physical refill
        call read_filemark             ; second physical terminating mark
        mov word ptr [filemark_residual], 4096
        mov ax, 5
        xor dx, dx
        call move_tape
        call close_device
        mov dx, offset buffered_rewind_name
        call open_named_device
        mov byte ptr [stage], 'K'
        call check_buffered_status
        test byte ptr [status+4], 4
        jnz buffered_rewind_selected
        jmp failed
buffered_rewind_selected:
        mov word ptr [stream_offset], 0
        mov word ptr [stream_expected], 300
        mov cx, 300
        call read_stream_chunk         ; leave unread data in MT0's cache
        call close_device              ; final MT0 close must discard and rewind
        call open_device
        mov byte ptr [stage], 'K'
        call check_close_status
        mov word ptr [stream_offset], 0
        mov word ptr [stream_expected], 1024
        mov cx, 1024
        call read_stream_chunk         ; prove BOT, not the cached/next record
        test word ptr [status_extended+4], 0100h
        require_equal
        mov ax, 5
        xor dx, dx
        call move_tape                 ; restore caller's raw handle at BOT
        call check_status
        mov dx, offset buffered_success
        call print_message
        ret
check_buffered_roundtrip endp

check_buffered_status proc near
        call check_status
        test byte ptr [status+4], 1
        jnz buffered_status_ok
        jmp failed
buffered_status_ok:
        ret
check_buffered_status endp

; CX = DOS request size; stream_expected = expected accepted byte count.
; Check every returned byte, including the zero padding from buffered close.
read_stream_chunk proc near
        call prepare_read_buffer
        mov bx, word ptr [handle]
        mov dx, offset buffer
        mov ah, 3Fh
        int 21h
        require_ok
        cmp ax, word ptr [stream_expected]
        require_equal
        mov cx, ax
        mov si, offset buffer
stream_verify_next:
        mov ax, word ptr [stream_offset]
        mov al, ah
        xor al, 5Ch
        cmp word ptr [stream_offset], 2500
        jb stream_byte_ready
        xor al, al
stream_byte_ready:
        cmp byte ptr [si], al
        require_equal
        inc si
        inc word ptr [stream_offset]
        loop stream_verify_next
        mov cx, word ptr [stream_expected]
        call check_read_tail
        call check_status
        ret
read_stream_chunk endp

buffered_name db 'NMT0', 0
buffered_rewind_name db 'MT0', 0
stream_index dw 0
stream_offset dw 0
stream_expected dw 0
stream_requests dw 300, 900, 1300
stream_reads dw 300, 900, 1900
stream_returns dw 300, 900, 1872
buffered_message db 'Checking buffered writes, physical records, padding and split reads', 13, 10, '$'
buffered_success db 'OpenASPI tape buffered-roundtrip verification passed', 13, 10, '$'
