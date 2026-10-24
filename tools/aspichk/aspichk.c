/* ASPICHK: checks a FAT12/16/32 drive and repairs it with /F.  Drives of
   ASPIDSK/ASPIFDD are read through their service (also when DOS has not
   mounted the medium), other drives through INT 21h 7305h (FAT32) or
   INT 25h/26h.
   ASPICHK d: [/F]
   Exit codes: 0 no errors (warnings possible), 1 errors found, 2 wrong use
   or no FAT drive, 3 read error in the boot sector. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <dos.h>
#include <i86.h>
#include <malloc.h>
#include "openaspi/fat_check.h"
#include "openaspi/exfat.h"             /* the code page tables */

#define VERSION "0.1"
#define CHUNK 32768U                    /* bytes of one block of the cluster map */
#define MAXCHUNKS 14

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

static enum { BY_ASPI, BY_7305, BY_25 } how;
static unsigned drive;                  /* 0 = A: */
static void __far *entry;
static oa_u8 unit;
static oa_u8 __far *chunks[MAXCHUNKS];
static unsigned nchunks;

static int aspi_call(oa_u8 func, struct packet *k, oa_u32 lba, void __far *buf)
{
    memset(k, 0, sizeof(*k));
    k->func = func; k->unit = unit; k->lba = lba; k->count = 1; k->buf = buf;
    svc(entry, k);
    return k->status ? -1 : 0;
}

static int io(int write, oa_u32 lba, void __far *buf)
{
    struct packet k;
    struct dio p;
    union REGS r;
    struct SREGS s;
    if (how == BY_ASPI) return aspi_call(write ? SVC_PWRITE : SVC_PREAD, &k, lba, buf);
    p.lba = lba; p.count = 1; p.buf = buf;
    if (how == BY_25) return (write ? int26((unsigned char)drive, &p) : int25((unsigned char)drive, &p)) ? -1 : 0;
    segread(&s);
    memset(&r, 0, sizeof(r));
    r.x.ax = 0x7305; r.x.cx = 0xFFFF; r.h.dl = (oa_u8)(drive + 1); r.x.si = write;
    r.x.bx = FP_OFF((void __far *)&p); s.ds = FP_SEG((void __far *)&p);
    intdosx(&r, &r, &s);
    return r.x.cflag ? -1 : 0;
}

static int rd(void *dev, oa_u32 lba, void __far *buf) { (void)dev; return io(0, lba, buf); }
static int wr(void *dev, oa_u32 lba, const void __far *buf) { (void)dev; return io(1, lba, (void __far *)buf); }

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
        unit = dpb[1];
        entry = MK_FP(FP_SEG(dev), *(oa_u16 __far *)(dev + 0x0F));
        return 0;
    }
    return -1;
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

static void flush(void)
{
    union REGS r;
    r.h.ah = 0x0D;
    intdos(&r, &r);
}

static void msg(void *ctx, int level, const char *text)
{
    (void)ctx;
    printf("%s%s\n", level == OA_FATCHK_ERROR ? "Error: " : level == OA_FATCHK_WARN ? "Warning: " :
           level == OA_FATCHK_FIXED ? "    Corrected: " : "", text);
}

static int mark(void *ctx, oa_u32 bit)
{
    oa_u8 __far *p = chunks[(unsigned)(bit / (CHUNK * 8UL))] + (unsigned)((bit % (CHUNK * 8UL)) >> 3);
    oa_u8 m = (oa_u8)(1 << (unsigned)(bit & 7));
    int old = (*p & m) != 0;
    (void)ctx;
    *p |= m;
    return old;
}

static void clear(void *ctx)
{
    unsigned i;
    (void)ctx;
    for (i = 0; i < nchunks; ++i) _fmemset(chunks[i], 0, CHUNK);
}

