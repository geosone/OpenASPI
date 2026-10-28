/* Sector access for ASPICHK and DEFRAG, see drive.h. */
#include <string.h>
#include <dos.h>
#include <i86.h>
#include "drive.h"

#pragma pack(1)
struct packet { oa_u8 func, unit; oa_u16 status; oa_u32 lba; oa_u16 count; void __far *buf; oa_u16 result; };
struct dio { oa_u32 lba; oa_u16 count; void __far *buf; };     /* INT 25h/26h, 7305h */
#pragma pack()

enum { SVC_INFO = 0, SVC_PREAD = 5, SVC_PWRITE = 6, SVC_CAPACITY = 7, SVC_RELOAD = 8 };
#define UF_EXFAT 0x80

/* far call of the exFAT service of ASPIDSK/ASPIFDD, ES:BX -> packet */
void svc(void __far *entry, struct packet __far *p);
#pragma aux svc = \
    "push bp" "push dx" "push ax" "mov bp, sp" "call dword ptr [bp]" "add sp, 4" "pop bp" \
    parm [dx ax] [es bx] modify [ax bx cx dx si di es];

/* INT 25h/26h with a packet: 0, or the error code */
unsigned int25(unsigned char drive, struct dio __far *p);
#pragma aux int25 = \
    "push ds" "push bp" "mov ds, dx" "mov cx, 0FFFFh" "int 25h" "pop cx" "pop bp" "pop ds" \
    "sbb cx, cx" "and ax, cx" \
    parm [al] [dx bx] value [ax] modify [bx cx dx si di];
unsigned int26(unsigned char drive, struct dio __far *p);
#pragma aux int26 = \
    "push ds" "push bp" "mov ds, dx" "mov cx, 0FFFFh" "int 26h" "pop cx" "pop bp" "pop ds" \
    "sbb cx, cx" "and ax, cx" \
    parm [al] [dx bx] value [ax] modify [bx cx dx si di];

oa_u32 drv_start;
oa_u8 drv_unit;
static int how;
static unsigned drive;
static void __far *entry;
static int locked;

static int aspi_call(oa_u8 func, struct packet *k, oa_u32 lba, unsigned count, void __far *buf)
{
    memset(k, 0, sizeof(*k));
    k->func = func; k->unit = drv_unit; k->lba = lba; k->count = count; k->buf = buf;
    svc(entry, k);
    return k->status ? -1 : 0;
}

int drv_io(int write, oa_u32 lba, unsigned count, void __far *buf)
{
    struct packet k;
    struct dio p;
    union REGS r;
    struct SREGS s;
    if (how == DRV_ASPI) return aspi_call(write ? SVC_PWRITE : SVC_PREAD, &k, drv_start + lba, count, buf);
    p.lba = drv_start + lba; p.count = count; p.buf = buf;
    if (how == DRV_25) return (write ? int26((unsigned char)drive, &p) : int25((unsigned char)drive, &p)) ? -1 : 0;
    segread(&s);
    memset(&r, 0, sizeof(r));
    r.x.ax = 0x7305; r.x.cx = 0xFFFF; r.h.dl = (oa_u8)(drive + 1); r.x.si = write;
    r.x.bx = FP_OFF((void __far *)&p); s.ds = FP_SEG((void __far *)&p);
    intdosx(&r, &r, &s);
    return r.x.cflag ? -1 : 0;
}

/* the drive letter of ASPIDSK/ASPIFDD ("EXF1" in the device header) */
static int aspi_drive(void)
{
    union REGS r;
    struct SREGS s;
    oa_u8 __far *dpb, __far *dev;
    segread(&s);
    r.h.ah = 0x52;
    intdosx(&r, &r, &s);
    for (dpb = *(oa_u8 __far * __far *)MK_FP(s.es, r.x.bx); FP_OFF(dpb) != 0xFFFF; dpb = *(oa_u8 __far * __far *)(dpb + 0x19)) {
        if (dpb[0] != drive) continue;
        dev = *(oa_u8 __far * __far *)(dpb + 0x13);
        if ((*(oa_u16 __far *)(dev + 4) & 0x8000) || _fmemcmp(dev + 0x0B, "EXF1", 4)) return -1;
        drv_unit = dpb[1];
        entry = MK_FP(FP_SEG(dev), *(oa_u16 __far *)(dev + 0x0F));
        return 0;
    }
    return -1;
}

int drv_open(unsigned d)
{
    static oa_u8 sec[4096];
    struct packet k;
    drive = d;
    drv_start = 0;
    if (!aspi_drive()) {
        how = DRV_ASPI;
        if (aspi_call(SVC_CAPACITY, &k, 0, 1, 0)) return DRV_NOMEDIA;
        /* the driver reads the volume again: the medium may have changed.  A
           boot sector that the driver rejects is still read (the FAT32
           backup) */
        aspi_call(SVC_RELOAD, &k, 0, 1, 0);
        if (aspi_call(SVC_INFO, &k, 0, 1, 0)) return DRV_NOREAD;
        if (k.count & UF_EXFAT) return DRV_EXFAT;
        drv_start = k.lba;
        return how;
    }
    how = DRV_7305;
    if (drv_io(0, 0, 1, sec)) {
        how = DRV_25;
        if (drv_io(0, 0, 1, sec)) return DRV_NOREAD;
    }
    return how;
}

static void flush(void)
{
    union REGS r;
    r.h.ah = 0x0D;
    intdos(&r, &r);
}

/* DOS 7 wants a lock for direct writes (also outside Windows); level 0 */
static void lock(int on)
{
    union REGS r;
    memset(&r, 0, sizeof(r));
    r.x.ax = 0x440D; r.h.bl = (oa_u8)(drive + 1);
    r.x.cx = on ? 0x084A : 0x086A;
    intdos(&r, &r);
}

void drv_begin(int write)
{
    union REGS r;
    flush();
    memset(&r, 0, sizeof(r));
    r.x.ax = 0x3000;
    intdos(&r, &r);
    locked = write && how != DRV_ASPI && r.h.al >= 7;
    if (locked) lock(1);
}

void drv_end(int write)
{
    struct packet k;
    if (locked) lock(0);
    locked = 0;
    if (write) {
        if (how == DRV_ASPI) aspi_call(SVC_RELOAD, &k, 0, 1, 0);
        flush();
    }
}
