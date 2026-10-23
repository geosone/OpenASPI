; Execute the real block driver entry points against memory-only ASPI.
; No installed manager, disk, or vendor driver is accessed.
        .8086
        option casemap:none
        .model tiny
        .code
        org 100h
        jmp test_start
ifdef TEST_FDD
FDD_DRIVER equ 1
endif
        include common/aspi/dos_aspi.inc
        include common/dos/devreq.inc
        include common/dos/blkdrv.inc
msg_banner db '$'
msg_no_device db '$'

REQUIRE_EQUAL macro
        local equal_ok
        je equal_ok
        jmp failed
equal_ok:
endm
EXPECT_STATUS macro expected
        call submit
        cmp word ptr [packet+RH_STATUS], expected
        REQUIRE_EQUAL
endm
EXPECT_WORD macro field, expected
        cmp word ptr [field], expected
        REQUIRE_EQUAL
endm

packet db 32 dup (0)
strategy_addr dw offset strategy, 0
interrupt_addr dw offset interrupt, 0
output_guard db 0A5h
output db 32 dup (0A5h)
output_end db 0A5h
phase dw 0
calls dw 0
bad db 0
mode db 0                       ; 0 superfloppy, 1 partitioned, 2 no media
boot db 0EBh, 3Ch, 90h
     db 'OPENASPI'
sample_bpb dw 512
     db 2
     dw 1
     db 2
     dw 112, 1440
     db 0F9h
     dw 3, 9, 2
     dd 0, 0
     db 0, 0
extended_sig db 29h
serial dd 11223344h
volume_label db 'TEST VOLUME'
filesystem db 'FAT12   '
     db 448 dup (0)
     dw 0AA55h
mbr db 446 dup (0)
     db 0, 0, 0, 0, 6, 0, 0, 0
     dd 32, 1440
     db 48 dup (0)
     dw 0AA55h
message_ok db 'Block IOCTL parameters/query tests passed',13,10,'$'
message_bad db 'Block IOCTL regression FAILED, phase $'

