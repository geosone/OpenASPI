#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include "openaspi/tape_api.h"

static void baseline(struct ot_tape_info_v1 *p)
{
    assert(ot_tape_info_init(p, OT_TAPE_API_REFRESH) == 0);
    p->valid_fields = OT_TAPE_VALID_SESSION;
    p->operations = OT_TAPE_OP_QUERY;
}

static void records(void)
{
    struct ot_tape_record_v1 p, saved;
    unsigned n;
    assert(sizeof(p) == 64u);
    assert(offsetof(struct ot_tape_record_v1, requested) == 28u);
    assert(offsetof(struct ot_tape_record_v1, buffer_offset) == 40u);
    assert(ot_tape_record_init(&p, 8UL) == 0);
    assert(ot_tape_record_validate(&p, sizeof(p)) == -1);
    saved = p;
    assert(ot_tape_record_init(&p, 0UL) == -1);
    assert(memcmp(&p, &saved, sizeof(p)) == 0);
    assert(ot_tape_record_init(&p, 65536UL) == -1);
    assert(ot_tape_record_init(0, 8UL) == -1);
    p.scsi_opcode = 8;
    p.actual = 8;
    p.completion_flags = 0x23;
    assert(ot_tape_record_validate(&p, sizeof(p)) == 0);
    for (n = 0; n < sizeof(p); ++n)
        assert(ot_tape_record_validate(&p, (oa_u16)n) == -1);
    saved = p;
    p.actual = 9; assert(ot_tape_record_validate(&p, sizeof(p)) == -1);
    p = saved; p.actual = 4; assert(ot_tape_record_validate(&p, sizeof(p)) == -1);
    p.stream_flags = OT_TAPE_STREAM_SHORT;
    assert(ot_tape_record_validate(&p, sizeof(p)) == 0);
    p.stream_flags |= OT_TAPE_STREAM_FILEMARK;
    assert(ot_tape_record_validate(&p, sizeof(p)) == -1);
    p.result = OT_TAPE_RESULT_STREAM; p.diagnostic_class = OT_TAPE_DIAG_TARGET;
    p.target_status = 2; p.sense_response = 0x70;
    assert(ot_tape_record_validate(&p, sizeof(p)) == 0);
    p.sense_response = 0x71; assert(ot_tape_record_validate(&p, sizeof(p)) == -1);
    p.sense_response = 0x72; p.host_status = 0x11;
    assert(ot_tape_record_validate(&p, sizeof(p)) == -1);
    p.host_status = 0; p.sense_key = 3;
    assert(ot_tape_record_validate(&p, sizeof(p)) == -1);
    p.result = OT_TAPE_RESULT_ERROR; p.completion_flags = 0x25;
    assert(ot_tape_record_validate(&p, sizeof(p)) == 0); /* data plus hard error */
    p.diagnostic_class = OT_TAPE_DIAG_TRANSPORT;
    assert(ot_tape_record_validate(&p, sizeof(p)) == -1);
    p.actual = 0; p.stream_flags = 0; p.completion_flags = 5;
    assert(ot_tape_record_validate(&p, sizeof(p)) == 0);
    p = saved; p.reserved[15] = 1;
    assert(ot_tape_record_validate(&p, sizeof(p)) == -1);
    assert(ot_tape_record_init(&p, 8UL) == 0);
    p.result = OT_TAPE_RESULT_BUSY;
    assert(ot_tape_record_validate(&p, sizeof(p)) == 0);
    p.result = OT_TAPE_RESULT_UNSUPPORTED; p.diagnostic_class = OT_TAPE_DIAG_UNSUPPORTED;
    assert(ot_tape_record_validate(&p, sizeof(p)) == 0);
    p.completion_flags = 1;
    assert(ot_tape_record_validate(&p, sizeof(p)) == -1);
    p = saved; p.result = OT_TAPE_RESULT_STREAM; p.diagnostic_class = OT_TAPE_DIAG_TARGET;
    p.target_status = 2; p.sense_response = 0x70; p.sense_key = 8;
    p.ascq = 5; p.actual = 0; p.stream_flags = OT_TAPE_STREAM_EOD | OT_TAPE_STREAM_SHORT;
    assert(ot_tape_record_validate(&p, sizeof(p)) == 0);
    p.ascq = 0; assert(ot_tape_record_validate(&p, sizeof(p)) == -1);
}

