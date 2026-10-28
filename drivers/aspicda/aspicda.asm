; Interface boundary: DOS/MSCDEX requests are translated to ASPI MMC CDBs.
; DS=CS in resident handlers; select_unit loads the addressed drive's state
; before use of the shared SRB and scratch buffers. Reply parsers must check
; lengths/descriptor bounds before exposing TOC, subchannel or audio settings.
; LBA is the transport address; Red Book MSF includes the 150-frame offset.
; Cache audio/media state only after checked device completion, and invalidate
; it when media state changes. Resident code ends at resident_end; enumeration
; and command-line parsing after that point may be reclaimed by DOS.
; MSCDEX/SHSUCDX provide drive letters and filesystem access, not this module.

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

ifndef ASPICDA_TEST
        .8086
        option casemap:none

        .model tiny
        .code
        org     0
endif

        include common/aspi/dos_aspi.inc
        include common/dos/devreq.inc

MAX_UNITS       equ     8
CHUNK_SECTORS   equ     16              ; 16 * 2352 bytes stay below 64 KB
DEV_ATTR        equ     0C800h          ; character, IOCTL, open/close
TOC_SIZE        equ     4 + 100 * 8
AUDIO_MODE_SIZE equ     64

; Baseline device status (IOCTL input 6). Playing, verified channel control
; and committed lock/tray commands are added per unit; other bits remain baseline.
CD_STATUS       equ     0216h

OPT_VERBOSE     equ     01h

; drive capabilities (MODE SENSE page 2Ah), the 4th byte of a unit entry
CAP_KNOWN       equ     80h             ; page 2Ah was read
CAP_ANALOG      equ     01h             ; plays audio (analog output)
CAP_CDDA        equ     02h             ; reads audio sectors (READ CD)
CAP_ACCURATE    equ     04h             ; CD-DA stream is accurate
U_AUDIO_STATE   equ     4              ; 0 idle, 1 playing, 2 paused
U_AUDIO_RANGE   equ     5              ; a successful PLAY supplied the range
U_AUDIO_START   equ     6              ; packed binary MSF DWORD
U_AUDIO_END     equ     10             ; exclusive end, packed binary MSF
U_AUDIO_CONTROL equ     14             ; 0 unknown, 1 verified, 2 unavailable
U_DOOR_STATE    equ     15             ; last successful driver command
DOOR_LOCKED     equ     01h
DOOR_OPEN       equ     02h
DISC_CHANGED    equ     80h             ; UNIT ATTENTION not yet reported
UNIT_ENTRY      equ     16

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

; Per-drive address/capabilities and committed audio state/range.
unit_table      db      MAX_UNITS * UNIT_ENTRY dup (0)
current_unit    dw      0
request_busy    dw      0

strategy proc far
        mov     word ptr cs:[request_ptr], bx
        mov     word ptr cs:[request_ptr+2], es
        ret
strategy endp

; Common DOS request boundary: use the resident stack, select the addressed
; unit, dispatch, then publish DONE/ERROR and any audio BUSY state. BUSY describes
; playback state for the relevant requests; it does not mean an SRB remains live.
; Per-unit playback data must not leak from the previously addressed CD drive.
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
        mov     word ptr [request_busy], 0
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
        mov     byte ptr [aspi_attention], 0
        les     bx, [request_ptr]
        call    word ptr [si+1]
        pushf
        call    latch_disc_attention
        popf
        jc      request_failed
request_ok:
        les     bx, [request_ptr]
        mov     ax, ST_DONE
        mov     dl, byte ptr es:[bx+RH_COMMAND]
        cmp     dl, CMD_IOCTL_IN
        je      request_audio_busy
        cmp     dl, CMD_IOCTL_OUT
        je      request_audio_busy
        cmp     dl, CMD_INPUT_FLUSH
        je      request_audio_busy
        cmp     dl, CMD_OPEN
        je      request_audio_busy
        cmp     dl, CMD_CLOSE
        jne     request_store_status
request_audio_busy:
        mov     si, word ptr [current_unit]
        cmp     byte ptr [si+U_AUDIO_STATE], 1
        jne     request_store_status
        or      ax, ST_BUSY
request_store_status:
        mov     word ptr es:[bx+RH_STATUS], ax
        jmp     short request_done
unknown_command:
        mov     al, ERR_UNKNOWN_CMD
request_failed:
        les     bx, [request_ptr]
        xor     ah, ah
        or      ax, ST_ERROR or ST_DONE
        or      ax, word ptr [request_busy]
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
        dw      audio_poll
        db      CMD_OUTPUT_FLUSH
        dw      do_nothing
        db      CMD_IOCTL_OUT
        dw      ioctl_output
        db      CMD_OPEN
        dw      audio_poll
        db      CMD_CLOSE
        dw      audio_poll
        db      CMD_READ_LONG
        dw      read_long
        db      CMD_READ_PREFETCH
        dw      seek_request
        db      CMD_SEEK
        dw      seek_request
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
        add     ax, offset unit_table
        mov     word ptr [current_unit], ax
        mov     al, byte ptr [unit_table+di]
        mov     byte ptr [unit_ha], al
        mov     al, byte ptr [unit_table+di+1]
        mov     byte ptr [unit_target], al
        mov     al, byte ptr [unit_table+di+2]
        mov     byte ptr [unit_lun], al
        clc
        ret
select_unit endp

; Transfer a current UNIT ATTENTION from any command of this request to the
; selected unit, so MEDIA CHANGED reports it even if the disc is ready again.
; Preserves all registers except flags.
latch_disc_attention proc near
        cmp     byte ptr [aspi_attention], 0
        je      latch_disc_done
        mov     byte ptr [aspi_attention], 0
        push    si
        mov     si, word ptr [current_unit]
        or      byte ptr [si+U_DOOR_STATE], DISC_CHANGED
        pop     si
latch_disc_done:
        ret
latch_disc_attention endp

; CF set: AL = DOS error code of the failed SCSI command
scsi_failed proc near
        call    cd_aspi_result
        jnc     scsi_failed_ok
        call    sense_to_doserr
        stc
scsi_failed_ok:
        ret
scsi_failed endp

