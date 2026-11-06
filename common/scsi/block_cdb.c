/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Block device command builders and READ CAPACITY decoding. */

#include <string.h>

#include "openaspi/scsi.h"

void oa_scsi_cdb_inquiry(oa_u8 cdb[6], oa_u8 allocation_length)
{
    memset(cdb, 0, 6);
    cdb[0] = OA_SCSI_INQUIRY;
    cdb[4] = allocation_length;
}

void oa_scsi_cdb_start_stop(oa_u8 cdb[6], int start, int load_eject, int immediate)
{
    memset(cdb, 0, 6);
    cdb[0] = OA_SCSI_START_STOP_UNIT;
    cdb[1] = immediate ? 0x01u : 0x00u;
    cdb[4] = (oa_u8)((start ? 0x01u : 0x00u) | (load_eject ? 0x02u : 0x00u));
}

void oa_scsi_cdb_mode_sense6(oa_u8 cdb[6], oa_u8 page, oa_u8 allocation_length)
{
    memset(cdb, 0, 6);
    cdb[0] = OA_SCSI_MODE_SENSE_6;
    cdb[2] = (oa_u8)(page & 0x3Fu);
    cdb[4] = allocation_length;
}

void oa_scsi_cdb_read_capacity10(oa_u8 cdb[10])
{
    memset(cdb, 0, 10);
    cdb[0] = OA_SCSI_READ_CAPACITY_10;
}

void oa_scsi_cdb_read_capacity16(oa_u8 cdb[16], oa_u32 allocation_length)
{
    memset(cdb, 0, 16);
    cdb[0] = OA_SCSI_SERVICE_ACTION_IN;
    cdb[1] = OA_SCSI_SAI_READ_CAPACITY;
    oa_put_be32(cdb + 10, allocation_length);
}

int oa_scsi_cdb_rw10(oa_u8 cdb[10], int write, oa_u64 lba, oa_u32 blocks)
{
    if (blocks > 0xFFFFu || lba > 0xFFFFFFFFul ||
        (oa_u64)blocks > (oa_u64)0xFFFFFFFFul + 1u - lba) {
        return -1;
    }
    memset(cdb, 0, 10);
    cdb[0] = write ? OA_SCSI_WRITE_10 : OA_SCSI_READ_10;
    oa_put_be32(cdb + 2, (oa_u32)lba);
    oa_put_be16(cdb + 7, (oa_u16)blocks);
    return 0;
}

void oa_scsi_cdb_rw16(oa_u8 cdb[16], int write, oa_u64 lba, oa_u32 blocks)
{
    memset(cdb, 0, 16);
    cdb[0] = write ? OA_SCSI_WRITE_16 : OA_SCSI_READ_16;
    oa_put_be64(cdb + 2, lba);
    oa_put_be32(cdb + 10, blocks);
}

void oa_scsi_cdb_sync_cache10(oa_u8 cdb[10])
{
    memset(cdb, 0, 10);
    cdb[0] = OA_SCSI_SYNC_CACHE_10;
}

int oa_scsi_decode_capacity10(const oa_u8 *data, oa_u16 length,
                              oa_u32 *last_lba, oa_u32 *block_size)
{
    if (data == 0 || length < 8u) {
        return -1;
    }
    *last_lba = oa_get_be32(data);
    *block_size = oa_get_be32(data + 4);
    return 0;
}

int oa_scsi_decode_capacity16(const oa_u8 *data, oa_u16 length,
                              oa_u64 *last_lba, oa_u32 *block_size)
{
    if (data == 0 || length < 12u) {
        return -1;
    }
    *last_lba = oa_get_be64(data);
    *block_size = oa_get_be32(data + 8);
    return 0;
}