static void writes(void)
{
    struct ot_tape_record_v1 p;
    struct ot_tape_control_v1 c;
    assert(ot_tape_write_init(&p, 8UL) == 0 && p.operation == OT_TAPE_RECORD_WRITE);
    assert(ot_tape_write_init(&p, 0UL) == -1 && p.operation == OT_TAPE_RECORD_WRITE);
    p.scsi_opcode = 0x0a; p.actual = 8; p.completion_flags = 0x23; p.session_state = 0x30;
    assert(ot_tape_record_validate(&p, sizeof(p)) == 0);
    p.actual = 4; p.stream_flags = OT_TAPE_STREAM_SHORT;
    assert(ot_tape_record_validate(&p, sizeof(p)) == -1); /* never successful short WRITE */
    p.result = OT_TAPE_RESULT_ERROR; p.completion_flags = 0x25;
    p.session_state = 0x70; p.diagnostic_class = OT_TAPE_DIAG_INCOMPLETE;
    assert(ot_tape_record_validate(&p, sizeof(p)) == 0);
    p.diagnostic_class = OT_TAPE_DIAG_MALFORMED;
    assert(ot_tape_record_validate(&p, sizeof(p)) == -1);
    p.diagnostic_class = OT_TAPE_DIAG_INCOMPLETE; p.session_state = 0x30;
    assert(ot_tape_record_validate(&p, sizeof(p)) == -1);
    assert(ot_tape_control_init(&c, OT_TAPE_CONTROL_BEGIN_WRITE) == 0);
    c.completion_flags = 0x42; c.session_state = 0x10;
    assert(ot_tape_control_validate(&c, sizeof(c)) == 0);
    c.completion_flags |= 1;
    assert(ot_tape_control_validate(&c, sizeof(c)) == -1); /* claim submits no CDB */
    assert(ot_tape_control_init(&c, OT_TAPE_CONTROL_ABORT_WRITE) == 0);
    c.completion_flags = 0x82; c.session_state = 0x60;
    assert(ot_tape_control_validate(&c, sizeof(c)) == 0);
    assert(ot_tape_control_init(&c, 0xffffu) == -1);
    assert(ot_tape_control_init(&c, OT_TAPE_CONTROL_FLUSH) == 0);
    c.scsi_opcode = 0x10; c.completion_flags = 3; c.session_state = 0x30;
    assert(ot_tape_control_validate(&c, sizeof(c)) == 0);
    assert(ot_tape_control_init(&c, OT_TAPE_CONTROL_END_WRITE) == 0);
    c.scsi_opcode = 0x10; c.completion_flags = 0x83;
    assert(ot_tape_control_validate(&c, sizeof(c)) == 0);
    c.result = 3; c.completion_flags = 5; c.session_state = 0x70;
    c.diagnostic_class = 2; c.target_status = 2; c.sense_key = 3; c.sense_response = 0x70;
    assert(ot_tape_control_validate(&c, sizeof(c)) == 0);
    c.completion_flags |= 0x80;
    assert(ot_tape_control_validate(&c, sizeof(c)) == -1); /* failed END cannot release */
}

static void fixed_packets(void)
{
    struct ot_tape_record_v1 p, saved;
    struct ot_tape_control_v1 c;
    assert(ot_tape_record_fixed_init(&p,0,1024,512)==0);
    assert(p.flags==1 && p.block_size==512 && p.requested==1024);
    saved=p;
    assert(ot_tape_record_fixed_init(&p,0,1023,512)==-1);
    assert(memcmp(&p,&saved,sizeof(p))==0);
    assert(ot_tape_record_fixed_init(&p,0,1024,0)==-1);
    assert(ot_tape_record_fixed_init(&p,0,1024,65536UL)==-1);
    assert(ot_tape_record_fixed_init(&p,2,1024,512)==-1);
    p.scsi_opcode=8; p.actual=1024; p.completion_flags=0x23;
    assert(ot_tape_record_validate(&p,sizeof(p))==0);
    p.actual=512; p.stream_flags=8;
    assert(ot_tape_record_validate(&p,sizeof(p))==0);
    p.actual=513;
    assert(ot_tape_record_validate(&p,sizeof(p))==-1);
    p.actual=512; p.result=5; p.diagnostic_class=2; p.target_status=2; p.sense_response=0x70;
    p.stream_flags=9;
    assert(ot_tape_record_validate(&p,sizeof(p))==0);
    p.stream_flags=12;
    assert(ot_tape_record_validate(&p,sizeof(p))==-1); /* fixed ILI is not short variable record */
    p.result=3; p.completion_flags=0x25;
    assert(ot_tape_record_validate(&p,sizeof(p))==0);
    assert(ot_tape_control_fixed_init(&c,512)==0);
    assert(c.operation==2 && c.flags==1 && c.block_size==512);
    c.completion_flags=0x42; c.session_state=0x10;
    assert(ot_tape_control_validate(&c,sizeof(c))==0);
    c.operation=3;
    assert(ot_tape_control_validate(&c,sizeof(c))==-1);
    assert(ot_tape_control_fixed_init(&c,0)==-1);
    assert(ot_tape_record_init(&p,1024)==0);
    p.result=2; p.block_size=512;
    assert(ot_tape_record_validate(&p,sizeof(p))==-1); /* no implicit mode inference */
}

