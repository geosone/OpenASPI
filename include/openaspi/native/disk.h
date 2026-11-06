/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native ASPI block device class: disks, removable media (floppy, LS-120,
 * ZIP, card readers, sticks) and CD/DVD data reads, through SCSI block
 * commands. The same code serves every transport. */

#ifndef OPENASPI_NATIVE_DISK_H
#define OPENASPI_NATIVE_DISK_H

#include "openaspi/native/hba.h"

/* Return values (0 = success). */
#define OA_OK         0
#define OA_EIO       -1 /* transport error or unrecovered medium error */
#define OA_ENOMEDIUM -2 /* no medium in a removable drive */
#define OA_EROFS     -3 /* medium is write-protected */
#define OA_EINVAL    -4 /* request outside the medium or bad arguments */
#define OA_ECHANGED  -5 /* medium was changed; reopen */
#define OA_ENOTSUP   -6 /* device does not support the operation */

struct oa_disk {
	struct oa_device *dev;
	oa_u64 blocks;          /* number of logical blocks */
	oa_u32 block_size;      /* bytes per block */
	oa_u32 max_blocks;      /* per command (transfer limit) */
	oa_u8 use16;            /* READ/WRITE (16) needed */
	oa_u8 write_protected;
	oa_u8 reserved[2];
};

/* Wait for the unit to become ready (spin-up, unit attention after reset or
 * medium change) and read its capacity. */
int oa_disk_open(struct oa_disk *disk, struct oa_device *dev);

int oa_disk_read(struct oa_disk *disk, oa_u64 lba, oa_u32 count, void *buf);
int oa_disk_write(struct oa_disk *disk, oa_u64 lba, oa_u32 count, const void *buf);
/* Flush the device's write cache. */
int oa_disk_sync(struct oa_disk *disk);

#endif
