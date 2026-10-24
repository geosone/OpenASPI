/* EXCHK: checks an exFAT drive of EXFAT.SYS, on a BIOS disk or an
   ASPIDSK/ASPIFDD medium.  It only reads and reports.
   EXCHK D:
   Exit codes: 0 no errors (warnings possible), 1 errors found, 2 wrong use
   or no exFAT drive of EXFAT.SYS, 3 read error in the boot region. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <dos.h>
#include <i86.h>
#include <malloc.h>
#include "openaspi/exfat_check.h"
#include "openaspi/exfatsys.h"

#define VERSION "0.1"
#define CHUNK 32768U                    /* bytes of one block of the cluster map */
#define MAXCHUNKS 14

#pragma pack(1)
struct packet { oa_u8 func, unit; oa_u16 status; oa_u32 lba; oa_u16 count; void __far *buf; oa_u16 result; };
struct dap { oa_u8 size, res; oa_u16 count; void __far *buf; oa_u32 lba, lba_hi; };
#pragma pack()

/* far call of the exFAT service of ASPIDSK/ASPIFDD, ES:BX -> packet */
void svc(void __far *entry, struct packet __far *p);
#pragma aux svc = \
    "push bp" "push dx" "push ax" "mov bp, sp" "call dword ptr [bp]" "add sp, 4" "pop bp" \
    parm [dx ax] [es bx] modify [ax bx cx dx si di es];

static struct oa_exfatsys_vol vol;
static oa_u8 __far *chunks[MAXCHUNKS];
static unsigned nchunks;
static oa_u8 bounce_area[1024];

static oa_u8 __far *bounce(void)
{
    oa_u32 lin = (oa_u32)FP_SEG(bounce_area) * 16 + FP_OFF(bounce_area);
    return (lin & 0xFFFF) > 0xFE00 ? bounce_area + 512 : bounce_area;
}

static int bios_read(void *dev, oa_u32 lba, void __far *buf)
{
    union REGS r;
    struct SREGS s;
    struct dap p;
    oa_u32 t;
    unsigned tries, cx = 0, dh = 0;
    (void)dev;
    if (!vol.ext) {
        t = lba / vol.spt;
        cx = (unsigned)(lba - t * vol.spt + 1);
        dh = (unsigned)(t % vol.heads);
        t /= vol.heads;
        if (t > 1023) return -1;
        cx |= (unsigned)((t & 0xFF) << 8 | (t >> 2 & 0xC0));
    }
    for (tries = 0; tries < 3; ++tries) {
        segread(&s);
        memset(&r, 0, sizeof(r));
        r.h.dl = vol.bios;
        if (vol.ext) {
            p.size = 16; p.res = 0; p.count = 1; p.buf = buf; p.lba = lba; p.lba_hi = 0;
            r.h.ah = 0x42; r.x.si = FP_OFF((void __far *)&p); s.ds = FP_SEG((void __far *)&p);
            int86x(0x13, &r, &r, &s);
            if (!r.x.cflag) return 0;
        } else {
            r.x.ax = 0x0201; r.x.cx = cx; r.h.dh = (oa_u8)dh;
            r.x.bx = FP_OFF(buf); s.es = FP_SEG(buf);
            int86x(0x13, &r, &r, &s);
            if (!r.x.cflag) return 0;
            if (r.h.ah == 0x09) {               /* DMA boundary */
                memset(&r, 0, sizeof(r));
                r.x.ax = 0x0201; r.x.cx = cx; r.h.dh = (oa_u8)dh; r.h.dl = vol.bios;
                r.x.bx = FP_OFF(bounce()); s.es = FP_SEG(bounce());
                int86x(0x13, &r, &r, &s);
                if (!r.x.cflag) { _fmemcpy(buf, bounce(), 512); return 0; }
            }
        }
        memset(&r, 0, sizeof(r));
        r.h.dl = vol.bios;
        int86(0x13, &r, &r);                    /* reset */
    }
    return -1;
}

static int aspi_read(void *dev, oa_u32 lba, void __far *buf)
{
    struct packet k;
    (void)dev;
    memset(&k, 0, sizeof(k));
    k.func = 1; k.unit = vol.unit; k.lba = lba; k.count = 1; k.buf = buf;
    svc(MK_FP(vol.svc_seg, vol.svc_off), &k);
    return k.status ? -1 : 0;
}