static void space_tests(void)
{
    struct ot_tape_control_v1 c, saved;
    const oa_s32 counts[] = {0,1,-1,8388607L,-8388608L};
    unsigned i, op;
    for (op=7;op<=16;++op) for (i=0;i<sizeof(counts)/sizeof(counts[0]);++i) {
        if(op>=9 && op<=13) continue;
        assert(ot_tape_space_init(&c,(oa_u16)op,counts[i])==0);
        assert(c.count==counts[i] && c.size==64);
        c.scsi_opcode=0x11; c.completion_flags=3;
        assert(ot_tape_control_validate(&c,sizeof(c))==0);
        saved=c; c.completion_flags|=OT_TAPE_POSITION_BOT;
        assert(ot_tape_control_validate(&c,sizeof(c))==-1);
        c=saved; c.result=OT_TAPE_RESULT_ERROR; c.diagnostic_class=OT_TAPE_DIAG_TRANSPORT;
        c.completion_flags=5; c.session_state=OT_TAPE_SESSION_NATIVE_FAILED;
        assert(ot_tape_control_validate(&c,sizeof(c))==0);
        c.session_state=0;
        assert(ot_tape_control_validate(&c,sizeof(c))==-1);
    }
    memset(&c,0xa5,sizeof(c)); saved=c;
    assert(ot_tape_space_init(&c,7,8388608L)==-1 && memcmp(&c,&saved,sizeof(c))==0);
    assert(ot_tape_space_init(&c,8,-8388609L)==-1 && memcmp(&c,&saved,sizeof(c))==0);
    assert(ot_tape_space_init(&c,9,1)==-1 && memcmp(&c,&saved,sizeof(c))==0);
    assert(ot_tape_space_init(&c,1,0)==-1 && memcmp(&c,&saved,sizeof(c))==0);
    assert(ot_tape_space_init(&c,9,0)==0);
    c.scsi_opcode=0x11; c.completion_flags=3;
    assert(ot_tape_control_validate(&c,sizeof(c))==0);
    c.count=1; assert(ot_tape_control_validate(&c,sizeof(c))==-1);
    ot_tape_control_init(&c,0); c.count=1; c.result=OT_TAPE_RESULT_BUSY;
    assert(ot_tape_control_validate(&c,sizeof(c))==-1);
}

static void media_tests(void)
{
    struct ot_tape_control_v1 p;
    unsigned op, state;
    for(op=10;op<=13;++op) for(state=0;state<=0x60;state+=0x20) {
        assert(ot_tape_control_init(&p,(oa_u16)op)==0);
        p.scsi_opcode=(oa_u8)(op>=12 ? 0x1e : 0x1b); p.completion_flags=3; p.session_state=(oa_u16)state;
        assert(ot_tape_control_validate(&p,sizeof(p))==(state==0x20 ? -1 : 0));
        p.result=3; p.diagnostic_class=1; p.completion_flags=(oa_u16)(op>=12 ? 1 : 5);
        assert(ot_tape_control_validate(&p,sizeof(p))==((op>=12 ? state!=0x20 : (state&0x40)!=0) ? 0 : -1));
    }
    ot_tape_control_init(&p,10); p.scsi_opcode=0x1b; p.completion_flags=3;
    p.count=1; assert(ot_tape_control_validate(&p,sizeof(p))==-1);
    p.count=0; p.flags=1; assert(ot_tape_control_validate(&p,sizeof(p))==-1);
    p.flags=0; p.completion_flags|=8; assert(ot_tape_control_validate(&p,sizeof(p))==-1);
    p.completion_flags=3; p.scsi_opcode=0x11; assert(ot_tape_control_validate(&p,sizeof(p))==-1);
    assert(ot_tape_space_init(&p,10,0)==-1);
    assert(ot_tape_control_init(&p,12)==0);
    p.scsi_opcode=0x1e; p.completion_flags=3;
    p.completion_flags|=8; assert(ot_tape_control_validate(&p,sizeof(p))==-1);
    p.result=3; p.diagnostic_class=2; p.completion_flags=5;
    assert(ot_tape_control_validate(&p,sizeof(p))==-1); /* no position mutation */
    p.completion_flags=1; assert(ot_tape_control_validate(&p,sizeof(p))==0);
    p.session_state=0x10; assert(ot_tape_control_validate(&p,sizeof(p))==-1);
    assert(ot_tape_control_init(&p,18)==-1);
    assert(ot_tape_space_init(&p,12,0)==-1);
}

