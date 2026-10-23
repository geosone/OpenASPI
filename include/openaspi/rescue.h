#ifndef OA_RESCUE_H
#define OA_RESCUE_H
#include "openaspi/types.h"
typedef unsigned (*oa_rescue_reader)(void *,oa_u32,unsigned,void *);
typedef int (*oa_rescue_bad)(void *,oa_u32,unsigned);
#define OA_RESCUE_DEVICE_READ 0x8000u
/* 0 clean, 1 zero-filled unreadable sectors, -1 fatal. Physical LBAs. */
int oa_rescue_read(void *,oa_rescue_reader,oa_rescue_bad,oa_u32,unsigned,void *,int);
#endif
