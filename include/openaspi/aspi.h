#ifndef OPENASPI_ASPI_H
#define OPENASPI_ASPI_H

#include "openaspi/types.h"

/* ASPI for DOS command codes. */
#define OA_ASPI_HA_INQUIRY       0x00u
#define OA_ASPI_GET_DEVICE_TYPE  0x01u
#define OA_ASPI_EXEC_SCSI        0x02u
#define OA_ASPI_ABORT_SRB        0x03u
#define OA_ASPI_RESET_DEVICE     0x04u
#define OA_ASPI_SET_HA_PARAMS    0x05u
#define OA_ASPI_GET_DISK_INFO    0x06u

/* SRB completion status. */
#define OA_ASPI_PENDING          0x00u
#define OA_ASPI_COMPLETE         0x01u
#define OA_ASPI_ABORTED          0x02u
#define OA_ASPI_ABORT_FAILED     0x03u
#define OA_ASPI_ERROR            0x04u
#define OA_ASPI_INVALID_COMMAND  0x80u
#define OA_ASPI_INVALID_HA       0x81u
#define OA_ASPI_NO_DEVICE        0x82u

/* Execute-SCSI flags. */
#define OA_ASPI_POSTING          0x01u
#define OA_ASPI_LINKING          0x02u
#define OA_ASPI_RESIDUAL         0x04u
#define OA_ASPI_DIRECTION_AUTO   0x00u
#define OA_ASPI_DIRECTION_IN     0x08u
#define OA_ASPI_DIRECTION_OUT    0x10u
#define OA_ASPI_DIRECTION_NONE   0x18u

/* SCSI peripheral device types used by the DOS component detectors. */
#define OA_ASPI_DEVICE_DISK      0x00u
#define OA_ASPI_DEVICE_TAPE      0x01u
#define OA_ASPI_DEVICE_CDA       0x05u

#define OA_ASPI_MANAGER_ID_SIZE  16u
#define OA_ASPI_IDENTIFIER_SIZE  16u
#define OA_ASPI_UNIQUE_SIZE      16u
#define OA_ASPI_CDB_SIZE         16u
#define OA_ASPI_SENSE_SIZE       32u
/* DOS autosense begins after the actual CDB length (6/10/12/16), not
 * necessarily after all sixteen bytes reserved for CDB storage below. */
#define OA_ASPI_SENSE_OFFSET(cdb_length) (64u + (cdb_length))

#if defined(__WATCOMC__)
#pragma pack(push, 1)
#endif

struct oa_aspi_far_pointer {
    oa_u16 offset;
    oa_u16 segment;
}
#if !defined(__WATCOMC__)
__attribute__((packed))
#endif
;

struct oa_aspi_header {
    oa_u8 command;
    oa_u8 status;
    oa_u8 host_adapter;
    oa_u8 flags;
    oa_u32 reserved;
}
#if !defined(__WATCOMC__)
__attribute__((packed))
#endif
;

struct oa_aspi_ha_inquiry {
    struct oa_aspi_header header;
    oa_u8 adapter_count;
    oa_u8 adapter_scsi_id;
    oa_u8 manager_id[OA_ASPI_MANAGER_ID_SIZE];
    oa_u8 identifier[OA_ASPI_IDENTIFIER_SIZE];
    oa_u8 unique[OA_ASPI_UNIQUE_SIZE];
    oa_u16 extension_flags;
}
#if !defined(__WATCOMC__)
__attribute__((packed))
#endif
;

struct oa_aspi_get_device_type {
    struct oa_aspi_header header;
    oa_u8 target;
    oa_u8 lun;
    oa_u8 device_type;
}
#if !defined(__WATCOMC__)
__attribute__((packed))
#endif
;

struct oa_aspi_exec_scsi {
    struct oa_aspi_header header;
    oa_u8 target;
    oa_u8 lun;
    oa_u32 buffer_length;
    oa_u8 sense_length;
    struct oa_aspi_far_pointer buffer;
    struct oa_aspi_far_pointer link;
    oa_u8 cdb_length;
    oa_u8 ha_status;
    oa_u8 target_status;
    struct oa_aspi_far_pointer post;
    oa_u8 workspace[34];
    oa_u8 cdb[OA_ASPI_CDB_SIZE];
    /* Extra storage; use OA_ASPI_SENSE_OFFSET(cdb_length) from the SRB base
     * to access autosense. For a six-byte CDB it overlaps cdb[6..15]. */
    oa_u8 sense_tail[OA_ASPI_SENSE_SIZE];
}
#if !defined(__WATCOMC__)
__attribute__((packed))
#endif
;

#if defined(__WATCOMC__)
#pragma pack(pop)
#endif

#endif
