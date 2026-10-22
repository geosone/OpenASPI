; DOS device driver request header: offsets, commands and status words
; shared by the OpenASPI drivers.  Block, character and CD-ROM drivers use
; different subsets; see docs/driver-suite.md.

RH_LENGTH       equ     00h
RH_UNIT         equ     01h
RH_COMMAND      equ     02h
RH_STATUS       equ     03h

; INIT (00h)
RH_INIT_UNITS   equ     0Dh             ; block: number of units
RH_INIT_END     equ     0Eh             ; dword: end of the resident part
RH_INIT_ARGS    equ     12h             ; dword: CONFIG.SYS line / block: BPB array
RH_INIT_DRIVE   equ     16h             ; block: first drive (0 = A:)

; MEDIA CHECK (01h)
RH_MEDIA_ID     equ     0Dh
RH_MEDIA_RET    equ     0Eh             ; 1 unchanged, 0 unknown, -1 changed
RH_MEDIA_VOL    equ     0Fh             ; dword: previous volume label

; BUILD BPB (02h)
RH_BPB_PTR      equ     12h             ; dword: returned BPB

; READ / WRITE (04h, 08h, 09h) and IOCTL (03h, 0Ch)
RH_MEDIA        equ     0Dh
RH_BUFFER       equ     0Eh             ; dword
RH_COUNT        equ     12h             ; sectors / bytes
RH_START        equ     14h             ; word start sector, 0FFFFh: dword below
RH_VOLUME       equ     16h             ; dword: volume label on error
RH_START32      equ     1Ah             ; dword start sector (DOS 4+)

; CD-ROM READ LONG (80h), PREFETCH (82h), SEEK (83h), PLAY (84h)
RH_CD_ADDRMODE  equ     0Dh             ; 0 HSG (LBA), 1 Red Book (MSF)
RH_CD_BUFFER    equ     0Eh             ; dword
RH_CD_COUNT     equ     12h             ; sectors
RH_CD_START     equ     14h             ; dword
RH_CD_READMODE  equ     18h             ; 0 cooked (2048), 1 raw (2352)
RH_CD_PLAYSTART equ     0Eh             ; PLAY AUDIO: dword start
RH_CD_PLAYCOUNT equ     12h             ; PLAY AUDIO: dword sectors

CMD_INIT        equ     00h
CMD_MEDIA_CHECK equ     01h
CMD_BUILD_BPB   equ     02h
CMD_IOCTL_IN    equ     03h
CMD_READ        equ     04h
CMD_INPUT_FLUSH equ     07h
CMD_WRITE       equ     08h
CMD_WRITE_VERIFY equ    09h
CMD_OUTPUT_FLUSH equ    0Bh
CMD_IOCTL_OUT   equ     0Ch
CMD_OPEN        equ     0Dh
CMD_CLOSE       equ     0Eh
CMD_REMOVABLE   equ     0Fh
CMD_GEN_IOCTL   equ     13h
CMD_GET_LOGICAL equ     17h
CMD_SET_LOGICAL equ     18h
CMD_IOCTL_QUERY equ     19h
CMD_READ_LONG   equ     80h
CMD_READ_PREFETCH equ   82h
CMD_SEEK        equ     83h
CMD_PLAY_AUDIO  equ     84h
CMD_STOP_AUDIO  equ     85h
CMD_WRITE_LONG  equ     86h
CMD_WRITE_LONG_VERIFY equ 87h
CMD_RESUME_AUDIO equ    88h

ST_DONE         equ     0100h
ST_BUSY         equ     0200h
ST_ERROR        equ     8000h

ERR_WRITE_PROTECT equ   00h
ERR_UNKNOWN_UNIT equ    01h
ERR_NOT_READY   equ     02h
ERR_UNKNOWN_CMD equ     03h
ERR_CRC         equ     04h
ERR_SEEK        equ     06h
ERR_UNKNOWN_MEDIA equ   07h
ERR_NOT_FOUND   equ     08h
ERR_WRITE       equ     0Ah
ERR_READ        equ     0Bh
ERR_GENERAL     equ     0Ch
ERR_MEDIA_CHANGE equ    0Fh

; SCSI sense key -> DOS error
; 2 NOT READY -> 02h, 3 MEDIUM ERROR -> 0Bh, 5 ILLEGAL REQUEST -> 08h,
; 6 UNIT ATTENTION -> 0Fh, 7 DATA PROTECT -> 00h, others -> 0Ch