static void position_tests(void)
{
    struct ot_tape_position_v1 p;
    unsigned i;
    assert(sizeof(p)==64 && ot_tape_position_init(0)==-1);
    assert(ot_tape_position_init(&p)==0);
    p.scsi_opcode=0x34; p.completion_flags=3; p.valid_fields=1;
    p.partition=255; p.first_block=0x89abcdefUL; p.last_block=0xffffffffUL;
    assert(ot_tape_position_validate(&p,sizeof(p))==0);
    p.partition=256; assert(ot_tape_position_validate(&p,sizeof(p))==-1); p.partition=255;
    p.device_flags=4; assert(ot_tape_position_validate(&p,sizeof(p))==-1);
    p.valid_fields=0; p.partition=p.first_block=p.last_block=0;
    assert(ot_tape_position_validate(&p,sizeof(p))==0);
    p.device_flags=2; assert(ot_tape_position_validate(&p,sizeof(p))==0);
    p.device_flags=8; assert(ot_tape_position_validate(&p,sizeof(p))==-1);
    p.device_flags=0; p.valid_fields=1;
    for(i=0;i<12;++i) {
        p.reserved[i]=1; assert(ot_tape_position_validate(&p,sizeof(p))==-1); p.reserved[i]=0;
    }
    p.valid_fields=0; p.result=1; p.diagnostic_class=5; p.probe_flags=1;
    assert(ot_tape_position_validate(&p,sizeof(p))==0);
    p.valid_fields=1; assert(ot_tape_position_validate(&p,sizeof(p))==-1); p.valid_fields=0;
    p.probe_flags=0; p.result=3; p.diagnostic_class=3;
    assert(ot_tape_position_validate(&p,sizeof(p))==0);
    p.completion_flags=1; assert(ot_tape_position_validate(&p,sizeof(p))==-1);
    p.diagnostic_class=1; assert(ot_tape_position_validate(&p,sizeof(p))==0);
    p.completion_flags=5; assert(ot_tape_position_validate(&p,sizeof(p))==-1);
    p.completion_flags=1; p.session_state=0x40;
    assert(ot_tape_position_validate(&p,sizeof(p))==0);
    p.session_state=0x60; assert(ot_tape_position_validate(&p,sizeof(p))==0);
    p.session_state=0x20; assert(ot_tape_position_validate(&p,sizeof(p))==-1);
    ot_tape_position_init(&p); p.result=2; p.session_state=0x10;
    assert(ot_tape_position_validate(&p,sizeof(p))==0);
    p.scsi_opcode=0x34; assert(ot_tape_position_validate(&p,sizeof(p))==-1);
    assert(ot_tape_position_validate(&p,63)==-1);
}

static void locate_tests(void)
{
    struct ot_tape_locate_v1 p,saved;
    unsigned i;
    memset(&p,0xa5,sizeof(p)); saved=p;
    assert(ot_tape_locate_init(&p,2,0,1)==-1 && memcmp(&p,&saved,sizeof(p))==0);
    assert(ot_tape_locate_init(&p,0,1,1)==-1 && memcmp(&p,&saved,sizeof(p))==0);
    assert(ot_tape_locate_init(&p,1,256,1)==-1 && memcmp(&p,&saved,sizeof(p))==0);
    assert(ot_tape_locate_init(0,0,0,0)==-1);
    assert(ot_tape_locate_init(&p,1,255,0xffffffffUL)==0);
    p.scsi_opcode=0x2b; p.completion_flags=3;
    assert(ot_tape_locate_validate(&p,sizeof(p))==0);
    for(i=0;i<28;++i) { p.reserved[i]=1; assert(ot_tape_locate_validate(&p,sizeof(p))==-1); p.reserved[i]=0; }
    p.completion_flags=0xb; assert(ot_tape_locate_validate(&p,sizeof(p))==-1);
    p.completion_flags=3; p.session_state=0x40; assert(ot_tape_locate_validate(&p,sizeof(p))==-1);
    p.result=3; p.diagnostic_class=4; p.completion_flags=5;
    assert(ot_tape_locate_validate(&p,sizeof(p))==0);
    p.session_state=0; assert(ot_tape_locate_validate(&p,sizeof(p))==-1);
    p.session_state=0x60; assert(ot_tape_locate_validate(&p,sizeof(p))==-1);
    p.session_state=0x40; p.diagnostic_class=3; assert(ot_tape_locate_validate(&p,sizeof(p))==-1);
    p.result=2; p.completion_flags=0; p.scsi_opcode=0; p.diagnostic_class=0;
    assert(ot_tape_locate_validate(&p,sizeof(p))==0);
    p.partition=256; assert(ot_tape_locate_validate(&p,sizeof(p))==-1);
    assert(ot_tape_locate_validate(&p,63)==-1);
}

