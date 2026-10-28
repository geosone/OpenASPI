/* DEFRAG: defragments a FAT12/16/32 drive, safe against power loss (see
   include/openaspi/fat_defrag.h).  The drive is checked first (the check of
   ASPICHK); with errors nothing is moved.
   DEFRAG d: [/U] [/A] [/B]
   /U only the fragmented files, /A analysis only, /B no screen (lines).
   Exit codes: 0 done, 1 the drive has errors (ASPICHK d: /F), 2 wrong use,
   no FAT drive or too little memory, 3 read or write error, 4 stopped
   with Esc. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <dos.h>
#include <i86.h>
#include <malloc.h>
#include <bios.h>
#include "openaspi/fat_check.h"
#include "openaspi/fat_defrag.h"
#include "openaspi/exfat.h"             /* the code page tables */
#include "../aspichk/drive.h"

#define VERSION "0.1"
#define CHUNK 32768U                    /* bytes of one block of work memory */
#define MAXCHUNKS 14
#define MAXITEMS 32000U                 /* files: the sorted list in one block */
#define TOP 2                           /* rows of the map */
#define ROWS 18
#define COLS 80

static unsigned drive;
static oa_u8 __far *chunks[MAXCHUNKS];
static unsigned nchunks;
static int batch;
static oa_u16 __far *screen;
static int mono;
static oa_u32 per, nclu;                /* clusters per cell */
static struct oa_defrag d;
static char last[16];

/* ---- the pre-check: as ASPICHK, without repairs ---- */

static int rd1(void *dev, oa_u32 lba, void __far *buf) { (void)dev; return drv_io(0, lba, 1, buf); }

