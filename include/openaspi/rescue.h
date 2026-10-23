/* Raw-sector reader contract: read(ctx,lba,count,buffer) returns zero or an
 * error; bad(ctx,lba,error) returns zero to accept a zero-filled sector. The
 * DEVICE_READ tag carries qualified device faults alongside DOS error codes.
 * Supply both callbacks and count*512 bytes of storage; rescue may proceed
 * past read faults, but does not authorize ignoring media/transport changes.
 */

#ifndef OA_RESCUE_H
#define OA_RESCUE_H
#include "openaspi/types.h"
typedef unsigned (*oa_rescue_reader)(void *,oa_u32,unsigned,void *);
typedef int (*oa_rescue_bad)(void *,oa_u32,unsigned);
#define OA_RESCUE_DEVICE_READ 0x8000u
/* 0 clean, 1 zero-filled unreadable sectors, -1 fatal. Physical LBAs. */
int oa_rescue_read(void *,oa_rescue_reader,oa_rescue_bad,oa_u32,unsigned,void *,int);
#endif
