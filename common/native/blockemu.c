/* SPDX-License-Identifier: GPL-2.0-or-later */
/* SCSI direct-access device emulation (see blockemu.h). */

#include <string.h>

#include "openaspi/aspi.h"
#include "openaspi/native/blockemu.h"
#include "openaspi/native/hba.h"
#include "openaspi/scsi.h"

static void set_sense(struct oa_blockemu *emu, struct oa_srb *srb, oa_u8 key, oa_u8 asc,
                      oa_u8 ascq)
{
    emu->pending.key = key;
    emu->pending.asc = asc;
    emu->pending.ascq = ascq;
    srb->target_status = OA_STATUS_CHECK_CONDITION;
    memset(srb->sense, 0, 18);
    srb->sense[0] = 0x70u;
    srb->sense[2] = key;
    srb->sense[7] = 10;
    srb->sense[12] = asc;
    srb->sense[13] = ascq;
    srb->sense_len = 18;
}

static void illegal(struct oa_blockemu *emu, struct oa_srb *srb, oa_u8 asc)
{
    set_sense(emu, srb, OA_SENSE_ILLEGAL_REQUEST, asc, 0);
}

/* Copy a reply into the request buffer, setting the residual. */
static void reply(struct oa_srb *srb, const void *buf, oa_u32 len, oa_u32 alloc)
{
    oa_u32 n = len < alloc ? len : alloc;

    if (n > srb->data_len) {
        n = srb->data_len;
    }
    if (srb->dir != OA_DIR_IN) {
        n = 0;
    }
    if (n != 0u) {
        memcpy(srb->data, buf, (size_t)n);
    }
    srb->residual = srb->data_len - n;
}

/* Copy a C string into a blank-padded field; src is not read past its
 * terminator. */
static void pad_copy(oa_u8 *dst, const char *src, oa_u16 size)
{
    oa_u16 i;
    int end = 0;

    for (i = 0; i < size; i++) {
        if (!end && src[i] == '\0') {
            end = 1;
        }
        dst[i] = end ? (oa_u8)' ' : (oa_u8)src[i];
    }
}

static void inquiry(struct oa_blockemu *emu, struct oa_srb *srb)
{
    oa_u8 buf[64];
    oa_u32 alloc = oa_get_be16(srb->cdb + 3);
    oa_u16 n;

    memset(buf, 0, sizeof(buf));
    if ((srb->cdb[1] & 0x01u) != 0u) { /* EVPD */
        switch (srb->cdb[2]) {
        case 0x00u: /* supported pages */
            buf[3] = 2;
            buf[4] = 0x00u;
            buf[5] = 0x80u;
            reply(srb, buf, 6, alloc);
            return;
        case 0x80u: /* unit serial number */
            n = (oa_u16)strlen(emu->serial);
            buf[1] = 0x80u;
            buf[3] = (oa_u8)n;
            memcpy(buf + 4, emu->serial, n);
            reply(srb, buf, 4u + n, alloc);
            return;
        }
        illegal(emu, srb, OA_ASC_INVALID_FIELD);
        return;
    }
    if (srb->cdb[2] != 0u) {
        illegal(emu, srb, OA_ASC_INVALID_FIELD);
        return;
    }
    buf[0] = OA_ASPI_DEVICE_DISK;
    buf[1] = emu->removable ? 0x80u : 0x00u;
    buf[2] = 0x05u; /* SPC-3 */
    buf[3] = 0x02u;
    buf[4] = 31;
    pad_copy(buf + 8, emu->vendor, 8);
    pad_copy(buf + 16, emu->model, 16);
    pad_copy(buf + 32, emu->firmware, 4);
    reply(srb, buf, OA_SCSI_INQUIRY_SIZE, alloc);
}

static void read_capacity(struct oa_blockemu *emu, struct oa_srb *srb, int sixteen)
{
    oa_u8 buf[32];
    oa_u64 last = emu->blocks - 1u;

    memset(buf, 0, sizeof(buf));
    if (!sixteen) {
        oa_put_be32(buf, last > 0xFFFFFFFFul ? 0xFFFFFFFFul : (oa_u32)last);
        oa_put_be32(buf + 4, emu->block_size);
        reply(srb, buf, 8, 8);
        return;
    }
    oa_put_be64(buf, last);
    oa_put_be32(buf + 8, emu->block_size);
    reply(srb, buf, 32, oa_get_be32(srb->cdb + 10));
}

static void result(struct oa_blockemu *emu, struct oa_srb *srb, int r,
                   const struct oa_blk_sense *s)
{
    if (r != OA_HOST_OK) {
        srb->host_status = (oa_u8)r;
    } else if (s->key != 0u) {
        set_sense(emu, srb, s->key, s->asc, s->ascq);
    }
}