static void wide_tests(void)
{
    const char *numbers[]={"0","1","4294967295","4294967296","9223372036854775808","18446744073709551615"};
    const oa_u32 lows[]={0,1,0xffffffffUL,0,0,0xffffffffUL};
    const oa_u32 highs[]={0,0,0,1,0x80000000UL,0xffffffffUL};
    struct ot_tape_position64_v1 p;
    struct ot_tape_locate64_v1 l;
    char text[21],saved[21];
    oa_u32 low=7,high=8;
    unsigned i;
    for(i=0;i<6;++i) {
        assert(ot_tape_u64_parse(numbers[i],&low,&high)==0 && low==lows[i] && high==highs[i]);
        assert(ot_tape_u64_format(low,high,text,sizeof(text))==0 && strcmp(text,numbers[i])==0);
    }
    low=7; high=8;
    assert(ot_tape_u64_parse("18446744073709551616",&low,&high)==-1 && low==7 && high==8);
    assert(ot_tape_u64_parse("-1",&low,&high)==-1 && low==7);
    assert(ot_tape_u64_parse("+1",&low,&high)==-1 && low==7);
    assert(ot_tape_u64_parse("",&low,&high)==-1 && low==7);
    assert(ot_tape_u64_parse("1x",&low,&high)==-1 && low==7);
    memset(text,'X',sizeof(text)); memcpy(saved,text,sizeof(text));
    assert(ot_tape_u64_format(0xffffffffUL,0xffffffffUL,text,20)==-1 && memcmp(text,saved,21)==0);
    assert(ot_tape_position64_init(&p)==0); p.scsi_opcode=0x34; p.completion_flags=3; p.valid_fields=3;
    p.partition=0xffffffffUL; p.block=p.block_high=p.file=p.file_high=0xffffffffUL;
    assert(ot_tape_position64_validate(&p,sizeof(p))==0);
    p.device_flags=8; p.valid_fields=1; p.file=p.file_high=0;
    assert(ot_tape_position64_validate(&p,sizeof(p))==0);
    p.device_flags=4; p.valid_fields=2; p.partition=p.block=p.block_high=0;
    assert(ot_tape_position64_validate(&p,sizeof(p))==0);
    p.device_flags=0x10; assert(ot_tape_position64_validate(&p,sizeof(p))==-1);
    p.device_flags=12; p.valid_fields=0; assert(ot_tape_position64_validate(&p,sizeof(p))==0);
    p.device_flags=0; p.result=1; p.diagnostic_class=5; p.probe_flags=1;
    assert(ot_tape_position64_validate(&p,sizeof(p))==0);
    assert(ot_tape_locate64_init(&l,1,255,0xffffffffUL,0xffffffffUL)==0);
    l.scsi_opcode=0x92; l.completion_flags=3;
    assert(ot_tape_locate64_validate(&l,sizeof(l))==0);
    l.scsi_opcode=0x2b; assert(ot_tape_locate64_validate(&l,sizeof(l))==-1);
    l.scsi_opcode=0x92; l.result=3; l.diagnostic_class=4; l.session_state=0x40; l.completion_flags=5;
    assert(ot_tape_locate64_validate(&l,sizeof(l))==0);
    assert(ot_tape_locate_validate(&l,sizeof(l))==-1);
}

static void partitions_tests(void)
{
    struct ot_tape_partitions_v1 p,saved;
    unsigned n;
    assert(sizeof(p)==64 && offsetof(struct ot_tape_partitions_v1,probe_flags)==56);
    assert(ot_tape_partitions_init(0)==-1);
    assert(ot_tape_partitions_init(&p)==0);
    assert(ot_tape_partitions_validate(&p,sizeof(p))==-1);
    p.scsi_opcode=0x1a; p.completion_flags=3; p.valid_fields=1;
    p.maximum_additional=0; p.defined_additional=255; p.partition_flags=255;
    p.format_recognition=255; p.partition_units=255; p.size_descriptors=26;
    assert(ot_tape_partitions_validate(&p,sizeof(p))==0);
    saved=p;
    for(n=0;n<64;++n) assert(ot_tape_partitions_validate(&p,n)==-1);
    p.maximum_additional=256; assert(ot_tape_partitions_validate(&p,64)==-1);
    p=saved; p.size_descriptors=27; assert(ot_tape_partitions_validate(&p,64)==-1);
    p=saved; p.flags=1; assert(ot_tape_partitions_validate(&p,64)==-1);
    p=saved; p.reserved[3]=1; assert(ot_tape_partitions_validate(&p,64)==-1);
    p=saved; p.valid_fields=0; assert(ot_tape_partitions_validate(&p,64)==-1);
    ot_tape_partitions_init(&p); p.result=2;
    assert(ot_tape_partitions_validate(&p,64)==0);
    p.maximum_additional=1; assert(ot_tape_partitions_validate(&p,64)==-1);
    ot_tape_partitions_init(&p); p.result=1; p.scsi_opcode=0x1a;
    p.completion_flags=3; p.diagnostic_class=5; p.probe_flags=1;
    assert(ot_tape_partitions_validate(&p,64)==0);
    p.valid_fields=1; assert(ot_tape_partitions_validate(&p,64)==-1);
}

