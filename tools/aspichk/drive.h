/* Sector access to a FAT drive for ASPICHK and DEFRAG: ASPIDSK/ASPIFDD
   media through the physical sector functions of their exFAT service (also
   when DOS has not mounted them), other drives through INT 21h 7305h or
   INT 25h/26h. */
#ifndef ASPICHK_DRIVE_H
#define ASPICHK_DRIVE_H
#include "openaspi/types.h"

#define DRV_ASPI 0
#define DRV_7305 1
#define DRV_25   2
#define DRV_NOMEDIA (-1)                /* ASPI drive without a medium */
#define DRV_EXFAT   (-2)                /* ASPI drive with an exFAT medium */
#define DRV_NOREAD  (-3)                /* sector 0 cannot be read */

extern oa_u32 drv_start;                /* first sector of the volume */
extern oa_u8 drv_unit;                  /* ASPI unit */

/* drive: 0 = A:; one of DRV_ */
int drv_open(unsigned drive);
int drv_io(int write, oa_u32 lba, unsigned count, void __far *buf);
/* around the work: DOS buffers written, with write the drive locked
   (DOS 7); after it the driver and DOS read the volume again */
void drv_begin(int write);
void drv_end(int write);
#endif
