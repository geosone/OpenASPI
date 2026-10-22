; ASPICDA.SYS: OpenASPI CD/DVD driver.
;
; A DOS CD-ROM device driver (the MSCDEX driver interface) for SCSI
; multimedia devices (peripheral type 05h) behind an installed ASPI manager
; such as AHCIASPI or EUSBASPI.  MSCDEX or SHSUCDX gives the drives letters:
;
;   DEVICE=ASPICDA.SYS /D:ASPICDA0
;   SHSUCDX /D:ASPICDA0         (or MSCDEX /D:ASPICDA0)
;
; Reads are cooked (2048 bytes, READ(10)) or raw (2352 bytes, READ CD), so
; the CD-audio SHSUCDX (deps/shsucd, /A:ON) can hand digital audio sectors to
; VSBHDA.  Addresses are HSG (LBA) or Red Book (MSF).
;
; Options: /D:name  device name (default ASPICDA0)
;          /V       list the drives found

        .8086
        option casemap:none

        .model tiny
        .code
        org     0

        include common/aspi/dos_aspi.inc
        include common/dos/devreq.inc

MAX_UNITS       equ     8
CHUNK_SECTORS   equ     16              ; 16 * 2352 bytes stay below 64 KB
DEV_ATTR        equ     0C800h          ; character, IOCTL, open/close
TOC_SIZE        equ     4 + 100 * 8

; device status (IOCTL input 6): door unlocked, cooked and raw reads,
; data read only, audio play, HSG and Red Book addressing
CD_STATUS       equ     0216h

OPT_VERBOSE     equ     01h

; drive capabilities (MODE SENSE page 2Ah), the 4th byte of a unit entry
CAP_KNOWN       equ     80h             ; page 2Ah was read
CAP_ANALOG      equ     01h             ; plays audio (analog output)
CAP_CDDA        equ     02h             ; reads audio sectors (READ CD)
CAP_ACCURATE    equ     04h             ; CD-DA stream is accurate
UNIT_ENTRY      equ     4

driver_start:
        dd      0FFFFFFFFh
        dw      DEV_ATTR
        dw      strategy
        dw      interrupt
device_name     db      'ASPICDA0'
        dw      0                       ; reserved
        db      0                       ; drive letter (set by MSCDEX)
unit_count      db      0

request_ptr     dd      0

; the drives: host adapter, target, LUN, capabilities
unit_table      db      MAX_UNITS * UNIT_ENTRY dup (0)

strategy proc far
        mov     word ptr cs:[request_ptr], bx
        mov     word ptr cs:[request_ptr+2], es
        ret
strategy endp

interrupt proc far
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        push    cs
        pop     ds
        cld
        ; DOS calls block drivers with a small stack, and the ASPI manager
        ; needs more: a stack of our own
        mov     word ptr [caller_ss], ss
        mov     word ptr [caller_sp], sp
        cli
        push    cs
        pop     ss
        mov     sp, offset driver_stack_top
        sti
        les     bx, [request_ptr]
        mov     al, byte ptr es:[bx+RH_COMMAND]
        cmp     al, CMD_INIT
        jne     not_init
        jmp     init_request
not_init:
        mov     si, offset command_table
next_command:
        cmp     byte ptr [si], 0FFh
        je      unknown_command
        cmp     al, byte ptr [si]
        je      found_command
        add     si, 3
        jmp     next_command
found_command:
        call    select_unit
        jc      request_failed
        les     bx, [request_ptr]
        call    word ptr [si+1]
        jc      request_failed
request_ok:
        les     bx, [request_ptr]
        mov     word ptr es:[bx+RH_STATUS], ST_DONE
        jmp     short request_done
unknown_command:
        mov     al, ERR_UNKNOWN_CMD
request_failed:
        les     bx, [request_ptr]
        xor     ah, ah
        or      ax, ST_ERROR or ST_DONE
        mov     word ptr es:[bx+RH_STATUS], ax
