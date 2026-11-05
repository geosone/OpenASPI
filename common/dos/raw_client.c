/* DOS large-model client for RAW1 generic block IOCTLs (INT 21h/440Dh).
 * Drives are zero-based here (A=0), one-based in DOS BX. Each instance owns
 * its request packet and BEGIN token; successful open must be paired with
 * close. Addresses/counts use physical 512-byte sectors, not partition LBAs.
 * Return 0/-1 and retain DOS plus driver/sense diagnostics in the instance.
 * The packet's integer/far-pointer stores intentionally target 16-bit DOS;
 * this file is not a portable host-side serialization implementation.
 */

/* Shared DOS wrapper for the checked ASPIFDD raw-media session API. GPL-2.0-or-later. */
#include <string.h>
#include <ctype.h>
#include <dos.h>
#include <i86.h>
#include "openaspi/raw_media.h"
#include "openaspi/rescue.h"

/* Far call to a driver entry with ES:BX = request header. */
#pragma aux drv_call = \
    "push bp" "push dx" "push ax" "mov bp, sp" "call dword ptr [bp]" "add sp, 4" "pop bp" \
    parm [dx ax] [es bx] modify [ax bx cx dx si di es];
static void drv_call(void __far *entry, void __far *rh);

/* MS-DOS 7 passes generic IOCTL category 80h of a block device to no
 * driver (error 1). Hand the same request to the drive's driver directly:
 * the DPB (DOS 4 or later layout) names it and the unit. -1 if the drive
 * has no DPB or its driver no generic IOCTL; else the DOS error, 0 done. */
static int direct_request(struct oa_raw_media *m, unsigned minor)
{
    union REGS r;
    struct SREGS s;
    unsigned char __far *dpb;
    unsigned char __far *dev;
    static unsigned char rh[0x17];
    unsigned status;
    memset(&r, 0, sizeof(r)); r.h.ah = 0x30; intdos(&r, &r);
    if (r.h.al < 4) return -1;
    memset(&r, 0, sizeof(r)); segread(&s); r.h.ah = 0x52; intdosx(&r, &r, &s);
    dpb = *(unsigned char __far * __far *)MK_FP(s.es, r.x.bx);
    while (FP_OFF(dpb) != 0xFFFF && dpb[0] != m->drive)
        dpb = *(unsigned char __far * __far *)(dpb + 0x19);
    if (FP_OFF(dpb) == 0xFFFF) return -1;
    dev = *(unsigned char __far * __far *)(dpb + 0x13);
    if ((*(unsigned __far *)(dev + 4) & 0x8040) != 0x0040) return -1;
    memset(rh, 0, sizeof(rh));
    rh[0] = sizeof(rh); rh[1] = dpb[1]; rh[2] = 0x13;   /* GENERIC IOCTL */
    rh[0x0D] = 0x80; rh[0x0E] = (unsigned char)minor;
    *(void __far * __far *)(rh + 0x13) = (void __far *)m->packet;
    drv_call(MK_FP(FP_SEG(dev), *(unsigned __far *)(dev + 6)), (void __far *)rh);
    drv_call(MK_FP(FP_SEG(dev), *(unsigned __far *)(dev + 8)), (void __far *)rh);
    status = *(unsigned *)(rh + 3);
    return (status & 0x8000) ? 0x13 + (status & 0xFF) : 0;  /* as DOS maps it */
}

static int request(struct oa_raw_media *m, unsigned minor)
{
    union REGS r;
    struct SREGS s;
    int rc;
    memset(&r, 0, sizeof(r)); segread(&s);
    r.x.ax = 0x440D; r.x.bx = m->drive + 1;
    r.x.cx = 0x8000 | minor;
    r.x.dx = FP_OFF(m->packet); s.ds = FP_SEG(m->packet);
    intdosx(&r, &r, &s);
    m->error = r.x.cflag ? r.x.ax : 0;
    if (m->error == 1 && (rc = direct_request(m, minor)) >= 0)
        m->error = rc;
    m->driver_error=m->error ? m->packet[13] : 0;
    m->sense_key=m->error ? m->packet[14] : 0;
    m->asc=m->error ? m->packet[15] : 0;
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
/* Flush DOS's filesystem buffers before acquiring exclusive raw access.
 * active is set only after BEGIN succeeds; no cleanup END is due on failure.
 */
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
/* Release once and reset DOS's filesystem view. Successful cleanup keeps
 * the preceding I/O diagnostics; failed cleanup exposes its own failure.
 * Never hide END failure behind a successful data copy or format report.
 */
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
/* Rescue callback: qualify device read faults using sense before tagging.
 * An unrelated ILLEGAL REQUEST must not become thousands of fake bad sectors;
 * ordinary DOS errors remain available to the shared conservative policy.
 */
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
