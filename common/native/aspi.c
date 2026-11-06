/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native ASPI core: adapter registry, request validation, sense decoding
 * and the INQUIRY bus scan. */

#include "openaspi/native/aspi.h"
#include "openaspi/native/host.h"
#include "util.h"

static struct oa_hba *hbas, **hba_tail = &hbas;
static unsigned hba_count;
static struct oa_device *devices;

int oa_hba_register(struct oa_hba *hba)
{
	hba->next = 0;
	hba->id = (uint8_t)hba_count++;
	*hba_tail = hba;
	hba_tail = &hba->next;
	oa_host_log(OA_LOG_INFO, "ASPI: adapter %u: %s\n", hba->id, hba->name);
	return hba->id;
}

struct oa_hba *oa_hba_first(void)
{
	return hbas;
}

static int cdb_len_ok(uint8_t op, uint8_t len)
{
	switch (op >> 5) { /* group code */
	case 0:
		return len >= 6;
	case 1:
	case 2:
		return len >= 10;
	case 4:
		return len >= 16;
	case 5:
		return len >= 12;
	default:
		return len >= 6; /* vendor specific */
	}
}

void oa_execute(struct oa_hba *hba, struct oa_srb *srb)
{
	srb->host_status = OA_HOST_OK;
	srb->target_status = OA_STATUS_GOOD;
	srb->sense_len = 0;
	srb->residual = 0;

	if (!hba || !hba->ops || !hba->ops->execute || srb->target > hba->max_target ||
	    srb->lun > hba->max_lun) {
		srb->host_status = OA_HOST_NO_DEVICE;
		return;
	}
	if (srb->cdb_len > OA_CDB_MAX || !cdb_len_ok(srb->cdb[0], srb->cdb_len) ||
	    srb->dir > OA_DIR_OUT || (srb->dir != OA_DIR_NONE && (!srb->data || !srb->data_len))) {
		srb->host_status = OA_HOST_UNSUPPORTED;
		return;
	}
	hba->ops->execute(hba, srb);
	if (srb->sense_len > OA_SENSE_MAX)
		srb->sense_len = OA_SENSE_MAX;
}

/* Fixed sense (70h/71h) or descriptor sense (72h/73h). */
int oa_sense_key(const struct oa_srb *srb)
{
	const uint8_t *s = srb->sense;
	if (srb->target_status != OA_STATUS_CHECK_CONDITION || srb->sense_len < 3)
		return -1;
	switch (s[0] & 0x7f) {
	case 0x70:
	case 0x71:
		return s[2] & 0x0f;
	case 0x72:
	case 0x73:
		return s[1] & 0x0f;
	}
	return -1;
}

int oa_sense_asc(const struct oa_srb *srb)
{
	const uint8_t *s = srb->sense;
	if (oa_sense_key(srb) < 0)
		return -1;
	if ((s[0] & 0x7f) >= 0x72)
		return srb->sense_len >= 4 ? (s[2] << 8 | s[3]) : -1;
	return srb->sense_len >= 14 ? (s[12] << 8 | s[13]) : -1;
}

static int inquiry(struct oa_hba *hba, uint8_t target, uint8_t lun, uint8_t *buf)
{
	struct oa_srb srb;
	oa_zero(&srb, sizeof(srb));
	srb.target = target;
	srb.lun = lun;
	srb.cdb_len = 6;
	srb.cdb[0] = 0x12; /* INQUIRY */
	srb.cdb[4] = 36;
	srb.dir = OA_DIR_IN;
	srb.data = buf;
	srb.data_len = 36;
	srb.timeout_ms = 5000;
	oa_zero(buf, 36);
	oa_execute(hba, &srb);
	if (srb.host_status != OA_HOST_OK)
		return -1;
	if (srb.target_status != OA_STATUS_GOOD) {
		/* Some devices report unit attention on the first command
		 * after reset: ask once more. */
		oa_execute(hba, &srb);
		if (!oa_srb_ok(&srb))
			return -1;
	}
	if (36 - srb.residual < 5)
		return -1;
	return 0;
}

int oa_scan(struct oa_device *pool, unsigned pool_count)
{
	struct oa_device **tail = &devices;
	unsigned used = 0;
	uint8_t buf[36];

	devices = 0;
	for (struct oa_hba *hba = hbas; hba; hba = hba->next) {
		for (unsigned t = 0; t <= hba->max_target; t++) {
			for (unsigned l = 0; l <= hba->max_lun; l++) {
				if (inquiry(hba, (uint8_t)t, (uint8_t)l, buf) < 0) {
					if (l == 0)
						break; /* no target: skip its LUNs */
					continue;
				}
				uint8_t qual = buf[0] >> 5, type = buf[0] & 0x1f;
				if (qual != 0 || type == OA_TYPE_NONE)
					continue;
				if (used == pool_count) {
					oa_host_log(OA_LOG_WARN, "ASPI: device table full\n");
					return (int)used;
				}
				struct oa_device *d = &pool[used++];
				oa_zero(d, sizeof(*d));
				d->hba = hba;
				d->target = (uint8_t)t;
				d->lun = (uint8_t)l;
				d->type = type;
				d->removable = (buf[1] & 0x80) != 0;
				oa_trim_copy(d->vendor, buf + 8, 8);
				oa_trim_copy(d->product, buf + 16, 16);
				oa_trim_copy(d->revision, buf + 32, 4);
				*tail = d;
				tail = &d->next;
				oa_host_log(OA_LOG_INFO, "ASPI: %u:%u:%u type %02x%s %s %s %s\n",
					    hba->id, t, l, type, d->removable ? " removable" : "",
					    d->vendor, d->product, d->revision);
			}
		}
	}
	return (int)used;
}

struct oa_device *oa_device_first(void)
{
	return devices;
}