request_done::
        cli
        mov     ss, word ptr cs:[caller_ss]
        mov     sp, word ptr cs:[caller_sp]
        sti
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
interrupt endp

; command, handler: CF and AL = DOS error code on failure
command_table:
        db      CMD_IOCTL_IN
        dw      ioctl_input
        db      CMD_INPUT_FLUSH
        dw      do_nothing
        db      CMD_OUTPUT_FLUSH
        dw      do_nothing
        db      CMD_IOCTL_OUT
        dw      ioctl_output
        db      CMD_OPEN
        dw      do_nothing
        db      CMD_CLOSE
        dw      do_nothing
        db      CMD_READ_LONG
        dw      read_long
        db      CMD_READ_PREFETCH
        dw      do_nothing
        db      CMD_SEEK
        dw      do_nothing
        db      CMD_PLAY_AUDIO
        dw      play_audio
        db      CMD_STOP_AUDIO
        dw      stop_audio
        db      CMD_RESUME_AUDIO
        dw      resume_audio
        db      0FFh

do_nothing proc near
        clc
        ret
do_nothing endp

; the drive of the request (subunit) -> unit_ha/unit_target/unit_lun
select_unit proc near
        mov     al, byte ptr es:[bx+RH_UNIT]
        cmp     al, byte ptr [unit_count]
        jb      select_unit_ok
        mov     al, ERR_UNKNOWN_UNIT
        stc
        ret
select_unit_ok:
        mov     ah, UNIT_ENTRY
        mul     ah
        mov     di, ax
        mov     al, byte ptr [unit_table+di]
        mov     byte ptr [unit_ha], al
        mov     al, byte ptr [unit_table+di+1]
        mov     byte ptr [unit_target], al
        mov     al, byte ptr [unit_table+di+2]
        mov     byte ptr [unit_lun], al
        clc
        ret
select_unit endp

; CF set: AL = DOS error code of the failed SCSI command
scsi_failed proc near
        call    aspi_result
        jnc     scsi_failed_ok
        call    sense_to_doserr
        stc
scsi_failed_ok:
        ret
scsi_failed endp

; Red Book (byte 0 frame, 1 second, 2 minute) in DX:AX -> LBA in DX:AX
msf_to_lba proc near
        push    bx
        push    cx
        mov     bl, al                          ; frame
        mov     cl, ah                          ; second
        mov     al, dl                          ; minute
        mov     ah, 60
        mul     ah
        xor     ch, ch
        add     ax, cx
        mov     cx, 75
        mul     cx
        xor     bh, bh
        add     ax, bx
        adc     dx, 0
        sub     ax, 150
        sbb     dx, 0
        pop     cx
        pop     bx
        ret
msf_to_lba endp

; LBA in DX:AX -> Red Book in DX:AX (AL frame, AH second, DL minute)
lba_to_msf proc near
        push    bx
        push    cx
        add     ax, 150
        adc     dx, 0
        mov     cx, 75
        div     cx                              ; AX = seconds, DX = frame
        mov     bl, dl
        xor     dx, dx
        mov     cx, 60
        div     cx                              ; AX = minutes, DX = seconds
        mov     ah, dl
        mov     dl, al
        mov     al, bl
        xor     dh, dh
        pop     cx
        pop     bx
        ret
lba_to_msf endp

; the start address of a READ LONG / PLAY request -> LBA in DX:AX
request_lba proc near
        mov     ax, word ptr es:[bx+RH_CD_START]
        mov     dx, word ptr es:[bx+RH_CD_START+2]
        cmp     byte ptr es:[bx+RH_CD_ADDRMODE], 0
        je      request_lba_done
        call    msf_to_lba
request_lba_done:
        ret
request_lba endp

;-----------------------------------------------------------------------------
; READ LONG: cooked (2048 bytes, READ(10)) or raw (2352 bytes, READ CD)
;-----------------------------------------------------------------------------