test_start:
        push cs
        pop ds
        push cs
        pop es
        cld
        mov ax, cs
        mov word ptr [strategy_addr+2], ax
        mov word ptr [interrupt_addr+2], ax
        mov word ptr [aspi_entry], offset fake_aspi
        mov word ptr [aspi_entry+2], ax
        mov byte ptr [unit_count], 1
        mov byte ptr [unit_table+U_FLAGS], UF_MEDIA or UF_REMOVABLE
        mov si, offset sample_bpb
        mov di, offset unit_table+U_DEFAULT_BPB
        mov cx, BPB_SIZE
        rep movsb
        mov si, offset sample_bpb
        mov di, offset unit_table+U_BPB
        mov cx, BPB_SIZE
        rep movsb
        ; Deliberately non-CS output segment, same physical buffer address.
        inc ax
        mov word ptr [packet+RH_IOCTL_PARAM+2], ax
        mov word ptr [packet+RH_IOCTL_PARAM], offset output-16
        mov byte ptr [packet+RH_LENGTH], 32
        mov byte ptr [packet+RH_IOCTL_CATEGORY], 8
        mov byte ptr [packet+RH_IOCTL_MINOR], 60h
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_QUERY
        EXPECT_STATUS ST_DONE
        EXPECT_WORD calls, 0
        inc word ptr [phase]
        mov byte ptr [packet+RH_COMMAND], CMD_GEN_IOCTL
        mov byte ptr [output], 4                ; default, uniform sectors
        EXPECT_STATUS ST_DONE
        EXPECT_WORD calls, 0
        EXPECT_WORD output+4, 80
        EXPECT_WORD output+7+BPB_TOTAL16, 1440
        cmp byte ptr [output+1], 7
        REQUIRE_EQUAL
        EXPECT_WORD output+2, 0                 ; no lock capability claim
        inc word ptr [phase]
        mov byte ptr [output], 1                ; current, refresh BPB
        mov word ptr [sample_bpb+BPB_TOTAL16], 2880
        EXPECT_STATUS ST_DONE
        EXPECT_WORD calls, 1
        EXPECT_WORD output+4, 160
        EXPECT_WORD output+7+BPB_TOTAL16, 2880
        inc word ptr [phase]
        mov byte ptr [output], 0                ; original defaults survived
        EXPECT_STATUS ST_DONE
        EXPECT_WORD calls, 1
        EXPECT_WORD output+7+BPB_TOTAL16, 1440
        inc word ptr [phase]
        mov byte ptr [mode], 1                  ; MBR + volume at LBA 32
        mov byte ptr [output], 1
        EXPECT_STATUS ST_DONE
        EXPECT_WORD calls, 3
        EXPECT_WORD output+7+BPB_HIDDEN, 32
        EXPECT_WORD output+4, 162                ; ceil((2880+32)/18)
        inc word ptr [phase]
        mov byte ptr [mode], 2
        call fill_output
        mov byte ptr [output], 1
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_NOT_READY
        call unchanged_output
        inc word ptr [phase]
        ; Supported-query result does not depend on a medium being present.
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_QUERY
        EXPECT_STATUS ST_DONE
        EXPECT_WORD calls, 4
        inc word ptr [phase]
        mov byte ptr [packet+RH_IOCTL_MINOR], 42h
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD
        mov byte ptr [packet+RH_COMMAND], CMD_GEN_IOCTL
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD
        call unchanged_output
        EXPECT_WORD calls, 4
        inc word ptr [phase]
        mov byte ptr [packet+RH_IOCTL_MINOR], 60h
        mov byte ptr [packet+RH_IOCTL_CATEGORY], 48h
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD
        mov byte ptr [packet+RH_IOCTL_CATEGORY], 8
        inc word ptr [phase]
        mov byte ptr [packet+RH_LENGTH], 16h
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD
        mov byte ptr [packet+RH_LENGTH], 32
        inc word ptr [phase]
        mov byte ptr [output], 2                ; invalid track-layout flag
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD
        mov byte ptr [output], 0
        mov word ptr [packet+RH_IOCTL_PARAM], 0FFE1h
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD
        mov word ptr [packet+RH_IOCTL_PARAM], offset output-16
        inc word ptr [phase]
        mov word ptr [packet+RH_IOCTL_PARAM], 0
        mov word ptr [packet+RH_IOCTL_PARAM+2], 0
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD
        mov word ptr [packet+RH_IOCTL_PARAM], offset output-16
        mov ax, cs
        inc ax
        mov word ptr [packet+RH_IOCTL_PARAM+2], ax
        inc word ptr [phase]
        mov byte ptr [packet+RH_UNIT], 1
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_UNIT
        mov byte ptr [packet+RH_UNIT], 0
        inc word ptr [phase]
        ; Fixed disks use cached current parameters without ASPI traffic.
        mov byte ptr [unit_table+U_FLAGS], UF_MEDIA
        mov byte ptr [output], 1
        EXPECT_STATUS ST_DONE
        EXPECT_WORD calls, 4
        EXPECT_WORD output+2, 1
        cmp byte ptr [output+1], 5
        REQUIRE_EQUAL
        inc word ptr [phase]
        ; Malformed/unrepresentable geometry must not divide-fault or write.
        call fill_output
        mov byte ptr [output], 1
        mov word ptr [unit_table+U_BPB+BPB_HEADS], 0
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA
        call unchanged_output
        mov word ptr [unit_table+U_BPB+BPB_HEADS], 0FFFFh
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA
        call unchanged_output
        mov word ptr [unit_table+U_BPB+BPB_HEADS], 1
        mov word ptr [unit_table+U_BPB+BPB_SPT], 1
        mov word ptr [unit_table+U_BPB+BPB_TOTAL16], 0
        mov word ptr [unit_table+U_BPB+BPB_HIDDEN], 0
        mov word ptr [unit_table+U_BPB+BPB_TOTAL32], 0
        mov word ptr [unit_table+U_BPB+BPB_TOTAL32+2], 1
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA
        call unchanged_output
        mov word ptr [unit_table+U_BPB+BPB_TOTAL32], 0FFFFh
        mov word ptr [unit_table+U_BPB+BPB_SPT], 2
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA
        call unchanged_output
        mov word ptr [unit_table+U_BPB+BPB_SPT], 1
        mov word ptr [unit_table+U_BPB+BPB_TOTAL32+2], 0FFFFh
        mov word ptr [unit_table+U_BPB+BPB_HIDDEN], 32
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA
        call unchanged_output
        inc word ptr [phase]
        mov byte ptr [packet+RH_COMMAND], CMD_IOCTL_QUERY
        mov byte ptr [packet+RH_LENGTH], 0Eh
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD
        mov byte ptr [packet+RH_LENGTH], 32
        mov byte ptr [packet+RH_IOCTL_MINOR], 0
        mov cx, 256
