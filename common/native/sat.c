/* SPDX-License-Identifier: GPL-2.0-or-later */
/* SCSI/ATA translation for ATA disks (see sat.h). */

#include <string.h>

#include "openaspi/native/sat.h"

#define ATA_IDENTIFY       0xECu
#define ATA_READ_PIO       0x20u
#define ATA_READ_PIO_EXT   0x24u
#define ATA_READ_DMA       0xC8u
#define ATA_READ_DMA_EXT   0x25u
#define ATA_WRITE_PIO      0x30u
#define ATA_WRITE_PIO_EXT  0x34u
#define ATA_WRITE_DMA      0xCAu
#define ATA_WRITE_DMA_EXT  0x35u
#define ATA_FLUSH          0xE7u
#define ATA_FLUSH_EXT      0xEAu

/* ATA strings hold two characters per word, high byte first. */
static void ata_string(char *dst, const oa_u16 *words, oa_u16 nwords)
{
    oa_u8 tmp[40];
    oa_u16 i, start = 0;

    for (i = 0; i < nwords; i++) {
        tmp[2u * i] = (oa_u8)(words[i] >> 8);
        tmp[2u * i + 1u] = (oa_u8)words[i];
    }
    while (start < 2u * nwords && tmp[start] == ' ') {
        start++;
    }
    oa_scsi_identity(dst, tmp + start, (oa_u16)(2u * nwords - start));
}

int oa_sat_init(struct oa_sat *sat, oa_ata_fn ata, void *ctx, int use_dma)
{
    struct oa_ata_cmd cmd;
    const oa_u16 *id;
    oa_u32 words;
    int r;

    memset(sat, 0, sizeof(*sat));
    sat->ata = ata;
    sat->ctx = ctx;
    sat->use_dma = (oa_u8)(use_dma != 0);

    memset(&cmd, 0, sizeof(cmd));
    cmd.command = ATA_IDENTIFY;
    cmd.dir = OA_DIR_IN;
    cmd.data = sat->identify;
    cmd.len = 512;
    cmd.timeout_ms = 10000;
    r = ata(ctx, &cmd);
    if (r != OA_HOST_OK) {
        return r;
    }
    if ((cmd.status & (OA_ATA_ERR | OA_ATA_DF)) != 0u) {
        return OA_HOST_NO_DEVICE;
    }

    id = sat->identify;
    if ((id[0] & 0x8000u) != 0u) { /* not an ATA device */
        return OA_HOST_NO_DEVICE;
    }
    sat->removable = (id[0] & 0x0080u) != 0u;
    sat->lba48 = (id[83] & 0x0400u) != 0u;
    if (sat->lba48) {
        sat->sectors = (oa_u64)id[100] | ((oa_u64)id[101] << 16) |
                       ((oa_u64)id[102] << 32) | ((oa_u64)id[103] << 48);
    }
    if (sat->sectors == 0u) {
        sat->lba48 = 0;
        sat->sectors = (oa_u32)id[60] | ((oa_u32)id[61] << 16);
    }
    sat->sector_size = 512;
    if ((id[106] & 0xC000u) == 0x4000u && (id[106] & 0x1000u) != 0u) {
        words = (oa_u32)id[117] | ((oa_u32)id[118] << 16);
        if (words >= 256u && words <= 32768u) {
            sat->sector_size = words * 2u;
        }
    }
    sat->max_sectors = sat->lba48 ? 65536ul : 256u;
    sat->has_flush = (id[83] & 0x3000u) != 0u || (id[82] & 0x0020u) != 0u;
    ata_string(sat->model, id + 27, 20);
    ata_string(sat->serial, id + 10, 10);
    ata_string(sat->firmware, id + 23, 4);
    if (sat->sectors == 0u) {
        return OA_HOST_NO_DEVICE; /* CHS-only disks are not supported */
    }
    return OA_HOST_OK;
}

static void set_sense(struct oa_sat *sat, struct oa_srb *srb, oa_u8 key, oa_u8 asc, oa_u8 ascq)
{
    sat->sense_key = key;
    sat->asc = asc;
    sat->ascq = ascq;
    srb->target_status = OA_STATUS_CHECK_CONDITION;
    memset(srb->sense, 0, 18);
    srb->sense[0] = 0x70u;
    srb->sense[2] = key;
    srb->sense[7] = 10;
    srb->sense[12] = asc;
    srb->sense[13] = ascq;
    srb->sense_len = 18;
}