read_lba        dw      0, 0
read_left       dw      0
read_buffer     dw      0, 0
read_raw        db      0
read_flags      db      0               ; READ CD byte 9

read_long proc near
        mov     cx, word ptr es:[bx+RH_CD_COUNT]
        mov     word ptr [read_left], cx
        call    request_lba
        mov     word ptr [read_lba], ax
        mov     word ptr [read_lba+2], dx
        mov     ax, word ptr es:[bx+RH_CD_BUFFER]
        mov     word ptr [read_buffer], ax
        mov     ax, word ptr es:[bx+RH_CD_BUFFER+2]
        mov     word ptr [read_buffer+2], ax
        mov     al, byte ptr es:[bx+RH_CD_READMODE]
        cmp     al, 1
        jbe     read_mode_ok
        mov     al, ERR_UNKNOWN_CMD
        stc
        ret
read_mode_ok:
        mov     byte ptr [read_raw], al
        mov     byte ptr [read_flags], 0F8h     ; sync, headers, data, EDC
read_next:
        mov     cx, word ptr [read_left]
        jcxz    read_done
        cmp     cx, CHUNK_SECTORS
        jbe     read_chunk
        mov     cx, CHUNK_SECTORS
read_chunk:
        call    read_sectors
        jnc     read_advance
        cmp     al, 08h                         ; ILLEGAL REQUEST: audio
        jne     read_failed                     ; sectors, user data only
        cmp     byte ptr [read_raw], 0
        je      read_failed
        cmp     byte ptr [read_flags], 10h
        je      read_failed
        mov     byte ptr [read_flags], 10h
        jmp     read_next
read_advance:
        sub     word ptr [read_left], cx
        add     word ptr [read_lba], cx
        adc     word ptr [read_lba+2], 0
        mov     ax, 128                         ; 2048 / 16 paragraphs
        cmp     byte ptr [read_raw], 0
        je      read_step
        mov     ax, 147                         ; 2352 / 16
read_step:
        mul     cx
        add     word ptr [read_buffer+2], ax
        jmp     read_next
read_done:
        clc
        ret
read_failed:
        stc
        ret
read_long endp

; CX sectors at read_lba into read_buffer.  CF and AL = DOS error.
read_sectors proc near
        push    cx
        mov     al, SRB_DIR_IN
        mov     cl, 10
        cmp     byte ptr [read_raw], 0
        je      read_prepare
        mov     cl, 12
read_prepare:
        call    aspi_prepare
        pop     cx
        mov     ax, word ptr [read_buffer]
        mov     word ptr [srb+SRB_BufPointer], ax
        mov     ax, word ptr [read_buffer+2]
        mov     word ptr [srb+SRB_BufPointer+2], ax
        mov     ax, word ptr [read_lba+2]
        xchg    al, ah
        mov     word ptr [srb+SRB_CDB+2], ax
        mov     ax, word ptr [read_lba]
        xchg    al, ah
        mov     word ptr [srb+SRB_CDB+4], ax
        cmp     byte ptr [read_raw], 0
        jne     read_cd
        mov     byte ptr [srb+SRB_CDB], 28h     ; READ(10)
        mov     byte ptr [srb+SRB_CDB+7], ch
        mov     byte ptr [srb+SRB_CDB+8], cl
        mov     ax, 2048
        jmp     short read_length
read_cd:
        mov     byte ptr [srb+SRB_CDB], 0BEh    ; READ CD, any sector type
        mov     byte ptr [srb+SRB_CDB+7], ch
        mov     byte ptr [srb+SRB_CDB+8], cl
        mov     al, byte ptr [read_flags]
        mov     byte ptr [srb+SRB_CDB+9], al
        mov     ax, 2352
read_length:
        push    cx
        mul     cx
        mov     word ptr [srb+SRB_BufLen], ax
        call    call_aspi
        pop     cx
        jmp     scsi_failed
read_sectors endp

;-----------------------------------------------------------------------------
; IOCTL input
;-----------------------------------------------------------------------------

