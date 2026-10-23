#ifndef OA_RAW_MEDIA_H
#define OA_RAW_MEDIA_H
#include "openaspi/types.h"
struct oa_raw_media {
    unsigned char packet[32];
    unsigned drive, error, active, fat32, sense_key, asc, driver_error;
    oa_u32 sectors, start, length;
    unsigned char address[3];
};
int oa_raw_open(struct oa_raw_media *, unsigned drive, int write);
int oa_raw_info(struct oa_raw_media *, unsigned drive);
int oa_raw_io(struct oa_raw_media *, int write, oa_u32 lba, unsigned count, void *);
unsigned oa_raw_read_source(void *,oa_u32,unsigned,void *);
int oa_raw_close(struct oa_raw_media *);
int oa_drive(const char *, unsigned *);
void oa_disk_reset(void);
#endif