; Keep the raw sense key for callers such as MEDIA CHANGED, but invalidate
; stale resume data even when they intentionally don't return a DOS error.
; Every checked NOT READY/UNIT ATTENTION can invalidate a resumable audio
; range, including an informational query that consumes the notification.
; Keep the original sense key/carry for callers that apply their own DOS policy;
; clearing stale playback state is separate from reporting that command's error.
cd_aspi_result proc near
        call    aspi_result
        jnc     cd_result_done
        cmp     al, 02h                         ; NOT READY
        je      cd_result_lost_media
        cmp     al, 06h                         ; UNIT ATTENTION
        jne     cd_result_failed
cd_result_lost_media:
        push    ax
        call    clear_audio                     ; any query may consume media change
        pop     ax
cd_result_failed:
        stc
cd_result_done:
        ret
cd_aspi_result endp

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
; Inverse address conversion: add the 150-frame lead-in, then divide by 75
; frames/second and 60 seconds/minute. Callers must bound input before conversion
; so the 16-bit DIV quotient and binary MSF fields remain representable.
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

; READ LONG / SEEK / PREFETCH start -> LBA. PLAY uses a different offset.
request_lba proc near
        mov     ax, word ptr es:[bx+RH_CD_START]
        mov     dx, word ptr es:[bx+RH_CD_START+2]
        ; Fall through to the common decoder, also used by PLAY AUDIO.
request_lba endp

; Address-format boundary: DOS may supply HSG LBA or Red Book MSF. Convert
; once here before constructing CDBs; MSF includes the lead-in offset, while
; ordinary LBA zero already denotes the first data sector.
decode_address proc near
        cmp     byte ptr es:[bx+RH_CD_ADDRMODE], 0
        je      address_ok
        cmp     byte ptr es:[bx+RH_CD_ADDRMODE], 1
        jne     address_bad
        or      dh, dh
        jnz     address_bad
        cmp     dl, 98
        ja      address_bad
        cmp     ah, 59
        ja      address_bad
        cmp     al, 74
        ja      address_bad
        call    msf_to_lba
        ; MSF before 00:02:00 is before logical sector zero.
        test    dx, 8000h
        jnz     address_bad
address_ok:
        clc
        ret
address_bad:
        mov     al, 08h
        stc
        ret
decode_address endp

; Both requests are positioning hints: SEEK(10), without a data transfer.
; Check against the current medium, not a cached capacity from another disc.
seek_request proc near
        cmp     byte ptr es:[bx+RH_LENGTH], 18h
        jb      seek_bad_length
        call    request_lba
        jc      seek_done
        push    dx
        push    ax
        call    read_capacity
        jc      seek_capacity_failed
        mov     cx, ax
        mov     si, dx
        pop     ax
        pop     dx
        cmp     dx, si
        ja      seek_outside
        jb      seek_in_range
        cmp     ax, cx
        ja      seek_outside
seek_in_range:
        push    dx
        push    ax
        mov     al, SRB_DIR_NONE
        mov     cl, 10
        call    aspi_prepare
        pop     ax
        pop     dx
        mov     byte ptr [srb+SRB_CDB], 2Bh
        mov     byte ptr [srb+SRB_CDB+2], dh
        mov     byte ptr [srb+SRB_CDB+3], dl
        mov     byte ptr [srb+SRB_CDB+4], ah
        mov     byte ptr [srb+SRB_CDB+5], al
        call    call_aspi
        jmp     scsi_failed
seek_bad_length:
        mov     al, 05h
        stc
        ret
seek_capacity_failed:
        add     sp, 4
        stc
        ret
seek_outside:
        mov     al, 08h
        stc
seek_done:
        ret
seek_request endp

;-----------------------------------------------------------------------------
; READ LONG: cooked (2048 bytes, READ(10)) or raw (2352 bytes, READ CD)
;-----------------------------------------------------------------------------

read_lba        dw      0, 0
read_left       dw      0
read_buffer     dw      0, 0
read_raw        db      0
read_flags      db      0               ; READ CD byte 9

; Cooked/raw sector sizes differ in both transfer bytes and pointer advance.
; A checked unsupported raw request may try the narrower audio-data selection;
; other failures return without treating unread bytes as completed sectors.
read_long proc near
        mov     cx, word ptr es:[bx+RH_CD_COUNT]
        mov     word ptr [read_left], cx
        call    request_lba
        jc      read_failed
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

; Shared input/output IOCTL envelope. ES:DI -> control block, AL -> code.
ioctl_control_block proc near
        cmp     byte ptr es:[bx+RH_LENGTH], 14h
        jb      ioctl_bad_packet
        cmp     word ptr es:[bx+RH_COUNT], 1
        jb      ioctl_bad_packet
        mov     ax, word ptr es:[bx+RH_BUFFER]
        or      ax, word ptr es:[bx+RH_BUFFER+2]
        jz      ioctl_bad_packet
        les     di, dword ptr es:[bx+RH_BUFFER]
        mov     al, byte ptr es:[di]
        clc
        ret
ioctl_bad_packet:
        mov     al, 05h
        stc
        ret
ioctl_control_block endp

; Input IOCTLs share a control-code dispatcher, but each reply has a different
; minimum length. Select a handler first, validate its complete control payload,
; and only then fill caller fields. The device name/header is not this payload.
ioctl_input proc near
        call    ioctl_control_block
        jnc     ioctl_input_valid
        ret
ioctl_input_valid:
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
        db      1
        dw      ioctl_head_position
        db      4
        dw      ioctl_get_channels
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
        db      12
        dw      ioctl_q_channel
        db      14
        dw      ioctl_upc
        db      15
        dw      ioctl_audio_status
        db      0FFh

; AX = required control-block size. Check count and segment wrap before
; reading/writing fields. ES:DI is retained, BX/CX/DX may change.
; Validate the command-specific minimum before touching caller fields.
; An IOCTL control block is not the DOS request header itself; both the supplied
; count and segment-offset wrap must permit the complete control payload.
check_ioctl_buffer proc near
        push    es
        les     bx, [request_ptr]
        mov     cx, word ptr es:[bx+RH_COUNT]
        pop     es
        cmp     cx, ax
        jb      ioctl_buffer_bad
        mov     dx, di
        dec     ax
        add     dx, ax
        jc      ioctl_buffer_bad
        clc
        ret
ioctl_buffer_bad:
        mov     al, 05h
        stc
        ret
check_ioctl_buffer endp

