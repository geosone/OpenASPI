/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native ASPI: host adapters, SCSI request blocks and devices.
 *
 * The same model as ASPI for DOS, as C for 32- and 64-bit kernels: a host
 * adapter (transport) only carries SCSI commands to a target and LUN; device
 * classes (disk.h) build the commands. Transports that drive ATA devices
 * translate with sat.h, so every device answers SCSI.
 *
 * Execution is synchronous and polled for now (GDOS). The structures keep
 * room for queued completion, which the server executive will add.
 */

#ifndef OPENASPI_NATIVE_ASPI_H
#define OPENASPI_NATIVE_ASPI_H

#include <stddef.h>
#include <stdint.h>

#define OA_CDB_MAX   16u
#define OA_SENSE_MAX 32u

/* Data direction. */
#define OA_DIR_NONE 0
#define OA_DIR_IN   1 /* device to host */
#define OA_DIR_OUT  2 /* host to device */

/* Host status: did the transport deliver the command? */
#define OA_HOST_OK          0x00
#define OA_HOST_NO_DEVICE   0x11 /* selection timeout, nothing at that address */
#define OA_HOST_TIMEOUT     0x09 /* command did not complete in time */
#define OA_HOST_DATA_RUN    0x12 /* data overrun or underrun beyond the residual */
#define OA_HOST_BUS_ERROR   0x14 /* transport or controller error */
#define OA_HOST_UNSUPPORTED 0x16 /* command cannot be carried (or translated) */

/* SCSI target status. */
#define OA_STATUS_GOOD            0x00
#define OA_STATUS_CHECK_CONDITION 0x02
#define OA_STATUS_BUSY            0x08

struct oa_srb {
	uint8_t target;
	uint8_t lun;
	uint8_t cdb_len;
	uint8_t dir;               /* OA_DIR_* */
	uint8_t cdb[OA_CDB_MAX];
	void *data;
	uint32_t data_len;
	uint32_t timeout_ms;       /* 0: the transport's default */

	/* Results, set by oa_execute(). */
	uint8_t host_status;       /* OA_HOST_* */
	uint8_t target_status;     /* OA_STATUS_* */
	uint8_t sense_len;         /* valid bytes in sense[] (autosense) */
	uint8_t reserved;
	uint32_t residual;         /* bytes not transferred */
	uint8_t sense[OA_SENSE_MAX];
};

struct oa_hba;

struct oa_hba_ops {
	/* Carry one command and wait for it. Fills the result fields; on CHECK
	 * CONDITION the transport fetches sense data (REQUEST SENSE or the
	 * device's autosense). */
	void (*execute)(struct oa_hba *hba, struct oa_srb *srb);
	/* Optional: reset one target (NULL: not supported). */
	int (*reset_target)(struct oa_hba *hba, uint8_t target);
};

struct oa_hba {
	const char *name;          /* e.g. "AHCI 0000:00:1f.2" */
	const struct oa_hba_ops *ops;
	void *priv;
	uint8_t max_target;        /* highest target id (inclusive) */
	uint8_t max_lun;           /* highest LUN probed (inclusive) */
	uint8_t id;                /* set by oa_hba_register() */
	uint8_t reserved;
	struct oa_hba *next;
};

/* Register an adapter; returns its id. Adapters stay registered. */
int oa_hba_register(struct oa_hba *hba);
struct oa_hba *oa_hba_first(void);

/* Validate and execute a request. Clears the result fields first. */
void oa_execute(struct oa_hba *hba, struct oa_srb *srb);

/* Command completed cleanly. */
static inline int oa_srb_ok(const struct oa_srb *srb)
{
	return srb->host_status == OA_HOST_OK && srb->target_status == OA_STATUS_GOOD;
}

/* Sense key / ASC / ASCQ of fixed or descriptor sense; -1 if none. */
int oa_sense_key(const struct oa_srb *srb);
int oa_sense_asc(const struct oa_srb *srb);   /* ASC << 8 | ASCQ */

/* Peripheral device types from INQUIRY. */
#define OA_TYPE_DISK      0x00
#define OA_TYPE_TAPE      0x01
#define OA_TYPE_CDROM     0x05
#define OA_TYPE_OPTICAL   0x07
#define OA_TYPE_NONE      0x1f

/* A device found by oa_scan(). */
struct oa_device {
	struct oa_hba *hba;
	uint8_t target;
	uint8_t lun;
	uint8_t type;              /* OA_TYPE_* */
	uint8_t removable;
	char vendor[9];
	char product[17];
	char revision[5];
	struct oa_device *next;
};

/* Probe every target and LUN of every registered adapter with INQUIRY and
 * build the device list (devices are allocated from `pool`, `pool_count`
 * entries). Returns the number of devices found. */
int oa_scan(struct oa_device *pool, unsigned pool_count);
struct oa_device *oa_device_first(void);

#endif
