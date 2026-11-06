/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native layer tests: an in-memory ATA disk behind the SCSI/ATA
 * translation, driven through adapter registration, the bus scan and the
 * block device class. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "openaspi/native/hba.h"
#include "openaspi/native/disk.h"
#include "openaspi/native/sat.h"

static int failures;
#define CHECK(c)                                                              \
	do {                                                                  \
		if (!(c)) {                                                   \
			fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #c); \
			failures++;                                           \
		}                                                             \
	} while (0)

static int sense_is(const struct oa_srb *srb, int key, int asc, int ascq)
{
	struct oa_scsi_sense s;
	return oa_srb_sense(srb, &s) == 0 && s.sense_key == key && s.asc == asc && s.ascq == ascq;
}

/* --- an ATA disk in memory ------------------------------------------ */

struct fake_ata {
	uint8_t *media;
	uint64_t sectors;
	int lba48;
	int fail_lba; /* reading this LBA gives UNC (-1: never) */
	unsigned commands;
	uint8_t last_command;
};

static void id_string(uint16_t *w, const char *s, unsigned words)
{
	char buf[64];
	memset(buf, ' ', sizeof(buf));
	memcpy(buf, s, strlen(s));
	for (unsigned i = 0; i < words; i++)
		w[i] = (uint16_t)((uint8_t)buf[2 * i] << 8 | (uint8_t)buf[2 * i + 1]);
}

static int fake_ata_cmd(void *ctx, struct oa_ata_cmd *c)
{
	struct fake_ata *d = ctx;
	d->commands++;
	d->last_command = c->command;
	c->status = OA_ATA_DRDY;
	c->error = 0;
	switch (c->command) {
	case 0xec: {
		uint16_t id[256];
		memset(id, 0, sizeof(id));
		id_string(id + 10, "SN123", 10);
		id_string(id + 23, "1.0", 4);
		id_string(id + 27, "QEMU HARDDISK", 20);
		uint32_t s28 = d->sectors > 0x0fffffff ? 0x0fffffff : (uint32_t)d->sectors;
		id[60] = (uint16_t)s28;
		id[61] = (uint16_t)(s28 >> 16);
		if (d->lba48) {
			id[83] = 0x0400 | 0x2000;
			id[100] = (uint16_t)d->sectors;
			id[101] = (uint16_t)(d->sectors >> 16);
			id[102] = (uint16_t)(d->sectors >> 32);
		}
		memcpy(c->data, id, 512);
		return OA_HOST_OK;
	}
	case 0x20: case 0x24: case 0x25: case 0xc8:
	case 0x30: case 0x34: case 0x35: case 0xca: {
		uint32_t n = c->count ? c->count : (c->lba48 ? 65536 : 256);
		int write = c->command == 0x30 || c->command == 0x34 || c->command == 0x35 || c->command == 0xca;
		if ((c->command == 0x24 || c->command == 0x25 || c->command == 0x34 || c->command == 0x35) != (c->lba48 != 0) ||
		    c->len != n * 512 || c->lba + n > d->sectors) {
			c->status |= OA_ATA_ERR;
			c->error = OA_ATA_ERR_IDNF;
			return OA_HOST_OK;
		}
		if (!write && d->fail_lba >= 0 && (uint64_t)d->fail_lba >= c->lba &&
		    (uint64_t)d->fail_lba < c->lba + n) {
			c->status |= OA_ATA_ERR;
			c->error = OA_ATA_ERR_UNC;
			return OA_HOST_OK;
		}
		if (write)
			memcpy(d->media + c->lba * 512, c->data, c->len);
		else
			memcpy(c->data, d->media + c->lba * 512, c->len);
		return OA_HOST_OK;
	}
	case 0xe7: case 0xea:
		return OA_HOST_OK;
	}
	c->status |= OA_ATA_ERR;
	c->error = OA_ATA_ERR_ABRT;
	return OA_HOST_OK;
}

/* --- an adapter with one SAT target --------------------------------- */

static struct oa_sat sat;

static void hba_execute(struct oa_hba *hba, struct oa_srb *srb)
{
	(void)hba;
	if (srb->target != 0) {
		srb->host_status = OA_HOST_NO_DEVICE;
		return;
	}
	oa_sat_execute(&sat, srb);
}

static const struct oa_hba_ops hba_ops = { .execute = hba_execute };