ioctl_head_position:
        mov     ax, 6
        call    check_ioctl_buffer
        jc      head_position_done
        mov     al, byte ptr es:[di+1]
        cmp     al, 1
        ja      head_position_mode_bad
        shl     al, 1                          ; MMC MSF bit
        call    read_sub_position
        jc      head_position_done
        cmp     byte ptr es:[di+1], 0
        jne     head_position_msf
        mov     dx, word ptr [sub_position+8]
        xchg    dl, dh
        mov     ax, word ptr [sub_position+10]
        xchg    al, ah
        jmp     short head_position_store
head_position_msf:
        mov     al, byte ptr [sub_position+11]  ; frame, second, minute, zero
        mov     ah, byte ptr [sub_position+10]
        mov     dl, byte ptr [sub_position+9]
        xor     dh, dh
head_position_store:
        mov     word ptr es:[di+2], ax
        mov     word ptr es:[di+4], dx
        clc
head_position_done:
        ret
head_position_mode_bad:
        mov     al, ERR_UNKNOWN_CMD
        stc
        ret

ioctl_q_channel:
        mov     ax, 11
        call    check_ioctl_buffer
        jc      q_channel_done
        mov     al, 2                          ; request binary MSF
        call    read_sub_position
        jc      q_channel_done
        mov     al, byte ptr [sub_position+5]   ; SCSI ADR/CONTROL -> DOS
        mov     cl, 4
        rol     al, cl
        mov     byte ptr es:[di+1], al
        mov     al, byte ptr [sub_position+6]
        cmp     al, 0AAh                       ; retain lead-out marker
        je      q_channel_track
        aam                                    ; binary track -> BCD
        mov     cl, 4
        shl     ah, cl
        or      al, ah
q_channel_track:
        mov     byte ptr es:[di+2], al
        mov     al, byte ptr [sub_position+7]   ; index remains binary
        mov     byte ptr es:[di+3], al
        mov     ax, word ptr [sub_position+13]  ; relative M, S
        mov     word ptr es:[di+4], ax
        mov     al, byte ptr [sub_position+15]
        mov     byte ptr es:[di+6], al
        mov     byte ptr es:[di+7], 0
        mov     ax, word ptr [sub_position+9]   ; absolute M, S
        mov     word ptr es:[di+8], ax
        mov     al, byte ptr [sub_position+11]
        mov     byte ptr es:[di+10], al
        clc
q_channel_done:
        ret

; DOS UPC/EAN is a mode-2 Q packet, not the MMC ASCII MCN response.
; Stage everything: even a failed follow-up CONTROL query leaves output alone.
ioctl_upc proc near
        mov     ax, 11
        call    check_ioctl_buffer
        jnc     upc_buffer_ok
        ret
upc_buffer_ok:
        mov     ax, 0200h                      ; format 2, MSF not applicable
        mov     cx, 24
        mov     si, offset mcn_data
        call    read_sub_channel
        jnc     upc_received
        ret
upc_received:
        cmp     byte ptr [mcn_data], 0
        jne     upc_bad
        cmp     word ptr [mcn_data+2], 1400h    ; 20-byte format-2 payload
        jne     upc_bad
        cmp     byte ptr [mcn_data+4], 2
        jne     upc_bad
        cmp     word ptr [mcn_data+5], 0
        jne     upc_bad
        cmp     byte ptr [mcn_data+7], 0
        jne     upc_bad
        test    byte ptr [mcn_data+8], 7Fh      ; MCVAL's other bits reserved
        jnz     upc_bad
        test    byte ptr [mcn_data+8], 80h
        jz      upc_missing
        cmp     byte ptr [mcn_data+22], 0
        jne     upc_bad
        cmp     byte ptr [mcn_data+23], 74
        ja      upc_bad
        mov     si, offset mcn_data+9
        mov     cx, 13
        xor     dx, dx
upc_validate_digit:
        lodsb
        sub     al, '0'
        cmp     al, 9
        ja      upc_bad
        or      dl, al
        loop    upc_validate_digit
        or      dl, dl
        jz      upc_missing                    ; all zeros means not supplied
        jmp     short upc_pack
upc_bad:
        mov     al, ERR_GENERAL
        stc
        ret
upc_missing:
        mov     al, ERR_NOT_FOUND              ; matches reference MCVAL failure
        stc
        ret
upc_pack:
        mov     si, offset mcn_data+9
        mov     bx, offset upc_result+1
        mov     cx, 6
upc_pack_pair:
        lodsw
        sub     ax, 3030h
        push    cx
        mov     cl, 4
        shl     al, cl
        pop     cx
        or      al, ah
        mov     byte ptr [bx], al
        inc     bx
        loop    upc_pack_pair
        lodsb
        sub     al, '0'
        mov     cl, 4
        shl     al, cl
        mov     byte ptr [upc_result+7], al     ; low nibble explicitly zero
        mov     byte ptr [upc_result+8], 0
        mov     al, byte ptr [mcn_data+23]      ; MMC binary -> raw mode-2 BCD
        aam
        shl     ah, cl
        or      al, ah
        mov     byte ptr [upc_result+9], al
        ; Format 2 has no CONTROL field. Obtain it from current Q data,
        ; as the original's standard 42h path at 0857h does.
        mov     al, 2
        call    read_sub_position
        jc      upc_done
        mov     al, byte ptr [sub_position+5]
        and     al, 0Fh
        mov     cl, 4
        shl     al, cl
        or      al, 2                          ; ADR = MCN, not position
        mov     byte ptr [upc_result], al
        mov     si, offset upc_result
        inc     di
        mov     cx, 10
        rep     movsb
        clc
upc_done:
        ret
ioctl_upc endp

; AL = 0 (LBA) or 2 (MSF). A fresh format-1 READ SUB-CHANNEL response;
; never copy incomplete/invalid data to the caller. No capability guessing
; from MODE page 2Ah: unsupported commands fail through the ASPI result.
read_sub_position proc near
        call    submit_sub_position
        jc      read_sub_done
        call    validate_sub_position
read_sub_done:
        ret
read_sub_position endp

; Prepare format-1 allocation parameters and tail-call shared subchannel I/O.
; This submits only; read_sub_position additionally validates the position, while
; audio_poll can accept a terminal status that no longer includes a position.
submit_sub_position proc near
        mov     ah, 1
        mov     cx, 16
        mov     si, offset sub_position
        jmp     short read_sub_channel
submit_sub_position endp

