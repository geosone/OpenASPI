/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native ASPI: host adapters, SCSI request blocks and devices.
 *
 * Not the DOS ABI of openaspi/aspi.h (packed SRBs with far pointers handed
 * to SCSIMGR$), but its C counterpart inside a kernel; both share the ASPI
 * constants, and the SCSI helpers of openaspi/scsi.h serve both.
 *
 * A host adapter (transport) only carries SCSI commands to a target and
 * LUN; device classes (disk.h) build the commands. Transports that drive
 * ATA devices translate with sat.h, so every device answers SCSI.
 *
 * Execution is synchronous and polled for now (GDOS). The structures keep
 * room for queued completion, which the server executive will add.
 */

#ifndef OPENASPI_NATIVE_HBA_H
#define OPENASPI_NATIVE_HBA_H

#include <stddef.h>

#include "openaspi/aspi.h" /* ASPI vocabulary shared with the DOS ABI */
#include "openaspi/scsi.h"

#define OA_CDB_MAX   OA_ASPI_CDB_SIZE
#define OA_SENSE_MAX OA_ASPI_SENSE_SIZE

/* Data direction. */
#define OA_DIR_NONE 0
#define OA_DIR_IN   1 /* device to host */
#define OA_DIR_OUT  2 /* host to device */

/* Host status: did the transport deliver the command? The ASPI host
 * adapter codes, plus one native code. */
#define OA_HOST_OK          OA_ASPI_HA_OK
#define OA_HOST_NO_DEVICE   OA_ASPI_HA_SELECTION_TIMEOUT /* nothing at that address */
#define OA_HOST_TIMEOUT     OA_ASPI_HA_TIMEOUT           /* did not complete in time */
#define OA_HOST_DATA_RUN    OA_ASPI_HA_DATA_RUN          /* overrun or underrun beyond the residual */
#define OA_HOST_BUS_ERROR   OA_ASPI_HA_PHASE_ERROR       /* transport or controller error */
#define OA_HOST_UNSUPPORTED 0x80u /* native only: request cannot be carried or translated */

/* SCSI target status. */
#define OA_STATUS_GOOD            0x00u
#define OA_STATUS_CHECK_CONDITION 0x02u
#define OA_STATUS_BUSY            0x08u

struct oa_srb {
    oa_u8 target;
    oa_u8 lun;
    oa_u8 cdb_len;
    oa_u8 dir;               /* OA_DIR_* */
    oa_u8 cdb[OA_CDB_MAX];
    void *data;
    oa_u32 data_len;
    oa_u32 timeout_ms;       /* 0: the transport's default */

    /* Results, set by oa_execute(). */
    oa_u8 host_status;       /* OA_HOST_* */
    oa_u8 target_status;     /* OA_STATUS_* */
    oa_u8 sense_len;         /* valid bytes in sense[] (autosense) */
    oa_u8 reserved;
    oa_u32 residual;         /* bytes not transferred */
    oa_u8 sense[OA_SENSE_MAX];
};

struct oa_hba;

struct oa_hba_ops {
    /* Carry one command and wait for it. Fills the result fields; on CHECK
     * CONDITION the transport supplies sense data (REQUEST SENSE or the
     * device's autosense). */
    void (*execute)(struct oa_hba *hba, struct oa_srb *srb);
    /* Optional: reset one target (NULL: not supported). */
    int (*reset_target)(struct oa_hba *hba, oa_u8 target);
    /* Optional: nonzero if the target is floppy-class removable media (a
     * floppy controller, a USB floppy speaking UFI, an LS-120/ZIP speaking
     * SFF-8070i). Such media take the drive letters A:/B:. NULL: not. */
    int (*is_floppy)(struct oa_hba *hba, oa_u8 target);
};

struct oa_host_lock;

struct oa_hba {
    const char *name;          /* e.g. "AHCI 0000:00:1f.2" */
    const struct oa_hba_ops *ops;
    void *priv;
    oa_u8 max_target;          /* highest target id (inclusive) */
    oa_u8 max_lun;             /* highest LUN probed (inclusive) */
    oa_u8 id;                  /* set by oa_hba_register() */
    oa_u8 reserved;
    struct oa_host_lock *lock; /* set by oa_hba_register(): serialises oa_execute (SMP) */
    struct oa_hba *next;
};

/* Register an adapter; returns its id. Adapters stay registered. */
int oa_hba_register(struct oa_hba *hba);
struct oa_hba *oa_hba_first(void);

/* Validate and execute a request. Clears the result fields first. */
void oa_execute(struct oa_hba *hba, struct oa_srb *srb);

/* Command completed cleanly (host and target status). */
int oa_srb_ok(const struct oa_srb *srb);

/* Decode the sense data of a request that ended in CHECK CONDITION (0);
 * -1 when there was none or it is not recognized. */
int oa_srb_sense(const struct oa_srb *srb, struct oa_scsi_sense *sense);

/* A device found by oa_scan(). */
struct oa_device {
    struct oa_hba *hba;
    oa_u8 target;
    oa_u8 lun;
    oa_u8 floppy;                   /* floppy-class removable media (A:/B:) */
    oa_u8 reserved[1];
    struct oa_scsi_inquiry inquiry; /* device_type, removable, identity */
    struct oa_device *next;
};

/* Probe every target and LUN of every registered adapter with INQUIRY and
 * build the device list from `pool` (`pool_count` entries). Returns the
 * number of devices found. */
int oa_scan(struct oa_device *pool, unsigned pool_count);
/* Probe only the adapters registered since the last scan (virtual ones,
 * such as a software RAID over the disks found) and append their devices,
 * from `pool` (`pool_count` entries; a new pool, the old one stays in
 * use). Returns the number of devices added. */
int oa_scan_more(struct oa_device *pool, unsigned pool_count);
/* Take a device off the list: another layer has taken it over (a disk
 * that is a member of a software RAID). */
void oa_device_remove(struct oa_device *dev);
struct oa_device *oa_device_first(void);

#endif
