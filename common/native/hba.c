/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native ASPI core: adapter registry, request validation and the INQUIRY
 * bus scan. */

#include <string.h>

#include "openaspi/native/hba.h"
#include "openaspi/native/host.h"

static struct oa_hba *hbas;
static struct oa_hba **hba_tail = &hbas;
static unsigned hba_count;
static struct oa_device *devices;
static struct oa_hba *scanned; /* the last adapter scanned */

int oa_hba_register(struct oa_hba *hba)
{
    hba->next = 0;
    hba->id = (oa_u8)hba_count++;
    hba->lock = oa_host_lock_create(); /* NULL on a single-threaded host */
    *hba_tail = hba;
    hba_tail = &hba->next;
    oa_host_log(OA_LOG_INFO, "ASPI: adapter %u: %s\n", (unsigned)hba->id, hba->name);
    return hba->id;
}

struct oa_hba *oa_hba_first(void)
{
    return hbas;
}

/* Minimum CDB length of the opcode's group. */
static int cdb_len_ok(oa_u8 op, oa_u8 len)
{
    switch (op >> 5) {
    case 1:
    case 2:
        return len >= 10u;
    case 4:
        return len >= 16u;
    case 5:
        return len >= 12u;
    default:
        return len >= 6u;
    }
}

void oa_execute(struct oa_hba *hba, struct oa_srb *srb)
{
    srb->host_status = OA_HOST_OK;
    srb->target_status = OA_STATUS_GOOD;
    srb->sense_len = 0;
    srb->residual = 0;

    if (hba == 0 || hba->ops == 0 || hba->ops->execute == 0 ||
        srb->target > hba->max_target || srb->lun > hba->max_lun) {
        srb->host_status = OA_HOST_NO_DEVICE;
        return;
    }
    if (srb->cdb_len > OA_CDB_MAX || !cdb_len_ok(srb->cdb[0], srb->cdb_len) ||
        srb->dir > OA_DIR_OUT ||
        (srb->dir != OA_DIR_NONE && (srb->data == 0 || srb->data_len == 0u))) {
        srb->host_status = OA_HOST_UNSUPPORTED;
        return;
    }
    /* Serialise the whole command against other CPUs driving this adapter
     * (SMP); no-op on a single-threaded host. The validation above touches only
     * the caller's SRB, so it stays outside the lock. */
    oa_host_lock_acquire(hba->lock);
    hba->ops->execute(hba, srb);
    oa_host_lock_release(hba->lock);
    if (srb->sense_len > OA_SENSE_MAX) {
        srb->sense_len = OA_SENSE_MAX;
    }
}

int oa_srb_ok(const struct oa_srb *srb)
{
    return srb->host_status == OA_HOST_OK && srb->target_status == OA_STATUS_GOOD;
}

int oa_srb_sense(const struct oa_srb *srb, struct oa_scsi_sense *sense)
{
    if (srb->host_status != OA_HOST_OK ||
        srb->target_status != OA_STATUS_CHECK_CONDITION) {
        return -1;
    }
    return oa_scsi_decode_sense(srb->sense, srb->sense_len, sense);
}

static int inquiry(struct oa_hba *hba, oa_u8 target, oa_u8 lun,
                   struct oa_scsi_inquiry *out)
{
    struct oa_srb srb;
    oa_u8 buf[OA_SCSI_INQUIRY_SIZE];

    memset(&srb, 0, sizeof(srb));
    memset(buf, 0, sizeof(buf));
    srb.target = target;
    srb.lun = lun;
    srb.cdb_len = 6;
    oa_scsi_cdb_inquiry(srb.cdb, (oa_u8)sizeof(buf));
    srb.dir = OA_DIR_IN;
    srb.data = buf;
    srb.data_len = sizeof(buf);
    srb.timeout_ms = 5000;
    oa_execute(hba, &srb);
    if (srb.host_status != OA_HOST_OK) {
        return -1;
    }
    if (srb.target_status != OA_STATUS_GOOD) {
        /* Unit attention after reset is reported once: ask again. */
        oa_execute(hba, &srb);
        if (!oa_srb_ok(&srb)) {
            return -1;
        }
    }
    return oa_scsi_decode_inquiry(buf, (oa_u16)(sizeof(buf) - srb.residual), out);
}

/* Probes every target and LUN of the adapters from `hba` on and appends
 * what answers to the device list, from pool[used] on. */
static unsigned scan_from(struct oa_hba *hba, struct oa_device *pool, unsigned pool_count, unsigned used)
{
    struct oa_device **tail = &devices;
    struct oa_scsi_inquiry inq;
    struct oa_device *d;
    unsigned t, l;

    while (*tail != 0) {
        tail = &(*tail)->next;
    }
    for (; hba != 0; hba = hba->next) {
        scanned = hba;
        for (t = 0; t <= hba->max_target; t++) {
            for (l = 0; l <= hba->max_lun; l++) {
                if (inquiry(hba, (oa_u8)t, (oa_u8)l, &inq) < 0) {
                    if (l == 0) {
                        break; /* no target: skip its LUNs */
                    }
                    continue;
                }
                if (inq.qualifier != 0u || inq.device_type == OA_ASPI_DEVICE_NONE) {
                    continue;
                }
                if (used == pool_count) {
                    oa_host_log(OA_LOG_WARN, "ASPI: device table full\n");
                    return used;
                }
                d = &pool[used++];
                memset(d, 0, sizeof(*d));
                d->hba = hba;
                d->target = (oa_u8)t;
                d->lun = (oa_u8)l;
                d->inquiry = inq;
                d->floppy = (hba->ops && hba->ops->is_floppy &&
                             hba->ops->is_floppy(hba, (oa_u8)t)) ? 1u : 0u;
                *tail = d;
                tail = &d->next;
                oa_host_log(OA_LOG_INFO, "ASPI: %u:%u:%u type %02x%s %s %s %s\n",
                            (unsigned)hba->id, t, l, (unsigned)inq.device_type,
                            inq.removable ? " removable" : "",
                            inq.vendor, inq.product, inq.revision);
            }
        }
    }
    return used;
}

int oa_scan(struct oa_device *pool, unsigned pool_count)
{
    devices = 0;
    scanned = 0;
    return (int)scan_from(hbas, pool, pool_count, 0);
}

int oa_scan_more(struct oa_device *pool, unsigned pool_count)
{
    return (int)scan_from(scanned ? scanned->next : hbas, pool, pool_count, 0);
}

void oa_device_remove(struct oa_device *dev)
{
    struct oa_device **p;

    for (p = &devices; *p != 0; p = &(*p)->next) {
        if (*p == dev) {
            *p = dev->next;
            dev->next = 0;
            return;
        }
    }
}

struct oa_device *oa_device_first(void)
{
    return devices;
}
