/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native ASPI block device class. */

#include <string.h>

#include "openaspi/native/disk.h"
#include "openaspi/native/host.h"

static void srb_init(struct oa_srb *srb, const struct oa_disk *disk, oa_u8 len)
{
    memset(srb, 0, sizeof(*srb));
    srb->target = disk->dev->target;
    srb->lun = disk->dev->lun;
    srb->cdb_len = len;
    srb->timeout_ms = 30000;
}

/* Map a completed request to a return value. */
static int result(const struct oa_srb *srb)
{
    struct oa_scsi_sense s;

    if (srb->host_status != OA_HOST_OK) {
        return OA_EIO;
    }
    if (srb->target_status == OA_STATUS_GOOD) {
        return OA_OK;
    }
    if (oa_srb_sense(srb, &s) < 0) {
        return OA_EIO;
    }
    switch (s.sense_key) {
    case OA_SENSE_NOT_READY:
        return s.asc == OA_ASC_MEDIUM_NOT_PRESENT ? OA_ENOMEDIUM : OA_EIO;
    case OA_SENSE_UNIT_ATTENTION:
        return s.asc == OA_ASC_MEDIUM_CHANGED ? OA_ECHANGED : OA_EIO;
    case OA_SENSE_DATA_PROTECT:
        return OA_EROFS;
    case OA_SENSE_ILLEGAL_REQUEST:
        return OA_ENOTSUP;
    default:
        return OA_EIO;
    }
}

static void run(struct oa_disk *disk, struct oa_srb *srb)
{
    oa_execute(disk->dev->hba, srb);
}

static void start_unit(struct oa_disk *disk)
{
    struct oa_srb srb;
    srb_init(&srb, disk, 6);
    oa_scsi_cdb_start_stop(srb.cdb, 1, 0, 0);
    srb.timeout_ms = 60000;
    run(disk, &srb);
}

static int read_capacity(struct oa_disk *disk)
{
    struct oa_srb srb;
    oa_u8 buf[32];
    oa_u32 last32, bs;
    oa_u64 last;
    int r;

    srb_init(&srb, disk, 10);
    oa_scsi_cdb_read_capacity10(srb.cdb);
    srb.dir = OA_DIR_IN;
    srb.data = buf;
    srb.data_len = 8;
    run(disk, &srb);
    r = result(&srb);
    if (r != OA_OK) {
        return r;
    }
    if (oa_scsi_decode_capacity10(buf, (oa_u16)(8u - srb.residual), &last32, &bs) < 0) {
        return OA_EIO;
    }
    last = last32;
    if (last32 == 0xFFFFFFFFul) {
        srb_init(&srb, disk, 16);
        oa_scsi_cdb_read_capacity16(srb.cdb, 32);
        srb.dir = OA_DIR_IN;
        srb.data = buf;
        srb.data_len = 32;
        run(disk, &srb);
        r = result(&srb);
        if (r != OA_OK) {
            return r;
        }
        if (oa_scsi_decode_capacity16(buf, (oa_u16)(32u - srb.residual), &last, &bs) < 0) {
            return OA_EIO;
        }
        disk->use16 = 1;
    }
    if (bs == 0u || bs > 65536ul || (bs & (bs - 1u)) != 0u) {
        return OA_EIO;
    }
    disk->blocks = last + 1u;
    disk->block_size = bs;
    return OA_OK;
}

/* MODE SENSE (6) header, byte 2 bit 7: write protect. Optional. */
static void check_write_protect(struct oa_disk *disk)
{
    struct oa_srb srb;
    oa_u8 buf[8];

    if (disk->dev->inquiry.device_type == OA_ASPI_DEVICE_CDA) {
        disk->write_protected = 1;
        return;
    }
    srb_init(&srb, disk, 6);
    oa_scsi_cdb_mode_sense6(srb.cdb, 0x3Fu, (oa_u8)sizeof(buf));
    srb.dir = OA_DIR_IN;
    srb.data = buf;
    srb.data_len = sizeof(buf);
    run(disk, &srb);
    if (oa_srb_ok(&srb) && sizeof(buf) - srb.residual >= 4u) {
        disk->write_protected = (buf[2] & 0x80u) != 0u;
    }
}

