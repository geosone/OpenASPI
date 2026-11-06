/* SPDX-License-Identifier: GPL-2.0-or-later */
/* SCSI/ATA translation for ATA disks (see sat.h). */

#include "openaspi/native/sat.h"
#include "openaspi/native/host.h"
#include "util.h"

#define ATA_IDENTIFY       0xec
#define ATA_READ_PIO       0x20
#define ATA_READ_PIO_EXT   0x24
#define ATA_READ_DMA       0xc8
#define ATA_READ_DMA_EXT   0x25
#define ATA_WRITE_PIO      0x30
#define ATA_WRITE_PIO_EXT  0x34
#define ATA_WRITE_DMA      0xca
#define ATA_WRITE_DMA_EXT  0x35
#define ATA_FLUSH          0xe7
#define ATA_FLUSH_EXT      0xea

/* Swap the bytes of ATA string words into a C string. */
static void ata_string(char *dst, const uint16_t *words, unsigned nwords)
{
	uint8_t tmp[40];
	for (unsigned i = 0; i < nwords; i++) {
		tmp[2 * i] = (uint8_t)(words[i] >> 8);
		tmp[2 * i + 1] = (uint8_t)words[i];
	}
	unsigned start = 0;
	while (start < 2 * nwords && tmp[start] == ' ')
		start++;
	oa_trim_copy(dst, tmp + start, 2 * nwords - start);
}

int oa_sat_init(struct oa_sat *sat, oa_ata_fn ata, void *ctx, int use_dma)
{
	struct oa_ata_cmd cmd;
	oa_zero(sat, sizeof(*sat));
	sat->ata = ata;
	sat->ctx = ctx;
	sat->use_dma = (uint8_t)(use_dma != 0);

	oa_zero(&cmd, sizeof(cmd));
	cmd.command = ATA_IDENTIFY;
	cmd.dir = OA_DIR_IN;
	cmd.data = sat->identify;
	cmd.len = 512;
	cmd.timeout_ms = 10000;
	int r = ata(ctx, &cmd);
	if (r != OA_HOST_OK)
		return r;
	if (cmd.status & (OA_ATA_ERR | OA_ATA_DF))
		return OA_HOST_NO_DEVICE;

	const uint16_t *id = sat->identify;
	if (id[0] & 0x8000) /* not an ATA device */
		return OA_HOST_NO_DEVICE;
	sat->removable = (id[0] & 0x0080) != 0;
	sat->lba48 = (id[83] & 0x0400) != 0;
	if (sat->lba48)
		sat->sectors = (uint64_t)id[100] | (uint64_t)id[101] << 16 |
			       (uint64_t)id[102] << 32 | (uint64_t)id[103] << 48;
	if (!sat->sectors) {
		sat->lba48 = 0;
		sat->sectors = (uint32_t)id[60] | (uint32_t)id[61] << 16;
	}
	sat->sector_size = 512;
	if ((id[106] & 0xc000) == 0x4000 && (id[106] & 0x1000)) {
		uint32_t words = (uint32_t)id[117] | (uint32_t)id[118] << 16;
		if (words >= 256 && words <= 32768)
			sat->sector_size = words * 2;
	}
	sat->max_sectors = sat->lba48 ? 65536 : 256;
	sat->has_flush = (id[83] & 0x3000) != 0 || (id[82] & 0x0020) != 0;
	ata_string(sat->model, id + 27, 20);
	ata_string(sat->serial, id + 10, 10);
	ata_string(sat->firmware, id + 23, 4);
	if (!sat->sectors)
		return OA_HOST_NO_DEVICE; /* CHS-only disks are not supported */
	return OA_HOST_OK;
}

static void set_sense(struct oa_sat *sat, struct oa_srb *srb, uint8_t key, uint8_t asc, uint8_t ascq)
{
	sat->sense_key = key;
	sat->asc = asc;
	sat->ascq = ascq;
	srb->target_status = OA_STATUS_CHECK_CONDITION;
	oa_zero(srb->sense, 18);
	srb->sense[0] = 0x70;
	srb->sense[2] = key;
	srb->sense[7] = 10;
	srb->sense[12] = asc;
	srb->sense[13] = ascq;
	srb->sense_len = 18;
}

static void illegal(struct oa_sat *sat, struct oa_srb *srb, uint8_t asc)
{
	set_sense(sat, srb, 0x5, asc, 0); /* 20h invalid opcode, 24h invalid field, 21h LBA range */
}

/* Copy a reply into the request buffer, setting the residual. */
static void reply(struct oa_srb *srb, const void *buf, uint32_t len, uint32_t alloc)
{
	uint32_t n = len < alloc ? len : alloc;
	if (n > srb->data_len)
		n = srb->data_len;
	if (srb->dir != OA_DIR_IN)
		n = 0;
	if (n)
		oa_copy(srb->data, buf, n);
	srb->residual = srb->data_len - n;
}