/* EXFAT.SYS's volume of drive letter (0 = A:) */
static int find_volume(unsigned letter)
{
    union REGS r;
    struct SREGS s;
    oa_u8 __far *dev, __far *v;
    const struct oa_exfatsys_info __far *info;
    unsigned i, n;
    segread(&s);
    r.h.ah = 0x52;
    intdosx(&r, &r, &s);
    for (dev = (oa_u8 __far *)MK_FP(s.es, r.x.bx + 0x22); FP_OFF(dev) != 0xFFFF; dev = *(oa_u8 __far * __far *)dev) {
        if (!(*(oa_u16 __far *)(dev + 4) & 0x8000) || _fmemcmp(dev + 10, "$EXFAT$ EXI1", 12)) continue;
        info = MK_FP(FP_SEG(dev), *(oa_u16 __far *)(dev + 22));
        if (info->version != 1) return -2;
        n = *(oa_u16 __far *)MK_FP(FP_SEG(dev), info->count);
        for (i = 0; i < n; ++i) {
            v = (oa_u8 __far *)MK_FP(FP_SEG(dev), info->table + i * info->stride);
            _fmemcpy(&vol, v, sizeof(vol));
            if (vol.letter == letter) return 0;
        }
        return -3;
    }
    return -1;
}

static void msg(void *ctx, int level, const char *text)
{
    (void)ctx;
    printf("%s%s\n", level == OA_EXCHK_ERROR ? "Error: " : level == OA_EXCHK_WARN ? "Warning: " : "", text);
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
    static oa_u8 boot[512];
    struct oa_exchk c;
    union REGS r;
    oa_u32 need;
    unsigned letter;
    int rc;
    printf("EXCHK " VERSION " - exFAT check, reports only\n");
    if (argc != 2 || strlen(argv[1]) != 2 || argv[1][1] != ':' || !isalpha((unsigned char)argv[1][0])) {
        printf("EXCHK d:   checks the exFAT drive d: of EXFAT.SYS\n");
        return 2;
    }
    letter = toupper((unsigned char)argv[1][0]) - 'A';
    rc = find_volume(letter);
    if (rc == -1) { printf("EXFAT.SYS is not loaded.\n"); return 2; }
    if (rc == -2) { printf("This EXFAT.SYS is of another version.\n"); return 2; }
    if (rc) { printf("%c: is not a drive of EXFAT.SYS.\n", 'A' + letter); return 2; }
    if (vol.aspi && vol.state != OA_EXFATSYS_OURS) { printf("%c: has no exFAT medium.\n", 'A' + letter); return 2; }
    memset(&c, 0, sizeof(c));
    if (vol.aspi) {
        c.read = aspi_read;
        printf("Checking %c: (ASPI unit %u)\n", 'A' + letter, vol.unit);
    } else {
        c.read = bios_read; c.start = vol.start;
        printf("Checking %c: (BIOS disk %02Xh, sector %lu)\n", 'A' + letter, vol.bios, (unsigned long)vol.start);
    }
    memset(&r, 0, sizeof(r));
    r.x.ax = 0x6601;
    intdos(&r, &r);
    c.cp = !r.x.cflag && r.x.bx == 850 ? &oa_exfat_cp850 : &oa_exfat_cp437;
    c.msg = msg; c.mark = mark; c.clear = clear;
    /* the cluster map: as much of it as there is memory for */
    if (c.read(0, c.start, boot)) { printf("Read error in the boot sector.\n"); return 3; }
    need = ((oa_u32)boot[92] | (oa_u32)boot[93] << 8 | (oa_u32)boot[94] << 16 | (oa_u32)boot[95] << 24) / 8 + 1;
    while (nchunks < MAXCHUNKS && (oa_u32)nchunks * CHUNK < need && (chunks[nchunks] = _fmalloc(CHUNK)) != 0) ++nchunks;
    if (!nchunks) { printf("Not enough memory.\n"); return 2; }
    c.window = nchunks * CHUNK * 8UL;
    if (c.window / 8 < need) printf("(%lu passes)\n", (unsigned long)((need + c.window / 8 - 1) / (c.window / 8)));
    rc = oa_exchk_run(&c);
    if (rc) {
        printf(rc == OA_EXFAT_EIO ? "Read error in the boot region.\n" : "%c: has no valid exFAT boot sector.\n", 'A' + letter);
        return rc == OA_EXFAT_EIO ? 3 : 2;
    }
    printf("Serial number %04lX-%04lX\n", (unsigned long)(c.serial >> 16), (unsigned long)(c.serial & 0xFFFF));
    printf("%10lu files\n%10lu directories\n", (unsigned long)c.files, (unsigned long)c.dirs);
    printf("%10lu clusters of %lu bytes\n%10lu used\n%10lu free\n",
           (unsigned long)c.clusters, (unsigned long)c.cluster_size, (unsigned long)c.used, (unsigned long)c.free);
    if (c.bad) printf("%10lu bad\n", (unsigned long)c.bad);
    if (!c.errors) printf("No errors found.\n");
    else printf("%lu errors found (lost %lu, unmarked %lu, cross-linked %lu clusters).\n",
                (unsigned long)c.errors, (unsigned long)c.lost, (unsigned long)c.unmarked, (unsigned long)c.cross);
    return c.errors ? 1 : 0;
}
