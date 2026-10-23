#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "openaspi/rescue.h"
struct state { unsigned reads,bad,critical,transient,attempts,map_fail; };
static unsigned read_data(void *ctx,oa_u32 lba,unsigned n,void *data)
{
    struct state *s=(struct state *)ctx;
    unsigned i;
    unsigned char *p=(unsigned char *)data;
    ++s->reads;
    if(s->critical) return s->critical;
    for(i=0;i<n;++i) {
        if(lba+i==5 || lba+i==9) {
            memset(p,0xCC,n*512U); /* a failing transport may alter its buffer */
            if(n==1 && lba==5 && s->transient && ++s->attempts>1) break;
            return 30;
        }
    }
    for(i=0;i<n;++i) memset(p+i*512U,(unsigned char)((lba+i)^0xA5),512);
    return 0;
}
static int bad_sector(void *ctx,oa_u32 lba,unsigned error)
{
    struct state *s=(struct state *)ctx;
    assert((lba==5 || lba==9) && error==30); ++s->bad; return s->map_fail;
}
int main(void)
{
    unsigned char buf[16*512+2];
    struct state s;
    unsigned i,j;
    memset(&s,0,sizeof(s)); memset(buf,0xEE,sizeof(buf));
    assert(oa_rescue_read(&s,read_data,bad_sector,0,16,buf+1,0)==-1);
    assert(s.reads==1 && s.bad==0);
    memset(&s,0,sizeof(s));
    assert(oa_rescue_read(&s,read_data,bad_sector,0,16,buf+1,1)==1);
    assert(s.bad==2 && buf[0]==0xEE && buf[sizeof(buf)-1]==0xEE);
    for(i=0;i<16;++i) for(j=0;j<512;++j)
        assert(buf[1+i*512+j]==(i==5 || i==9 ? 0 : (unsigned char)(i^0xA5)));
    memset(&s,0,sizeof(s)); s.transient=1;
    assert(oa_rescue_read(&s,read_data,bad_sector,0,8,buf,1)==0);
    assert(s.bad==0 && buf[5*512]==(5^0xA5));
    for(i=0;i<4;++i) {
        static const unsigned errors[]={19,21,31,34};
        memset(&s,0,sizeof(s)); s.critical=errors[i];
        assert(oa_rescue_read(&s,read_data,bad_sector,0,16,buf,1)==-1);
        assert(s.bad==0 && s.reads==1);
    }
    memset(&s,0,sizeof(s)); s.map_fail=1;
    assert(oa_rescue_read(&s,read_data,bad_sector,0,16,buf,1)==-1);
    assert(s.bad==1);
    memset(&s,0,sizeof(s));
    assert(oa_rescue_read(&s,read_data,bad_sector,0,0,buf,1)==-1);
    assert(oa_rescue_read(&s,read_data,bad_sector,0xFFFFFFFFUL,2,buf,1)==-1);
    assert(s.reads==0);
    puts("Rescue sector isolation, retry, zero-fill and fatal-error tests passed"); return 0;
}