query_every_minor:
        call submit
        cmp byte ptr [packet+RH_IOCTL_MINOR], 60h
        je query_supported
        cmp byte ptr [packet+RH_IOCTL_MINOR], 66h
        je query_supported
        cmp word ptr [packet+RH_STATUS], ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD
        jmp short query_checked
query_supported:
        cmp word ptr [packet+RH_STATUS], ST_DONE
query_checked:
        REQUIRE_EQUAL
        inc byte ptr [packet+RH_IOCTL_MINOR]
        loop query_every_minor
        EXPECT_WORD calls, 4
        ; EDR-DOS query ABI: category/minor in legacy IOCTL byte count.
        mov byte ptr [packet+RH_LENGTH], 16h
        mov byte ptr [packet+RH_MEDIA], 0
        mov word ptr [packet+RH_COUNT], 0860h
        EXPECT_STATUS ST_DONE
        EXPECT_WORD packet+RH_COUNT, 0
        mov word ptr [packet+RH_COUNT], 0866h
        EXPECT_STATUS ST_DONE
        EXPECT_WORD packet+RH_COUNT, 0
        mov word ptr [packet+RH_COUNT], 0842h
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD
        mov word ptr [packet+RH_COUNT], 0860h
        mov byte ptr [packet+RH_COMMAND], CMD_GEN_IOCTL
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD
        EXPECT_WORD calls, 4
        inc word ptr [phase]
        mov word ptr [calls], 0
        mov byte ptr [mode], 0
        mov byte ptr [packet+RH_LENGTH], 32
        mov byte ptr [packet+RH_IOCTL_CATEGORY], 8
        mov byte ptr [packet+RH_IOCTL_MINOR], 66h
        ; Legacy EDR count overlaps the standard generic parameter pointer.
        mov word ptr [packet+RH_IOCTL_PARAM], offset output-16
        mov word ptr [sector_buf+27h], 0BEEFh    ; stale shared-sector contents
        call fill_output
        mov word ptr [output], 0
        EXPECT_STATUS ST_DONE
        EXPECT_WORD calls, 1
        call check_id
        inc word ptr [phase]
        mov byte ptr [mode], 1
        mov word ptr [serial], 7788h
        mov word ptr [serial+2], 5566h
        EXPECT_STATUS ST_DONE
        EXPECT_WORD calls, 3
        call check_id
        EXPECT_WORD output+2, 7788h
        EXPECT_WORD unit_table+U_START, 32
        inc word ptr [phase]
        call fill_output
        mov word ptr [output], 0
        mov byte ptr [mode], 2
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_NOT_READY
        call unchanged_id
        inc word ptr [phase]
        mov byte ptr [mode], 0
        mov byte ptr [extended_sig], 0
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA
        call unchanged_id
        mov byte ptr [extended_sig], 29h
        mov word ptr [sample_bpb+BPB_FATSIZE], 0
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_MEDIA
        call unchanged_id
        mov word ptr [sample_bpb+BPB_FATSIZE], 3
        inc word ptr [phase]
        mov word ptr [calls], 0
        mov word ptr [output], 0100h             ; info level is a WORD
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD
        mov word ptr [output], 0
        mov word ptr [packet+RH_IOCTL_PARAM], 0FFE8h
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD
        mov word ptr [packet+RH_IOCTL_PARAM], offset output-16
        mov word ptr [packet+RH_IOCTL_PARAM], 0
        mov word ptr [packet+RH_IOCTL_PARAM+2], 0
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD
        mov word ptr [packet+RH_IOCTL_PARAM], offset output-16
        mov ax, cs
        inc ax
        mov word ptr [packet+RH_IOCTL_PARAM+2], ax
        mov byte ptr [packet+RH_IOCTL_MINOR], 46h
        EXPECT_STATUS ST_DONE or ST_ERROR or ERR_UNKNOWN_CMD
        EXPECT_WORD calls, 0
        call unchanged_id
        cmp byte ptr [output_guard], 0A5h
        REQUIRE_EQUAL
        cmp byte ptr [output_end], 0A5h
        REQUIRE_EQUAL
        cmp byte ptr [bad], 0
        REQUIRE_EQUAL
        mov dx, offset message_ok
        mov ah, 09h
        int 21h
        mov ax, 4C00h
        int 21h
