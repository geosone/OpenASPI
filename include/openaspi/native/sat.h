/* SPDX-License-Identifier: GPL-2.0-or-later */
/* SCSI/ATA translation (after T10 SAT) for transports that drive ATA disks
 * directly: AHCI, IDE, ATA bridges. The transport supplies one function
 * that runs an ATA command; this module answers the SCSI commands a block
 * device class needs from it (INQUIRY, READ CAPACITY, READ/WRITE, ...).
 * ATAPI devices need no translation: their transport sends the CDB as a
 * packet. */

#ifndef OPENASPI_NATIVE_SAT_H
#define OPENASPI_NATIVE_SAT_H

#include "openaspi/native/blockemu.h"
#include "openaspi/native/hba.h"

/* ATA status and error bits. */
#define OA_ATA_ERR  0x01
#define OA_ATA_DRQ  0x08
#define OA_ATA_DF   0x20
#define OA_ATA_DRDY 0x40
#define OA_ATA_BSY  0x80

#define OA_ATA_ERR_ABRT 0x04
#define OA_ATA_ERR_IDNF 0x10
#define OA_ATA_ERR_UNC  0x40
#define OA_ATA_ERR_WP   0x40 /* removable media: write protect (with ABRT) */
#define OA_ATA_ERR_MC   0x20 /* media changed */
#define OA_ATA_ERR_NM   0x02 /* no media */

struct oa_ata_cmd {
	oa_u8 command;
	oa_u8 features;
	oa_u8 device;     /* bit 6 LBA; the transport adds the drive select */
	oa_u8 lba48;      /* use the extended (48-bit) register set */
	oa_u16 count;     /* sector count register (0 = 256 or 65536) */
	oa_u64 lba;
	oa_u8 dir;        /* OA_DIR_* */
	oa_u8 dma;        /* data phase by DMA (else PIO) */
	void *data;
	oa_u32 len;       /* bytes */
	oa_u32 timeout_ms;
	/* results */
	oa_u8 status;
	oa_u8 error;
};

/* Run one ATA command; returns OA_HOST_OK when the device completed it
 * (check status/error then), otherwise an OA_HOST_* transport error. */
typedef int (*oa_ata_fn)(void *ctx, struct oa_ata_cmd *cmd);

struct oa_sat {
	struct oa_blockemu emu; /* SCSI side: blocks, block size, identity */
	oa_ata_fn ata;
	void *ctx;
	oa_u8 use_dma;        /* transport moves data by DMA (AHCI) */
	oa_u8 lba48;
	oa_u32 max_sectors;   /* per ATA command */
	oa_u16 identify[256];
};

/* IDENTIFY DEVICE and set up the translation. Returns OA_HOST_OK, or an
 * error when no ATA disk answers. */
int oa_sat_init(struct oa_sat *sat, oa_ata_fn ata, void *ctx, int use_dma);

/* Answer one SCSI command for LUN 0 (other LUNs: no device). */
void oa_sat_execute(struct oa_sat *sat, struct oa_srb *srb);

#endif