static void ata_error(struct oa_sat *sat, struct oa_srb *srb, const struct oa_ata_cmd *cmd)
{
	uint8_t e = cmd->error;
	if (cmd->status & OA_ATA_DF)
		set_sense(sat, srb, 0x4, 0x44, 0);          /* internal target failure */
	else if (e & OA_ATA_ERR_NM)
		set_sense(sat, srb, 0x2, 0x3a, 0);          /* medium not present */
	else if (e & OA_ATA_ERR_MC)
		set_sense(sat, srb, 0x6, 0x28, 0);          /* medium changed */
	else if ((e & OA_ATA_ERR_UNC) && cmd->dir == OA_DIR_IN)
		set_sense(sat, srb, 0x3, 0x11, 0x04);       /* unrecovered read error */
	else if ((e & OA_ATA_ERR_WP) && cmd->dir == OA_DIR_OUT)
		set_sense(sat, srb, 0x7, 0x27, 0);          /* write protected */
	else if (e & OA_ATA_ERR_IDNF)
		set_sense(sat, srb, 0x5, 0x21, 0);          /* LBA out of range */
	else
		set_sense(sat, srb, 0xb, 0, 0);             /* aborted command */
}

static void inquiry(struct oa_sat *sat, struct oa_srb *srb)
{
	uint8_t buf[64];
	uint32_t alloc = oa_be16(srb->cdb + 3);

	oa_zero(buf, sizeof(buf));
	if (srb->cdb[1] & 0x01) { /* EVPD */
		switch (srb->cdb[2]) {
		case 0x00:
			buf[3] = 2;
			buf[4] = 0x00;
			buf[5] = 0x80;
			reply(srb, buf, 6, alloc);
			return;
		case 0x80: {
			unsigned n = 0;
			while (sat->serial[n])
				n++;
			buf[1] = 0x80;
			buf[3] = (uint8_t)n;
			oa_copy(buf + 4, sat->serial, n);
			reply(srb, buf, 4 + n, alloc);
			return;
		}
		}
		illegal(sat, srb, 0x24);
		return;
	}
	if (srb->cdb[2]) {
		illegal(sat, srb, 0x24);
		return;
	}
	buf[0] = OA_TYPE_DISK;
	buf[1] = sat->removable ? 0x80 : 0;
	buf[2] = 0x05; /* SPC-3 */
	buf[3] = 0x02;
	buf[4] = 31;
	oa_copy(buf + 8, "ATA     ", 8);
	/* Product: the first 16 characters of the ATA model string. */
	for (unsigned i = 0, end = 0; i < 16; i++) {
		if (!sat->model[i])
			end = 1;
		buf[16 + i] = end ? ' ' : (uint8_t)sat->model[i];
	}
	for (unsigned i = 0, end = 0; i < 4; i++) {
		if (!sat->firmware[i])
			end = 1;
		buf[32 + i] = end ? ' ' : (uint8_t)sat->firmware[i];
	}
	reply(srb, buf, 36, alloc);
}

static void read_capacity(struct oa_sat *sat, struct oa_srb *srb, int sixteen)
{
	uint8_t buf[32];
	uint64_t last = sat->sectors - 1;

	oa_zero(buf, sizeof(buf));
	if (!sixteen) {
		oa_put_be32(buf, last > 0xffffffffu ? 0xffffffffu : (uint32_t)last);
		oa_put_be32(buf + 4, sat->sector_size);
		reply(srb, buf, 8, 8);
		return;
	}
	oa_put_be64(buf, last);
	oa_put_be32(buf + 8, sat->sector_size);
	reply(srb, buf, 32, oa_be32(srb->cdb + 10));
}