int main(int argc, char **argv)
{
    static oa_u8 boot[OA_FATCHK_MAXSECT];
    struct oa_fatchk c;
    struct packet k;
    union REGS r;
    oa_u32 need, total;
    int rc, fix = 0, dos7;
    printf("ASPICHK " VERSION " - FAT check and repair\n");
    if (argc == 3 && (!strcmp(argv[2], "/F") || !strcmp(argv[2], "/f"))) fix = 1;
    if (argc != 2 + fix || strlen(argv[1]) != 2 || argv[1][1] != ':' || !isalpha((unsigned char)argv[1][0])) {
        printf("ASPICHK d: [/F]   checks the FAT drive d:, /F repairs it\n");
        return 2;
    }
    drive = toupper((unsigned char)argv[1][0]) - 'A';
    memset(&c, 0, sizeof(c));
    if (!aspi_drive()) {
        how = BY_ASPI;
        if (aspi_call(SVC_CAPACITY, &k, 0, 0)) { printf("%c: has no medium.\n", 'A' + drive); return 2; }
        /* the driver reads the volume again: the medium may have changed.  A
           boot sector that the driver rejects is still checked (the FAT32
           backup) */
        aspi_call(SVC_RELOAD, &k, 0, 0);
        if (aspi_call(SVC_INFO, &k, 0, 0)) { printf("%c: cannot be read.\n", 'A' + drive); return 2; }
        if (k.count & UF_EXFAT) { printf("%c: is exFAT: use EXCHK.\n", 'A' + drive); return 2; }
        c.start = k.lba;
        printf("Checking %c: (ASPI unit %u, sector %lu)\n", 'A' + drive, unit, (unsigned long)c.start);
    } else {
        how = BY_7305;
        if (io(0, 0, boot)) {
            how = BY_25;
            if (io(0, 0, boot)) { printf("%c: cannot be read (no FAT drive?).\n", 'A' + drive); return 2; }
        }
        printf("Checking %c:%s\n", 'A' + drive, how == BY_25 ? "" : " (FAT32 interface)");
    }
    memset(&r, 0, sizeof(r));
    r.x.ax = 0x3000;
    intdos(&r, &r);
    dos7 = r.h.al >= 7;
    memset(&r, 0, sizeof(r));
    r.x.ax = 0x6601;
    intdos(&r, &r);
    c.cp = (!r.x.cflag && r.x.bx == 850 ? &oa_exfat_cp850 : &oa_exfat_cp437)->uni;
    c.read = rd; c.msg = msg; c.mark = mark; c.clear = clear;
    if (fix) c.write = wr;
    /* the cluster map: as much of it as there is memory for */
    if (rd(0, c.start, boot)) { printf("Read error in the boot sector.\n"); return 3; }
    total = boot[19] | boot[20] << 8 ? (oa_u32)(boot[19] | boot[20] << 8) :
            (oa_u32)boot[32] | (oa_u32)boot[33] << 8 | (oa_u32)boot[34] << 16 | (oa_u32)boot[35] << 24;
    need = (boot[13] ? total / boot[13] : total) / 8 + 1;
    while (nchunks < MAXCHUNKS && (oa_u32)nchunks * CHUNK < need && (chunks[nchunks] = _fmalloc(CHUNK)) != 0) ++nchunks;
    if (!nchunks) { printf("Not enough memory.\n"); return 2; }
    c.window = nchunks * CHUNK * 8UL;
    if (c.window / 8 < need) printf("(%lu passes)\n", (unsigned long)((need + c.window / 8 - 1) / (c.window / 8)));
    flush();
    if (fix && how != BY_ASPI && dos7) lock(1);
    rc = oa_fatchk_run(&c);
    if (fix && how != BY_ASPI && dos7) lock(0);
    if (fix) {                                  /* DOS and the driver read the volume again */
        if (how == BY_ASPI) aspi_call(SVC_RELOAD, &k, 0, 0);
        flush();
    }
    if (rc) {
        printf(rc == OA_FATCHK_EIO ? "Read error in the boot sector.\n" : "%c: has no valid FAT boot sector.\n", 'A' + drive);
        return rc == OA_FATCHK_EIO ? 3 : 2;
    }
    if (c.serial) printf("Serial number %04lX-%04lX\n", (unsigned long)(c.serial >> 16), (unsigned long)(c.serial & 0xFFFF));
    printf("FAT%u\n%10lu files\n%10lu directories\n", c.bits, (unsigned long)c.files, (unsigned long)c.dirs);
    printf("%10lu clusters of %lu bytes\n%10lu used\n%10lu free\n",
           (unsigned long)c.clusters, (unsigned long)c.cluster_size, (unsigned long)c.used, (unsigned long)c.free);
    if (c.bad) printf("%10lu bad\n", (unsigned long)c.bad);
    if (c.fixed) printf("%lu repairs written.\n", (unsigned long)c.fixed);
    if (!c.errors) printf("No errors found.\n");
    else printf("%lu errors found (lost %lu, cross-linked %lu clusters).\n",
                (unsigned long)c.errors, (unsigned long)c.lost, (unsigned long)c.cross);
    return c.errors ? 1 : 0;
}
