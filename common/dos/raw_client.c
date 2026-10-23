/* Shared DOS wrapper for the checked ASPIFDD raw-media session API. GPL-3.0. */
#include <string.h>
#include <ctype.h>
#include <dos.h>
#include <i86.h>
#include "openaspi/raw_media.h"
#include "openaspi/rescue.h"

static int request(struct oa_raw_media *m, unsigned minor)
{
    union REGS r;
    struct SREGS s;
    memset(&r, 0, sizeof(r)); segread(&s);
    r.x.ax = 0x440D; r.x.bx = m->drive + 1;
    r.x.cx = 0x8000 | minor;
    r.x.dx = FP_OFF(m->packet); s.ds = FP_SEG(m->packet);
    intdosx(&r, &r, &s);
    m->error = r.x.cflag ? r.x.ax : 0;
    m->driver_error=r.x.cflag ? m->packet[13] : 0;
    m->sense_key=r.x.cflag ? m->packet[14] : 0;
    m->asc=r.x.cflag ? m->packet[15] : 0;
    return m->error ? -1 : 0;
}
void oa_disk_reset(void)
{
    union REGS r;
    memset(&r, 0, sizeof(r)); r.h.ah = 0x0D;
    intdos(&r, &r);
}
static void init(struct oa_raw_media *m, unsigned drive)
{
    memset(m, 0, sizeof(*m)); m->drive = drive;
    memcpy(m->packet, "RAW1", 4);
    *(unsigned *)(m->packet + 4) = 32;
}
static void result(struct oa_raw_media *m)
{
    m->sectors = *(oa_u32 *)(m->packet + 20);
    m->start = *(oa_u32 *)(m->packet + 24);
    m->length = *(oa_u32 *)(m->packet + 28);
    memcpy(m->address, m->packet + 8, 3);
    m->fat32=m->packet[11]!=0;
}
int oa_raw_info(struct oa_raw_media *m, unsigned drive)
{
    init(m, drive);
    if (request(m, 0)) return -1;
    result(m); return 0;
}
int oa_raw_open(struct oa_raw_media *m, unsigned drive, int write)
{
    oa_disk_reset();
    init(m, drive);
    *(unsigned *)(m->packet + 14) = write ? 1 : 0;
    if (request(m, 1)) return -1;
    m->active = 1; result(m); return 0;
}
int oa_raw_io(struct oa_raw_media *m, int write, oa_u32 lba, unsigned count, void *buf)
{
    int rc;
    if (!m->active || !count || count > 32 || lba >= m->sectors ||
        (oa_u32)count > m->sectors - lba) {
        m->error = 87; m->driver_error=0; m->sense_key=0; m->asc=0;
        return -1;
    }
    *(oa_u32 *)(m->packet + 8) = lba;
    *(unsigned *)(m->packet + 12) = count;
    *(unsigned *)(m->packet + 16) = FP_OFF(buf);
    *(unsigned *)(m->packet + 18) = FP_SEG(buf);
    *(unsigned *)(m->packet + 14)=0;
    rc=request(m, write ? 3 : 2);
    return rc;
}
int oa_raw_close(struct oa_raw_media *m)
{
    int rc;
    unsigned previous=m->error;
    unsigned old_driver=m->driver_error, old_sense=m->sense_key, old_asc=m->asc;
    if (!m->active) return 0;
    memset(m->packet+13,0,3);
    rc = request(m, 4);
    if(!rc) { m->error=previous; m->driver_error=old_driver; m->sense_key=old_sense; m->asc=old_asc; }
    m->active = 0;
    oa_disk_reset();
    return rc;
}
unsigned oa_raw_read_source(void *ctx,oa_u32 lba,unsigned count,void *buf)
{
    struct oa_raw_media *m=(struct oa_raw_media *)ctx;
    if(!oa_raw_io(m,0,lba,count,buf)) return 0;
    if(m->sense_key==3 || m->sense_key==4 || m->sense_key==11)
        return m->error|OA_RESCUE_DEVICE_READ;
    if(m->sense_key==5 && m->asc!=0x21) return 31;
    return m->error;
}
int oa_drive(const char *s, unsigned *drive)
{
    int c;
    if (strlen(s) != 2 || s[1] != ':') return -1;
    c = toupper((unsigned char)s[0]);
    if (c < 'A' || c > 'Z') return -1;
    *drive = c - 'A'; return 0;
}