static void setmark_tests(void)
{
    struct ot_tape_record_v1 p,saved;
    unsigned response;
    for(response=0x70;response<=0x72;response+=2) {
        ot_tape_record_init(&p,8); p.actual=0; p.result=5; p.diagnostic_class=2;
        p.scsi_opcode=8; p.target_status=2; p.sense_response=(oa_u8)response; p.ascq=3;
        p.completion_flags=0x23; p.stream_flags=OT_TAPE_STREAM_SETMARK|OT_TAPE_STREAM_SHORT;
        assert(ot_tape_record_validate(&p,64)==0); saved=p;
        p.stream_flags|=OT_TAPE_STREAM_FILEMARK; assert(ot_tape_record_validate(&p,64)==-1);
        p=saved; p.stream_flags=9; assert(ot_tape_record_validate(&p,64)==-1); /* old provider misclassification */
        p=saved; p.stream_flags|=OT_TAPE_STREAM_EOD; assert(ot_tape_record_validate(&p,64)==-1);
        p=saved; p.ascq=1; assert(ot_tape_record_validate(&p,64)==-1);
        p=saved; p.sense_response++; assert(ot_tape_record_validate(&p,64)==-1);
        p=saved; p.host_status=0x11; assert(ot_tape_record_validate(&p,64)==-1);
        p=saved; p.sense_key=3; assert(ot_tape_record_validate(&p,64)==-1);
        p.result=3; p.completion_flags=0x25; assert(ot_tape_record_validate(&p,64)==0);
        p=saved; p.actual=4; assert(ot_tape_record_validate(&p,64)==0);
        p=saved; p.actual=8; p.stream_flags=OT_TAPE_STREAM_SETMARK;
        assert(ot_tape_record_validate(&p,64)==0);
        p.operation=OT_TAPE_RECORD_WRITE; p.scsi_opcode=0x0a;
        assert(ot_tape_record_validate(&p,64)==-1);
        ot_tape_record_fixed_init(&p,0,1024,512); p.actual=512; p.result=5;
        p.diagnostic_class=2; p.scsi_opcode=8; p.target_status=2; p.sense_response=(oa_u8)response;
        p.ascq=3; p.completion_flags=0x23; p.stream_flags=0x48;
        assert(ot_tape_record_validate(&p,64)==0);
    }
}

static void setmark_write_packets(void)
{
    struct ot_tape_control_v1 p,saved;
    unsigned state;
    assert(ot_tape_control_init(&p,OT_TAPE_CONTROL_SETMARK)==0);
    p.scsi_opcode=0x10; p.completion_flags=3; p.session_state=0x30;
    assert(ot_tape_control_validate(&p,64)==0); saved=p;
    for(state=0;state<=0x70;state+=0x10) {
        p=saved; p.session_state=(oa_u16)state;
        assert((ot_tape_control_validate(&p,64)==0)==(state==0x30));
    }
    p=saved; p.flags=1; p.block_size=512; assert(ot_tape_control_validate(&p,64)==-1);
    p=saved; p.count=1; assert(ot_tape_control_validate(&p,64)==-1);
    p=saved; p.completion_flags|=OT_TAPE_POSITION_BOT; assert(ot_tape_control_validate(&p,64)==-1);
    p=saved; p.result=3; p.session_state=0x70; p.completion_flags=5; p.diagnostic_class=2;
    p.target_status=2; p.sense_key=7; p.sense_response=0x70; p.asc=0x27;
    assert(ot_tape_control_validate(&p,64)==0);
    p.session_state=0x50; assert(ot_tape_control_validate(&p,64)==-1);
    ot_tape_control_init(&p,OT_TAPE_CONTROL_SETMARK); p.result=2;
    assert(ot_tape_control_validate(&p,64)==0);
    assert(ot_tape_space_init(&p,OT_TAPE_CONTROL_SETMARK,0)==-1);
}

