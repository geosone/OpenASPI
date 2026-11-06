/* SPDX-License-Identifier: GPL-2.0-or-later */
/* ATAPI packet rules shared by every transport that carries packet
 * commands (AHCI, IDE, ATAPI bridges): 6-byte commands that ATAPI devices
 * commonly reject are sent in their 10-byte form, and sense data falls back
 * to the ATA error register when REQUEST SENSE fails. The same rules as
 * AHCIASPI's translate_cdb and auto_sense. */

#ifndef OPENASPI_NATIVE_ATAPI_H
#define OPENASPI_NATIVE_ATAPI_H

#include "openaspi/types.h"

#define OA_ATAPI_XLATE_NONE       0 /* CDB sent unchanged */
#define OA_ATAPI_XLATE_RW         1 /* READ/WRITE (6) as (10) */
#define OA_ATAPI_XLATE_MODE_SENSE 2 /* MODE SENSE (6) as (10), reply converted */

/* Packet size of the device from IDENTIFY PACKET DEVICE word 0. */
#define OA_ATAPI_PACKET_SIZE(word0) (((word0) & 3u) == 1u ? 16u : 12u)

/* Translate `in` (length in_len) for an ATAPI device of peripheral type
 * `type` into `out` (16 bytes, the packet). Returns OA_ATAPI_XLATE_*. For
 * MODE SENSE the reply is longer by 4 bytes: *alloc10 gets the allocation
 * length to request. */
int oa_atapi_translate(oa_u8 out[16], const oa_u8 *in, oa_u8 in_len, oa_u8 type,
                       oa_u16 *alloc10);

/* Convert a MODE SENSE (10) reply of `len` bytes in place to the (6) form;
 * returns the length of the 6-byte reply. */
oa_u16 oa_atapi_mode10_to_6(oa_u8 *buf, oa_u16 len);

/* Fixed-format sense (18 bytes) from the ATA error register of a failed
 * packet command: its high nibble is the sense key. */
void oa_atapi_sense_from_error(oa_u8 sense[18], oa_u8 error);

/* --- running SCSI requests on an ATAPI device ---------------------------
 *
 * The transport sends one packet (12 or 16 bytes, the buffer always holds
 * 16) with the data phase in `dir` (OA_DIR_*) and reports the ATA status
 * and error registers and the bytes moved. Returns OA_HOST_OK when the
 * device completed the command (check status then), else an OA_HOST_*
 * transport error. */
typedef int (*oa_atapi_fn)(void *ctx, const oa_u8 packet[16], oa_u8 dir, void *data,
                           oa_u32 len, oa_u32 timeout_ms, oa_u8 *status, oa_u8 *error,
                           oa_u32 *xfer);

struct oa_atapi {
    oa_atapi_fn packet;
    void *ctx;
    oa_u8 type;         /* peripheral device type from INQUIRY */
    oa_u8 packet_size;  /* 12 or 16, from IDENTIFY PACKET DEVICE */
    oa_u8 dma;          /* IDENTIFY: DMA supported */
    oa_u8 dmadir;       /* IDENTIFY: DMADIR bit required */
    oa_u8 reply[264];   /* MODE SENSE (10) reply, converted to (6) */
};

struct oa_srb;

/* Set up from the IDENTIFY PACKET DEVICE words and learn the device type
 * with INQUIRY. Returns OA_HOST_OK or the transport error. */
int oa_atapi_init(struct oa_atapi *dev, oa_atapi_fn packet, void *ctx, const oa_u16 identify[256]);

/* Run one SCSI request: CDB translation, REQUEST SENSE as autosense,
 * sense from the error register when that fails. */
void oa_atapi_execute(struct oa_atapi *dev, struct oa_srb *srb);

#endif