ioctl_input proc near
        les     di, dword ptr es:[bx+RH_BUFFER]
        mov     al, byte ptr es:[di]
        mov     si, offset ioctl_in_table
ioctl_in_next:
        cmp     byte ptr [si], 0FFh
        je      ioctl_unknown
        cmp     al, byte ptr [si]
        je      ioctl_in_found
        add     si, 3
        jmp     ioctl_in_next
ioctl_in_found:
        jmp     word ptr [si+1]                 ; ES:DI = control block
ioctl_unknown:
        mov     al, ERR_UNKNOWN_CMD
        stc
        ret
ioctl_input endp

ioctl_in_table:
        db      0
        dw      ioctl_header_address
        db      6
        dw      ioctl_device_status
        db      7
        dw      ioctl_sector_size
        db      8
        dw      ioctl_volume_size
        db      9
        dw      ioctl_media_changed
        db      10
        dw      ioctl_disk_info
        db      11
        dw      ioctl_track_info
        db      0FFh

ioctl_header_address:
        mov     word ptr es:[di+1], 0
        mov     word ptr es:[di+3], cs
        clc
        ret

ioctl_device_status:
        mov     word ptr es:[di+1], CD_STATUS
        mov     word ptr es:[di+3], 0
        clc
        ret

ioctl_sector_size:
        mov     ax, 2048
        cmp     byte ptr es:[di+1], 0
        je      sector_size_ready
        mov     ax, 2352
sector_size_ready:
        mov     word ptr es:[di+2], ax
        clc
        ret

ioctl_volume_size:
        push    es
        push    di
        mov     al, SRB_DIR_IN
        mov     cl, 10
        call    aspi_prepare
        mov     byte ptr [srb+SRB_CDB], 25h     ; READ CAPACITY
        mov     word ptr [srb+SRB_BufLen], 8
        mov     word ptr [srb+SRB_BufPointer], offset capacity_data
        mov     word ptr [srb+SRB_BufPointer+2], cs
        call    call_aspi
        pop     di
        pop     es
        call    scsi_failed
        jc      volume_size_done
        mov     ax, word ptr [capacity_data+2]   ; last LBA, big-endian
        xchg    al, ah
        mov     dx, word ptr [capacity_data]
        xchg    dl, dh
        add     ax, 1
        adc     dx, 0
        mov     word ptr es:[di+1], ax
        mov     word ptr es:[di+3], dx
        clc
volume_size_done:
        ret

; 1 unchanged, 0FFh changed (UNIT ATTENTION), 0 don't know
ioctl_media_changed:
        push    es
        push    di
        mov     al, SRB_DIR_NONE
        mov     cl, 6
        call    aspi_prepare                    ; TEST UNIT READY: CDB zero
        call    call_aspi
        call    aspi_result
        pop     di
        pop     es
        mov     ah, 1
        jnc     media_changed_ready
        mov     ah, 0FFh
        cmp     al, 06h
        je      media_changed_ready
        mov     ah, 0
media_changed_ready:
        mov     byte ptr es:[di+1], ah
        clc
        ret

; lowest track, highest track, lead-out (Red Book)
ioctl_disk_info:
        call    read_toc
        jc      disk_info_done
        mov     al, byte ptr [toc_data+2]
        mov     byte ptr es:[di+1], al
        mov     al, byte ptr [toc_data+3]
        mov     byte ptr es:[di+2], al
        mov     al, 0AAh                        ; lead-out
        call    find_toc_track
        jc      disk_info_done
        call    store_toc_msf
        mov     word ptr es:[di+3], ax
        mov     word ptr es:[di+5], dx
        clc
disk_info_done:
        ret

; track start (Red Book) and control/ADR of track es:[di+1]
ioctl_track_info:
        call    read_toc
        jc      track_info_done
        mov     al, byte ptr es:[di+1]
        call    find_toc_track
        jc      track_info_done
        call    store_toc_msf
        mov     word ptr es:[di+2], ax
        mov     word ptr es:[di+4], dx
        mov     al, byte ptr [toc_data+si+1]    ; ADR (high), CONTROL (low)
        mov     cl, 4
        rol     al, cl
        mov     byte ptr es:[di+6], al
        clc