failed:
        mov dx, offset message_bad
        mov ah, 09h
        int 21h
        mov ax, word ptr [phase]
        aam
        add ax, 3030h
        mov dl, ah
        mov dh, al
        mov ah, 02h
        int 21h
        mov dl, dh
        int 21h
        mov ax, 4C01h
        int 21h

submit proc near
        push cs
        pop es
        mov bx, offset packet
        mov word ptr [packet+RH_STATUS], 0FFFFh
        call dword ptr [strategy_addr]
        call dword ptr [interrupt_addr]
        ret
submit endp
fill_output proc near
        push cs
        pop es
        mov di, offset output
        mov cx, 32
        mov al, 0A5h
        rep stosb
        ret
fill_output endp
unchanged_output proc near
        mov si, offset output+1
        mov cx, 31
unchanged_next:
        cmp byte ptr [si], 0A5h
        REQUIRE_EQUAL
        inc si
        loop unchanged_next
        ret
unchanged_output endp
check_id proc near
        push cs
        pop es
        mov si, offset serial
        mov di, offset output+2
        mov cx, 23
        repe cmpsb
        REQUIRE_EQUAL
        mov si, offset output+25
        mov cx, 7
        jmp short unchanged_id_bytes
check_id endp
unchanged_id proc near
        EXPECT_WORD output, 0
        mov si, offset output+2
        mov cx, 30
unchanged_id_bytes::
        cmp byte ptr [si], 0A5h
        REQUIRE_EQUAL
        inc si
        loop unchanged_id_bytes
        ret
unchanged_id endp

fake_aspi proc far
        push ds
        push cs
        pop ds
        inc word ptr [calls]
        cmp byte ptr [srb+SRB_CDB], 28h
        jne fake_bad
        cmp word ptr [srb+SRB_BufLen], 512
        jne fake_bad
        cmp byte ptr [srb+SRB_CDB+8], 1
        jne fake_bad
        cmp byte ptr [mode], 2
        je fake_absent
        mov si, offset boot
        cmp byte ptr [srb+SRB_CDB+5], 0
        jne fake_partition
        cmp byte ptr [mode], 1
        jne fake_copy
        mov si, offset mbr
        jmp short fake_copy
fake_partition:
        cmp byte ptr [srb+SRB_CDB+5], 32
        jne fake_bad
fake_copy:
        les di, dword ptr [srb+SRB_BufPointer]
        mov cx, 512
        rep movsb
        mov byte ptr [srb+SRB_Status], SS_COMP
        pop ds
        ret
fake_bad:
        mov byte ptr [bad], 1
fake_absent:
        mov byte ptr [srb+SRB_Status], SS_ERR
        mov byte ptr [srb+SRB_TargStat], 2
        mov byte ptr [srb+SRB_CDB+10+2], 2
        pop ds
        ret
fake_aspi endp
        end test_start