static void rw(struct oa_blockemu *emu, struct oa_srb *srb, oa_u64 lba, oa_u32 count, int write)
{
    struct oa_blk_sense s;
    oa_u64 bytes;
    int r;

    if (count == 0u) {
        srb->residual = srb->data_len;
        return;
    }
    if (lba >= emu->blocks || count > emu->blocks - lba) {
        illegal(emu, srb, OA_ASC_LBA_OUT_OF_RANGE);
        return;
    }
    bytes = (oa_u64)count * emu->block_size;
    if (srb->dir != (write ? OA_DIR_OUT : OA_DIR_IN) || bytes > srb->data_len) {
        illegal(emu, srb, OA_ASC_INVALID_FIELD);
        return;
    }
    if (write && emu->write_protected) {
        set_sense(emu, srb, OA_SENSE_DATA_PROTECT, OA_ASC_WRITE_PROTECTED, 0);
        return;
    }
    memset(&s, 0, sizeof(s));
    r = emu->rw(emu->ctx, lba, count, write, srb->data,
                srb->timeout_ms != 0u ? srb->timeout_ms : 30000ul, &s);
    result(emu, srb, r, &s);
    if (r == OA_HOST_OK && s.key == 0u) {
        srb->residual = srb->data_len - (oa_u32)bytes;
    }
}

void oa_blockemu_execute(struct oa_blockemu *emu, struct oa_srb *srb)
{
    const oa_u8 *c = srb->cdb;
    struct oa_blk_sense s;
    oa_u8 buf[18];
    int r;

    if (srb->lun != 0u) {
        srb->host_status = OA_HOST_NO_DEVICE;
        return;
    }
    switch (c[0]) {
    case OA_SCSI_TEST_UNIT_READY:
    case OA_SCSI_START_STOP_UNIT:
        break;
    case OA_SCSI_REQUEST_SENSE:
        memset(buf, 0, sizeof(buf));
        buf[0] = 0x70u;
        buf[2] = emu->pending.key;
        buf[7] = 10;
        buf[12] = emu->pending.asc;
        buf[13] = emu->pending.ascq;
        memset(&emu->pending, 0, sizeof(emu->pending));
        reply(srb, buf, 18, c[4]);
        return;
    case OA_SCSI_INQUIRY:
        inquiry(emu, srb);
        return;
    case OA_SCSI_READ_CAPACITY_10:
        read_capacity(emu, srb, 0);
        return;
    case OA_SCSI_SERVICE_ACTION_IN:
        if ((c[1] & 0x1Fu) == OA_SCSI_SAI_READ_CAPACITY) {
            read_capacity(emu, srb, 1);
            return;
        }
        illegal(emu, srb, OA_ASC_INVALID_FIELD);
        return;
    case OA_SCSI_MODE_SENSE_6: /* header only */
        memset(buf, 0, 4);
        buf[0] = 3;
        buf[2] = emu->write_protected ? 0x80u : 0u;
        reply(srb, buf, 4, c[4]);
        return;
    case OA_SCSI_MODE_SENSE_10:
        memset(buf, 0, 8);
        buf[1] = 6;
        buf[3] = emu->write_protected ? 0x80u : 0u;
        reply(srb, buf, 8, oa_get_be16(c + 7));
        return;
    case OA_SCSI_READ_6:
    case OA_SCSI_WRITE_6:
        rw(emu, srb, ((oa_u32)(c[1] & 0x1Fu) << 16) | ((oa_u32)c[2] << 8) | c[3],
           c[4] != 0u ? c[4] : 256u, c[0] == OA_SCSI_WRITE_6);
        return;
    case OA_SCSI_READ_10:
    case OA_SCSI_WRITE_10:
        rw(emu, srb, oa_get_be32(c + 2), oa_get_be16(c + 7), c[0] == OA_SCSI_WRITE_10);
        return;
    case OA_SCSI_READ_12:
    case OA_SCSI_WRITE_12:
        rw(emu, srb, oa_get_be32(c + 2), oa_get_be32(c + 6), c[0] == OA_SCSI_WRITE_12);
        return;
    case OA_SCSI_READ_16:
    case OA_SCSI_WRITE_16:
        rw(emu, srb, oa_get_be64(c + 2), oa_get_be32(c + 10), c[0] == OA_SCSI_WRITE_16);
        return;
    case OA_SCSI_SYNC_CACHE_10:
    case OA_SCSI_SYNC_CACHE_16:
        if (emu->flush != 0) {
            memset(&s, 0, sizeof(s));
            r = emu->flush(emu->ctx, &s);
            result(emu, srb, r, &s);
        }
        return;
    default:
        illegal(emu, srb, OA_ASC_INVALID_OPCODE);
        return;
    }
    if (srb->dir == OA_DIR_IN) {
        srb->residual = srb->data_len;
    }
}