track_info_done:
        ret

; READ TOC in MSF form into toc_data.  Keeps ES:DI.
read_toc proc near
        push    es
        push    di
        mov     al, SRB_DIR_IN
        mov     cl, 10
        call    aspi_prepare
        mov     byte ptr [srb+SRB_CDB], 43h     ; READ TOC
        mov     byte ptr [srb+SRB_CDB+1], 02h   ; MSF
        mov     byte ptr [srb+SRB_CDB+7], high TOC_SIZE
        mov     byte ptr [srb+SRB_CDB+8], low TOC_SIZE
        mov     word ptr [srb+SRB_BufLen], TOC_SIZE
        mov     word ptr [srb+SRB_BufPointer], offset toc_data
        mov     word ptr [srb+SRB_BufPointer+2], cs
        call    call_aspi
        pop     di
        pop     es
        jmp     scsi_failed
read_toc endp

; AL = track -> SI = offset of its descriptor in toc_data; CF if missing
find_toc_track proc near
        mov     cx, word ptr [toc_data]         ; data length, big-endian
        xchg    cl, ch
        sub     cx, 2
        jbe     toc_missing
        mov     si, 4
toc_search:
        cmp     byte ptr [toc_data+si+2], al
        je      toc_found
        add     si, 8
        cmp     si, TOC_SIZE
        jae     toc_missing
        sub     cx, 8
        ja      toc_search
toc_missing:
        mov     al, ERR_NOT_FOUND
        stc
        ret
toc_found:
        clc
        ret
find_toc_track endp

; descriptor SI (0, M, S, F) -> DX:AX in Red Book order (F, S, M, 0)
store_toc_msf proc near
        mov     al, byte ptr [toc_data+si+7]
        mov     ah, byte ptr [toc_data+si+6]
        mov     dl, byte ptr [toc_data+si+5]
        xor     dh, dh
        ret
store_toc_msf endp

;-----------------------------------------------------------------------------
; IOCTL output: eject, lock/unlock, reset, close tray
;-----------------------------------------------------------------------------

ioctl_output proc near
        les     di, dword ptr es:[bx+RH_BUFFER]
        mov     al, byte ptr es:[di]
        cmp     al, 0
        je      eject_disk
        cmp     al, 1
        je      lock_door
        cmp     al, 2
        je      reset_drive
        cmp     al, 5
        je      close_tray
        mov     al, ERR_UNKNOWN_CMD
        stc
        ret
eject_disk:
        mov     ah, 02h                         ; LoEj, stop
        jmp     short start_stop
close_tray:
        mov     ah, 03h                         ; LoEj, start
start_stop:
        push    ax
        mov     al, SRB_DIR_NONE
        mov     cl, 6
        call    aspi_prepare
        pop     ax
        mov     byte ptr [srb+SRB_CDB], 1Bh     ; START STOP UNIT
        mov     byte ptr [srb+SRB_CDB+4], ah
        call    call_aspi
        jmp     scsi_failed
lock_door:
        mov     ah, byte ptr es:[di+1]          ; 1 lock, 0 unlock
        and     ah, 1
        push    ax
        mov     al, SRB_DIR_NONE
        mov     cl, 6
        call    aspi_prepare
        pop     ax
        mov     byte ptr [srb+SRB_CDB], 1Eh     ; PREVENT ALLOW MEDIUM REMOVAL
        mov     byte ptr [srb+SRB_CDB+4], ah
        call    call_aspi
        jmp     scsi_failed
reset_drive:
        clc
        ret
ioctl_output endp

;-----------------------------------------------------------------------------
; analog audio: PLAY AUDIO MSF, PAUSE/RESUME
;-----------------------------------------------------------------------------

