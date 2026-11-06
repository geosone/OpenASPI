/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native ASPI block device class. */

#include "openaspi/native/disk.h"
#include "openaspi/native/host.h"
#include "util.h"

#define SK_NOT_READY       0x2
#define SK_MEDIUM_ERROR    0x3
#define SK_HARDWARE_ERROR  0x4
#define SK_ILLEGAL_REQUEST 0x5
#define SK_UNIT_ATTENTION  0x6
#define SK_DATA_PROTECT    0x7

#define ASC_NO_MEDIUM      0x3a
#define ASC_MEDIUM_CHANGED 0x28

static void srb_init(struct oa_srb *srb, const struct oa_disk *disk, uint8_t len)
{
	oa_zero(srb, sizeof(*srb));
	srb->target = disk->dev->target;
	srb->lun = disk->dev->lun;
	srb->cdb_len = len;
	srb->timeout_ms = 30000;
}

/* Map a completed request to a return value. */
static int result(const struct oa_srb *srb)
{
	if (srb->host_status != OA_HOST_OK)
		return OA_EIO;
	if (srb->target_status == OA_STATUS_GOOD)
		return OA_OK;
	int key = oa_sense_key(srb), asc = oa_sense_asc(srb);
	switch (key) {
	case SK_NOT_READY:
		return (asc >> 8) == ASC_NO_MEDIUM ? OA_ENOMEDIUM : OA_EIO;
	case SK_UNIT_ATTENTION:
		return (asc >> 8) == ASC_MEDIUM_CHANGED ? OA_ECHANGED : OA_EIO;
	case SK_DATA_PROTECT:
		return OA_EROFS;
	case SK_ILLEGAL_REQUEST:
		return OA_ENOTSUP;
	default:
		return OA_EIO;
	}
}

static void run(struct oa_disk *disk, struct oa_srb *srb)
{
	oa_execute(disk->dev->hba, srb);
}

static int test_unit_ready(struct oa_disk *disk, struct oa_srb *srb)
{
	srb_init(srb, disk, 6);
	srb->cdb[0] = 0x00;
	run(disk, srb);
	return result(srb);
}

static int start_unit(struct oa_disk *disk)
{
	struct oa_srb srb;
	srb_init(&srb, disk, 6);
	srb.cdb[0] = 0x1b; /* START STOP UNIT */
	srb.cdb[4] = 0x01; /* START */
	srb.timeout_ms = 60000;
	run(disk, &srb);
	return result(&srb);
}

static int read_capacity(struct oa_disk *disk)
{
	struct oa_srb srb;
	uint8_t buf[32];

	srb_init(&srb, disk, 10);
	srb.cdb[0] = 0x25; /* READ CAPACITY (10) */
	srb.dir = OA_DIR_IN;
	srb.data = buf;
	srb.data_len = 8;
	run(disk, &srb);
	int r = result(&srb);
	if (r)
		return r;
	uint32_t last = oa_be32(buf), bs = oa_be32(buf + 4);
	if (last == 0xffffffffu) {
		srb_init(&srb, disk, 16);
		srb.cdb[0] = 0x9e; /* SERVICE ACTION IN (16) */
		srb.cdb[1] = 0x10; /* READ CAPACITY (16) */
		oa_put_be32(srb.cdb + 10, 32);
		srb.dir = OA_DIR_IN;
		srb.data = buf;
		srb.data_len = 32;
		run(disk, &srb);
		r = result(&srb);
		if (r)
			return r;
		disk->blocks = oa_be64(buf) + 1;
		bs = oa_be32(buf + 8);
		disk->use16 = 1;
	} else {
		disk->blocks = (uint64_t)last + 1;
	}
	if (bs == 0 || bs > 65536 || (bs & (bs - 1)))
		return OA_EIO;
	disk->block_size = bs;
	return OA_OK;
}

/* MODE SENSE (6), header byte 2 bit 7: write protect. Optional. */
static void check_write_protect(struct oa_disk *disk)
{
	struct oa_srb srb;
	uint8_t buf[8];

	if (disk->dev->type == OA_ASPI_DEVICE_CDA) {
		disk->write_protected = 1;
		return;
	}
	srb_init(&srb, disk, 6);
	srb.cdb[0] = 0x1a;
	srb.cdb[2] = 0x3f; /* all pages; only the header is used */
	srb.cdb[4] = sizeof(buf);
	srb.dir = OA_DIR_IN;
	srb.data = buf;
	srb.data_len = sizeof(buf);
	run(disk, &srb);
	if (oa_srb_ok(&srb) && sizeof(buf) - srb.residual >= 4)
		disk->write_protected = (buf[2] & 0x80) != 0;
}