; AL = address mode, AH = format, CX = allocation, DS:SI = scratch buffer.
; Shared transport for position and MCN. ES:DI (DOS output) is retained.
read_sub_channel proc near
        push    ax
        push    cx
        push    si
        push    es
        push    di
        push    cs
        pop     es
        mov     di, si
        mov     al, 0FFh                       ; poison unreturned bytes
        rep     stosb
        pop     di
        pop     es
        mov     al, SRB_DIR_IN
        mov     cl, 10
        call    aspi_prepare
        pop     si
        pop     cx
        pop     ax
        mov     byte ptr [srb+SRB_CDB], 42h
        mov     byte ptr [srb+SRB_CDB+1], al
        mov     byte ptr [srb+SRB_CDB+2], 40h    ; SUBQ
        mov     byte ptr [srb+SRB_CDB+3], ah
        mov     byte ptr [srb+SRB_CDB+8], cl
        mov     word ptr [srb+SRB_BufLen], cx
        mov     word ptr [srb+SRB_BufPointer], si
        mov     word ptr [srb+SRB_BufPointer+2], cs
        call    call_aspi
        jmp     scsi_failed
read_sub_channel endp

; Transport success is insufficient for Q-channel data: require the expected
; format/length and bounded track/index/MSF fields before copying a position to
; DOS. Scratch bytes were poisoned so untouched data cannot look like success.
validate_sub_position proc near
        cmp     byte ptr [sub_position], 0     ; reserved header byte
        jne     sub_position_bad
        cmp     word ptr [sub_position+2], 0C00h ; 12-byte format-1 payload
        jne     sub_position_bad
        cmp     byte ptr [sub_position+4], 1
        jne     sub_position_bad
        mov     al, byte ptr [sub_position+6]
        cmp     al, 0AAh
        je      sub_track_ok
        cmp     al, 1
        jb      sub_position_bad
        cmp     al, 99
        ja      sub_position_bad
sub_track_ok:
        cmp     byte ptr [sub_position+7], 99
        ja      sub_position_bad
        cmp     byte ptr [srb+SRB_CDB+1], 0
        je      sub_position_ok
        cmp     byte ptr [sub_position+8], 0
        jne     sub_position_bad
        cmp     byte ptr [sub_position+12], 0
        jne     sub_position_bad
        mov     si, offset sub_position+9
        call    check_sub_msf
        jc      sub_position_bad
        mov     si, offset sub_position+13
        call    check_sub_msf
        jc      sub_position_bad
sub_position_ok:
        clc
sub_position_done:
        ret
sub_position_bad:
        mov     al, ERR_GENERAL
        stc
        ret
validate_sub_position endp

; Only a driver-issued active PLAY needs polling. Terminal status can be
; valid even when there is no current Q position (e.g. after completion).
; Reconcile cached playback with READ SUB-CHANNEL. Inactive state avoids an
; unneeded command; active/paused reports require a valid position. Terminal
; statuses may legitimately omit Q-position data, so validate their header/status
; without demanding a still-current track. Publish only a qualified new state.
audio_poll proc near
        mov     si, word ptr [current_unit]
        cmp     byte ptr [si+U_AUDIO_STATE], 0
        je      audio_poll_ok
        mov     al, 2
        call    submit_sub_position
        jc      audio_poll_error
        cmp     byte ptr [sub_position], 0
        jne     audio_poll_malformed
        cmp     word ptr [sub_position+2], 0
        je      audio_poll_header_ok
        cmp     word ptr [sub_position+2], 0C00h
        jne     audio_poll_malformed
audio_poll_header_ok:
        mov     al, byte ptr [sub_position+1]
        cmp     al, 11h
        je      audio_poll_active
        cmp     al, 12h
        je      audio_poll_active
        cmp     al, 13h
        jb      audio_poll_unsupported
        cmp     al, 15h
        ja      audio_poll_malformed
        mov     si, word ptr [current_unit]
        mov     byte ptr [si+U_AUDIO_STATE], 0
        jmp     short audio_poll_ok
audio_poll_active:
        call    validate_sub_position
        jc      audio_poll_done
        mov     al, byte ptr [sub_position+1]
        sub     al, 10h
        mov     si, word ptr [current_unit]
        mov     byte ptr [si+U_AUDIO_STATE], al
audio_poll_ok:
        clc
audio_poll_done:
        ret
audio_poll_unsupported:
        or      al, al
        jnz     audio_poll_malformed
        mov     al, ERR_UNKNOWN_CMD
        stc
        ret
audio_poll_malformed:
        mov     al, ERR_GENERAL
        stc
        ret
audio_poll_error:
        ; Common SCSI error handling has already invalidated lost media.
        stc
        ret
audio_poll endp

; Invalidate both playback state AND the saved resume range. Clearing only
; the playing flag would allow RESUME to reuse positions from a removed disc.
; This changes software state only; it is not a STOP/PAUSE hardware command.
clear_audio proc near
        mov     si, word ptr [current_unit]
        mov     byte ptr [si+U_AUDIO_STATE], 0
        mov     byte ptr [si+U_AUDIO_RANGE], 0
        mov     word ptr [si+U_AUDIO_START], 0
        mov     word ptr [si+U_AUDIO_START+2], 0
        mov     word ptr [si+U_AUDIO_END], 0
        mov     word ptr [si+U_AUDIO_END+2], 0
        clc
        ret
clear_audio endp

ioctl_audio_status:
        mov     ax, 11
        call    check_ioctl_buffer
        jc      audio_status_done
        call    audio_poll
        jc      audio_status_done
        mov     si, word ptr [current_unit]
        xor     ax, ax
        cmp     byte ptr [si+U_AUDIO_STATE], 2
        jne     audio_status_store
        inc     ax
audio_status_store:
        mov     word ptr es:[di+1], ax
        mov     ax, word ptr [si+U_AUDIO_START]
        mov     word ptr es:[di+3], ax
        mov     ax, word ptr [si+U_AUDIO_START+2]
        mov     word ptr es:[di+5], ax
        mov     ax, word ptr [si+U_AUDIO_END]
        mov     word ptr es:[di+7], ax
        mov     ax, word ptr [si+U_AUDIO_END+2]
        mov     word ptr es:[di+9], ax
        clc
audio_status_done:
        ret

; Binary M/S/F response fields (relative time has no 150-frame bias).
check_sub_msf proc near
        cmp     byte ptr [si], 99
        ja      sub_msf_bad
        cmp     byte ptr [si+1], 59
        ja      sub_msf_bad
        cmp     byte ptr [si+2], 74
        ja      sub_msf_bad
        clc
        ret
