/* SPDX-License-Identifier: GPL-2.0-or-later */
/* SCSI direct-access device emulation for block devices that do not speak
 * SCSI themselves (ATA disks through SAT, NVMe namespaces): INQUIRY with
 * the serial number page, READ CAPACITY (10/16), MODE SENSE header, REQUEST
 * SENSE, READ/WRITE (6/10/12/16) with range checks, SYNCHRONIZE CACHE.
 * The backend only moves blocks and flushes; its errors come back as SCSI
 * sense data, kept for REQUEST SENSE and given as autosense.
 *
 * Removable media: a backend that can tell (a floppy drive's change line)
 * sets `media`. It is asked before every command that touches the medium
 * (TEST UNIT READY, READ CAPACITY, MODE SENSE, READ, WRITE, SYNCHRONIZE
 * CACHE): a changed medium is reported once as UNIT ATTENTION 28h/00h
 * (the backend has set blocks, block_size and write_protected for the new
 * one before it answers), an empty drive as NOT READY 3Ah/00h. Without
 * `media` the medium is always there. */

#ifndef OPENASPI_NATIVE_BLOCKEMU_H
#define OPENASPI_NATIVE_BLOCKEMU_H

#include "openaspi/types.h"

struct oa_srb;

struct oa_blk_sense {
    oa_u8 key, asc, ascq; /* key 0: no error */
};

/* Move `count` blocks at `lba` (inside the device, at most the request's
 * length) to or from `buf`. Returns OA_HOST_OK with *sense filled in (key
 * 0 on success), else an OA_HOST_* transport error. */
typedef int (*oa_blk_rw_fn)(void *ctx, oa_u64 lba, oa_u32 count, int write, void *buf,
                            oa_u32 timeout_ms, struct oa_blk_sense *sense);
/* Flush the write cache; same results. */
typedef int (*oa_blk_flush_fn)(void *ctx, struct oa_blk_sense *sense);

struct oa_blockemu;

/* The state of the medium (see above). */
#define OA_BLK_MEDIUM_PRESENT 0 /* the same medium as before */
#define OA_BLK_MEDIUM_CHANGED 1 /* another one since the last answer */
#define OA_BLK_MEDIUM_NONE    2 /* the drive is empty */
typedef int (*oa_blk_media_fn)(void *ctx, struct oa_blockemu *emu);

struct oa_blockemu {
    oa_blk_rw_fn rw;
    oa_blk_flush_fn flush; /* NULL: no volatile cache */
    oa_blk_media_fn media; /* NULL: a fixed medium */
    void *ctx;
    oa_u64 blocks;
    oa_u32 block_size;
    oa_u8 removable;
    oa_u8 write_protected;
    char vendor[9];        /* INQUIRY vendor, e.g. "ATA", "NVMe" */
    char model[41];        /* the first 16 characters go into INQUIRY */
    char serial[21];
    char firmware[9];
    struct oa_blk_sense pending; /* for REQUEST SENSE */
};

/* Answer one SCSI command for LUN 0 (other LUNs: no device). */
void oa_blockemu_execute(struct oa_blockemu *emu, struct oa_srb *srb);

#endif
