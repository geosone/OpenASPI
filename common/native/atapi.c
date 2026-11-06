/* SPDX-License-Identifier: GPL-2.0-or-later */
/* ATAPI packet rules (see atapi.h). */

#include <string.h>

#include "openaspi/aspi.h"
#include "openaspi/native/atapi.h"
#include "openaspi/native/hba.h"
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

int oa_atapi_init(struct oa_atapi *dev, oa_atapi_fn packet, void *ctx, const oa_u16 identify[256])
{
    oa_u8 cdb[16], inq[36], status = 0, error = 0;
    oa_u32 xfer = 0;
    int r;

    dev->packet = packet;
    dev->ctx = ctx;
    dev->packet_size = (oa_u8)OA_ATAPI_PACKET_SIZE(identify[0]);
    dev->dma = (oa_u8)((identify[49] & 0x0100u) != 0u);
    dev->dmadir = (oa_u8)((identify[62] & 0x8000u) != 0u);
    dev->type = (oa_u8)((identify[0] >> 8) & 0x1Fu);
    memset(cdb, 0, sizeof(cdb));
    cdb[0] = OA_SCSI_INQUIRY;
    cdb[4] = sizeof(inq);
    memset(inq, 0, sizeof(inq));
    r = packet(ctx, cdb, OA_DIR_IN, inq, sizeof(inq), 5000, &status, &error, &xfer);
    if (r == OA_HOST_OK && !(status & 0x01u) && xfer >= 1u) {
        dev->type = (oa_u8)(inq[0] & 0x1Fu);
    }
    return r;
}

void oa_atapi_execute(struct oa_atapi *dev, struct oa_srb *srb)
{
    oa_u8 packet[16], sense_cdb[16], status = 0, error = 0;
    oa_u16 alloc10 = 0;
    oa_u32 len = srb->data_len, xfer = 0;
    void *buf = srb->data;
    int kind, r;

    if (srb->lun != 0u) {
        srb->host_status = OA_HOST_NO_DEVICE;
        return;
    }
    kind = oa_atapi_translate(packet, srb->cdb, srb->cdb_len, dev->type, &alloc10);
    if (kind == OA_ATAPI_XLATE_MODE_SENSE) {
        len = alloc10; /* at most 259 bytes */
        buf = dev->reply;
    }
    if (srb->dir == OA_DIR_NONE) {
        buf = 0;
        len = 0;
    }
    r = dev->packet(dev->ctx, packet, srb->dir, buf, len, srb->timeout_ms, &status, &error, &xfer);
    if (r != OA_HOST_OK) {
        srb->host_status = (oa_u8)r;
        return;
    }
    if (status & 0x01u) { /* ERR: CHECK CONDITION, fetch the sense data */
        srb->target_status = OA_STATUS_CHECK_CONDITION;
        memset(sense_cdb, 0, sizeof(sense_cdb));
        sense_cdb[0] = OA_SCSI_REQUEST_SENSE;
        sense_cdb[4] = 18;
        r = dev->packet(dev->ctx, sense_cdb, OA_DIR_IN, srb->sense, 18, 5000, &status, &error, &xfer);
        if (r == OA_HOST_OK && !(status & 0x01u) && xfer >= 8u) {
            srb->sense_len = (oa_u8)xfer;
        } else {
            oa_atapi_sense_from_error(srb->sense, error);
            srb->sense_len = 18;
        }
        return;
    }
    if (kind == OA_ATAPI_XLATE_MODE_SENSE) {
        xfer = oa_atapi_mode10_to_6(dev->reply, (oa_u16)xfer);
        if (xfer > srb->data_len) {
            xfer = srb->data_len;
        }
        memcpy(srb->data, dev->reply, (size_t)xfer);
    }
    srb->residual = srb->dir == OA_DIR_NONE ? 0 : srb->data_len - xfer;
}