static void chk_msg(void *ctx, int level, const char *text)
{
    (void)ctx;
    if (level == OA_FATCHK_ERROR) printf("Error: %s\n", text);
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

/* ---- the screen ---- */

static void put(unsigned row, unsigned col, const char *s, oa_u8 attr)
{
    oa_u16 __far *p = screen + row * COLS + col;
    for (; *s && col < COLS; ++s, ++col) *p++ = (oa_u16)(attr << 8 | (oa_u8)*s);
}

static void line(unsigned row, const char *s, oa_u8 attr)
{
    char buf[COLS + 1];
    sprintf(buf, "%-80.80s", s);
    put(row, 0, buf, attr);
}

static oa_u8 color(oa_u8 c, oa_u8 m) { return mono ? m : c; }

/* the cells of clusters clu .. clu+count-1 */
static void cells(oa_u32 clu, oa_u32 count, int state)
{
    oa_u32 cell = (clu - 2) / per, end = (clu - 2 + count - 1) / per, c, lo, hi;
    oa_u16 v;
    int any;
    for (; cell <= end && cell < ROWS * COLS; ++cell) {
        lo = 2 + cell * per; hi = lo + per > nclu + 2 ? nclu + 2 : lo + per;
        if (state == OA_DEFRAG_READ) v = (oa_u16)(color(0x1F, 0x70) << 8 | 'r');
        else if (state == OA_DEFRAG_WRITE) v = (oa_u16)(color(0x1F, 0x70) << 8 | 'W');
        else {
            for (any = 0, c = lo; c < hi && !any; ++c) any = oa_defrag_used(c);
            if (!any) v = (oa_u16)(color(0x13, 0x07) << 8 | 0xB0);
            else if (d.mode == OA_DEFRAG_FULL && hi <= d.done) v = (oa_u16)(color(0x1A, 0x0F) << 8 | 0xFE);
            else v = (oa_u16)(color(0x1E, 0x07) << 8 | 0xFE);
        }
        screen[(TOP + cell / COLS) * COLS + cell % COLS] = v;
    }
}

static void map(void *ctx, oa_u32 clu, oa_u32 count, int state)
{
    (void)ctx;
    if (batch) return;
    if (!per) {                         /* the volume is known from the first call on */
        nclu = d.clusters;
        per = (nclu + ROWS * COLS - 1) / (ROWS * COLS);
    }
    cells(clu, count, state);
}

static void status(void *ctx, const char *text)
{
    char buf[COLS + 1];
    (void)ctx;
    if (batch) {                        /* a line per phase */
        if (strncmp(last, text, sizeof(last) - 1)) printf("%s\n", text);
        strncpy(last, text, sizeof(last) - 1);
        return;
    }
    line(23, text, color(0x1F, 0x0F));
    sprintf(buf, "Files moved: %lu   clusters moved: %lu", (unsigned long)d.moves, (unsigned long)d.moved);
    line(24, buf, color(0x1F, 0x07));
}

static int stop(void *ctx)
{
    (void)ctx;
    return _bios_keybrd(_KEYBRD_READY) && (_bios_keybrd(_KEYBRD_READ) & 0xFF) == 27;
}

static void cursor(int on)
{
    union REGS r;
    r.h.ah = 0x01; r.x.cx = on ? 0x0607 : 0x2000;
    int86(0x10, &r, &r);
}

static void screen_on(void)
{
    union REGS r;
    char buf[COLS + 1];
    unsigned i;
    r.h.ah = 0x0F;
    int86(0x10, &r, &r);
    mono = r.h.al == 7;
    screen = (oa_u16 __far *)MK_FP(mono ? 0xB000 : 0xB800, 0);
    cursor(0);
    for (i = 0; i < 25; ++i) line(i, "", color(0x17, 0x07));
    sprintf(buf, " OpenASPI DEFRAG " VERSION " - drive %c: - Esc stops", 'A' + drive);
    line(0, buf, color(0x30, 0x70));
    put(21, 1, "\xFE used   ", color(0x1E, 0x07));
    put(21, 11, "\xFE in place   ", color(0x1A, 0x0F));
    put(21, 25, "\xB0 free   ", color(0x13, 0x07));
    put(21, 35, "r reading   W writing", color(0x17, 0x07));
}

static void screen_off(void)
{
    union REGS r;
    r.h.ah = 0x0F;
    int86(0x10, &r, &r);
    r.h.ah = 0x00;                      /* the same mode again: a clear screen */
    int86(0x10, &r, &r);
    cursor(1);
}

/* ---- the defragmentation ---- */

static int rdn(void *dev, oa_u32 lba, unsigned count, void __far *buf) { (void)dev; return drv_io(0, lba, count, buf); }
static int wrn(void *dev, oa_u32 lba, unsigned count, const void __far *buf) { (void)dev; return drv_io(1, lba, count, (void __far *)buf); }
static void __far *mem(void *ctx, oa_u32 off) { (void)ctx; return chunks[(unsigned)(off >> 15)] + (unsigned)(off & (CHUNK - 1)); }

static int check(void)
{
    static oa_u8 boot[OA_FATCHK_MAXSECT];
    struct oa_fatchk c;
    union REGS r;
    oa_u32 total, need;
    int rc;
    memset(&c, 0, sizeof(c));
    memset(&r, 0, sizeof(r));
    r.x.ax = 0x6601;
    intdos(&r, &r);
    c.cp = (!r.x.cflag && r.x.bx == 850 ? &oa_exfat_cp850 : &oa_exfat_cp437)->uni;
    c.read = rd1; c.msg = chk_msg; c.mark = mark; c.clear = clear;
    if (rd1(0, 0, boot)) { printf("Read error in the boot sector.\n"); return 3; }
    total = boot[19] | boot[20] << 8 ? (oa_u32)(boot[19] | boot[20] << 8) :
            (oa_u32)boot[32] | (oa_u32)boot[33] << 8 | (oa_u32)boot[34] << 16 | (oa_u32)boot[35] << 24;
    need = (boot[13] ? total / boot[13] : total) / 8 + 1;
    while (nchunks < MAXCHUNKS && (oa_u32)nchunks * CHUNK < need && (chunks[nchunks] = _fmalloc(CHUNK)) != 0) ++nchunks;
    if (!nchunks) { printf("Not enough memory.\n"); return 2; }
    c.window = nchunks * CHUNK * 8UL;
    printf("Checking the drive...\n");
    rc = oa_fatchk_run(&c);
    while (nchunks) _ffree(chunks[--nchunks]);
    if (rc) { printf("%c: has no valid FAT boot sector.\n", 'A' + drive); return rc == OA_FATCHK_EIO ? 3 : 2; }
    if (c.errors) { printf("%c: has errors: run ASPICHK %c: /F first.\n", 'A' + drive, 'A' + drive); return 1; }
    return 0;
}

int main(int argc, char **argv)
{
    static const char *const why[] = { "", "no FAT drive", "read or write error", "too little memory for this drive",
                                       "stopped", "a directory entry is not as expected" };
    oa_u16 __far *order;
    int rc, i, mode = OA_DEFRAG_FULL;
    printf("DEFRAG " VERSION " - FAT defragmentation (OpenASPI)\n");
    for (i = 2; i < argc; ++i) {
        if (!strcmp(argv[i], "/U") || !strcmp(argv[i], "/u")) mode = OA_DEFRAG_FILES;
        else if (!strcmp(argv[i], "/A") || !strcmp(argv[i], "/a")) mode = OA_DEFRAG_ANALYZE;
        else if (!strcmp(argv[i], "/B") || !strcmp(argv[i], "/b")) batch = 1;
        else break;
    }
    if (argc < 2 || i < argc || strlen(argv[1]) != 2 || argv[1][1] != ':' || !isalpha((unsigned char)argv[1][0])) {
        printf("DEFRAG d: [/U] [/A] [/B]\n"
               "  defragments the FAT drive d: (files contiguous, directories first,\n"
               "  free space at the end); /U only joins fragmented files, /A only\n"
               "  analyzes, /B without the screen\n");
        return 2;
    }
    drive = toupper((unsigned char)argv[1][0]) - 'A';
    switch (drv_open(drive)) {
    case DRV_NOMEDIA: printf("%c: has no medium.\n", 'A' + drive); return 2;
    case DRV_EXFAT: printf("%c: is exFAT: not supported.\n", 'A' + drive); return 2;
    case DRV_NOREAD: printf("%c: cannot be read (no FAT drive?).\n", 'A' + drive); return 2;
    }
    if ((rc = check()) != 0) return rc;
    memset(&d, 0, sizeof(d));
    d.read = rdn; d.write = wrn; d.mode = mode;
    d.bufsize = CHUNK;
    if ((d.buf = _fmalloc(CHUNK)) == 0 || (order = _fmalloc(MAXITEMS * 2)) == 0) { printf("Not enough memory.\n"); return 2; }
    d.order = order; d.maxitems = MAXITEMS;
    while (nchunks < MAXCHUNKS && (chunks[nchunks] = _fmalloc(CHUNK)) != 0) ++nchunks;
    d.mem = mem; d.memsize = nchunks * (oa_u32)CHUNK; d.block = CHUNK;
    d.map = map; d.status = status; d.stop = stop;
    if (!batch) screen_on();
    drv_begin(mode != OA_DEFRAG_ANALYZE);
    rc = oa_defrag_run(&d);
    drv_end(mode != OA_DEFRAG_ANALYZE);
    if (!batch) {
        if (per) cells(2, nclu, OA_DEFRAG_USED);     /* "in place" up to the end */
        line(23, rc ? why[-rc] : "Finished.", color(0x1F, 0x0F));
        line(24, "Press a key.", color(0x1F, 0x07));
        _bios_keybrd(_KEYBRD_READ);
        screen_off();
    }
    if (d.bits)
        printf("%c: FAT%u, %lu clusters of %lu bytes, %lu used\n"
               "%lu files, %lu directories; fragmented: %lu before, %lu after\n"
               "%lu moves, %lu clusters moved\n", 'A' + drive, d.bits, (unsigned long)d.clusters,
               (unsigned long)d.cluster_size, (unsigned long)d.used, (unsigned long)d.files, (unsigned long)d.dirs,
               (unsigned long)d.fragmented, (unsigned long)d.fragmented_after, (unsigned long)d.moves,
               (unsigned long)d.moved);
    if (!rc) { printf(mode == OA_DEFRAG_ANALYZE ? "Analysis done.\n" : "Defragmentation done.\n"); return 0; }
    printf("Stopped: %s.\n", why[-rc]);
    if (rc == OA_DEFRAG_ESTOP) return 4;
    if (rc == OA_DEFRAG_EMEM || rc == OA_DEFRAG_EBAD) return 2;
    printf("Run ASPICHK %c: /F.\n", 'A' + drive);
    return 3;
}
