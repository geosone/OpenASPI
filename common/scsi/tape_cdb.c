/* Pure six-byte sequential-access CDB builders: no submission or device state.
 * Clear reserved bits and encode multi-byte fields in SCSI big-endian order.
 * Checked builders return -1 without changing the CDB on an unencodable input.
 * A representable command does not imply that a particular drive supports it.
 */

#include <string.h>

#include "openaspi/scsi_tape.h"

static void oa_zero_cdb(oa_u8 cdb[OA_SCSI_CDB6_SIZE])
{
    memset(cdb, 0, OA_SCSI_CDB6_SIZE);
}

static void oa_store_u24(oa_u8 *destination, oa_u32 value)
{
    destination[0] = (oa_u8)(value >> 16);
    destination[1] = (oa_u8)(value >> 8);
    destination[2] = (oa_u8)value;
}

void oa_scsi_cdb_test_unit_ready(oa_u8 cdb[OA_SCSI_CDB6_SIZE])
{
    oa_zero_cdb(cdb);
    cdb[0] = OA_SCSI_TEST_UNIT_READY;
}

void oa_scsi_cdb_rewind(oa_u8 cdb[OA_SCSI_CDB6_SIZE], int immediate)
{
    oa_zero_cdb(cdb);
    cdb[0] = OA_SCSI_REWIND;
    cdb[1] = immediate ? 0x01u : 0x00u;
}

/* FIXED changes transfer_length units: whole blocks when set, bytes for
 * one variable record otherwise. The caller supplies the correctly converted
 * count; this builder does not know the current device block size.
 */
int oa_scsi_cdb_read_write(oa_u8 cdb[OA_SCSI_CDB6_SIZE], int write,
                           int fixed_blocks, oa_u32 transfer_length)
{
    if (transfer_length > 0x00FFFFFFUL) {
        return -1;
    }

    oa_zero_cdb(cdb);
    cdb[0] = write ? OA_SCSI_WRITE_6 : OA_SCSI_READ_6;
    cdb[1] = fixed_blocks ? 0x01u : 0x00u;
    oa_store_u24(&cdb[2], transfer_length);
    return 0;
}

int oa_scsi_cdb_write_filemarks(oa_u8 cdb[OA_SCSI_CDB6_SIZE],
                                oa_u32 count, int immediate)
{
    if (count > 0x00FFFFFFUL) {
        return -1;
    }

    oa_zero_cdb(cdb);
    cdb[0] = OA_SCSI_WRITE_FILEMARKS;
    cdb[1] = immediate ? 0x01u : 0x00u;
    oa_store_u24(&cdb[2], count);
    return 0;
}

/* SPACE uses a signed 24-bit count. Keep its two's-complement low 24 bits
 * after checking range; do not encode a negative count as an unsigned size.
 * The code selects blocks/filemarks/etc.; it is an enum, not a bitmask.
 */
int oa_scsi_cdb_space(oa_u8 cdb[OA_SCSI_CDB6_SIZE], oa_u8 code,
                      oa_s32 count)
{
    oa_u32 encoded;

    if (code > OA_SCSI_SPACE_EOD ||
        count < (oa_s32)-8388608L || count > (oa_s32)8388607L) {
        return -1;
    }

    oa_zero_cdb(cdb);
    cdb[0] = OA_SCSI_SPACE;
    cdb[1] = code;
    encoded = ((oa_u32)count) & 0x00FFFFFFUL;
    oa_store_u24(&cdb[2], encoded);
    return 0;
}

void oa_scsi_cdb_load_unload(oa_u8 cdb[OA_SCSI_CDB6_SIZE], int load,
                             int retension, int immediate)
{
    oa_zero_cdb(cdb);
    cdb[0] = OA_SCSI_LOAD_UNLOAD;
    cdb[1] = immediate ? 0x01u : 0x00u;
    cdb[4] = (load ? 0x01u : 0x00u) | (retension ? 0x02u : 0x00u);
}

void oa_scsi_cdb_request_sense(oa_u8 cdb[OA_SCSI_CDB6_SIZE],
                               oa_u8 allocation_length)
{
    oa_zero_cdb(cdb);
    cdb[0] = OA_SCSI_REQUEST_SENSE;
    cdb[4] = allocation_length;
}