static void illegal(struct oa_sat *sat, struct oa_srb *srb, oa_u8 asc)
{
    set_sense(sat, srb, OA_SENSE_ILLEGAL_REQUEST, asc, 0);
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

static void ata_error(struct oa_sat *sat, struct oa_srb *srb, const struct oa_ata_cmd *cmd)
{
    oa_u8 e = cmd->error;

    if ((cmd->status & OA_ATA_DF) != 0u) {
        set_sense(sat, srb, OA_SENSE_HARDWARE_ERROR, 0x44u, 0); /* internal target failure */
    } else if ((e & OA_ATA_ERR_NM) != 0u) {
        set_sense(sat, srb, OA_SENSE_NOT_READY, OA_ASC_MEDIUM_NOT_PRESENT, 0);
    } else if ((e & OA_ATA_ERR_MC) != 0u) {
        set_sense(sat, srb, OA_SENSE_UNIT_ATTENTION, OA_ASC_MEDIUM_CHANGED, 0);
    } else if ((e & OA_ATA_ERR_UNC) != 0u && cmd->dir == OA_DIR_IN) {
        set_sense(sat, srb, OA_SENSE_MEDIUM_ERROR, 0x11u, 0x04u); /* unrecovered read error */
    } else if ((e & OA_ATA_ERR_WP) != 0u && cmd->dir == OA_DIR_OUT) {
        set_sense(sat, srb, OA_SENSE_DATA_PROTECT, OA_ASC_WRITE_PROTECTED, 0);
    } else if ((e & OA_ATA_ERR_IDNF) != 0u) {
        set_sense(sat, srb, OA_SENSE_ILLEGAL_REQUEST, OA_ASC_LBA_OUT_OF_RANGE, 0);
    } else {
        set_sense(sat, srb, OA_SENSE_ABORTED_COMMAND, 0, 0);
    }
}

/* Copy a C string into a blank-padded field. */
static void pad_copy(oa_u8 *dst, const char *src, oa_u16 size)
{
    oa_u16 i;
    int end = 0;

    /* src is not read past its terminator */
    for (i = 0; i < size; i++) {
        if (!end && src[i] == '\0') {
            end = 1;
        }
        dst[i] = end ? (oa_u8)' ' : (oa_u8)src[i];
    }
}

static void inquiry(struct oa_sat *sat, struct oa_srb *srb)
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
            n = (oa_u16)strlen(sat->serial);
            buf[1] = 0x80u;
            buf[3] = (oa_u8)n;
            memcpy(buf + 4, sat->serial, n);
            reply(srb, buf, 4u + n, alloc);
            return;
        }
        illegal(sat, srb, OA_ASC_INVALID_FIELD);
        return;
    }
    if (srb->cdb[2] != 0u) {
        illegal(sat, srb, OA_ASC_INVALID_FIELD);
        return;
    }
    buf[0] = OA_ASPI_DEVICE_DISK;
    buf[1] = sat->removable ? 0x80u : 0x00u;
    buf[2] = 0x05u; /* SPC-3 */
    buf[3] = 0x02u;
    buf[4] = 31;
    pad_copy(buf + 8, "ATA", 8);
    pad_copy(buf + 16, sat->model, 16);   /* the first 16 characters */
    pad_copy(buf + 32, sat->firmware, 4);
    reply(srb, buf, OA_SCSI_INQUIRY_SIZE, alloc);
}

static void read_capacity(struct oa_sat *sat, struct oa_srb *srb, int sixteen)
{
    oa_u8 buf[32];
    oa_u64 last = sat->sectors - 1u;

    memset(buf, 0, sizeof(buf));
    if (!sixteen) {
        oa_put_be32(buf, last > 0xFFFFFFFFul ? 0xFFFFFFFFul : (oa_u32)last);
        oa_put_be32(buf + 4, sat->sector_size);
        reply(srb, buf, 8, 8);
        return;
    }
    oa_put_be64(buf, last);
    oa_put_be32(buf + 8, sat->sector_size);
    reply(srb, buf, 32, oa_get_be32(srb->cdb + 10));
}

static oa_u8 rw_command(const struct oa_sat *sat, int write)
{
    if (sat->lba48) {
        if (write) {
            return sat->use_dma ? ATA_WRITE_DMA_EXT : ATA_WRITE_PIO_EXT;
        }
        return sat->use_dma ? ATA_READ_DMA_EXT : ATA_READ_PIO_EXT;
    }
    if (write) {
        return sat->use_dma ? ATA_WRITE_DMA : ATA_WRITE_PIO;
    }
    return sat->use_dma ? ATA_READ_DMA : ATA_READ_PIO;
}

