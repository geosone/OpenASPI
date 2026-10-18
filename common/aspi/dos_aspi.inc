; ASPI for DOS SCSI Request Block offsets and constants.
; Keep these byte-for-byte in sync with include/openaspi/aspi.h.

SRB_Cmd                 equ     00h
SRB_Status              equ     01h
SRB_HaId                equ     02h
SRB_Flags               equ     03h
SRB_Hdr_Rsvd            equ     04h

HA_Count                equ     08h
HA_SCSI_ID              equ     09h
HA_ManagerId            equ     0Ah
HA_Identifier           equ     1Ah
HA_Unique               equ     2Ah
HA_ExtFlags             equ     3Ah

SRB_Target              equ     08h
SRB_Lun                 equ     09h
SRB_DeviceType          equ     0Ah

SRB_BufLen              equ     0Ah
SRB_SenseLen            equ     0Eh
SRB_BufPointer          equ     0Fh
SRB_LinkPointer         equ     13h
SRB_CDBLen              equ     17h
SRB_HaStat              equ     18h
SRB_TargStat            equ     19h
SRB_PostProc            equ     1Ah
SRB_Workspace           equ     1Eh
SRB_CDB                 equ     40h

SC_HA_INQUIRY           equ     00h
SC_GET_DEV_TYPE         equ     01h
SC_EXEC_SCSI_CMD        equ     02h
SC_ABORT_SRB            equ     03h
SC_RESET_DEV            equ     04h
SC_SET_HA_PARMS         equ     05h
SC_GET_DISK_INFO        equ     06h

SS_PENDING              equ     00h
SS_COMP                 equ     01h
SS_ABORTED              equ     02h
SS_ABORT_FAIL           equ     03h
SS_ERR                  equ     04h
SS_INVALID_CMD          equ     80h
SS_INVALID_HA           equ     81h
SS_NO_DEVICE            equ     82h

SRB_POSTING             equ     01h
SRB_LINKING             equ     02h
SRB_RESIDUAL            equ     04h
SRB_DIR_AUTO            equ     00h
SRB_DIR_IN              equ     08h
SRB_DIR_OUT             equ     10h
SRB_DIR_NONE            equ     18h

ASPI_SRB_SIZE           equ     SRB_CDB + 16 + 32
ASPI_DEV_DISK           equ     00h
ASPI_DEV_TAPE           equ     01h
ASPI_DEV_CDA            equ     05h
