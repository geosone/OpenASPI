; Buffered aliases: physical records, filemarks, IOCTL invalidation and errors.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h

expect_ok macro
        local ok
        jnc ok
        jmp failed
ok:
endm
expect_equal macro
        local ok
        je ok
        jmp failed
ok:
endm
expect_error macro
        local ok
        jc ok
        jmp failed
ok:
endm

start:
        push cs
        pop ds
        mov ax, 3524h
        int 21h
        mov word ptr [old_int24], bx
        mov word ptr [old_int24+2], es
        mov dx, offset critical_error
        mov ax, 2524h
        int 21h
ifdef BUFFER_DISABLED
        mov dx, offset mt_name
        mov ax, 3D00h
        int 21h
        expect_error
        cmp ax, 2
        expect_equal
        mov dx, offset nmt_name
        mov ax, 3D00h
        int 21h
        expect_error
        cmp ax, 2
        expect_equal
        jmp success
else
ifdef BUFFER_DISCARD
        jmp discard_scenario
endif
ifdef BUFFER_ERROR
        jmp error_scenario
endif
        mov byte ptr [stage], '1'
        mov dx, offset mt_name
        call open_raw
        expect_ok
        mov word ptr [handle], ax
        mov byte ptr [stage], 'A'
        call get_status
        expect_ok
        cmp byte ptr [status+4], 5
        expect_equal
        mov byte ptr [stage], 'B'
        mov dx, offset raw_name
        call open_raw                ; DOS does not reliably fail device opens
        expect_ok
        mov word ptr [handle2], ax
        mov bx, ax
        mov cx, 2
        mov dx, offset buffer
        mov ah, 3Fh
        int 21h                     ; mixed-mode data transfers must fail
        expect_error
        mov bx, word ptr [handle2]
        mov ah, 3Eh
        int 21h
        expect_ok
        mov byte ptr [stage], 'C'
        call close_handle
        expect_ok
        mov byte ptr [stage], 'D'
        mov dx, offset nmt_name
        call open_raw
        expect_ok
        mov word ptr [handle], ax

        mov byte ptr [stage], '2'
ifdef BUFFER_SINGLE
        mov cx, 1
        mov ax, 1
        call read_expect
        mov word ptr [far_count], 299
else
        mov bx, word ptr [handle]
        mov cx, 1
        mov dx, offset buffer
        mov ah, 3Fh
        int 21h
        expect_error
        mov bx, word ptr [handle]
        mov cx, 1
        mov dx, offset buffer
        mov ah, 40h
        int 21h
        expect_error
endif
        ; Cross a 64K offset boundary with the caller's far transfer pointer.
        ; Keep the COM's 64K stack segment and allocate a separate 68K block.
        push ds
        pop es
        mov bx, 1000h
        mov ah, 4Ah
        int 21h
        expect_ok
        mov bx, 1100h
        mov ah, 48h
        int 21h
        expect_ok
        mov word ptr [far_segment], ax
        inc ax
        mov bx, word ptr [handle]
        mov cx, word ptr [far_count]
        push ds
        mov ds, ax
        mov dx, 0FFF0h
        mov ah, 3Fh
        int 21h
        pop ds
        expect_ok
        cmp ax, word ptr [far_count]
        expect_equal
        mov ax, word ptr [far_segment]
        add ax, 1000h
        mov es, ax
        xor di, di
        mov cx, word ptr [far_count]
        mov al, 'A'
        repe scasb
        expect_equal
        ; The next read combines the remainder of A with a new B record.
        mov cx, 900
        mov ax, 900
        call read_expect
        mov si, offset buffer
        mov cx, 724
        mov al, 'A'
        call verify_bytes
        mov cx, 176
        mov al, 'B'
        call verify_bytes
        mov word ptr [control], 7     ; TUR must preserve the read cache
        call run_mtop
        expect_ok
        mov cx, 848
        mov ax, 848
        call read_expect
        mov si, offset buffer
        mov cx, 848
        mov al, 'B'
        call verify_bytes
        mov cx, 2000
        xor ax, ax
        call read_expect             ; filemark without data

        mov byte ptr [stage], '3'
ifdef FIXED_BLOCK
        mov cx, 2200
        mov ax, 2048
else
        mov cx, 1100
        mov ax, 1036