int oa_disk_open(struct oa_disk *disk, struct oa_device *dev)
{
	struct oa_srb srb;
	int r = OA_EIO, started = 0;

	oa_zero(disk, sizeof(*disk));
	disk->dev = dev;
	if (dev->type != OA_ASPI_DEVICE_DISK && dev->type != OA_ASPI_DEVICE_CDA && dev->type != OA_ASPI_DEVICE_OPTICAL)
		return OA_ENOTSUP;

	/* Unit attention after reset or medium change is reported once;
	 * becoming ready may take seconds (spin-up, CD loading). */
	uint64_t deadline = oa_host_time_us() + 20000000u;
	for (;;) {
		r = test_unit_ready(disk, &srb);
		if (r == OA_OK)
			break;
		if (r == OA_ENOMEDIUM)
			return r;
		int key = oa_sense_key(&srb), asc = oa_sense_asc(&srb);
		if (srb.host_status != OA_HOST_OK)
			return OA_EIO;
		if (key == SK_NOT_READY && asc == 0x0402 && !started) {
			started = 1; /* "initializing command required" */
			start_unit(disk);
			continue;
		}
		if (oa_host_time_us() > deadline)
			return r == OA_ECHANGED ? OA_EIO : r;
		if (key != SK_UNIT_ATTENTION)
			oa_host_delay_us(100000);
	}
	r = read_capacity(disk);
	if (r)
		return r;
	/* 64 KiB per command keeps every transport within its limits
	 * (IDE PIO, single-PRD bounce buffers, USB BOT). */
	disk->max_blocks = 65536 / disk->block_size;
	if (!disk->max_blocks)
		disk->max_blocks = 1;
	check_write_protect(disk);
	return OA_OK;
}

static int transfer(struct oa_disk *disk, uint64_t lba, uint32_t count, void *buf, int write)
{
	uint8_t *p = buf;

	if (!disk->block_size || !count || lba >= disk->blocks || count > disk->blocks - lba)
		return OA_EINVAL;
	if (write && disk->write_protected)
		return OA_EROFS;
	while (count) {
		uint32_t n = count < disk->max_blocks ? count : disk->max_blocks;
		struct oa_srb srb;
		if (disk->use16 || lba + n > 0xffffffffu) {
			srb_init(&srb, disk, 16);
			srb.cdb[0] = write ? 0x8a : 0x88;
			oa_put_be64(srb.cdb + 2, lba);
			oa_put_be32(srb.cdb + 10, n);
		} else {
			srb_init(&srb, disk, 10);
			srb.cdb[0] = write ? 0x2a : 0x28;
			oa_put_be32(srb.cdb + 2, (uint32_t)lba);
			oa_put_be16(srb.cdb + 7, (uint16_t)n);
		}
		srb.dir = write ? OA_DIR_OUT : OA_DIR_IN;
		srb.data = p;
		srb.data_len = n * disk->block_size;
		int r = OA_EIO;
		for (int tries = 0; tries < 3; tries++) {
			run(disk, &srb);
			r = result(&srb);
			if (r == OA_OK && srb.residual)
				r = OA_EIO;
			if (r != OA_EIO || srb.host_status == OA_HOST_NO_DEVICE)
				break;
		}
		if (r)
			return r;
		lba += n;
		count -= n;
		p += (size_t)n * disk->block_size;
	}
	return OA_OK;
}

int oa_disk_read(struct oa_disk *disk, uint64_t lba, uint32_t count, void *buf)
{
	return transfer(disk, lba, count, buf, 0);
}

int oa_disk_write(struct oa_disk *disk, uint64_t lba, uint32_t count, const void *buf)
{
	return transfer(disk, lba, count, (void *)buf, 1);
}

int oa_disk_sync(struct oa_disk *disk)
{
	struct oa_srb srb;
	srb_init(&srb, disk, 10);
	srb.cdb[0] = 0x35; /* SYNCHRONIZE CACHE (10) */
	srb.timeout_ms = 60000;
	run(disk, &srb);
	int r = result(&srb);
	return r == OA_ENOTSUP ? OA_OK : r;
}