static void rw(struct oa_sat *sat, struct oa_srb *srb, uint64_t lba, uint32_t count, int write)
{
	if (count == 0) {
		srb->residual = srb->data_len;
		return;
	}
	if (lba >= sat->sectors || count > sat->sectors - lba) {
		illegal(sat, srb, 0x21);
		return;
	}
	uint64_t bytes = (uint64_t)count * sat->sector_size;
	if (srb->dir != (write ? OA_DIR_OUT : OA_DIR_IN) || bytes > srb->data_len) {
		illegal(sat, srb, 0x24);
		return;
	}
	if (!sat->lba48 && lba + count > 0x0fffffff) {
		illegal(sat, srb, 0x21);
		return;
	}

	uint8_t *p = srb->data;
	while (count) {
		uint32_t n = count < sat->max_sectors ? count : sat->max_sectors;
		struct oa_ata_cmd cmd;
		oa_zero(&cmd, sizeof(cmd));
		cmd.lba48 = sat->lba48;
		cmd.dma = sat->use_dma;
		if (sat->lba48)
			cmd.command = write ? (sat->use_dma ? ATA_WRITE_DMA_EXT : ATA_WRITE_PIO_EXT)
					    : (sat->use_dma ? ATA_READ_DMA_EXT : ATA_READ_PIO_EXT);
		else
			cmd.command = write ? (sat->use_dma ? ATA_WRITE_DMA : ATA_WRITE_PIO)
					    : (sat->use_dma ? ATA_READ_DMA : ATA_READ_PIO);
		cmd.device = 0x40;
		cmd.lba = lba;
		cmd.count = (uint16_t)n; /* 65536 and 256 wrap to 0, as ATA wants */
		cmd.dir = write ? OA_DIR_OUT : OA_DIR_IN;
		cmd.data = p;
		cmd.len = n * sat->sector_size;
		cmd.timeout_ms = srb->timeout_ms ? srb->timeout_ms : 30000;
		int r = sat->ata(sat->ctx, &cmd);
		if (r != OA_HOST_OK) {
			srb->host_status = (uint8_t)r;
			return;
		}
		if (cmd.status & (OA_ATA_ERR | OA_ATA_DF)) {
			ata_error(sat, srb, &cmd);
			return;
		}
		p += cmd.len;
		lba += n;
		count -= n;
	}
	srb->residual = srb->data_len - (uint32_t)bytes;
}

static void flush(struct oa_sat *sat, struct oa_srb *srb)
{
	struct oa_ata_cmd cmd;
	if (!sat->has_flush)
		return;
	oa_zero(&cmd, sizeof(cmd));
	cmd.command = sat->lba48 ? ATA_FLUSH_EXT : ATA_FLUSH;
	cmd.timeout_ms = 60000;
	int r = sat->ata(sat->ctx, &cmd);
	if (r != OA_HOST_OK)
		srb->host_status = (uint8_t)r;
	else if (cmd.status & (OA_ATA_ERR | OA_ATA_DF))
		ata_error(sat, srb, &cmd);
}

void oa_sat_execute(struct oa_sat *sat, struct oa_srb *srb)
{
	const uint8_t *c = srb->cdb;

	if (srb->lun != 0) {
		srb->host_status = OA_HOST_NO_DEVICE;
		return;
	}
	switch (c[0]) {
	case 0x00: /* TEST UNIT READY */
	case 0x1b: /* START STOP UNIT */
		break;
	case 0x03: { /* REQUEST SENSE */
		uint8_t buf[18];
		oa_zero(buf, sizeof(buf));
		buf[0] = 0x70;
		buf[2] = sat->sense_key;
		buf[7] = 10;
		buf[12] = sat->asc;
		buf[13] = sat->ascq;
		sat->sense_key = sat->asc = sat->ascq = 0;
		reply(srb, buf, 18, c[4]);
		return;
	}
	case 0x12:
		inquiry(sat, srb);
		return;
	case 0x25:
		read_capacity(sat, srb, 0);
		return;
	case 0x9e:
		if ((c[1] & 0x1f) == 0x10) {
			read_capacity(sat, srb, 1);
			return;
		}
		illegal(sat, srb, 0x24);
		return;
	case 0x1a: { /* MODE SENSE (6): header only */
		uint8_t buf[4] = { 3, 0, 0, 0 };
		reply(srb, buf, 4, c[4]);
		return;
	}
	case 0x5a: { /* MODE SENSE (10): header only */
		uint8_t buf[8] = { 0, 6, 0, 0, 0, 0, 0, 0 };
		reply(srb, buf, 8, oa_be16(c + 7));
		return;
	}
	case 0x08:
	case 0x0a: {
		uint32_t lba = ((uint32_t)(c[1] & 0x1f) << 16) | (uint32_t)c[2] << 8 | c[3];
		rw(sat, srb, lba, c[4] ? c[4] : 256, c[0] == 0x0a);
		return;
	}
	case 0x28:
	case 0x2a:
		rw(sat, srb, oa_be32(c + 2), oa_be16(c + 7), c[0] == 0x2a);
		return;
	case 0xa8:
	case 0xaa:
		rw(sat, srb, oa_be32(c + 2), oa_be32(c + 6), c[0] == 0xaa);
		return;
	case 0x88:
	case 0x8a:
		rw(sat, srb, oa_be64(c + 2), oa_be32(c + 10), c[0] == 0x8a);
		return;
	case 0x35: /* SYNCHRONIZE CACHE (10) */
	case 0x91: /* SYNCHRONIZE CACHE (16) */
		flush(sat, srb);
		return;
	default:
		illegal(sat, srb, 0x20);
		return;
	}
	if (srb->dir == OA_DIR_IN)
		srb->residual = srb->data_len;
}
