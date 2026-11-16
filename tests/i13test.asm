; I13TEST.COM: checks ASPIDSK /I13's INT 13h drives (tests/dos_ntfs_i13.sh).
; For every hard disk 80h.. (count at 0040:0075): 41h, 48h, 08h, 15h,
; LBA 0 by 42h and by CHS 02h (must be equal), and the partition type of
; the first MBR entry.  I13TEST W: also write the last sector of the last
; drive by 43h, read it back by 42h and restore it; then the same with CHS
; sector 0/0/2 by 03h and 02h.
; Output lines "I13 dd ..." and "I13TEST PASSED" or "I13TEST FAILED".
        org     100h
        cld
        mov     si, 81h
        mov     byte [opt_write], 0
.args:  lodsb
        cmp     al, 13
        je      .go
        and     al, 0DFh
        cmp     al, 'W'
        jne     .args
        mov     byte [opt_write], 1
        jmp     .args
.go:    push    ds
        mov     ax, 40h
        mov     ds, ax
        mov     cl, [75h]
        pop     ds
        xor     ch, ch
        mov     [count], cl
        mov     byte [drive], 80h
.drive: cmp     cx, 0
        je      .writes
        push    cx
        call    check_drive
        pop     cx
        inc     byte [drive]
        dec     cx
        jmp     .drive
.writes:
        cmp     byte [opt_write], 0
        je      .end
        dec     byte [drive]
        call    write_test
.end:   cmp     byte [failed], 0
        jne     .bad
        mov     dx, msg_passed
        jmp     .out
.bad:   mov     dx, msg_failed
.out:   mov     ah, 9
        int     21h
        mov     ax, 4C00h
        int     21h

check_drive:
        mov     dx, msg_i13
        call    puts
        mov     al, [drive]
        call    hex8
        ; 41h
        mov     ah, 41h
        mov     bx, 55AAh
        mov     dl, [drive]
        int     13h
        jc      .noext
        cmp     bx, 0AA55h
        jne     .noext
        push    ax
        mov     dx, msg_ext
        call    puts
        pop     ax
        mov     al, ah
        call    hex8
        jmp     .p48
.noext: mov     dx, msg_noext
        call    puts
        ret                                     ; a BIOS disk without them
.p48:   ; 48h
        mov     word [edd], 1Eh
        mov     ah, 48h
        mov     dl, [drive]
        mov     si, edd
        int     13h
        jc      .fail48
        mov     dx, msg_sectors
        call    puts
        mov     ax, [edd+12h]
        call    hex16
        mov     ax, [edd+10h]
        call    hex16
        jmp     .p08
.fail48:
        call    fail
.p08:   ; 08h
        mov     ah, 08h
        mov     dl, [drive]
        int     13h
        jc      .fail08
        push    dx
        push    cx
        mov     dx, msg_chs
        call    puts
        pop     cx
        mov     al, cl
        and     al, 3Fh
        mov     [spt], al
        mov     al, ch
        call    hex8                            ; cylinder low
        pop     dx
        mov     [heads], dh
        mov     al, dh
        call    hex8
        mov     al, [spt]
        call    hex8
        jmp     .p15
.fail08:
        call    fail
.p15:   mov     ah, 15h
        mov     dl, [drive]
        int     13h
        jc      .fail15
        cmp     ah, 3
        je      .p42
.fail15:
        call    fail
.p42:   ; LBA 0 by 42h
        mov     word [dap], 10h
        mov     word [dap+2], 1
        mov     word [dap+4], buf1
        mov     [dap+6], ds
        xor     ax, ax
        mov     [dap+8], ax
        mov     [dap+10], ax
        mov     [dap+12], ax
        mov     [dap+14], ax
        mov     ah, 42h
        mov     dl, [drive]
        mov     si, dap
        int     13h
        jnc     .p02
        call    fail
        jmp     .crlf
.p02:   ; CHS 0/0/1 by 02h
        push    ds
        pop     es
        mov     ax, 0201h
        mov     cx, 0001h
        mov     dh, 0
        mov     dl, [drive]
        mov     bx, buf2
        int     13h
        jc      .fail02
        cmp     al, 1
        jne     .fail02
        mov     si, buf1
        mov     di, buf2
        mov     cx, 256
        repe cmpsw
        jne     .fail02
        mov     dx, msg_type
        call    puts
        mov     al, [buf1+1C2h]
        call    hex8
        mov     ax, [buf1+1FEh]
        call    hex16
        jmp     .crlf
