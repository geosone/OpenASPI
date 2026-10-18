#ifndef OPENASPI_ASPITAPE_H
#define OPENASPI_ASPITAPE_H

#include "openaspi/types.h"

/* INT 21h AX=440Ch generic character-device IOCTL interface. */
#define OA_ASPITAPE_IOCTL_CATEGORY       0x07u
#define OA_ASPITAPE_IOCTL_MTOP           0x01u
#define OA_ASPITAPE_IOCTL_MTGET          0x02u
#define OA_ASPITAPE_IOCTL_IGNORE_EOT     0x03u
#define OA_ASPITAPE_IOCTL_ENABLE_EOT     0x04u

/* Operation values in the six-byte mtop parameter block. */
#define OA_MTWEOF 0u
#define OA_MTFSF  1u
#define OA_MTBSF  2u
#define OA_MTFSR  3u
#define OA_MTBSR  4u
#define OA_MTREW  5u
#define OA_MTOFFL 6u
#define OA_MTNOP  7u

/* mtget.device_parameters */
#define OA_MT_PARAM_FIXED_BLOCK 0x01u
#define OA_MT_PARAM_ASPI_DEVICE 0x80u

/* mtget.current_state */
#define OA_MT_STATE_BUFFERED       0x01u
#define OA_MT_STATE_UNBUFFERED     0x02u
#define OA_MT_STATE_REWIND_CLOSE   0x04u
#define OA_MT_STATE_WRITTEN        0x08u
#define OA_MT_STATE_READ           0x10u
#define OA_MT_STATE_EOF_NEXT_READ  0x20u
#define OA_MT_STATE_EOM_AS_EOF     0x40u
#define OA_MT_STATE_REWINDING      0x80u

#if defined(__WATCOMC__)
#pragma pack(push, 1)
#endif

struct oa_aspitape_mtop {
    oa_u16 operation;
    oa_u32 count;
}
#if !defined(__WATCOMC__)
__attribute__((packed))
#endif
;

struct oa_aspitape_mtget {
    oa_u8  host_id;
    oa_u8  target_id;
    oa_u8  lun;
    oa_u8  device_parameters;
    oa_u8  current_state;
    oa_u8  unit_number;
    oa_u16 fixed_block_size;
    oa_u8  last_scsi_status;
    oa_u8  last_sense_key;
    oa_u16 last_scsi_opcode;
    oa_u16 residual_bytes;
}
#if !defined(__WATCOMC__)
__attribute__((packed))
#endif
;

#if defined(__WATCOMC__)
#pragma pack(pop)
#endif

#endif