play_audio proc near
        mov     cx, word ptr es:[bx+RH_CD_PLAYCOUNT]
        or      cx, word ptr es:[bx+RH_CD_PLAYCOUNT+2]
        jz      play_done
        call    request_lba
        push    dx
        push    ax
        add     ax, word ptr es:[bx+RH_CD_PLAYCOUNT]
        adc     dx, word ptr es:[bx+RH_CD_PLAYCOUNT+2]
        call    lba_to_msf
        mov     word ptr [play_end], ax
        mov     byte ptr [play_end+2], dl
        pop     ax
        pop     dx
        call    lba_to_msf
        push    dx
        push    ax
        mov     al, SRB_DIR_NONE
        mov     cl, 10
        call    aspi_prepare
        pop     ax
        pop     dx
        mov     byte ptr [srb+SRB_CDB], 47h     ; PLAY AUDIO MSF
        mov     byte ptr [srb+SRB_CDB+3], dl    ; start M, S, F
        mov     byte ptr [srb+SRB_CDB+4], ah
        mov     byte ptr [srb+SRB_CDB+5], al
        mov     al, byte ptr [play_end+2]       ; end M, S, F
        mov     byte ptr [srb+SRB_CDB+6], al
        mov     al, byte ptr [play_end+1]
        mov     byte ptr [srb+SRB_CDB+7], al
        mov     al, byte ptr [play_end]
        mov     byte ptr [srb+SRB_CDB+8], al
        call    call_aspi
        jmp     scsi_failed
play_done:
        clc
        ret
play_audio endp

stop_audio proc near
        xor     ah, ah                          ; pause
        jmp     short pause_resume
stop_audio endp

resume_audio proc near
        mov     ah, 1
resume_audio endp

pause_resume proc near
        push    ax
        mov     al, SRB_DIR_NONE
        mov     cl, 10
        call    aspi_prepare
        pop     ax
        mov     byte ptr [srb+SRB_CDB], 4Bh     ; PAUSE/RESUME
        mov     byte ptr [srb+SRB_CDB+8], ah
        call    call_aspi
        jmp     scsi_failed
pause_resume endp

        include common/aspi/aspi_client.inc

play_end        db      3 dup (0)
capacity_data   db      8 dup (0)
toc_data        db      TOC_SIZE dup (0)

caller_ss       dw      0
caller_sp       dw      0
driver_stack    db      768 dup (0)
driver_stack_top label byte

resident_end label byte

;=============================================================================
; initialization (discarded after INIT)
;=============================================================================

        include common/aspi/aspi_init.inc

options         db      0

init_request:
        call    parse_options
        mov     dx, offset msg_banner
        mov     ah, 09h
        int     21h
        call    aspi_open
        jnc     init_scan
        mov     dx, offset msg_no_manager
        jmp     init_failed
init_scan:
        call    aspi_scan_first
init_next_device:
        call    aspi_scan_next
        jc      init_scan_done
        cmp     byte ptr [scan_type], ASPI_DEV_CDA
        jne     init_next_device
        mov     al, byte ptr [unit_count]
        cmp     al, MAX_UNITS
        jae     init_scan_done
        mov     ah, UNIT_ENTRY
        mul     ah
        mov     di, ax
        mov     al, byte ptr [scan_ha]
        mov     byte ptr [unit_table+di], al
        mov     al, byte ptr [scan_target]
        mov     byte ptr [unit_table+di+1], al
        mov     al, byte ptr [scan_lun]
        mov     byte ptr [unit_table+di+2], al
        push    di
        call    cd_capabilities
        pop     di
        mov     byte ptr [unit_table+di+3], al
        inc     byte ptr [unit_count]
        test    byte ptr [options], OPT_VERBOSE
        jz      init_next_device
        call    print_unit
        jmp     init_next_device
init_scan_done:
        cmp     byte ptr [unit_count], 0
        jne     init_installed
        mov     dx, offset msg_no_drive