int main(void)
{
	static struct fake_ata ata;
	ata.sectors = 70000; /* more than one 64 KiB transfer, LBA28 */
	ata.media = calloc(ata.sectors, 512);
	ata.fail_lba = -1;

	CHECK(oa_sat_init(&sat, fake_ata_cmd, &ata, 0) == OA_HOST_OK);
	CHECK(sat.sectors == 70000 && sat.sector_size == 512 && !sat.lba48);
	CHECK(strcmp(sat.model, "QEMU HARDDISK") == 0);
	CHECK(strcmp(sat.serial, "SN123") == 0);

	static struct oa_hba hba = { .name = "test", .ops = &hba_ops, .max_target = 3, .max_lun = 1 };
	CHECK(oa_hba_register(&hba) == 0);

	struct oa_device pool[4];
	CHECK(oa_scan(pool, 4) == 1);
	struct oa_device *dev = oa_device_first();
	CHECK(dev && dev->inquiry.device_type == OA_ASPI_DEVICE_DISK && dev->target == 0 && dev->lun == 0);
	CHECK(dev && strcmp(dev->inquiry.vendor, "ATA") == 0 && strcmp(dev->inquiry.product, "QEMU HARDDISK") == 0);

	struct oa_disk disk;
	CHECK(oa_disk_open(&disk, dev) == OA_OK);
	CHECK(disk.blocks == 70000 && disk.block_size == 512 && !disk.write_protected);

	/* write and read back across several commands */
	uint32_t n = 300;
	uint8_t *out = malloc(n * 512), *in = malloc(n * 512);
	for (uint32_t i = 0; i < n * 512; i++)
		out[i] = (uint8_t)(i * 7 + 3);
	CHECK(oa_disk_write(&disk, 1000, n, out) == OA_OK);
	CHECK(memcmp(ata.media + 1000 * 512, out, n * 512) == 0);
	CHECK(oa_disk_read(&disk, 1000, n, in) == OA_OK);
	CHECK(memcmp(in, out, n * 512) == 0);
	CHECK(ata.last_command == 0x20); /* PIO, LBA28 */

	/* bounds */
	CHECK(oa_disk_read(&disk, 69999, 2, in) == OA_EINVAL);
	CHECK(oa_disk_read(&disk, 69999, 1, in) == OA_OK);

	/* medium error becomes EIO with sense 3/11/04 */
	ata.fail_lba = 5;
	CHECK(oa_disk_read(&disk, 0, 8, in) == OA_EIO);
	{
		struct oa_srb srb;
		memset(&srb, 0, sizeof(srb));
		srb.cdb_len = 10;
		srb.cdb[0] = 0x28;
		srb.cdb[5] = 5;
		srb.cdb[8] = 1;
		srb.dir = OA_DIR_IN;
		srb.data = in;
		srb.data_len = 512;
		oa_execute(&hba, &srb);
		CHECK(srb.target_status == OA_STATUS_CHECK_CONDITION);
		CHECK(sense_is(&srb, 3, 0x11, 0x04));
	}
	ata.fail_lba = -1;

	/* unknown command: ILLEGAL REQUEST, invalid opcode */
	{
		struct oa_srb srb;
		memset(&srb, 0, sizeof(srb));
		srb.cdb_len = 6;
		srb.cdb[0] = 0x04; /* FORMAT UNIT */
		oa_execute(&hba, &srb);
		CHECK(sense_is(&srb, 5, 0x20, 0x00));
	}

	/* request validation */
	{
		struct oa_srb srb;
		memset(&srb, 0, sizeof(srb));
		srb.cdb_len = 6;
		srb.cdb[0] = 0x28; /* READ (10) needs 10 bytes */
		oa_execute(&hba, &srb);
		CHECK(srb.host_status == OA_HOST_UNSUPPORTED);
		srb.cdb_len = 10;
		srb.target = 9;
		oa_execute(&hba, &srb);
		CHECK(srb.host_status == OA_HOST_NO_DEVICE);
	}

	/* descriptor sense */
	{
		struct oa_srb srb;
		memset(&srb, 0, sizeof(srb));
		srb.target_status = OA_STATUS_CHECK_CONDITION;
		srb.sense[0] = 0x72;
		srb.sense[1] = 0x02;
		srb.sense[2] = 0x3a;
		srb.sense_len = 8;
		CHECK(sense_is(&srb, 2, 0x3a, 0x00));
	}

	CHECK(oa_disk_sync(&disk) == OA_OK);

	/* LBA48 with DMA commands */
	static struct fake_ata big;
	big.sectors = 0x10000100ull; /* beyond LBA28, sparse use only */
	big.media = NULL;
	big.lba48 = 1;
	big.fail_lba = -1;
	struct oa_sat sat48;
	CHECK(oa_sat_init(&sat48, fake_ata_cmd, &big, 1) == OA_HOST_OK);
	CHECK(sat48.lba48);
	CHECK(sat48.sectors == 0x10000100ull);
	CHECK(sat48.max_sectors == 65536);
	{
		uint8_t buf[32];
		struct oa_srb srb;
		memset(&srb, 0, sizeof(srb));
		srb.cdb_len = 16;
		srb.cdb[0] = 0x9e;
		srb.cdb[1] = 0x10;
		srb.cdb[13] = 32;
		srb.dir = OA_DIR_IN;
		srb.data = buf;
		srb.data_len = 32;
		oa_sat_execute(&sat48, &srb);
		CHECK(srb.target_status == OA_STATUS_GOOD && srb.residual == 0);
		CHECK(buf[4] == 0x10 && buf[6] == 0x00 && buf[7] == 0xff && buf[10] == 0x02);
	}

	free(out);
	free(in);
	free(ata.media);
	if (failures) {
		fprintf(stderr, "%d check(s) failed\n", failures);
		return 1;
	}
	printf("native: all checks passed\n");
	return 0;
}
