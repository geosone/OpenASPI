/* Legacy ASPITAPE-compatible character-device IOCTL packets (category 07h).
 * This ABI is distinct from native OTAP packets in tape_api.h. Select the
 * 14-byte or 16-byte status layout explicitly; do not infer it from buffer
 * contents. Packed fields preserve DOS offsets across compilers; status and
 * operation encodings describe the legacy contract, not generic SCSI CDBs.
 */

#ifndef OPENASPI_ASPITAPE_H
#define OPENASPI_ASPITAPE_H

#include "openaspi/types.h"

/* INT 21h AX=440Ch generic character-device IOCTL interface. */
#define OA_ASPITAPE_IOCTL_CATEGORY       0x07u
#define OA_ASPITAPE_IOCTL_MTOP           0x01u
#define OA_ASPITAPE_IOCTL_MTGET          0x02u
#define OA_ASPITAPE_IOCTL_IGNORE_EOT     0x03u
#define OA_ASPITAPE_IOCTL_ENABLE_EOT     0x04u
#define OA_ASPITAPE_IOCTL_MTGET16        0x05u

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

/* 1992 IOCTL.H/MTIO.H layout: function 05h, or 02h with driver -2.
 * The upper state bits differ from the fourteen-byte manual layout. */
#define OA_MT16_STATE_MTOP         0x0020u
#define OA_MT16_STATE_EOF_NEXT_READ 0x0040u
#define OA_MT16_STATE_EOM_AS_EOF    0x0080u
#define OA_MT16_STATE_REWINDING     0x0100u
#define OA_MT16_STATE_WRITE_ERROR   0x0200u /* saved write/finalization failure */
#define OA_MT_ERROR_NOT_READY      16u
#define OA_MT_ERROR_MULTIPLE       17u
#define OA_MT_ERROR_SINGLE_BYTE    18u
#define OA_MT_ERROR_READ_AFTER_WRITE 19u
#define OA_MT_ERROR_IOCTL          20u
#define OA_MT_ERROR_MTOP           21u
#define OA_MT_ERROR_BUSY           22u
#define OA_MT_ERROR_INTERRUPTED    23u
#define OA_MT_ERROR_UNSPECIFIED    31u /* OpenASPI extension */

#if defined(__WATCOMC__)
#pragma pack(push, 1)
#endif

/* Six-byte request, little-endian operation/count. count is unsigned at the
 * ABI boundary; the operation chooses forward/backward semantics and the driver
 * checks the command-specific SCSI range before encoding a signed SPACE count.
 */
struct oa_aspitape_mtop {
    oa_u16 operation;
    oa_u32 count;
}
#if !defined(__WATCOMC__)
__attribute__((packed))
#endif
;

/* Fourteen-byte status response. fixed_block_size=0 describes variable mode;
 * residual_bytes is untransferred data, not an absolute tape position. Status
 * fields can report a saved write failure; requesting status does not run TUR.
 */
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

/* Sixteen-byte status response, selected via explicit 05h or configured 02h.
 * The WORD current_state moves every following field relative to the 14-byte
 * layout; driver_error is separate from SCSI sense. WRITE_ERROR marks a saved
 * write/finalization snapshot that a later successful status query cannot erase.
 */
struct oa_aspitape_mtget16 {
    oa_u8  host_id;
    oa_u8  target_id;
    oa_u8  lun;
    oa_u8  device_parameters;
    oa_u16 current_state;
    oa_u8  unit_number;
    oa_u8  driver_error;
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