sub_msf_bad:
        stc
        ret
check_sub_msf endp

ioctl_header_address:
        mov     word ptr es:[di+1], 0
        mov     word ptr es:[di+3], cs
        clc
        ret

ioctl_device_status:
        mov     ax, 5
        call    check_ioctl_buffer
        jc      device_status_done
        call    audio_poll
        jc      device_status_done
        call    audio_control_capability
        mov     word ptr es:[di+1], CD_STATUS
        mov     word ptr es:[di+3], 0
        mov     si, word ptr [current_unit]
        test    byte ptr [si+U_DOOR_STATE], DOOR_LOCKED
        jz      device_status_unlocked
        and     word ptr es:[di+1], not 2
device_status_unlocked:
        test    byte ptr [si+U_DOOR_STATE], DOOR_OPEN
        jz      device_status_closed
        or      word ptr es:[di+1], 1
device_status_closed:
        cmp     byte ptr [si+U_AUDIO_CONTROL], 1
        jne     device_status_audio
        or      word ptr es:[di+1], 0100h
device_status_audio:
        cmp     byte ptr [si+U_AUDIO_STATE], 1
        jne     device_status_ok
        or      word ptr es:[di+1], 0400h
device_status_ok:
        clc
device_status_done:
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

; DOS asks for a sector count, whereas READ CAPACITY returns the last LBA.
; Add one exactly once here. read_capacity rejects FFFFFFFFh (the CAPACITY(16)
; sentinel), so it must not wrap into an apparently empty volume.
ioctl_volume_size:
        call    read_capacity
        jc      volume_size_done
        add     ax, 1
        adc     dx, 0
        mov     word ptr es:[di+1], ax
        mov     word ptr es:[di+3], dx
        clc
volume_size_done:
        ret

; Current last logical block in DX:AX (not the block count).
read_capacity proc near
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
        jc      capacity_done
        mov     ax, word ptr [capacity_data+2]   ; last LBA, big-endian
        xchg    al, ah
        mov     dx, word ptr [capacity_data]
        xchg    dl, dh
        ; FFFFFFFFh means READ CAPACITY(16) is required, not a zero-size CD.
        cmp     dx, 0FFFFh
        jne     capacity_ok
        cmp     ax, 0FFFFh
        jne     capacity_ok
        mov     al, 08h
        stc
        ret
capacity_ok:
        clc
capacity_done:
        ret
read_capacity endp

; 1 unchanged, 0FFh changed (UNIT ATTENTION), 0 don't know
; Return a media-change hint, not the TUR error as a failed IOCTL: READY=1,
; checked UNIT ATTENTION=FFh, other failure=0 unknown. cd_aspi_result separately
; invalidates stale playback state. A change hint does not establish disc type.
; A UNIT ATTENTION consumed by an earlier request is reported once as changed,
; even when this TEST UNIT READY succeeds. The probe always runs, so a new
; notification still invalidates playback state.
ioctl_media_changed:
        push    es
        push    di
        mov     al, SRB_DIR_NONE
        mov     cl, 6
        call    aspi_prepare                    ; TEST UNIT READY: CDB zero
        call    call_aspi
        call    cd_aspi_result
        pop     di
        pop     es
        mov     ah, 1
        jnc     media_changed_ready
        mov     ah, 0FFh
        mov     byte ptr [aspi_attention], 0    ; reported now, do not latch again
        cmp     al, 06h
        je      media_changed_ready
        mov     ah, 0
media_changed_ready:
        mov     si, word ptr [current_unit]
        test    byte ptr [si+U_DOOR_STATE], DISC_CHANGED
        jz      media_changed_store
        and     byte ptr [si+U_DOOR_STATE], not DISC_CHANGED
        mov     ah, 0FFh
media_changed_store:
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
; MMC packs ADR in the high nibble and CONTROL in the low nibble. DOS uses
; the opposite nibble order, so rotate by four rather than treating the byte as
; a channel or sense mask. Position bytes are copied in DOS Red Book order.
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
; Search eight-byte format-0 descriptors for the requested track (AAh is
; lead-out). The TOC length is big-endian and excludes its own two bytes; after
; removing first/last-track bytes, traverse descriptors within TOC_SIZE. This
; routine searches the transport buffer; it does not perform another device read.
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
; Audio Control page 0Eh. Read current hardware state, not a software echo.
; DOS input/output channel bytes are indexes; SCSI selectors are bitmasks.
;-----------------------------------------------------------------------------

ioctl_get_channels proc near
        mov     ax, 9
        call    check_ioctl_buffer
        jc      get_channels_done
        xor     al, al                         ; current values, PC=0
        call    read_audio_page
        jc      get_channels_done
        mov     bx, word ptr [audio_page]
        add     bx, 8                          ; first selector/volume pair
        mov     si, offset audio_desired
        xor     dx, dx                         ; output port number
        mov     cx, 4
get_channel_next:
        mov     al, byte ptr [bx]
        and     al, 0Fh
        mov     ah, byte ptr [bx+1]
        or      al, al
        jnz     get_channel_routed
        ; Muted port: the input is immaterial; report its own index and
        ; zero amplitude rather than pretending an audible input is routed.
        mov     al, dl
        xor     ah, ah
        jmp     short get_channel_store
get_channel_routed:
        call    selector_to_channel
        jc      get_channels_done              ; mixed selectors not expressible
get_channel_store:
        mov     word ptr [si], ax
        add     si, 2
        add     bx, 2
        inc     dx
        loop    get_channel_next
        mov     si, offset audio_desired
        inc     di
        mov     cx, 8
        rep     movsb
        clc
get_channels_done:
        ret
ioctl_get_channels endp

; AL = one-hot channel mask -> AL = DOS channel index, AH retained.
selector_to_channel proc near
        cmp     al, 1
        je      selector_zero
        cmp     al, 2
        je      selector_one
        cmp     al, 4
        je      selector_two
        cmp     al, 8
        je      selector_three
        mov     al, ERR_UNKNOWN_CMD
        stc
        ret
selector_zero:
        xor     al, al
        ret
selector_one:
        mov     al, 1
        clc
        ret
selector_two:
        mov     al, 2
        clc
        ret
selector_three:
        mov     al, 3
        clc
        ret
selector_to_channel endp