init_failed:
        mov     ah, 09h
        int     21h
        les     bx, [request_ptr]
        mov     byte ptr es:[bx+RH_INIT_UNITS], 0
        mov     word ptr es:[bx+RH_INIT_END], 0
        mov     word ptr es:[bx+RH_INIT_END+2], cs
        mov     word ptr es:[bx+RH_STATUS], ST_ERROR or ST_DONE or ERR_GENERAL
        jmp     request_done
init_installed:
        mov     dl, byte ptr [unit_count]
        add     dl, '0'
        mov     ah, 02h
        int     21h
        mov     dx, offset msg_installed
        mov     ah, 09h
        int     21h
        mov     si, offset device_name
        mov     cx, 8
print_name:
        lodsb
        cmp     al, ' '
        je      print_name_done
        mov     dl, al
        mov     ah, 02h
        int     21h
        loop    print_name
print_name_done:
        mov     dx, offset msg_crlf
        mov     ah, 09h
        int     21h
        les     bx, [request_ptr]
        mov     byte ptr es:[bx+RH_INIT_UNITS], 0
        mov     word ptr es:[bx+RH_INIT_END], offset resident_end
        mov     word ptr es:[bx+RH_INIT_END+2], cs
        mov     word ptr es:[bx+RH_STATUS], ST_DONE
        jmp     request_done

; "  ha:target:lun  VENDOR PRODUCT"
print_unit proc near
        mov     dx, offset msg_unit
        mov     ah, 09h
        int     21h
        mov     al, byte ptr [scan_ha]
        call    print_digit
        mov     dl, ':'
        mov     ah, 02h
        int     21h
        mov     al, byte ptr [scan_target]
        call    print_digit
        mov     dl, ':'
        mov     ah, 02h
        int     21h
        mov     al, byte ptr [scan_lun]
        call    print_digit
        mov     dl, ' '
        mov     ah, 02h
        int     21h
        mov     al, byte ptr [unit_table+di+3]
        push    ax
        call    aspi_inquiry
        jc      print_unit_caps
        call    print_inquiry_name
print_unit_caps:
        pop     ax
        mov     dx, offset msg_caps_unknown
        test    al, CAP_KNOWN
        jz      print_unit_text
        push    ax
        mov     dx, offset msg_analog_no
        test    al, CAP_ANALOG
        jz      print_analog
        mov     dx, offset msg_analog_yes
print_analog:
        mov     ah, 09h
        int     21h
        pop     ax
        mov     dx, offset msg_digital_no
        test    al, CAP_CDDA
        jz      print_unit_text
        mov     dx, offset msg_digital_yes
        test    al, CAP_ACCURATE
        jnz     print_unit_text
        mov     dx, offset msg_digital_inexact
print_unit_text:
        mov     ah, 09h
        int     21h
print_unit_done:
        mov     dx, offset msg_crlf
        mov     ah, 09h
        int     21h
        ret
print_unit endp

; MODE SENSE(10) page 2Ah of the scan_* drive -> AL = CAP_* (0 if the
; drive has no such page: pre-MMC, the capabilities are unknown)
cd_capabilities proc near
        mov     al, byte ptr [scan_ha]
        mov     byte ptr [unit_ha], al
        mov     al, byte ptr [scan_target]
        mov     byte ptr [unit_target], al
        mov     al, byte ptr [scan_lun]
        mov     byte ptr [unit_lun], al
        mov     al, SRB_DIR_IN
        mov     cl, 10
        call    aspi_prepare
        mov     byte ptr [srb+SRB_CDB], 5Ah     ; MODE SENSE(10)
        mov     byte ptr [srb+SRB_CDB+1], 08h   ; no block descriptors
        mov     byte ptr [srb+SRB_CDB+2], 2Ah   ; CD capabilities page
        mov     byte ptr [srb+SRB_CDB+8], 40
        mov     word ptr [srb+SRB_BufLen], 40
        mov     word ptr [srb+SRB_BufPointer], offset toc_data
        mov     word ptr [srb+SRB_BufPointer+2], cs
        call    call_aspi
        call    aspi_result
        mov     al, 0
        jc      cd_caps_done
        mov     bx, word ptr [toc_data+6]       ; block descriptor length
        xchg    bl, bh
        cmp     bx, 16
        ja      cd_caps_done
        add     bx, offset toc_data+8
        mov     ah, byte ptr [bx]
        and     ah, 3Fh
        cmp     ah, 2Ah
        jne     cd_caps_done
        mov     al, CAP_KNOWN
        test    byte ptr [bx+4], 01h            ; Audio Play
        jz      cd_caps_cdda
        or      al, CAP_ANALOG