endif
        call read_expect
        mov si, offset buffer
        mov cx, 1024
        mov al, 'C'
        call verify_bytes
ifdef FIXED_BLOCK
        mov cx, 1024
else
        mov cx, 12
endif
        mov al, 'X'
        call verify_bytes
        mov cx, 16
        xor ax, ax
        call read_expect             ; exactly one deferred zero-byte EOF
        mov cx, 16
        mov ax, 16
        call read_expect
        mov si, offset buffer
        mov cx, 16
        mov al, 'D'
        call verify_bytes
        mov word ptr [control], 3     ; MTFSR discards the unread D cache
        mov word ptr [control+2], 1
        call run_mtop
        expect_ok
        mov cx, 8
        mov ax, 8
        call read_expect
        mov si, offset buffer
        mov cx, 8
        mov al, 'E'
        call verify_bytes

        mov byte ptr [stage], '4'
        push ds
        pop es
        mov di, offset buffer
        mov cx, 600
        mov al, 'Q'
        rep stosb
        mov cx, 600
        call write_expect
        mov di, offset buffer
        mov cx, 700
        mov al, 'R'
        rep stosb
        mov cx, 700
        call write_expect
        mov bx, word ptr [handle]
        mov dx, offset buffer
        mov cx, 2
        mov ah, 3Fh
        int 21h
        expect_error                 ; reject reading after buffered writes
        mov word ptr [control], 3
        mov word ptr [control+4], 0100h
        call run_mtop                ; rejected counts must preserve the tail
        expect_error
        mov word ptr [control+2], 0
        mov word ptr [control+4], 0080h
        call run_mtop                ; +800000h must not move backwards
        expect_error
        mov word ptr [control], 1
        call run_mtop
        expect_error
        mov word ptr [control+2], 0FFFFh
        mov word ptr [control+4], 00FFh
        call run_mtop                ; +FFFFFFh must not become SPACE -1
        expect_error
        mov word ptr [control], 3
        call run_mtop
        expect_error
        mov word ptr [control+2], 1
        mov word ptr [control+4], 0
        mov word ptr [control], 7
        call run_mtop                ; TUR must preserve the write tail
        expect_ok
        xor cx, cx
        call write_expect
        call close_handle            ; 276 R bytes, 748 zeros, two filemarks
        expect_ok
        jmp check_final_event

ifdef BUFFER_DISCARD
discard_scenario:
        mov byte ptr [stage], 'T'
        mov dx, offset nmt_name
        call open_raw
        expect_ok
        mov word ptr [handle], ax
        mov cx, 10
        call write_expect
        mov word ptr [control], 3
        mov word ptr [control+2], 1
        call run_mtop               ; movement discards the unwritten tail
        expect_ok
        call close_handle           ; filemarks but no padded data record
        expect_ok
        jmp check_final_event
endif
ifdef BUFFER_ERROR
error_scenario:
        mov byte ptr [stage], 'E'
ifdef RAW_WRITE_TEST
        mov dx, offset raw_name
else
ifdef FINAL_RAW
ifdef FINAL_REWIND_ERROR
        mov dx, offset rmt_raw_name
else
        mov dx, offset raw_name
endif
else
ifdef FINAL_REWIND_ERROR
        mov dx, offset mt_name
else
        mov dx, offset nmt_name
endif
endif
endif
        call open_raw
        expect_ok
        mov word ptr [handle], ax
        push ds
        pop es
        mov di, offset buffer
        mov cx, 1100
        mov al, 'Z'
        rep stosb
ifdef EXPLICIT_MARK_ERROR
        mov word ptr [control], 0
        mov word ptr [control+2], 2
        call run_mtop
        expect_error
        call verify_write_error
        ; A readiness success must not acknowledge the failed filemarks.
        mov word ptr [control], 7
        call run_mtop
        expect_ok
        call verify_write_error
else
ifdef BUFFER_WRITE_ERROR
        mov bx, word ptr [handle]
        mov dx, offset buffer
ifdef RAW_WRITE_TEST
        mov cx, 1024
else
        mov cx, 1100
endif
ifdef RAW_EOT_IGNORE
        mov cx, 0703h
        mov dx, offset status
        mov ax, 440Ch
        int 21h
        expect_ok
        mov bx, word ptr [handle]
        mov dx, offset buffer
        mov cx, 1024
