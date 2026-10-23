#include <string.h>
#include "openaspi/rescue.h"
static int recoverable(unsigned error)
{
    /* DOS CRC, sector-not-found and read-fault. Not media change, not-ready,
       write protection, or an unclassified controller/transport failure. */
    return (error&OA_RESCUE_DEVICE_READ) || error==23 || error==27 || error==30;
}
int oa_rescue_read(void *ctx,oa_rescue_reader read,oa_rescue_bad bad,
                   oa_u32 lba,unsigned count,void *buffer,int enabled)
{
    unsigned error,i,attempt;
    int gaps=0;
    unsigned char *sector=(unsigned char *)buffer;
    if(!count || count>32 || lba>0xFFFFFFFFUL-(count-1)) return -1;
    error=read(ctx,lba,count,buffer);
    if(!error) return 0;
    if(!enabled || !recoverable(error)) return -1;
    for(i=0;i<count;++i,sector+=512) {
        for(attempt=0;attempt<2;++attempt) {
            error=read(ctx,lba+i,1,sector);
            if(!error) break;
            if(!recoverable(error)) return -1;
        }
        if(error) {
            memset(sector,0,512);
            if(bad(ctx,lba+i,error)) return -1;
            gaps=1;
        }
    }
    return gaps;
}
