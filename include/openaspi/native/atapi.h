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

#endif