; Translate four DOS channel/volume pairs to MMC audio page 0Eh. Stage all
; requested pairs before drive access; preserve unrelated page fields and check
; changeability instead of overwriting the whole device mode configuration.
ioctl_set_channels proc near
        mov     ax, 9
        call    check_ioctl_buffer
        jnc     set_channels_buffer_ok
        ret
set_channels_buffer_ok:
        ; Stage and validate all four pairs before any drive access.
        xor     bx, bx
set_channel_stage:
        mov     al, byte ptr es:[di+bx+1]
        cmp     al, 3
        jbe     set_channel_valid
        mov     al, ERR_UNKNOWN_CMD
        stc
        ret
set_channel_valid:
        mov     ah, byte ptr es:[di+bx+2]
        mov     word ptr [audio_desired+bx], ax
        add     bx, 2
        cmp     bx, 8
        jb      set_channel_stage
        xor     al, al
        call    read_audio_page
        jnc     set_channels_current_ok
        ret
set_channels_current_ok:
        ; Only page 0Eh goes to MODE SELECT: zero header, no descriptors,
        ; no other pages. Retain all non-routing fields and any page tail.
        push    es
        push    di
        push    cs
        pop     es
        mov     di, offset audio_select
        xor     ax, ax
        mov     cx, 4
        rep     stosw
        mov     si, word ptr [audio_page]
        mov     cx, word ptr [audio_page_size]
        mov     ax, cx
        add     ax, 8
        mov     word ptr [audio_select_size], ax
        rep     movsb
        and     byte ptr [audio_select+8], 7Fh  ; PS is not valid in SELECT
        pop     di
        pop     es
        mov     al, 40h                        ; changeable values, PC=1
        call    read_audio_page
        jnc     set_channels_mask_ok
        ret
set_channels_mask_ok:
        mov     ax, word ptr [audio_page_size]
        add     ax, 8
        cmp     ax, word ptr [audio_select_size]
        je      set_channels_same_page
        mov     al, ERR_GENERAL
        stc
        ret
set_channels_same_page:
        mov     byte ptr [audio_changeable], 0
        mov     si, word ptr [audio_page]
        add     si, 8
        mov     bx, offset audio_select+16
        xor     dx, dx                         ; pair offset 0,2,4,6
set_channel_apply:
        push    bx
        mov     bx, dx
        mov     cl, byte ptr [audio_desired+bx]
        mov     ah, byte ptr [audio_desired+bx+1]
        pop     bx
        or      ah, ah
        jnz     set_channel_encode
        mov     al, byte ptr [bx]
        and     al, 0Fh
        jnz     set_channel_encode
        ; GET maps a muted selector to volume zero. Its original amplitude
        ; may be fixed and nonzero: retain the already-silent hardware pair
        ; when that semantic zero-volume result is written back unchanged.
        mov     ax, word ptr [bx]
        jmp     short set_channel_encoded
set_channel_encode:
        mov     al, 1
        shl     al, cl
        mov     cl, byte ptr [bx]
        and     cl, 0F0h                       ; preserve reserved selector bits
        or      al, cl
; AX contains the requested encoded pair; [BX] is the current pair. XOR gives
; the bits that would change. AND with the inverted changeable mask rejects any
; change to fixed bits; this accepts a no-op even when a field is not changeable.
; It must not silently clamp an unsupported channel or volume to another value.
set_channel_encoded:
        ; Reject requested changes to fixed bits; never silently clamp.
        mov     cx, word ptr [bx]
        xor     cx, ax
        push    ax
        mov     ax, word ptr [si]
        test    ax, 0FF0Fh
        jz      set_channel_fixed_mask
        mov     byte ptr [audio_changeable], 1
set_channel_fixed_mask:
        not     ax
        and     cx, ax
        pop     ax
        jcxz    set_channel_changeable
        mov     al, ERR_UNKNOWN_CMD
        stc
        ret
set_channel_changeable:
        mov     word ptr [bx], ax
        add     bx, 2
        add     si, 2
        add     dx, 2
        cmp     dx, 8
        jb      set_channel_apply
        mov     al, SRB_DIR_OUT
        mov     cl, 10
        call    aspi_prepare
        mov     byte ptr [srb+SRB_CDB], 55h     ; MODE SELECT(10)
        mov     byte ptr [srb+SRB_CDB+1], 10h   ; PF=1, SP=0 (not persistent)
        mov     ax, word ptr [audio_select_size]
        mov     byte ptr [srb+SRB_CDB+8], al
        mov     word ptr [srb+SRB_BufLen], ax
        mov     word ptr [srb+SRB_BufPointer], offset audio_select
        mov     word ptr [srb+SRB_BufPointer+2], cs
        call    call_aspi
        call    scsi_failed
        jc      set_channels_done
        cmp     byte ptr [audio_changeable], 0
        je      set_channels_success
        mov     si, word ptr [current_unit]
        mov     byte ptr [si+U_AUDIO_CONTROL], 1
set_channels_success:
        clc
set_channels_done:
        ret
ioctl_set_channels endp

; Optional drive capability probe. A failed/unsupported page must not break
; basic device-status queries. Only explicit ILLEGAL REQUEST or an entirely
; fixed page is cached as unavailable; transient failures remain unknown.
audio_control_capability proc near
        mov     si, word ptr [current_unit]
        cmp     byte ptr [si+U_AUDIO_CONTROL], 0
        jne     audio_control_probe_done
        xor     al, al
        call    read_audio_page
        jc      audio_control_probe_error
        mov     ax, word ptr [audio_page_size]
        mov     word ptr [audio_probe_size], ax
        mov     al, 40h
        call    read_audio_page
        jc      audio_control_probe_error
        mov     ax, word ptr [audio_page_size]
        cmp     ax, word ptr [audio_probe_size]
        jne     audio_control_probe_done
        mov     bx, word ptr [audio_page]
        add     bx, 8
        mov     cx, 4
audio_control_probe_pair:
        mov     ax, word ptr [bx]
        and     ax, 0FF0Fh
        jnz     audio_control_probe_supported
        add     bx, 2
        loop    audio_control_probe_pair
        jmp     short audio_control_probe_unavailable
audio_control_probe_error:
        cmp     al, ERR_NOT_FOUND              ; mapped ILLEGAL REQUEST
        jne     audio_control_probe_done
audio_control_probe_unavailable:
        mov     si, word ptr [current_unit]
        mov     byte ptr [si+U_AUDIO_CONTROL], 2
        ret