static void alert_packets(void)
{
    struct ot_tape_alerts_v1 p,saved;
    unsigned i;
    memset(&p,0xa5,sizeof(p)); saved=p;
    assert(ot_tape_alerts_init(&p,0)==-1 && memcmp(&p,&saved,sizeof(p))==0);
    assert(ot_tape_alerts_init(&p,3)==-1 && memcmp(&p,&saved,sizeof(p))==0);
    assert(ot_tape_alerts_init(&p,1)==0 && sizeof(p)==64);
    p.scsi_opcode=0x4d; p.completion_flags=3; p.valid_fields=1;
    p.reported_low=0x80080001UL; p.reported_high=0x80000001UL;
    p.active_low=0x80080000UL; p.active_high=0x80000000UL;
    assert(ot_tape_alerts_validate(&p,64)==0);
    assert(ot_tape_alert_state(&p,1)==0 && ot_tape_alert_state(&p,20)==1);
    assert(ot_tape_alert_state(&p,32)==1 && ot_tape_alert_state(&p,33)==0 && ot_tape_alert_state(&p,64)==1);
    assert(ot_tape_alert_state(&p,2)==-1 && ot_tape_alert_state(&p,0)==-1 && ot_tape_alert_state(&p,65)==-1);
    saved=p;
    for(i=0;i<64;++i) assert(ot_tape_alerts_validate(&p,(oa_u16)i)==-1);
    p.active_low|=2; assert(ot_tape_alerts_validate(&p,64)==-1);
    p=saved; p.flags=0; assert(ot_tape_alerts_validate(&p,64)==-1);
    p=saved; p.valid_fields=0; assert(ot_tape_alerts_validate(&p,64)==-1);
    p=saved; p.reserved[11]=1; assert(ot_tape_alerts_validate(&p,64)==-1);
    ot_tape_alerts_init(&p,1); p.result=2;
    assert(ot_tape_alerts_validate(&p,64)==0 && ot_tape_alert_state(&p,20)==-1);
    ot_tape_alerts_init(&p,1); p.result=1; p.scsi_opcode=0x4d; p.completion_flags=3;
    p.diagnostic_class=5; p.probe_flags=1;
    assert(ot_tape_alerts_validate(&p,64)==0);
    p.reported_low=1; assert(ot_tape_alerts_validate(&p,64)==-1);
}