cd_caps_cdda:
        mov     ah, byte ptr [bx+5]
        and     ah, 03h                         ; CD-DA commands, accurate
        shl     ah, 1
        or      al, ah
cd_caps_done:
        ret
cd_capabilities endp

print_digit proc near
        cmp     al, 10
        jb      print_digit_one
        push    ax
        mov     dl, '1'
        mov     ah, 02h
        int     21h
        pop     ax
        sub     al, 10
print_digit_one:
        add     al, '0'
        mov     dl, al
        mov     ah, 02h
        int     21h
        ret
print_digit endp

; /D:name and /V from the CONFIG.SYS line (after the driver path)
parse_options proc near
        push    ds
        les     bx, [request_ptr]
        lds     si, dword ptr es:[bx+RH_INIT_ARGS]
skip_path:
        lodsb
        cmp     al, ' '
        je      parse_next
        cmp     al, 9
        je      parse_next
        cmp     al, 0Dh
        je      parse_done
        cmp     al, 0Ah
        je      parse_done
        or      al, al
        jz      parse_done
        jmp     skip_path
parse_next:
        lodsb
        cmp     al, 0Dh
        je      parse_done
        cmp     al, 0Ah
        je      parse_done
        or      al, al
        jz      parse_done
        cmp     al, '/'
        je      parse_switch
        cmp     al, '-'
        jne     parse_next
parse_switch:
        lodsb
        and     al, 0DFh
        cmp     al, 'V'
        jne     parse_not_v
        or      byte ptr cs:[options], OPT_VERBOSE
        jmp     parse_next
parse_not_v:
        cmp     al, 'D'
        jne     parse_next
        cmp     byte ptr [si], ':'
        jne     parse_next
        inc     si
        mov     di, offset device_name
        mov     cx, 8
copy_name:
        mov     al, byte ptr [si]
        cmp     al, ' '
        jbe     pad_name
        cmp     al, '/'
        je      pad_name
        cmp     al, 'a'
        jb      store_name
        cmp     al, 'z'
        ja      store_name
        sub     al, 20h
store_name:
        mov     byte ptr cs:[di], al
        inc     si
        inc     di
        loop    copy_name
        jmp     parse_next
pad_name:
        mov     byte ptr cs:[di], ' '
        inc     di
        loop    pad_name
        jmp     parse_next
parse_done:
        pop     ds
        ret
parse_options endp

msg_banner      db      'ASPICDA 0.1 - OpenASPI CD/DVD driver', 13, 10, '$'
msg_no_manager  db      'No ASPI manager (SCSIMGR$) - ASPICDA not installed', 13, 10, '$'
msg_no_drive    db      'No CD/DVD drives found - ASPICDA not installed', 13, 10, '$'
msg_installed   db      ' CD/DVD drive(s), device $'
msg_unit        db      '  $'
msg_crlf        db      13, 10, '$'
msg_caps_unknown db     ' (audio capabilities unknown)$'
msg_analog_yes  db      ' (analog audio$'
msg_analog_no   db      ' (no analog audio$'
msg_digital_yes db      ', digital audio)$'
msg_digital_inexact db  ', digital audio inexact)$'
msg_digital_no  db      ', no digital audio)$'

        end     driver_start
