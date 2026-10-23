/* Sector images and DISKCOPY-style removable-media copying. GPL-3.0. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <fcntl.h>
#include <io.h>
#include <sys/stat.h>
#include <conio.h>
#include "openaspi/raw_media.h"
#include "openaspi/rescue.h"
#ifdef OA_GUI
#include "copy_ui.h"
#endif
#define CHUNK 16
static unsigned char data[CHUNK*512], verify[CHUNK*512];
static volatile sig_atomic_t cancelled;
static int rescue_mode;
static oa_u32 damaged;
static FILE *map_file;
static const char *map_option;
static char map_name[260];
static void cancel(int sig) { (void)sig; cancelled=1; }
static unsigned read_sectors(void *ctx,oa_u32 lba,unsigned n,void *buf)
{
    struct oa_raw_media *m=(struct oa_raw_media *)ctx;
    if(cancelled) return 995;
    return oa_raw_read_source(m,lba,n,buf);
}
static int mark_bad(void *ctx,oa_u32 lba,unsigned error)
{
    struct oa_raw_media *m=(struct oa_raw_media *)ctx;
    if(!map_file || fprintf(map_file,"%lu,%u,%02X,%02X\r\n",(unsigned long)lba,error&~OA_RESCUE_DEVICE_READ,m->sense_key,m->asc)<0 || fflush(map_file)) return -1;
    ++damaged; return 0;
}
static int read_chunk(struct oa_raw_media *m,oa_u32 lba,unsigned n)
{
    if(oa_rescue_read(m,read_sectors,mark_bad,lba,n,data,rescue_mode)<0) {
        printf("Read failed at LBA %lu: DOS %u, sense %u/%02X\n",(unsigned long)lba,m->error,m->sense_key,m->asc);
        return -1;
    }
    return 0;
}
static void phase(const char *name,unsigned drive,oa_u32 total)
{
#ifdef OA_GUI
    dd_ui_phase(name,drive,total);
#else
    (void)name; (void)drive; (void)total;
#endif
}
static int progress(oa_u32 done,oa_u32 total)
{
#ifdef OA_GUI
    (void)total;
    if(dd_ui_progress(done,damaged)) cancelled=1;
#else
    if(done==total) printf("%lu sectors processed.\n",(unsigned long)done);
#endif
    return cancelled ? -1 : 0;
}
static int write_chunk(struct oa_raw_media *m, oa_u32 lba, unsigned n)
{
    return oa_raw_io(m,1,lba,n,data) || oa_raw_io(m,0,lba,n,verify) ||
           memcmp(data,verify,n*512U) ? -1 : 0;
}
static int stream(struct oa_raw_media *m, FILE *file, int write)
{
    oa_u32 lba;
    unsigned n;
    phase(write ? "Write/verify target" : "Read source",m->drive,m->sectors);
    for (lba=0; lba<m->sectors; lba+=n) {
        if (progress(lba,m->sectors)) return -1;
        n=m->sectors-lba>CHUNK ? CHUNK : (unsigned)(m->sectors-lba);
        if (write) {
            if (fread(data,512,n,file)!=n || write_chunk(m,lba,n)) return -1;
        } else if (read_chunk(m,lba,n) || fwrite(data,512,n,file)!=n) return -1;
    }
    if(progress(m->sectors,m->sectors)) return -1;
    return ferror(file) ? -1 : 0;
}
static FILE *new_image(const char *name)
{
    int fd=open(name,O_CREAT|O_EXCL|O_RDWR|O_BINARY,S_IREAD|S_IWRITE);
    FILE *f;
    if (fd<0) return NULL;
    f=fdopen(fd,"w+b");
    if (!f) close(fd);
    return f;
}
static int same_file_drive(const char *path,unsigned drive)
{
    char full[260];
    if (!_fullpath(full,path,sizeof(full))) return 1;
    return ((full[0]>='a' && full[0]<='z' ? full[0]-'a' : full[0]-'A') == (int)drive);
}
static int open_map(unsigned source,unsigned target,const char *image_path)
{
    const char *dir;
    char *dot,*slash;
    unsigned i;
    if(!rescue_mode) return 0;
    if(map_option || image_path) {
        const char *p=map_option ? map_option : image_path;
        if(strlen(p)>250) return -1;
        strcpy(map_name,p);
        if(!map_option) {
            dot=strrchr(map_name,'.'); slash=strrchr(map_name,'\\');
            if(dot && (!slash || dot>slash)) *dot=0;
            strcat(map_name,".MAP");
        }
        if(same_file_drive(map_name,source) || same_file_drive(map_name,target)) return -1;
        map_file=new_image(map_name);
    } else {
        dir=getenv("TEMP"); if(!dir) dir=getenv("TMP"); if(!dir) dir=".";
        if(strlen(dir)>220) return -1;
        for(i=0;i<1000 && !map_file;++i) {
            sprintf(map_name,"%s\\OA%03u.MAP",dir,i);
            if(same_file_drive(map_name,source) || same_file_drive(map_name,target)) return -1;
            map_file=new_image(map_name);
        }
    }
    if(!map_file) return -1;
    if(fputs("PHYSICAL_LBA,DOS_ERROR,SENSE_KEY,ASC\r\n",map_file)<0 || fflush(map_file)) return -1;
    printf("Rescue map: %s\n",map_name); return 0;
}
static int sane_size(struct oa_raw_media *m)
{
    return m->sectors && m->sectors<=4194303UL;
}
static int image(unsigned drive,const char *path,int write)
{
    struct oa_raw_media m;
    FILE *f;
    long size;
    int rc=1;
    if (same_file_drive(path,drive)) { puts("Image file must be on another drive."); return 2; }
    f=write ? fopen(path,"rb") : new_image(path);
    if (!f) { puts("Cannot open image (new output files must not exist)."); return 1; }
    if (oa_raw_open(&m,drive,write)) {
        printf("Cannot acquire %c: media session: DOS %u\n",'A'+drive,m.error); goto file_done;
    }
    if (!sane_size(&m)) goto media_done;
    if (write) {
        if (fseek(f,0,SEEK_END) || (size=ftell(f))<0 ||
            (oa_u32)size!=m.sectors*512UL || fseek(f,0,SEEK_SET)) {
            puts("Image size must exactly match the physical medium."); goto media_done;
        }
    }
    if (!stream(&m,f,write)) rc=0;
media_done:
    if (oa_raw_close(&m)) rc=1;
file_done:
    if (fclose(f)) rc=1;
    return rc;
}
static int copy_drives(unsigned source,unsigned target)
{
    struct oa_raw_media s,d;
    oa_u32 lba;
    unsigned n;
    int rc=1;
    if (oa_raw_open(&s,source,0)) { printf("Source unavailable: DOS %u\n",s.error); return 1; }
    if (oa_raw_open(&d,target,1)) { printf("Target unavailable: DOS %u\n",d.error); goto source_done; }
    if (!sane_size(&s) || s.sectors!=d.sectors || !memcmp(s.address,d.address,3)) {
        puts("Source and target must be distinct, equally sized media."); goto target_done;
    }
    phase("Copy/verify",target,s.sectors);
    for (lba=0; lba<s.sectors; lba+=n) {
        n=s.sectors-lba>CHUNK ? CHUNK : (unsigned)(s.sectors-lba);
        if (progress(lba,s.sectors) || read_chunk(&s,lba,n) || write_chunk(&d,lba,n)) goto target_done;
    }
    if(progress(s.sectors,s.sectors)) goto target_done;
    rc=0;
target_done:
    if (oa_raw_close(&d)) rc=1;
source_done:
    if (oa_raw_close(&s)) rc=1;
    return rc;
}
static int one_drive(unsigned drive,const char *temp)
{
    struct oa_raw_media m;
    FILE *f;
    char path[260];
    const char *dir;
    unsigned i, attempts;
    oa_u32 sectors;
    int rc=1, key;
    if (temp) {
        if (strlen(temp)>=sizeof(path)) return 2;
        strcpy(path,temp);
        if (same_file_drive(path,drive)) return 2;
        f=new_image(path);
    } else {
        dir=getenv("TEMP"); if (!dir) dir=getenv("TMP"); if (!dir) dir=".";
        if (strlen(dir)>220) return 2;
        f=NULL;
        for (i=0;i<1000 && !f;++i) {
            sprintf(path,"%s\\OA%03u.TMP",dir,i);
            if (same_file_drive(path,drive)) { puts("Set TEMP to another drive."); return 2; }
            f=new_image(path);
        }
    }
    if (!f) { puts("Cannot create temporary image."); return 1; }
    printf("Temporary image: %s\n",path);
    if (oa_raw_open(&m,drive,0)) goto done;
    sectors=m.sectors;
    rc=!sane_size(&m) || stream(&m,f,0) || fflush(f);
    if (oa_raw_close(&m)) rc=1;
    if (rc) goto done;
    printf("Insert TARGET medium in %c:; Enter copies it, Esc cancels.\n",'A'+drive);
#ifdef OA_GUI
    key=dd_ui_exchange(drive);
#else
    do { key=getch(); } while (key!=13 && key!=27 && !cancelled);
#endif
    if (key==27 || cancelled || fseek(f,0,SEEK_SET)) { rc=1; goto done; }
    /* An intentional exchange may queue several UNIT ATTENTION reports.
       Drain only those notifications before writing, never retry data writes. */
    for(attempts=0;attempts<8;++attempts) {
        if(!oa_raw_open(&m,drive,1)) break;
        /* DOS maps the driver's UNIT ATTENTION/media-change error to 34.
           Consume only these queued exchange notifications before any data
           writes; never retry an interrupted write or a protection error. */
        if(m.error!=34) break;
    }
    if (!m.active) {
        printf("Target session failed: DOS %u\n",m.error); rc=1; goto done;
    }
    if (m.sectors!=sectors) printf("Target size %lu differs from source %lu sectors.\n",(unsigned long)m.sectors,(unsigned long)sectors);
    rc=m.sectors!=sectors || stream(&m,f,1);
    if (rc) printf("Target copy failed: DOS %u, image error %u\n",m.error,(unsigned)ferror(f));
    if (oa_raw_close(&m)) rc=1;
