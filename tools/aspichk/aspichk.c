/* ASPICHK: checks a FAT12/16/32 drive and repairs it with /F.  Drives of
   ASPIDSK/ASPIFDD are read through their service (also when DOS has not
   mounted the medium), other drives through INT 21h 7305h or INT 25h/26h
   (drive.c).
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
#include "drive.h"

#define VERSION "0.1"
#define CHUNK 32768U                    /* bytes of one block of the cluster map */
#define MAXCHUNKS 14

static unsigned drive;                  /* 0 = A: */
static oa_u8 __far *chunks[MAXCHUNKS];
static unsigned nchunks;

static int rd(void *dev, oa_u32 lba, void __far *buf) { (void)dev; return drv_io(0, lba, 1, buf); }
static int wr(void *dev, oa_u32 lba, const void __far *buf) { (void)dev; return drv_io(1, lba, 1, (void __far *)buf); }

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
    union REGS r;
    oa_u32 need, total;
    int rc, fix = 0;
    printf("ASPICHK " VERSION " - FAT check and repair\n");
    if (argc == 3 && (!strcmp(argv[2], "/F") || !strcmp(argv[2], "/f"))) fix = 1;
    if (argc != 2 + fix || strlen(argv[1]) != 2 || argv[1][1] != ':' || !isalpha((unsigned char)argv[1][0])) {
        printf("ASPICHK d: [/F]   checks the FAT drive d:, /F repairs it\n");
        return 2;
    }
    drive = toupper((unsigned char)argv[1][0]) - 'A';
    memset(&c, 0, sizeof(c));
    switch (rc = drv_open(drive)) {
    case DRV_NOMEDIA: printf("%c: has no medium.\n", 'A' + drive); return 2;
    case DRV_EXFAT: printf("%c: is exFAT: use EXCHK.\n", 'A' + drive); return 2;
    case DRV_NOREAD: printf("%c: cannot be read (no FAT drive?).\n", 'A' + drive); return 2;
    case DRV_ASPI: printf("Checking %c: (ASPI unit %u, sector %lu)\n", 'A' + drive, drv_unit, (unsigned long)drv_start); break;
    default: printf("Checking %c:%s\n", 'A' + drive, rc == DRV_25 ? "" : " (FAT32 interface)");
    }
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
    drv_begin(fix);
    rc = oa_fatchk_run(&c);
    drv_end(fix);
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
