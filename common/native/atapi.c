/* SPDX-License-Identifier: GPL-2.0-or-later */
/* ATAPI packet rules (see atapi.h). */

#include <string.h>

#include "openaspi/aspi.h"
#include "openaspi/native/atapi.h"
#include "openaspi/scsi.h"

static int block_device(oa_u8 type)
{
    /* READ(6)/WRITE(6) address blocks only on disk, WORM, CD and MO devices;
     * on tape the same opcodes carry a transfer length with a fixed bit. */
    return type == OA_ASPI_DEVICE_DISK || type == 0x04u ||
           type == OA_ASPI_DEVICE_CDA || type == OA_ASPI_DEVICE_OPTICAL;
}

int oa_atapi_translate(oa_u8 out[16], const oa_u8 *in, oa_u8 in_len, oa_u8 type,
                       oa_u16 *alloc10)
{
    oa_u32 lba;
    oa_u16 blocks;

    memset(out, 0, 16);
    if ((in[0] == OA_SCSI_READ_6 || in[0] == OA_SCSI_WRITE_6) && block_device(type)) {
        lba = ((oa_u32)(in[1] & 0x1Fu) << 16) | ((oa_u32)in[2] << 8) | in[3];
        blocks = in[4] != 0u ? in[4] : 256u;
        out[0] = in[0] == OA_SCSI_READ_6 ? OA_SCSI_READ_10 : OA_SCSI_WRITE_10;
        oa_put_be32(out + 2, lba);
        oa_put_be16(out + 7, blocks);
        out[9] = in[5];
        return OA_ATAPI_XLATE_RW;
    }
    if (in[0] == OA_SCSI_MODE_SENSE_6) {
        out[0] = OA_SCSI_MODE_SENSE_10;
        out[1] = (oa_u8)(in[1] & 0x08u); /* DBD */
        out[2] = in[2];                  /* PC, page code */
        out[3] = in[3];                  /* subpage */
        *alloc10 = (oa_u16)(in[4] + 4u);
        oa_put_be16(out + 7, *alloc10);
        out[9] = in[5];
        return OA_ATAPI_XLATE_MODE_SENSE;
    }
    memcpy(out, in, in_len > 16u ? 16u : in_len);
    return OA_ATAPI_XLATE_NONE;
}

oa_u16 oa_atapi_mode10_to_6(oa_u8 *buf, oa_u16 len)
{
    oa_u16 data_len, bd_len, n;

    if (len < 8u) {
        return 0;
    }
    data_len = oa_get_be16(buf);     /* bytes after this field */
    bd_len = oa_get_be16(buf + 6);
    /* 6-byte header: data length, medium type, device-specific, BD length */
    n = (oa_u16)(len - 4u);
    buf[0] = (oa_u8)(data_len >= 3u + 0xFFu ? 0xFFu : (data_len > 3u ? data_len - 3u : 0u));
    buf[1] = buf[2];
    buf[2] = buf[3];
    buf[3] = (oa_u8)(bd_len > 0xFFu ? 0xFFu : bd_len);
    memmove(buf + 4, buf + 8, n - 4u);
    return n;
}

void oa_atapi_sense_from_error(oa_u8 sense[18], oa_u8 error)
{
    memset(sense, 0, 18);
    sense[0] = 0x70u;
    sense[2] = (oa_u8)(error >> 4);
    sense[7] = 10;
}
