/* SPDX-License-Identifier: GPL-2.0-or-later */
/* SCSI/ATA translation for ATA disks (see sat.h): IDENTIFY DEVICE sets up
 * the SCSI block device emulation, which then reads, writes and flushes
 * with ATA commands. */

#include <string.h>

#include "openaspi/native/sat.h"
#include "openaspi/scsi.h"

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

static void set(struct oa_blk_sense *s, oa_u8 key, oa_u8 asc, oa_u8 ascq)
{
    s->key = key;
    s->asc = asc;
    s->ascq = ascq;
}

static void ata_error(const struct oa_ata_cmd *cmd, struct oa_blk_sense *s)
{
    oa_u8 e = cmd->error;

    if ((cmd->status & OA_ATA_DF) != 0u) {
        set(s, OA_SENSE_HARDWARE_ERROR, 0x44u, 0); /* internal target failure */
    } else if ((e & OA_ATA_ERR_NM) != 0u) {
        set(s, OA_SENSE_NOT_READY, OA_ASC_MEDIUM_NOT_PRESENT, 0);
    } else if ((e & OA_ATA_ERR_MC) != 0u) {
        set(s, OA_SENSE_UNIT_ATTENTION, OA_ASC_MEDIUM_CHANGED, 0);
    } else if ((e & OA_ATA_ERR_UNC) != 0u && cmd->dir == OA_DIR_IN) {
        set(s, OA_SENSE_MEDIUM_ERROR, 0x11u, 0x04u); /* unrecovered read error */
    } else if ((e & OA_ATA_ERR_WP) != 0u && cmd->dir == OA_DIR_OUT) {
        set(s, OA_SENSE_DATA_PROTECT, OA_ASC_WRITE_PROTECTED, 0);
    } else if ((e & OA_ATA_ERR_IDNF) != 0u) {
        set(s, OA_SENSE_ILLEGAL_REQUEST, OA_ASC_LBA_OUT_OF_RANGE, 0);
    } else {
        set(s, OA_SENSE_ABORTED_COMMAND, 0, 0);
    }
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

static int sat_rw(void *ctx, oa_u64 lba, oa_u32 count, int write, void *buf, oa_u32 timeout_ms,
                  struct oa_blk_sense *s)
{
    struct oa_sat *sat = ctx;
    struct oa_ata_cmd cmd;
    oa_u8 *p = buf;
    oa_u32 n;
    int r;

    if (!sat->lba48 && lba + count > 0x0FFFFFFFul) {
        set(s, OA_SENSE_ILLEGAL_REQUEST, OA_ASC_LBA_OUT_OF_RANGE, 0);
        return OA_HOST_OK;
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
        cmd.len = n * sat->emu.block_size;
        cmd.timeout_ms = timeout_ms;
        r = sat->ata(sat->ctx, &cmd);
        if (r != OA_HOST_OK) {
            return r;
        }
        if ((cmd.status & (OA_ATA_ERR | OA_ATA_DF)) != 0u) {
            ata_error(&cmd, s);
            return OA_HOST_OK;
        }
        p += cmd.len;
        lba += n;
        count -= n;
    }
    return OA_HOST_OK;
}

static int sat_flush(void *ctx, struct oa_blk_sense *s)
{
    struct oa_sat *sat = ctx;
    struct oa_ata_cmd cmd;
    int r;

    memset(&cmd, 0, sizeof(cmd));
    cmd.command = sat->lba48 ? ATA_FLUSH_EXT : ATA_FLUSH;
    cmd.timeout_ms = 60000ul;
    r = sat->ata(sat->ctx, &cmd);
    if (r == OA_HOST_OK && (cmd.status & (OA_ATA_ERR | OA_ATA_DF)) != 0u) {
        ata_error(&cmd, s);
    }
    return r;
}

int oa_sat_init(struct oa_sat *sat, oa_ata_fn ata, void *ctx, int use_dma)
{
    struct oa_blockemu *emu = &sat->emu;
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
    emu->rw = sat_rw;
    emu->ctx = sat;
    emu->removable = (id[0] & 0x0080u) != 0u;
    sat->lba48 = (id[83] & 0x0400u) != 0u;
    if (sat->lba48) {
        emu->blocks = (oa_u64)id[100] | ((oa_u64)id[101] << 16) |
                      ((oa_u64)id[102] << 32) | ((oa_u64)id[103] << 48);
    }
    if (emu->blocks == 0u) {
        sat->lba48 = 0;
        emu->blocks = (oa_u32)id[60] | ((oa_u32)id[61] << 16);
    }
    emu->block_size = 512;
    if ((id[106] & 0xC000u) == 0x4000u && (id[106] & 0x1000u) != 0u) {
        words = (oa_u32)id[117] | ((oa_u32)id[118] << 16);
        if (words >= 256u && words <= 32768u) {
            emu->block_size = words * 2u;
        }
    }
    sat->max_sectors = sat->lba48 ? 65536ul : 256u;
    if ((id[83] & 0x3000u) != 0u || (id[82] & 0x0020u) != 0u) {
        emu->flush = sat_flush;
    }
    memcpy(emu->vendor, "ATA", 4);
    ata_string(emu->model, id + 27, 20);
    ata_string(emu->serial, id + 10, 10);
    ata_string(emu->firmware, id + 23, 4);
    if (emu->blocks == 0u) {
        return OA_HOST_NO_DEVICE; /* CHS-only disks are not supported */
    }
    return OA_HOST_OK;
}

void oa_sat_execute(struct oa_sat *sat, struct oa_srb *srb)
{
    oa_blockemu_execute(&sat->emu, srb);
}