endif
        mov ah, 40h
        int 21h
        expect_error
        mov byte ptr [stage], 'a'
        call verify_write_error
        mov word ptr [control], 7
        mov byte ptr [stage], 'b'
        call run_mtop                ; readiness must not erase the write error
        expect_ok
        mov byte ptr [stage], 'c'
        call verify_write_error
        mov word ptr [control], 8
        call run_mtop                ; nor may a later invalid operation
        expect_error
        mov byte ptr [stage], 'd'
        call verify_write_error
        mov bx, word ptr [handle]
        mov dx, offset buffer
ifdef RAW_WRITE_TEST
        mov cx, 1                    ; guard rejection must not replace cause
else
        mov cx, 2
endif
        mov ah, 40h
        int 21h
        expect_error
        mov byte ptr [stage], 'e'
        call verify_write_error
ifdef RAW_WRITE_TEST
ifdef FIXED_BLOCK
        mov bx, word ptr [handle]
        mov dx, offset buffer
        mov cx, 2                    ; not an integral mandatory tape block
        mov ah, 40h
        int 21h
        expect_error
        call verify_write_error
endif
endif
ifdef RAW_RETRY
        mov cx, 1024
        call write_expect            ; explicit raw retry, never driver replay
        call verify_write_recovered
endif
else
ifdef FINAL_EMPTY
        xor cx, cx
        call write_expect            ; SvarDOS short-circuits empty DOS writes
        call get_status
        expect_ok
        test byte ptr [status+4], 8
        expect_equal                 ; no written-session state was delivered
else
ifdef FINAL_RAW
        mov cx, 1024
        call write_expect            ; finalization fails after a full raw write
else
        mov cx, 3
        call write_expect            ; error will occur while padding on close
endif
endif
endif
endif
        mov byte ptr [stage], 'f'
        call close_handle            ; DOS may ignore device-close errors
        mov dx, offset raw_name
        call open_raw
        expect_ok
        mov word ptr [handle], ax
        mov byte ptr [stage], 'g'
        call get_status
        expect_ok
ifdef RAW_RETRY
        call verify_write_recovered
else
        call verify_write_error
endif
        jmp final_tur
endif
check_final_event:
        mov byte ptr [stage], '5'
        mov dx, offset raw_name
        call open_raw
        expect_ok
        mov word ptr [handle], ax
final_tur:
        mov word ptr [control], 7
        call run_mtop                ; proves every prior expected CDB occurred
        expect_ok
ifdef BUFFER_ERROR
ifdef RAW_RETRY
        call verify_write_recovered
else
        call verify_write_error
endif
endif
        call close_handle
        expect_ok
ifdef BUFFER_RECOVERY
ifndef RAW_RETRY
        call recover_write
endif
endif
endif
success:
        call restore_int24
        mov dx, offset success_message
        mov ah, 09h
        int 21h
        mov ax, 4C00h
        int 21h
failed:
        call restore_int24
        mov dx, offset failure_message
        mov ah, 09h
        int 21h
        mov dl, byte ptr [stage]
        mov ah, 02h
        int 21h
        mov ax, 4C01h
        int 21h

ifdef BUFFER_ERROR
verify_write_error proc near
        call get_status
        expect_ok
ifdef FINAL_EMPTY
        cmp word ptr [status+8], 0
        expect_equal
        cmp byte ptr [status_extended+7], 0
        expect_equal
        test word ptr [status_extended+4], 0200h
        expect_equal
        ret
else
ifdef FINAL_ERROR
        cmp byte ptr [status+8], 2
        expect_equal
        cmp byte ptr [status+9], 3
        expect_equal
        cmp byte ptr [status_extended+7], 3
        expect_equal
        cmp word ptr [status+12], 0
        expect_equal
ifdef FINAL_MARK_ERROR
        cmp byte ptr [status+10], 10h
else
ifdef FINAL_SPACE_ERROR
        cmp byte ptr [status+10], 11h
else
        cmp byte ptr [status+10], 1
endif
endif
        expect_equal
else
ifdef RAW_BAD_RESIDUAL
        cmp word ptr [status+8], 0
        expect_equal
        cmp byte ptr [status_extended+7], 31
        expect_equal
        cmp word ptr [status+12], 1024
        expect_equal