int oa_disk_open(struct oa_disk *disk, struct oa_device *dev)
{
    struct oa_srb srb;
    struct oa_scsi_sense s;
    oa_u64 deadline;
    int r, started = 0;
    oa_u8 type = dev->inquiry.device_type;

    memset(disk, 0, sizeof(*disk));
    disk->dev = dev;
    if (type != OA_ASPI_DEVICE_DISK && type != OA_ASPI_DEVICE_CDA &&
        type != OA_ASPI_DEVICE_OPTICAL) {
        return OA_ENOTSUP;
    }

    /* Unit attention after reset or medium change is reported once;
     * becoming ready may take seconds (spin-up, CD loading). */
    deadline = oa_host_time_us() + 20000000ul;
    for (;;) {
        srb_init(&srb, disk, 6);
        srb.cdb[0] = OA_SCSI_TEST_UNIT_READY;
        run(disk, &srb);
        r = result(&srb);
        if (r == OA_OK) {
            break;
        }
        if (r == OA_ENOMEDIUM || srb.host_status != OA_HOST_OK) {
            return r;
        }
        if (oa_srb_sense(&srb, &s) == 0 && s.sense_key == OA_SENSE_NOT_READY &&
            s.asc == 0x04u && s.ascq == 0x02u && !started) {
            started = 1; /* "initializing command required" */
            start_unit(disk);
            continue;
        }
        if (oa_host_time_us() > deadline) {
            return r == OA_ECHANGED ? OA_EIO : r;
        }
        if (r != OA_ECHANGED) {
            oa_host_delay_us(100000ul);
        }
    }
    r = read_capacity(disk);
    if (r != OA_OK) {
        return r;
    }
    /* 64 KiB per command keeps every transport within its limits
     * (IDE PIO, single-PRD bounce buffers, USB BOT). */
    disk->max_blocks = 65536ul / disk->block_size;
    if (disk->max_blocks == 0u) {
        disk->max_blocks = 1;
    }
    check_write_protect(disk);
    return OA_OK;
}

static int transfer(struct oa_disk *disk, oa_u64 lba, oa_u32 count, void *buf, int write)
{
    oa_u8 *p = buf;
    struct oa_srb srb;
    oa_u32 n;
    int r, tries;

    if (disk->block_size == 0u || count == 0u || lba >= disk->blocks ||
        count > disk->blocks - lba) {
        return OA_EINVAL;
    }
    if (write && disk->write_protected) {
        return OA_EROFS;
    }
    while (count > 0u) {
        n = count < disk->max_blocks ? count : disk->max_blocks;
        srb_init(&srb, disk, 10);
        if (disk->use16 || oa_scsi_cdb_rw10(srb.cdb, write, lba, n) < 0) {
            srb.cdb_len = 16;
            oa_scsi_cdb_rw16(srb.cdb, write, lba, n);
        }
        srb.dir = write ? OA_DIR_OUT : OA_DIR_IN;
        srb.data = p;
        srb.data_len = n * disk->block_size;
        r = OA_EIO;
        for (tries = 0; tries < 3; tries++) {
            run(disk, &srb);
            r = result(&srb);
            if (r == OA_OK && srb.residual != 0u) {
                r = OA_EIO;
            }
            if (r != OA_EIO || srb.host_status == OA_HOST_NO_DEVICE) {
                break;
            }
        }
        if (r != OA_OK) {
            return r;
        }
        lba += n;
        count -= n;
        p += n * disk->block_size;
    }
    return OA_OK;
}

int oa_disk_read(struct oa_disk *disk, oa_u64 lba, oa_u32 count, void *buf)
{
    return transfer(disk, lba, count, buf, 0);
}

int oa_disk_write(struct oa_disk *disk, oa_u64 lba, oa_u32 count, const void *buf)
{
    return transfer(disk, lba, count, (void *)buf, 1);
}

int oa_disk_sync(struct oa_disk *disk)
{
    struct oa_srb srb;
    int r;

    srb_init(&srb, disk, 10);
    oa_scsi_cdb_sync_cache10(srb.cdb);
    srb.timeout_ms = 60000ul;
    run(disk, &srb);
    r = result(&srb);
    return r == OA_ENOTSUP ? OA_OK : r;
}
