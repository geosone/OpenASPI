/* FAT filesystem format and surface check through ASPIFDD's raw service. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <time.h>
#include "openaspi/raw_media.h"
#include "openaspi/fat_format.h"
#include "openaspi/rescue.h"
static unsigned char data[512], verify[512], boot[512];
static unsigned char scan_buffer[16*512],fat_sector[512],fat_next[512];
static volatile sig_atomic_t cancelled;
static void cancel(int sig) { (void)sig; cancelled = 1; }
static int put(struct oa_raw_media *m, oa_u32 sector, unsigned char *buf)
{
    if (cancelled || oa_raw_io(m, 1, sector, 1, buf) ||
        oa_raw_io(m, 0, sector, 1, verify) || memcmp(buf, verify, 512)) return -1;
    return 0;
}
struct surface_scan {
    struct oa_raw_media *media;
    const struct oa_fat_layout *fat;
    oa_u32 base,data_start,bad_clusters,bad_sectors;
};
static unsigned scan_read(void *ctx,oa_u32 lba,unsigned n,void *buffer)
{
    struct surface_scan *s=(struct surface_scan *)ctx;
    return cancelled ? 995 : oa_raw_read_source(s->media,lba,n,buffer);
}
static int bad_cluster(void *ctx,oa_u32 lba,unsigned error)
{
    struct surface_scan *s=(struct surface_scan *)ctx;
    const struct oa_fat_layout *f=s->fat;
    oa_u32 cluster,offset,fat_lba;
    unsigned position,n,i,copy;
    unsigned char entry[4];
    int changed;
    (void)error;
    if(cancelled || lba<s->base+s->data_start) return -1;
    cluster=2+(lba-s->base-s->data_start)/f->spc;
    if(cluster>=f->clusters+2 || (f->bits==32 && cluster==2)) {
        printf("Unreadable required filesystem area: LBA %lu, cluster %lu.\n",(unsigned long)lba,(unsigned long)cluster);
        return -1;
    }
    ++s->bad_sectors;
    offset=oa_fat_entry_offset(f->bits,cluster); position=(unsigned)(offset%512);
    if(offset/512>=f->fat_sectors) return -1;
    fat_lba=s->base+f->reserved+offset/512;
    n=f->bits==32 ? 4 : 2;
    if(oa_raw_io(s->media,0,fat_lba,1,fat_sector)) {
        printf("Cannot read FAT metadata: DOS %u.\n",s->media->error); return -1;
    }
    if(position+n>512 && oa_raw_io(s->media,0,fat_lba+1,1,fat_next)) {
        puts("Cannot read FAT entry continuation."); return -1;
    }
    for(i=0;i<n;++i) entry[i]=position+i<512 ? fat_sector[position+i] : fat_next[position+i-512];
    changed=oa_fat_mark_bad(f->bits,cluster,entry);
    if(changed<0) { puts("Cannot encode FAT bad-cluster entry."); return -1; }
    if(!changed) return 0;
    for(i=0;i<n;++i) {
        if(position+i<512) fat_sector[position+i]=entry[i]; else fat_next[position+i-512]=entry[i];
    }
    for(copy=0;copy<2;++copy) {
        if(put(s->media,fat_lba+copy*(oa_u32)f->fat_sectors,fat_sector)) {
            printf("Cannot verify FAT bad-cluster entry: DOS %u.\n",s->media->error); return -1;
        }
        if(position+n>512 && put(s->media,fat_lba+copy*(oa_u32)f->fat_sectors+1,fat_next)) return -1;
    }
    ++s->bad_clusters;
    printf("Unreadable LBA %lu: FAT%u cluster %lu marked bad.\n",(unsigned long)lba,f->bits,(unsigned long)cluster);
    return 0;
}
int main(int argc, char **argv)
{
    struct oa_raw_media m;
    struct oa_fat_layout f;
    unsigned drive, i;
    oa_u32 base, length, end, sector, capacity, old_start, old_length;
    int yes=0, whole=0, fat32=0, rc=1;
    struct surface_scan scan;
    oa_u32 lba,limit;
    unsigned n;
    if (argc < 2 || oa_drive(argv[1], &drive)) goto usage;
    for (i=2; i<(unsigned)argc; ++i) {
        if (!stricmp(argv[i], "/YES")) yes=1;
        else if (!stricmp(argv[i], "/WHOLE")) whole=1;
        else if (!stricmp(argv[i], "/FAT:32")) fat32=1;
        else goto usage;
    }
    if (oa_raw_info(&m, drive)) {
        printf("ASPIFDD raw-media query failed: DOS %u\n", m.error); return 1;
    }
    base=whole ? 0 : m.start; length=whole || !m.length ? m.sectors : m.length;
    capacity=m.sectors; old_start=m.start; old_length=m.length;
    if (fat32 && !m.fat32) { puts("This DOS/driver combination does not support FAT32."); return 2; }
    if (base >= m.sectors || length > m.sectors-base ||
        (fat32 ? oa_fat_layout32(&f,length,base) : oa_fat_layout(&f,length,base))) {
        puts("Unsupported media size or partition bounds."); return 1;
    }
    printf("Format %c: FAT%u, %lu sectors at physical LBA %lu (ASPI %u:%u:%u).\n",
           'A'+drive, f.bits, (unsigned long)length, (unsigned long)base,
           m.address[0],m.address[1],m.address[2]);
    if (!yes) { puts("Preview only. Add /YES to erase the selected filesystem."); return 0; }
    signal(SIGINT,cancel);
    if (oa_raw_open(&m,drive,1)) {
        printf("Cannot acquire exclusive media session: DOS %u\n",m.error); return 1;
    }
    /* Revalidate the selected range after acquiring the medium lock. */
    if (m.sectors!=capacity || base >= m.sectors || length > m.sectors-base ||
        (!whole && (m.start!=old_start || m.length!=old_length))) {
        puts("Medium layout changed before exclusive access; no format was started."); goto done;
    }
    if (oa_raw_io(&m,0,0,1,boot)) goto done;
    if (!whole && !m.length && boot[510]==0x55 && boot[511]==0xAA) {
        for (i=0; i<4; ++i) if (boot[446+i*16+4]) {
            puts("Unrecognized partitioned medium. Use /WHOLE only to erase its layout.");
            goto done;
        }
    }
    oa_fat_boot(&f,(oa_u32)time(NULL),boot);
    end=f.reserved+2UL*f.fat_sectors+(f.bits==32 ? f.spc : f.root_sectors);
    for (sector=1; sector<end; ++sector) {
        memset(data,0,sizeof(data));
        if (sector==f.reserved || sector==f.reserved+(oa_u32)f.fat_sectors) oa_fat_first(&f,data);
        if (f.bits==32 && sector==6) memcpy(data,boot,512);
        if (f.bits==32 && (sector==1 || sector==7)) oa_fat_fsinfo(&f,data);
        if (put(&m,base+sector,data)) goto done;
    }
    memset(&scan,0,sizeof(scan)); scan.media=&m; scan.fat=&f; scan.base=base;
    scan.data_start=f.reserved+2UL*f.fat_sectors+(f.bits==32 ? 0 : f.root_sectors);
    {
        puts("Checking data surface; repeated unreadable sectors will mark FAT clusters bad.");
        limit=scan.data_start+f.clusters*f.spc;
        for(lba=scan.data_start;lba<limit;lba+=n) {
            n=limit-lba>16 ? 16 : (unsigned)(limit-lba);
            if(cancelled || oa_rescue_read(&scan,scan_read,bad_cluster,base+lba,n,scan_buffer,1)<0) {
                printf("Surface stopped at LBA %lu: DOS %u, sense %02X/%02X.\n",(unsigned long)(base+lba),m.error,m.sense_key,m.asc);
                puts("Surface/metadata check failed; no successful format is reported."); goto done;
            }
        }
        if(scan.bad_clusters>=f.clusters-(f.bits==32 ? 1 : 0)) goto done;
    }
    if(f.bits==32 && scan.bad_clusters) {
        oa_fat_fsinfo(&f,data);
        *(oa_u32 *)(data+488)=f.clusters-1-scan.bad_clusters;
        *(oa_u32 *)(data+492)=0xFFFFFFFFUL;
        if(put(&m,base+1,data) || put(&m,base+7,data)) goto done;
    }
    if (put(&m,base,boot)) goto done;
    printf("Bad clusters: %lu (%lu unreadable sectors).\n",(unsigned long)scan.bad_clusters,(unsigned long)scan.bad_sectors);
    rc=0;
done:
    if (oa_raw_close(&m)) rc=1;
    if (cancelled) rc=1;
    puts(rc ? "Format failed/incomplete; medium is not qualified for use." :
              "FAT format and metadata read-back verification passed.");
    return rc;
usage:
    puts("ASPIFMT X: [/YES] [/WHOLE] [/FAT:32]");
    puts("Read surface test and FAT bad-cluster marking are included.");
    puts("FAT32 needs DOS support. /WHOLE discards partitions.");
    return 2;
}