static void rw(struct oa_sat *sat, struct oa_srb *srb, oa_u64 lba, oa_u32 count, int write)
{
    struct oa_ata_cmd cmd;
    oa_u8 *p = srb->data;
    oa_u64 bytes;
    oa_u32 n;
    int r;

    if (count == 0u) {
        srb->residual = srb->data_len;
        return;
    }
    if (lba >= sat->sectors || count > sat->sectors - lba ||
        (!sat->lba48 && lba + count > 0x0FFFFFFFul)) {
        illegal(sat, srb, OA_ASC_LBA_OUT_OF_RANGE);
        return;
    }
    bytes = (oa_u64)count * sat->sector_size;
    if (srb->dir != (write ? OA_DIR_OUT : OA_DIR_IN) || bytes > srb->data_len) {
        illegal(sat, srb, OA_ASC_INVALID_FIELD);
        return;
    }

    while (count > 0u) {
        n = count < sat->max_sectors ? count : sat->max_sectors;
        memset(&cmd, 0, sizeof(cmd));
        cmd.command = rw_command(sat, write);
        cmd.lba48 = sat->lba48;
        cmd.dma = sat->use_dma;
        cmd.device = 0x40u;
        cmd.lba = lba;
        cmd.count = (oa_u16)n; /* 65536 and 256 wrap to 0, as ATA wants */
        cmd.dir = write ? OA_DIR_OUT : OA_DIR_IN;
        cmd.data = p;
        cmd.len = n * sat->sector_size;
        cmd.timeout_ms = srb->timeout_ms != 0u ? srb->timeout_ms : 30000ul;
        r = sat->ata(sat->ctx, &cmd);
        if (r != OA_HOST_OK) {
            srb->host_status = (oa_u8)r;
            return;
        }
        if ((cmd.status & (OA_ATA_ERR | OA_ATA_DF)) != 0u) {
            ata_error(sat, srb, &cmd);
            return;
        }
        p += cmd.len;
        lba += n;
        count -= n;
    }
    srb->residual = srb->data_len - (oa_u32)bytes;
}

static void flush(struct oa_sat *sat, struct oa_srb *srb)
{
    struct oa_ata_cmd cmd;
    int r;

    if (!sat->has_flush) {
        return;
    }
    memset(&cmd, 0, sizeof(cmd));
    cmd.command = sat->lba48 ? ATA_FLUSH_EXT : ATA_FLUSH;
    cmd.timeout_ms = 60000ul;
    r = sat->ata(sat->ctx, &cmd);
    if (r != OA_HOST_OK) {
        srb->host_status = (oa_u8)r;
    } else if ((cmd.status & (OA_ATA_ERR | OA_ATA_DF)) != 0u) {
        ata_error(sat, srb, &cmd);
    }
}

void oa_sat_execute(struct oa_sat *sat, struct oa_srb *srb)
{
    const oa_u8 *c = srb->cdb;
    oa_u8 buf[18];

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
        buf[2] = sat->sense_key;
        buf[7] = 10;
        buf[12] = sat->asc;
        buf[13] = sat->ascq;
        sat->sense_key = sat->asc = sat->ascq = 0;
        reply(srb, buf, 18, c[4]);
        return;
    case OA_SCSI_INQUIRY:
        inquiry(sat, srb);
        return;
    case OA_SCSI_READ_CAPACITY_10:
        read_capacity(sat, srb, 0);
        return;
    case OA_SCSI_SERVICE_ACTION_IN:
        if ((c[1] & 0x1Fu) == OA_SCSI_SAI_READ_CAPACITY) {
            read_capacity(sat, srb, 1);
            return;
        }
        illegal(sat, srb, OA_ASC_INVALID_FIELD);
        return;
    case OA_SCSI_MODE_SENSE_6: /* header only, not write protected */
        memset(buf, 0, 4);
        buf[0] = 3;
        reply(srb, buf, 4, c[4]);
        return;
    case OA_SCSI_MODE_SENSE_10:
        memset(buf, 0, 8);
        buf[1] = 6;
        reply(srb, buf, 8, oa_get_be16(c + 7));
        return;
    case OA_SCSI_READ_6:
    case OA_SCSI_WRITE_6:
        rw(sat, srb, ((oa_u32)(c[1] & 0x1Fu) << 16) | ((oa_u32)c[2] << 8) | c[3],
           c[4] != 0u ? c[4] : 256u, c[0] == OA_SCSI_WRITE_6);
        return;
    case OA_SCSI_READ_10:
    case OA_SCSI_WRITE_10:
        rw(sat, srb, oa_get_be32(c + 2), oa_get_be16(c + 7), c[0] == OA_SCSI_WRITE_10);
        return;
    case OA_SCSI_READ_12:
    case OA_SCSI_WRITE_12:
        rw(sat, srb, oa_get_be32(c + 2), oa_get_be32(c + 6), c[0] == OA_SCSI_WRITE_12);
        return;
    case OA_SCSI_READ_16:
    case OA_SCSI_WRITE_16:
        rw(sat, srb, oa_get_be64(c + 2), oa_get_be32(c + 10), c[0] == OA_SCSI_WRITE_16);
        return;
    case OA_SCSI_SYNC_CACHE_10:
    case OA_SCSI_SYNC_CACHE_16:
        flush(sat, srb);
        return;
    default:
        illegal(sat, srb, OA_ASC_INVALID_OPCODE);
        return;
    }
    if (srb->dir == OA_DIR_IN) {
        srb->residual = srb->data_len;
    }
}