else
ifdef BUFFER_SHORT_WRITE
ifdef RAW_EOT
        cmp byte ptr [status+8], 2
else
        cmp byte ptr [status+8], 0
endif
        expect_equal
        cmp byte ptr [status+9], 0
        expect_equal
        cmp byte ptr [status_extended+7], 31
        expect_equal
        cmp word ptr [status+12], 512
        expect_equal
else
        cmp byte ptr [status+8], 2
        expect_equal
        cmp byte ptr [status+9], 7
        expect_equal
        cmp byte ptr [status_extended+7], 7
        expect_equal
        cmp word ptr [status+12], 1024
        expect_equal
endif
endif
        cmp byte ptr [status+10], 0Ah
        expect_equal
endif
        mov ax, word ptr [status_extended+4]
        and ax, 0200h
        cmp ax, 0200h
        expect_equal
        ret
endif
verify_write_error endp
endif

ifdef BUFFER_RECOVERY
recover_write proc near
        mov byte ptr [stage], 'R'
ifdef BUFFER_RAW_RECOVERY
        mov dx, offset raw_name
else
        mov dx, offset nmt_name
endif
        call open_raw
        expect_ok
        mov word ptr [handle], ax
        call verify_write_error       ; opening must not acknowledge failure
ifdef BUFFER_RAW_RECOVERY
        mov cx, 1024
else
        xor cx, cx
        call write_expect             ; no physical write, error must survive
        call verify_write_error
        mov cx, 3
        call write_expect             ; buffering is not physical completion
        call verify_write_error
        mov cx, 1021
endif
        call write_expect
        call verify_write_recovered
        call close_handle
        expect_ok
        mov dx, offset raw_name
        call open_raw
        expect_ok
        mov word ptr [handle], ax
        mov word ptr [control], 7
        call run_mtop
        expect_ok
        call verify_write_recovered
        call close_handle
        expect_ok
        ret
recover_write endp
verify_write_recovered proc near
        call get_status
        expect_ok
        test word ptr [status_extended+4], 0200h
        expect_equal
        cmp byte ptr [status_extended+7], 0
        expect_equal
        cmp word ptr [status+8], 0
        expect_equal
        cmp word ptr [status+12], 0
        expect_equal
        ret
verify_write_recovered endp
endif

read_expect proc near
        push ax
        mov bx, word ptr [handle]
        mov dx, offset buffer
        mov ah, 3Fh
        int 21h
        expect_ok
        pop dx
        cmp ax, dx
        expect_equal
        ret
read_expect endp
write_expect proc near
        push cx
        mov bx, word ptr [handle]
        mov dx, offset buffer
        mov ah, 40h
        int 21h
        expect_ok
        pop dx
        cmp ax, dx
        expect_equal
        ret
write_expect endp
verify_bytes proc near
verify_next:
        cmp byte ptr [si], al
        expect_equal
        inc si
        loop verify_next
        ret
verify_bytes endp
open_raw proc near
        mov ax, 3D02h
        int 21h
        jc open_done
        mov bx, ax
        mov ax, 4400h
        int 21h
        jc open_done
        or dl, 20h
        xor dh, dh
        mov ax, 4401h
        int 21h
        jc open_done
        mov ax, bx
open_done:
        ret
open_raw endp
close_handle proc near
        mov bx, word ptr [handle]
        mov ah, 3Eh
        int 21h
        ret
close_handle endp
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
restore_int24 proc near
        push ds
        mov dx, word ptr cs:[old_int24]
        mov ax, word ptr cs:[old_int24+2]
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
ifdef BUFFER_RENAMED
mt_name db 'ST0$', 0
nmt_name db 'NST0$', 0
raw_name db 'NRST0$', 0
else
mt_name db 'MT0', 0
nmt_name db 'NMT0', 0
raw_name db 'NRMT0', 0
endif
rmt_raw_name db 'RMT0', 0
stage db '?'
handle dw 0
handle2 dw 0
far_segment dw 0
far_count dw 300
old_int24 dd 0
        include tests/tape_status.inc
status db 18 dup (0)
control dw 7
        dd 0
buffer db 2300 dup (0)
success_message db 'OpenASPI buffered tape smoke test passed', 13, 10, '$'
failure_message db 'OpenASPI buffered tape smoke test FAILED at stage $'
        end start