int main(void)
{
    struct ot_tape_info_v1 p, saved;
    struct ot_tape_control_v1 control;
    oa_u16 n;
    assert(sizeof(p) == 128u);
    assert(offsetof(struct ot_tape_info_v1, diagnostic_class) == 78u);
    assert(offsetof(struct ot_tape_info_v1, probe_flags) == 88u);
    baseline(&p);
    assert(ot_tape_info_validate(&p, sizeof(p)) == 0);
    for (n = 0; n < sizeof(p); ++n) assert(ot_tape_info_validate(&p, n) == -1);
    assert(ot_tape_info_validate(0, sizeof(p)) == -1);
    saved = p;
    p.operations = 3UL; /* Future operations do not invalidate QUERY v1. */
    assert(ot_tape_info_validate(&p, sizeof(p)) == 0);
    p.operations = 2UL;
    assert(ot_tape_info_validate(&p, sizeof(p)) == -1);
    p = saved;
    assert(ot_tape_info_init(&p, 2u) == -1);
    assert(memcmp(&p, &saved, sizeof(p)) == 0);
    p.magic[0] = 'X'; assert(ot_tape_info_validate(&p, sizeof(p)) == -1);
    p = saved; p.size = 127; assert(ot_tape_info_validate(&p, sizeof(p)) == -1);
    p = saved; p.version = 0x0200; assert(ot_tape_info_validate(&p, sizeof(p)) == -1);
    p = saved; p.features_supported = 1; assert(ot_tape_info_validate(&p, sizeof(p)) == -1);
    p = saved; p.features_known = 1; assert(ot_tape_info_validate(&p, sizeof(p)) == -1);
    p = saved; p.current_state = OT_TAPE_STATE_FIXED; assert(ot_tape_info_validate(&p, sizeof(p)) == -1);
    p = saved; p.result = OT_TAPE_RESULT_PARTIAL; assert(ot_tape_info_validate(&p, sizeof(p)) == -1);
    p.diagnostic_class = OT_TAPE_DIAG_UNSUPPORTED;
    assert(ot_tape_info_validate(&p, sizeof(p)) == 0);
    assert(ot_tape_info_feature(&p, OT_TAPE_FEATURE_COMPRESSION) == -1);
    p = saved; p.result = OT_TAPE_RESULT_BUSY;
    assert(ot_tape_info_validate(&p, sizeof(p)) == 0);
    p.valid_fields |= OT_TAPE_VALID_LIMITS;
    assert(ot_tape_info_validate(&p, sizeof(p)) == -1);
    p = saved;
    p.valid_fields |= OT_TAPE_VALID_COMPRESSION;
    p.features_known = OT_TAPE_FEATURE_COMPRESSION;
    assert(ot_tape_info_validate(&p, sizeof(p)) == 0);
    assert(ot_tape_info_feature(&p, OT_TAPE_FEATURE_COMPRESSION) == 0);
    p.features_supported = OT_TAPE_FEATURE_COMPRESSION;
    p.current_state = OT_TAPE_STATE_COMPRESSION;
    assert(ot_tape_info_validate(&p, sizeof(p)) == 0);
    assert(ot_tape_info_feature(&p, OT_TAPE_FEATURE_COMPRESSION) == 1);
    assert(ot_tape_info_feature(&p, 3UL) == -1);
    p.valid_fields |= OT_TAPE_VALID_LIMITS;
    p.minimum_block = 512; p.maximum_block = 1; p.block_granularity = 1;
    assert(ot_tape_info_validate(&p, sizeof(p)) == -1);
    p.maximum_block = 32768;
    assert(ot_tape_info_validate(&p, sizeof(p)) == 0);
    assert(ot_tape_info_block_valid(&p, 511) == 0);
    assert(ot_tape_info_block_valid(&p, 512) == 1);
    assert(ot_tape_info_block_valid(&p, 32769) == 0);
    p.minimum_block = 1; p.block_granularity = 4;
    assert(ot_tape_info_block_valid(&p, 513) == 1);
    assert(ot_tape_info_block_valid(&p, 512) == 0);
    p.maximum_block = 0;
    assert(ot_tape_info_validate(&p, sizeof(p)) == 0);
    assert(ot_tape_info_block_valid(&p, 65537UL) == 1);
    p.block_granularity = 3;
    assert(ot_tape_info_validate(&p, sizeof(p)) == -1);
    assert(ot_tape_info_block_valid(&p, 513) == -1);
    p = saved; p.valid_fields |= OT_TAPE_VALID_IDENTITY;
    memset(p.vendor, ' ', 8); memset(p.product, ' ', 16); memset(p.revision, ' ', 4);
    assert(ot_tape_info_validate(&p, sizeof(p)) == 0);
    p.product[15] = 0x1b;
    assert(ot_tape_info_validate(&p, sizeof(p)) == -1);
    p = saved; p.reserved[31] = 1;
    assert(ot_tape_info_validate(&p, sizeof(p)) == -1);
    p = saved; p.probe_flags = OT_TAPE_PROBE_UNVERIFIED_LENGTH;
    assert(ot_tape_info_validate(&p, sizeof(p)) == 0);
    assert(sizeof(control) == 64u);
    assert(ot_tape_control_init(&control, OT_TAPE_CONTROL_REWIND) == 0);
    assert(ot_tape_control_validate(&control, sizeof(control)) == -1); /* no completion */
    control.scsi_opcode = 1;
    control.completion_flags = OT_TAPE_COMPLETION_SUBMITTED | OT_TAPE_COMPLETION_DONE | OT_TAPE_POSITION_BOT;
    assert(ot_tape_control_validate(&control, sizeof(control)) == 0);
    control.host_status = 0x11;
    assert(ot_tape_control_validate(&control, sizeof(control)) == -1);
    control.result = OT_TAPE_RESULT_ERROR;
    control.diagnostic_class = OT_TAPE_DIAG_TRANSPORT;
    control.completion_flags = OT_TAPE_COMPLETION_SUBMITTED | OT_TAPE_POSITION_UNKNOWN;
    assert(ot_tape_control_validate(&control, sizeof(control)) == 0);
    control.completion_flags |= OT_TAPE_POSITION_BOT;
    assert(ot_tape_control_validate(&control, sizeof(control)) == -1);
    assert(ot_tape_control_init(&control, OT_TAPE_CONTROL_READY) == 0);
    control.result = OT_TAPE_RESULT_BUSY;
    assert(ot_tape_control_validate(&control, sizeof(control)) == 0);
    control.completion_flags = OT_TAPE_COMPLETION_SUBMITTED;
    assert(ot_tape_control_validate(&control, sizeof(control)) == -1);
    for (n = 0; n < sizeof(control); ++n) assert(ot_tape_control_validate(&control, n) == -1);
    records();
    writes();
    fixed_packets();
    space_tests();
    media_tests();
    position_tests();
    locate_tests();
    wide_tests();
    partitions_tests();
    setmark_tests();
    setmark_write_packets();
    alert_packets();
    puts("Native tape API validation/capability/control/record/writer/fixed tests passed");
    return 0;
}