audio_control_probe_supported:
        mov     si, word ptr [current_unit]
        mov     byte ptr [si+U_AUDIO_CONTROL], 1
audio_control_probe_done:
        ret
audio_control_capability endp

; AL = PC bits 00h/40h. A bounded MODE SENSE(10) page, including a possible
; block descriptor returned despite DBD. ES:DI is retained. No MODE(6) fallback.
; MODE SENSE(10) header length and block-descriptor length determine where
; page 0Eh starts, even when DBD requested no descriptors. Poison the allocation,
; bound the complete page before returning its pointer, and reject subpage or
; wrong-page layouts. A successful SRB alone cannot validate returned mode data.
read_audio_page proc near
        push    ax
        push    es
        push    di
        push    cs
        pop     es
        mov     di, offset audio_mode
        mov     cx, AUDIO_MODE_SIZE
        mov     al, 0FFh
        rep     stosb
        pop     di
        pop     es
        mov     al, SRB_DIR_IN
        mov     cl, 10
        call    aspi_prepare
        pop     ax
        or      al, 0Eh
        mov     byte ptr [srb+SRB_CDB], 5Ah
        mov     byte ptr [srb+SRB_CDB+1], 08h   ; DBD
        mov     byte ptr [srb+SRB_CDB+2], al
        mov     byte ptr [srb+SRB_CDB+8], AUDIO_MODE_SIZE
        mov     word ptr [srb+SRB_BufLen], AUDIO_MODE_SIZE
        mov     word ptr [srb+SRB_BufPointer], offset audio_mode
        mov     word ptr [srb+SRB_BufPointer+2], cs
        call    call_aspi
        call    scsi_failed
        jc      audio_page_done
        mov     dx, word ptr [audio_mode]
        xchg    dl, dh
        cmp     dx, AUDIO_MODE_SIZE-2
        ja      audio_page_bad
        add     dx, 2                          ; total response length
        cmp     dx, 24
        jb      audio_page_bad
        mov     bx, word ptr [audio_mode+6]
        xchg    bl, bh
        cmp     bx, AUDIO_MODE_SIZE-24
        ja      audio_page_bad
        add     bx, 8
        mov     ax, bx
        add     ax, 16
        cmp     ax, dx
        ja      audio_page_bad
        add     bx, offset audio_mode
        mov     al, byte ptr [bx]
        and     al, 7Fh                        ; PS allowed, SPF not allowed
        cmp     al, 0Eh
        jne     audio_page_bad
        xor     ax, ax
        mov     al, byte ptr [bx+1]
        cmp     al, 14
        jb      audio_page_bad
        add     ax, 2
        mov     cx, bx
        sub     cx, offset audio_mode
        add     cx, ax
        cmp     cx, dx
        ja      audio_page_bad
        mov     word ptr [audio_page], bx
        mov     word ptr [audio_page_size], ax
        clc
audio_page_done:
        ret
audio_page_bad:
        mov     al, ERR_GENERAL
        stc
        ret
read_audio_page endp

;-----------------------------------------------------------------------------
; IOCTL output: eject, lock/unlock, reset, audio channels, close tray
;-----------------------------------------------------------------------------

ioctl_output proc near
        call    ioctl_control_block
        jnc     ioctl_output_valid
        ret
ioctl_output_valid:
        cmp     al, 3
        jne     ioctl_output_other
        jmp     ioctl_set_channels
ioctl_output_other:
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
        mov     si, word ptr [current_unit]
        test    byte ptr [si+U_DOOR_STATE], DOOR_LOCKED
        jnz     media_control_locked
        mov     ah, 02h                         ; LoEj, stop
        jmp     short start_stop
close_tray:
        mov     ah, 03h                         ; LoEj, start
start_stop:
        mov     al, 1Bh
        push    ax
        call    aspi_media_control
        call    scsi_failed
        pop     dx                             ; DH = requested tray operation
        jc      start_stop_done
        mov     si, word ptr [current_unit]
        and     byte ptr [si+U_DOOR_STATE], not DOOR_OPEN
        test    dh, 1
        jnz     start_stop_audio
        or      byte ptr [si+U_DOOR_STATE], DOOR_OPEN
start_stop_audio:
        call    clear_audio
start_stop_done:
        ret
lock_door:
        mov     ax, 2
        call    check_ioctl_buffer
        jc      media_control_done
        mov     ah, byte ptr es:[di+1]          ; 1 lock, 0 unlock
        cmp     ah, 1
        ja      media_control_bad
        mov     al, 1Eh
        push    ax
        call    aspi_media_control
        call    scsi_failed
        pop     dx
        jc      media_control_done
        mov     si, word ptr [current_unit]
        and     byte ptr [si+U_DOOR_STATE], not DOOR_LOCKED
        or      byte ptr [si+U_DOOR_STATE], dh
        clc
media_control_done:
        ret
media_control_bad:
        mov     al, ERR_UNKNOWN_CMD
        stc
        ret
media_control_locked:
        mov     al, ERR_GENERAL
        stc
        ret
; Compatibility no-op: this handler returns success but issues no reset CDB
; or ASPI reset. Keep that limitation explicit; callers cannot use this request
; as proof that the hardware, media state or outstanding audio was reset.
reset_drive:
        clc
        ret
ioctl_output endp

;-----------------------------------------------------------------------------
; analog audio: PLAY AUDIO MSF, PAUSE/RESUME
;-----------------------------------------------------------------------------

; PLAY uses a start plus frame count, while MMC PLAY AUDIO MSF takes start/end.
; Reject addition overflow and unrepresentable endpoints before CDB construction.
; A successful command publishes the saved range and playing state; a rejected
; second PLAY must not overwrite the currently active range.
play_audio proc near
        cmp     byte ptr es:[bx+RH_LENGTH], 16h
        jae     play_length_ok
        mov     al, 05h
        stc
        ret
play_length_ok:
        mov     cx, word ptr es:[bx+RH_CD_PLAYCOUNT]
        or      cx, word ptr es:[bx+RH_CD_PLAYCOUNT+2]
        jnz     play_nonempty
        clc
        ret
play_nonempty:
        mov     si, word ptr [current_unit]
        cmp     byte ptr [si+U_AUDIO_STATE], 1
        jne     play_not_busy
        call    audio_poll
        jnc     play_poll_ok
        ret