done:
    if (fclose(f)) rc=1;
    if (rc || damaged) printf("Temporary source image retained: %s\n",path);
    else if (remove(path)) { puts("Copy verified; could not remove temporary image."); rc=1; }
    return rc;
}
int main(int argc,char **argv)
{
    unsigned s=0,d=0,i,n=0;
    const char *args[3];
    const char *temp=NULL;
    int yes=0, rc=1,write=0,image_mode=0;
    signal(SIGINT,cancel);
    for(i=1;i<(unsigned)argc;++i) {
        if(!stricmp(argv[i],"/RESCUE")) rescue_mode=1;
        else if(!stricmp(argv[i],"/YES")) yes=1;
        else if(!strnicmp(argv[i],"/MAP:",5)) map_option=argv[i]+5;
        else if(!strnicmp(argv[i],"/TEMP:",6)) temp=argv[i]+6;
        else if(argv[i][0]=='/' || n==3) goto usage;
        else args[n++]=argv[i];
    }
#ifdef OA_GUI
    if(n==0) {
        if(dd_ui_select(&s,&d,&rescue_mode)) { dd_ui_finish(1,0); return 2; }
    } else
#endif
    if(n==3 && (!stricmp(args[0],"READ") || !stricmp(args[0],"WRITE"))) {
        image_mode=1; write=!stricmp(args[0],"WRITE");
        if(oa_drive(args[1],&s) || (write && (!yes || rescue_mode))) goto usage;
        d=s;
    } else {
        if(!n || n>2 || oa_drive(args[0],&s)) goto usage;
        d=s; if(n==2 && oa_drive(args[1],&d)) goto usage;
    }
    if(map_option && !rescue_mode) goto usage;
    if(!image_mode && !yes) {
#ifdef OA_GUI
        if(!dd_ui_confirm(s,d)) { dd_ui_finish(1,0); return 2; }
#else
            printf("Copy %c: to %c: overwrites the target. Continue (Y/N)? ", 'A'+s,'A'+d);
            i=(unsigned)getch(); puts("");
            if (i!='Y' && i!='y') return 2;
#endif
    }
    if(open_map(s,d,image_mode && !write ? args[2] : NULL)) {
        puts("Cannot create rescue map on a separate drive (existing maps are preserved).");
        if(map_file) fclose(map_file);
        return 1;
    }
    rc=image_mode ? image(s,args[2],write) : s==d ? one_drive(s,temp) : copy_drives(s,d);
    if(map_file && fclose(map_file)) rc=1;
    if(cancelled) rc=1;
    if(!rc && damaged) rc=3;
    if(rc==3) printf("ASPIDD rescue completed with %lu unreadable sectors; see %s.\n",(unsigned long)damaged,map_name);
    else puts(rc ? "ASPIDD failed/incomplete." : "ASPIDD copy/image completed; written sectors verified.");
#ifdef OA_GUI
    dd_ui_finish(rc,damaged);
#endif
    return rc;
usage:
    puts("ASPIDD X: [Y:] [/YES] [/TEMP:C:\\COPY.IMG]");
    puts("ASPIDD READ X: FILE.IMG");
    puts("ASPIDD WRITE X: FILE.IMG /YES");
    puts("/RESCUE [/MAP:C:\\BAD.MAP]: continue past unreadable media sectors.");
    return 2;
}