.fail02:
        call    fail
.crlf:  mov     dx, msg_crlf
        jmp     puts

; the last drive: LBA (sectors - 1) by 43h and back, CHS sector 2 by 03h
write_test:
        mov     dx, msg_write
        call    puts
        mov     word [edd], 1Ah
        mov     ah, 48h
        mov     dl, [drive]
        mov     si, edd
        int     13h
        jc      .bad
        mov     ax, [edd+10h]
        mov     dx, [edd+12h]
        sub     ax, 1
        sbb     dx, 0
        mov     [lba], ax
        mov     [lba+2], dx
        ; keep the old contents
        mov     bx, buf1
        mov     ah, 42h
        call    ext_rw
        jc      .bad
        ; a pattern
        mov     di, buf2
        mov     cx, 512
        mov     al, 0
.pat:   stosb
        add     al, 7
        loop    .pat
        mov     bx, buf2
        mov     ah, 43h
        call    ext_rw
        jc      .bad
        mov     di, buf3
        mov     cx, 256
        xor     ax, ax
        rep stosw
        mov     bx, buf3
        mov     ah, 42h
        call    ext_rw
        jc      .bad
        mov     si, buf2
        mov     di, buf3
        mov     cx, 256
        repe cmpsw
        jne     .bad
        mov     bx, buf1                        ; restored
        mov     ah, 43h
        call    ext_rw
        jc      .bad
        ; CHS 0/0/2: read, write the pattern, read back, restore
        push    ds
        pop     es
        mov     ax, 0201h
        mov     cx, 2
        mov     dh, 0
        mov     dl, [drive]
        mov     bx, buf1
        int     13h
        jc      .bad
        mov     ax, 0301h
        mov     cx, 2
        mov     dh, 0
        mov     dl, [drive]
        mov     bx, buf2
        int     13h
        jc      .bad
        mov     ax, 0201h
        mov     cx, 2
        mov     dh, 0
        mov     dl, [drive]
        mov     bx, buf3
        int     13h
        jc      .bad
        mov     si, buf2
        mov     di, buf3
        mov     cx, 256
        repe cmpsw
        jne     .bad
        mov     ax, 0301h
        mov     cx, 2
        mov     dh, 0
        mov     dl, [drive]
        mov     bx, buf1
        int     13h
        jc      .bad
        mov     dx, msg_ok
        jmp     puts
.bad:   call    fail
        mov     dx, msg_crlf
        jmp     puts

; AH = 42h/43h: one sector at [lba] from/to DS:BX. CF.
ext_rw:
        mov     word [dap], 10h
        mov     word [dap+2], 1
        mov     [dap+4], bx
        mov     [dap+6], ds
        mov     bx, [lba]
        mov     [dap+8], bx
        mov     bx, [lba+2]
        mov     [dap+10], bx
        mov     word [dap+12], 0
        mov     word [dap+14], 0
        mov     al, 0
        mov     dl, [drive]
        mov     si, dap
        int     13h
        ret

fail:   mov     byte [failed], 1
        mov     dx, msg_fail
        jmp     puts

puts:   mov     ah, 9
        int     21h
        ret

hex16:  push    ax
        mov     al, ah
        call    hex8
        pop     ax
hex8:   push    ax
        shr     al, 4
        call    .nib
        pop     ax
.nib:   and     al, 0Fh
        add     al, '0'
        cmp     al, '9'
        jbe     .out
        add     al, 7
.out:   mov     dl, al
        mov     ah, 2
        int     21h
        ret

msg_i13     db  'I13 $'
msg_ext     db  ' ext $'
msg_noext   db  ' no extensions', 13, 10, '$'
msg_sectors db  ' sectors $'
msg_chs     db  ' chs $'
msg_type    db  ' type $'
msg_write   db  'I13 write $'
msg_ok      db  'ok', 13, 10, '$'
msg_fail    db  ' FAIL$'
msg_crlf    db  13, 10, '$'
msg_passed  db  'I13TEST PASSED', 13, 10, '$'
msg_failed  db  'I13TEST FAILED', 13, 10, '$'
opt_write   db  0
failed      db  0
count       db  0
drive       db  0
heads       db  0
spt         db  0
lba         dd  0
dap         times 16 db 0
edd         times 30 db 0
buf1        times 512 db 0
buf2        times 512 db 0
buf3        times 512 db 0