play_poll_ok:
        mov     si, word ptr [current_unit]
        cmp     byte ptr [si+U_AUDIO_STATE], 1
        jne     play_not_busy
        mov     word ptr [request_busy], ST_BUSY
        mov     al, ERR_NOT_READY
        stc
        ret
play_not_busy:
        mov     ax, word ptr es:[bx+RH_CD_PLAYSTART]
        mov     dx, word ptr es:[bx+RH_CD_PLAYSTART+2]
        call    decode_address
        jnc     play_address_ok
        ret
play_address_ok:
        mov     word ptr [play_start], ax
        mov     word ptr [play_start+2], dx
        add     ax, word ptr es:[bx+RH_CD_PLAYCOUNT]
        adc     dx, word ptr es:[bx+RH_CD_PLAYCOUNT+2]
        jc      play_outside
        ; PLAY AUDIO MSF uses binary minutes. Limit to a representable CD
        ; position before conversion (also prevents 8086 DIV overflow).
        cmp     dx, 449849 shr 16
        ja      play_outside
        jb      play_range_ok
        cmp     ax, 449849 and 0FFFFh
        jbe     play_range_ok
play_outside:
        mov     al, 08h
        stc
        ret
play_range_ok:
        call    lba_to_msf
        mov     word ptr [play_end], ax
        mov     byte ptr [play_end+2], dl
        mov     ax, word ptr [play_start]
        mov     dx, word ptr [play_start+2]
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
        call    scsi_failed
        jc      play_failed
        mov     ax, word ptr [play_start]
        mov     dx, word ptr [play_start+2]
        call    lba_to_msf
        mov     si, word ptr [current_unit]
        mov     word ptr [si+U_AUDIO_START], ax
        mov     word ptr [si+U_AUDIO_START+2], dx
        mov     ax, word ptr [play_end]
        mov     word ptr [si+U_AUDIO_END], ax
        xor     ah, ah
        mov     al, byte ptr [play_end+2]
        mov     word ptr [si+U_AUDIO_END+2], ax
        mov     byte ptr [si+U_AUDIO_RANGE], 1
        mov     byte ptr [si+U_AUDIO_STATE], 1
play_done:
        clc
play_failed:
        ret
play_audio endp

; DOS STOP preserves resume semantics: poll current state, then pause a playing
; range. If playback has already ended, discard saved range instead. This is not
; a generic drive reset or tray operation.
stop_audio proc near
        call    audio_poll
        jc      stop_audio_done
        mov     si, word ptr [current_unit]
        cmp     byte ptr [si+U_AUDIO_STATE], 1
        je      stop_audio_playing
        jmp     clear_audio
stop_audio_playing:
        xor     ah, ah                          ; pause
        jmp     short pause_resume
stop_audio_done:
        ret
stop_audio endp

; RESUME requires both a qualified paused state and a saved range from this
; unit. Poll first, since cached PAUSED can be stale after a media notification.
; Do not invent a PLAY range when the device reports no resumable operation.
resume_audio proc near
        call    audio_poll
        jc      resume_audio_done
        mov     si, word ptr [current_unit]
        cmp     byte ptr [si+U_AUDIO_STATE], 2
        jne     resume_audio_invalid
        cmp     byte ptr [si+U_AUDIO_RANGE], 1
        jne     resume_audio_invalid
        mov     ah, 1
        jmp     short pause_resume
resume_audio_invalid:
        mov     al, ERR_UNKNOWN_CMD
        stc
resume_audio_done:
        ret
resume_audio endp

; AH selects PAUSE=0/RESUME=1. Preserve it across SRB preparation, send one
; MMC command, and update the selected unit's audio state only after checked
; completion. A failure must not publish the requested state as if it occurred.
pause_resume proc near
        push    ax
        mov     al, SRB_DIR_NONE
        mov     cl, 10
        call    aspi_prepare
        pop     ax
        mov     byte ptr [srb+SRB_CDB], 4Bh     ; PAUSE/RESUME
        mov     byte ptr [srb+SRB_CDB+8], ah
        call    call_aspi
        call    scsi_failed
        jc      pause_resume_done
        mov     si, word ptr [current_unit]
        mov     byte ptr [si+U_AUDIO_STATE], 1
        cmp     byte ptr [srb+SRB_CDB+8], 1
        je      pause_resume_ok
        mov     byte ptr [si+U_AUDIO_STATE], 2
        ; Pause reports the saved resume position, as in the reference.
        mov     al, byte ptr [sub_position+11]
        mov     ah, byte ptr [sub_position+10]
        mov     word ptr [si+U_AUDIO_START], ax
        xor     ah, ah
        mov     al, byte ptr [sub_position+9]
        mov     word ptr [si+U_AUDIO_START+2], ax
pause_resume_ok:
        clc
pause_resume_done:
        ret
pause_resume endp

        include common/aspi/aspi_client.inc
        include common/aspi/media_control.inc

play_end        db      3 dup (0)
play_start      dd      0
capacity_data   db      8 dup (0)
sub_position    db      16 dup (0)
mcn_data        db      24 dup (0)
upc_result      db      10 dup (0)
audio_page      dw      0
audio_page_size dw      0
audio_select_size dw    0
audio_probe_size dw     0
audio_changeable db     0
audio_desired   db      8 dup (0)
audio_mode      db      AUDIO_MODE_SIZE dup (0)
audio_select    db      AUDIO_MODE_SIZE dup (0)
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

; Register type-05h devices independently of whether media are inserted.
; Page-2Ah capability discovery is optional: an unknown capability byte must
; not suppress the DOS CD unit. Unit addresses/capability summaries remain
; resident; option parsing and verbose reports below this boundary are INIT-only.
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
; Optional INIT summary for analog audio, digital audio and accuracy. Start
; with AL=0 unknown and set CAP_KNOWN only after finding the expected page.
; Do not use a missing/pre-MMC page as proof that basic READ/IOCTLs are absent;
; command-specific runtime checks remain responsible for actual operations.
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
; Parse the CONFIG.SYS initialization string, not a PSP command tail.
; /D supplies the device name shared with MSCDEX/SHSUCDX, not a DOS drive letter.
; Preserve the resident default when no name is supplied. Parsing is transient;
; request-time handlers consume the resulting header/options, not this string.
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

ifndef ASPICDA_TEST
DRIVER_ENTRY textequ <driver_start>
endif
        end     DRIVER_ENTRY
