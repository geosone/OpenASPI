/* NTFS.SYS: NTFS volumes as DOS drives through the network redirector
   interface (INT 2Fh AH=11h), read-only.  The volumes are found on the BIOS
   hard disks (INT 13h), and so on the disks of ASPIDSK /I13 too:
   superfloppies, MBR partitions of type 07h (also logical ones) and GPT
   basic data partitions.  The NTFS part is openfat's src/ntfs/ntfs.c; the
   DOS side follows EXFAT.SYS (drivers/exfat/exfatsys.c), whose assembler
   frame it shares (exfatsys.asm with NTFS_SYS).  8.3 names: the DOS names
   Windows gave, else "~n" names as EXFAT.SYS makes them.  Compressed and
   encrypted files cannot be read (access denied).  NTFS keeps UTC: /Z:h
   (or /Z:-h, /Z:h:mm) gives the local time for DOS.

   Copyright (C) 2026 GeosOne.  GNU General Public License version 2 or later. */
#include <string.h>
#include <i86.h>
#include "openfat/ntfs.h"
#include "openaspi/exfatsys.h"
#include "openaspi/cptab.h"

#define VERSION "0.1"
#define MAXVOL 8
#define STACKSIZE 1024                  /* as in exfatsys.asm */

#pragma pack(1)
struct regs { oa_u16 es, ds, bp, di, si, dx, cx, bx, ax, sp, ss, flags; };
struct iregs { oa_u16 ax, bx, cx, dx, si, di, ds, es; };
struct dap { oa_u8 size, res; oa_u16 count; void __far *buf; oa_u32 lba, lba_hi; };
#pragma pack()

extern int __cdecl int13(struct iregs *);
extern int __cdecl int21(struct iregs *);
extern void __cdecl hook(void);
extern char bss_start[], resident_end[];

struct drive {
    struct oa_exfatsys_vol pub; /* as EXFAT.SYS's table (BIOS disks only) */
    struct ofat_ntfs v;
};

static struct drive drv[MAXVOL];
static unsigned ndrv;
/* "NTI1" in the device header: the volumes, as EXFAT.SYS's "EXI1" */
const struct { oa_u16 version; unsigned *count; struct drive *table; oa_u16 stride; }
    exfat_info = { 1, &ndrv, drv, sizeof(struct drive) };
static oa_u8 __far *sda;
static oa_u8 __far *nul_dev;          /* the DOS device chain */
static oa_u8 first_letter;
static const struct ofat_cp *cp;
static struct ofat_cp cptab;           /* the active one, copied at INIT */
static struct ofat_ntfs_ent ent;
typedef char ent_bounces[sizeof(struct ofat_ntfs_ent) >= 512 ? 1 : -1];
/* the buffers of all volumes: two MFT records, an index block, a sector */
static oa_u8 nbuf[OFAT_NTFS_MAXREC * 3 + 512];
static struct drive *buf_owner;
static oa_u8 __far *cds;

/* run cache of open files: the run last read */
static struct { struct drive *d; oa_u32 first, idx, clu, rlen; } walks[4];
static unsigned next_walk;

static struct ofat_ntfs_file pdir;      /* the directory of the last part of a path */

#define NONE 0xFFFFFFFFUL
#define DS_SEG() FP_SEG((void __far *)&ndrv)
#define W(p, o) (*(oa_u16 __far *)((p) + (o)))
#define D(p, o) (*(oa_u32 __far *)((p) + (o)))

/* DOS errors */
#define E_NOTFOUND 2
#define E_PATH     3
#define E_ACCESS   5
#define E_NOMORE   0x12
#define E_NOTREADY 0x15

/* SDA offsets, DOS 4 and later */
#define SDA_DTA    0x0C
#define SDA_FN1    0x9E
#define SDA_SDB    0x19E
#define SDA_SATTR  0x24D
#define SDA_ACTION 0x2DD
#define SDA_MODE   0x2E1

/* ---- BIOS disks ---- */

static int bios_read(void *dev, oa_u32 lba, void __far *buf)
{
    struct drive *d = dev;
    struct iregs r;
    struct dap p;
    unsigned tries;
    oa_u16 cx = 0, dx = d->pub.bios;
    oa_u32 t;
    if (!d->pub.ext) {
        t = lba / d->pub.spt;
        cx = (oa_u16)(lba - t * d->pub.spt + 1);
        dx |= (oa_u16)(t % d->pub.heads) << 8;
        t /= d->pub.heads;
        if (t > 1023) return -1;
        cx |= (oa_u16)((t & 0xFF) << 8 | (t >> 2 & 0xC0));
    }
    for (tries = 0; tries < 3; ++tries) {
        memset(&r, 0, sizeof(r));
        r.dx = dx;
        if (d->pub.ext) {
            p.size = 16; p.res = 0; p.count = 1; p.buf = buf; p.lba = lba; p.lba_hi = 0;
            r.ax = 0x4200; r.si = (oa_u16)&p; r.ds = DS_SEG();
            if (!int13(&r)) return 0;
        } else {
            r.ax = 0x0201; r.cx = cx;
            r.bx = FP_OFF(buf); r.es = FP_SEG(buf);
            if (!int13(&r)) return 0;
            /* DMA boundary: through ent, unused while file data goes to
               DOS's buffer (the own buffers are not moved) */
            if (r.ax >> 8 == 0x09 && FP_SEG(buf) != DS_SEG()) {
                r.ax = 0x0201; r.cx = cx; r.dx = dx; r.bx = (oa_u16)&ent; r.es = DS_SEG();
                if (!int13(&r)) { _fmemcpy(buf, &ent, 512); return 0; }
            }
        }
        memset(&r, 0, sizeof(r));
        r.dx = d->pub.bios;
        int13(&r);                              /* reset */
    }
    return -1;
}

static oa_u16 rd16(const oa_u8 *p) { return (oa_u16)(p[0] | p[1] << 8); }
static oa_u32 rd32(const oa_u8 *p) { return rd16(p) | (oa_u32)rd16(p+2) << 16; }

/* ---- the redirector ---- */

static struct drive *drive_of(oa_u8 letter)
{
    struct drive *d;
    for (d = drv; d < drv + ndrv; ++d) {
        if (d->pub.letter != letter) continue;
        if (buf_owner != d) {                   /* the buffers are shared */
            d->v.buf_lba = NONE;
            d->v.rec_no = d->v.rec2_no = d->v.idx_no = NONE;
            buf_owner = d;
        }
        return d;
    }
    return 0;
}

static struct drive *drive_of_path(const char __far *p)
{
    oa_u8 c = (oa_u8)p[0];
    if (c >= 'a' && c <= 'z') c -= 32;
    if (c < 'A' || c > 'Z' || p[1] != ':') return 0;
    return drive_of((oa_u8)(c - 'A'));
}

/* "NAME.EXT" (ending at '\' or 0) to FCB form, '*' as '?'s */
static const char __far *to_fcb(const char __far *p, char fcb[11])
{
    unsigned i = 0, max = 8;
    oa_u8 c;
    memset(fcb, ' ', 11);
    while ((c = (oa_u8)*p) != 0 && c != '\\') {
        ++p;
        if (c == '.' && max == 8 && i) { i = 8; max = 11; continue; }
        if (c >= 'a' && c <= 'z') c -= 32;
        if (c == '*') { while (i < max) fcb[i++] = '?'; continue; }
        if (i < max) fcb[i++] = (char)c;
    }
    return p;
}

/* The directory of a path and its last part; E_PATH when a directory
   on the way is missing. */
static int split_path(struct drive *d, const char __far *p, struct ofat_ntfs_file *dir, char fcb[11])
{
    ofat_ntfs_rootdir(&d->v, dir);
    p += 3;                                     /* "X:\" */
    memset(fcb, ' ', 11);
    while (*p) {
        p = to_fcb(p, fcb);
        if (!*p) return 0;
        ++p;
        if (ofat_ntfs_lookup(&d->v, dir, fcb, &ent) || !(ent.attr & OFAT_NTFS_DIR)) return E_PATH;
        *dir = ent.file;
        memset(fcb, ' ', 11);
    }
    return 0;
}

/* name (8 characters, blank padded) is a DOS character device: AUX, NUL, ... */
static int dev_name(const char *name)
{
    oa_u8 __far *dev;
    for (dev = nul_dev; dev && FP_OFF(dev) != 0xFFFF; dev = *(oa_u8 __far * __far *)dev)
        if ((W(dev, 4) & 0x8000) && !_fmemcmp(dev + 10, name, 8)) return 1;
    return 0;
}

static char last_fcb[11];

/* Finds a path: 0 and ent (last_fcb its 8.3 name, pdir its directory),
   -1 for the root directory, or a DOS error. */
static int find_path(struct drive *d, const char __far *p)
{
    char *fcb = last_fcb;
    int r = split_path(d, p, &pdir, fcb);
    if (r) return r;
    if (fcb[0] == ' ') return -1;
    if (dev_name(fcb)) return E_ACCESS;
    r = ofat_ntfs_lookup(&d->v, &pdir, fcb, &ent);
    if (r == OFAT_NTFS_END) return E_NOTFOUND;
    return r ? E_NOTREADY : 0;
}

static int error(struct regs *r, oa_u16 code)
{
    r->ax = code; r->flags |= 1;
    return 0;
}

static int ok(struct regs *r)
{
    r->flags &= ~1;
    return 0;
}

/* SFT: 7 initialized size, 0Bh flags (1 resident, 2 compressed, 4 cut at
   4 GB), 11h size, 1Bh MFT record */
static void fill_sft(oa_u8 __far *sft, struct drive *d)
{
    sft[4] = (oa_u8)ent.attr;
    W(sft, 5) = 0x8040 | d->pub.letter;
    D(sft, 7) = ent.file.valid;
    W(sft, 0x0B) = (oa_u16)(ent.file.nofat | ent.file.big << 2);
    W(sft, 0x0D) = ent.time; W(sft, 0x0F) = ent.date;
    D(sft, 0x11) = ent.file.size;
    D(sft, 0x15) = 0;
    W(sft, 0x19) = 0;
    D(sft, 0x1B) = ent.file.first;
    sft[0x1F] = 0;
    _fmemcpy(sft + 0x20, last_fcb, 11);
}

static void sft_file(struct drive *d, const oa_u8 __far *sft, struct ofat_ntfs_file *f)
{
    unsigned i;
    memset(f, 0, sizeof(*f));
    f->first = D(sft, 0x1B); f->size = D(sft, 0x11); f->valid = D(sft, 7);
    f->nofat = (oa_u8)(W(sft, 0x0B) & 3);
    for (i = 0; i < 4; ++i)
        if (walks[i].d == d && walks[i].first == f->first) {
            f->idx = walks[i].idx; f->clu = walks[i].clu; f->rlen = walks[i].rlen;
        }
}

static void sft_walk(struct drive *d, const struct ofat_ntfs_file *f)
{
    unsigned i;
    for (i = 0; i < 4 && (walks[i].d != d || walks[i].first != f->first); ++i) ;
    if (i == 4) { i = next_walk; next_walk = (next_walk + 1) & 3; }
    walks[i].d = d; walks[i].first = f->first;
    walks[i].idx = f->idx; walks[i].clu = f->clu; walks[i].rlen = f->rlen;
}

static int match(const char *name, const oa_u8 __far *tpl)
{
    unsigned i;
    for (i = 0; i < 11; ++i) if (tpl[i] != '?' && tpl[i] != (oa_u8)name[i]) return 0;
    return 1;
}

/* Search data block (21 bytes): drive|C0h, template, attribute, WORD 13
   and WORD 19 the position in the directory (low, high; high DOTS + n
   while "." and ".." of a subdirectory are given; both FFFFh: the end),
   DWORD 15 the MFT record of the directory. */
#define DOTS 0xFFF0
static int find(struct regs *r, struct drive *d, oa_u8 __far *sdb)
{
    struct ofat_ntfs_file dir;
    oa_u8 __far *fdb = *(oa_u8 __far * __far *)(sda + SDA_DTA) + 21;
    oa_u8 attr = sdb[12];
    oa_u16 hi = W(sdb, 19);
    oa_u32 pos;
    int rc;
    char name[11];
    ofat_ntfs_rootdir(&d->v, &dir);
    dir.first = D(sdb, 15);
    if (hi == 0xFFFF && W(sdb, 13) == 0xFFFF) return error(r, E_NOMORE);
    _fmemset(fdb, 0, 32);
    while (hi >= DOTS && hi < DOTS + 2) {
        memset(name, ' ', 11); name[0] = '.';
        if (hi++ != DOTS) name[1] = '.';
        W(sdb, 19) = hi;
        if ((attr & OFAT_NTFS_DIR) && match(name, sdb + 1)) {
            _fmemcpy(fdb, name, 11); fdb[11] = OFAT_NTFS_DIR;
            return ok(r);
        }
    }
    pos = hi >= DOTS ? 0 : (oa_u32)hi << 16 | W(sdb, 13);
    for (;;) {
        rc = ofat_ntfs_dir_next(&d->v, &dir, &pos, &ent);
        if (rc == OFAT_NTFS_END) break;
        if (rc) return error(r, E_NOTREADY);
        if ((ent.attr & ~attr) & (OFAT_NTFS_HIDDEN | OFAT_NTFS_SYSTEM | OFAT_NTFS_DIR)) continue;
        if (ofat_ntfs_short(&d->v, &dir, &ent, name)) return error(r, E_NOTREADY);
        if (!match(name, sdb + 1)) continue;
        _fmemcpy(fdb, name, 11);
        fdb[11] = (oa_u8)ent.attr;
        W(fdb, 22) = ent.time; W(fdb, 24) = ent.date;
        D(fdb, 28) = ent.file.size;
        W(sdb, 13) = (oa_u16)pos; W(sdb, 19) = (oa_u16)(pos >> 16);
        return ok(r);
    }
    W(sdb, 13) = W(sdb, 19) = 0xFFFF;
    return error(r, E_NOMORE);
}

static int find_first(struct regs *r, struct drive *d)
{
    struct ofat_ntfs_file dir;
    oa_u8 __far *sdb = sda + SDA_SDB;
    oa_u8 __far *fdb = *(oa_u8 __far * __far *)(sda + SDA_DTA) + 21;
    char fcb[11];
    unsigned i;
    oa_u8 c;
    if (split_path(d, (const char __far *)(sda + SDA_FN1), &dir, fcb)) return error(r, E_PATH);
    if (fcb[0] == ' ') memset(fcb, '?', 11);
    sdb[0] = (oa_u8)(d->pub.letter | 0xC0);
    _fmemcpy(sdb + 1, fcb, 11);
    sdb[12] = sda[SDA_SATTR];
    W(sdb, 13) = 0;
    W(sdb, 19) = dir.first == OFAT_NTFS_ROOT ? 0 : DOTS;
    D(sdb, 15) = dir.first;
    if (sdb[12] == 0x08) {                      /* the volume label */
        _fmemset(fdb, 0, 32);
        _fmemset(fdb, ' ', 11);
        for (i = 0; i < d->v.label_len && i < 11; ++i) {
            c = d->v.label[i] < 0x80 ? (oa_u8)d->v.label[i] : '_';
            fdb[i] = c >= 'a' && c <= 'z' ? (oa_u8)(c - 32) : c;
        }
        fdb[11] = 0x08;
        W(sdb, 13) = W(sdb, 19) = 0xFFFF;
        return d->v.label_len ? ok(r) : error(r, E_NOMORE);
    }
    return find(r, d, sdb);
}

static int disk_space(struct regs *r, struct drive *d)
{
    oa_u32 total = d->v.clusters, avail, bytes = 512UL << d->v.cshift;
    oa_u16 bps = 512;
    if (d->v.free == NONE && ofat_ntfs_free(&d->v, &avail)) return error(r, E_NOTREADY);
    avail = d->v.free;
    while (total > 0xFFFF) { total >>= 1; avail >>= 1; bytes <<= 1; }
    /* one sector per cluster where it fits: EDR-DOS's INT 21h AH=36h
       takes the sectors per cluster of a redirector drive as 1 (its
       redir_getdpb sets the cluster mask, not the shift func36 uses) */
    while (bytes / bps > 1 && bps < 0x8000) bps <<= 1;
    if (bytes / bps > 128) bytes = 128UL * bps;
    r->ax = (oa_u16)(bytes / bps) | 0xF8 << 8;
    r->bx = (oa_u16)total; r->cx = bps; r->dx = (oa_u16)avail;
    return ok(r);
}

static int do_open(struct regs *r, struct drive *d, oa_u16 mode)
{
    oa_u8 __far *sft = (oa_u8 __far *)MK_FP(r->es, r->di);
    int rc = find_path(d, (const char __far *)(sda + SDA_FN1));
    if (rc < 0 || (!rc && (ent.attr & OFAT_NTFS_DIR))) return error(r, E_ACCESS);
    if (rc) return error(r, (oa_u16)rc);
    if (mode & 3) return error(r, E_ACCESS);     /* read-only */
    fill_sft(sft, d);
    return ok(r);
}

/* The action of an extended open in CX, also in the caller's frame when
   it is 6C00h's (see exfatsys.c). */
static int action(struct regs *r, oa_u16 cx)
{
    oa_u16 __far *user;
    if (r->flags & 1) return 0;
    r->cx = cx;
    user = MK_FP(W(sda, 0x264 + 2), W(sda, 0x264));
    if (user[0] == 0x6C00) user[2] = cx;
    return 0;
}

static struct drive *sft_drive(const oa_u8 __far *sft)
{
    return W(sft, 5) & 0x8000 ? drive_of((oa_u8)(W(sft, 5) & 0x3F)) : 0;
}

int __cdecl redir(struct regs *r)
{
    oa_u8 fn = (oa_u8)r->ax;
    oa_u8 __far *sft = (oa_u8 __far *)MK_FP(r->es, r->di);
    const char __far *fn1 = (const char __far *)(sda + SDA_FN1);
    struct ofat_ntfs_file f;
    struct drive *d;
    oa_u16 done;
    oa_u32 pos;
    int rc;
    if (!sda) return 1;                         /* no drives yet */
    switch (fn) {
    case 0x00:                                  /* installation check */
        r->ax = 0x11FF;
        return 0;
    case 0x01: case 0x03: case 0x0E:            /* rmdir, mkdir, set attributes */
    case 0x11: case 0x13: case 0x17:            /* rename, delete, create */
        if (!(d = drive_of_path(fn1))) return 1;
        return error(r, E_ACCESS);
    case 0x05:                                  /* change directory */
        if (!(d = drive_of_path(fn1))) return 1;
        rc = find_path(d, fn1);
        if (rc > 0 || (!rc && !(ent.attr & OFAT_NTFS_DIR))) return error(r, E_PATH);
        return ok(r);
    case 0x06:                                  /* close */
        if (!(d = sft_drive(sft))) return 1;
        if (W(sft, 0)) --W(sft, 0);
        return ok(r);
    case 0x07: case 0x0A: case 0x0B:            /* commit, lock, unlock */
        if (!(d = sft_drive(sft))) return 1;
        return ok(r);
    case 0x08:                                  /* read */
        if (!(d = sft_drive(sft))) return 1;
        sft_file(d, sft, &f);
        pos = D(sft, 0x15);
        rc = ofat_ntfs_read(&d->v, &f, pos, *(void __far * __far *)(sda + SDA_DTA), r->cx, &done);
        sft_walk(d, &f);
        if (rc == OFAT_NTFS_ECOMP) return error(r, E_ACCESS);
        if (rc) return error(r, E_NOTREADY);
        D(sft, 0x15) = pos + done;
        r->cx = done;
        return ok(r);
    case 0x09:                                  /* write */
        if (!(d = sft_drive(sft))) return 1;
        return error(r, E_ACCESS);
    case 0x0C:                                  /* disk space */
        if (!(d = drive_of_path((const char __far *)sft))) return 1;
        return disk_space(r, d);
    case 0x0F:                                  /* attributes */
        if (!(d = drive_of_path(fn1))) return 1;
        rc = find_path(d, fn1);
        if (rc < 0) { r->ax = OFAT_NTFS_DIR; r->bx = r->di = r->cx = r->dx = 0; return ok(r); }
        if (rc) return error(r, (oa_u16)rc);
        r->ax = ent.attr; r->cx = ent.time; r->dx = ent.date;
        r->bx = (oa_u16)(ent.file.size >> 16); r->di = (oa_u16)ent.file.size;
        return ok(r);
    case 0x16:                                  /* open */
        if (!(d = drive_of_path(fn1))) return 1;
        return do_open(r, d, *(oa_u16 __far *)MK_FP(r->ss, r->sp + 6));
    case 0x1B:                                  /* find first */
        if (!(d = drive_of_path(fn1))) return 1;
        return find_first(r, d);
    case 0x1C:                                  /* find next */
        sft = sda + SDA_SDB;
        if (!(sft[0] & 0x80) || !(d = drive_of((oa_u8)(sft[0] & 0x3F)))) return 1;
        return find(r, d, sft);
    case 0x21:                                  /* seek from the end */
        if (!(d = sft_drive(sft))) return 1;
        pos = D(sft, 0x11) + ((oa_u32)r->cx << 16 | r->dx);
        D(sft, 0x15) = pos;
        r->dx = (oa_u16)(pos >> 16); r->ax = (oa_u16)pos;
        return ok(r);
    case 0x2E:                                  /* extended open/create */
        if (!(d = drive_of_path(fn1))) return 1;
        rc = find_path(d, fn1);
        if (rc == E_NOTFOUND) return error(r, (sda[SDA_ACTION] & 0x10) ? E_ACCESS : E_NOTFOUND);
        if (!rc && (sda[SDA_ACTION] & 0x0F) != 1) return error(r, E_ACCESS);
        do_open(r, d, sda[SDA_MODE]);
        return action(r, 1);
    }
    return 1;
}

/* EXFAT.SYS's frame calls it for ASPI units; NTFS.SYS has none. */
void __cdecl aspi_notify(unsigned unit, unsigned seg)
{
    (void)unit; (void)seg;
}

/* Called at the first program start: drive letters for the volumes. */
int __cdecl assign(void __far *unused)
{
    struct iregs q;
    oa_u8 __far *lol, __far *e;
    unsigned i, l, last;
    (void)unused;
    memset(&q, 0, sizeof(q));
    q.ax = 0x5D06;
    int21(&q);
    sda = (oa_u8 __far *)MK_FP(q.ds, q.si);
    memset(&q, 0, sizeof(q));
    q.ax = 0x5200;
    int21(&q);
    lol = (oa_u8 __far *)MK_FP(q.es, q.bx);
    cds = *(oa_u8 __far * __far *)(lol + 0x16);
    nul_dev = lol + 0x22;
    last = lol[0x21];
    if (!cds || FP_OFF(cds) == 0xFFFF) return 0;
    l = first_letter;
    for (i = 0; i < ndrv; ++i) {
        for (; l < last; ++l) if (!(W(cds + 0x58 * l, 0x43) & 0xC000)) break;
        if (l >= last) break;
        drv[i].pub.letter = (oa_u8)l;
        e = cds + 0x58 * l;
        _fmemset(e, 0, 0x58);
        e[0] = (oa_u8)('A' + l); e[1] = ':'; e[2] = '\\';
        W(e, 0x43) = 0xC080;
        W(e, 0x4F) = 2;
        ++l;
    }
    return 0;
}

/* ---- INIT: after the resident part, freed when INIT returns ---- */
#pragma code_seg("INIT_TEXT", "INIT")
#pragma data_seg("INIT_DATA", "INIT")
static char efi_part[] = "EFI PART", hexdig[] = "0123456789ABCDEF";
static char msg_hello[] = "NTFS " VERSION " - NTFS drives, read-only\r\n$";
static char msg_none[] = "No NTFS volumes - NTFS not installed\r\n$";
static char msg_bios[] = "  NTFS volume on BIOS disk $", msg_h[] = "h\r\n$";
static char msg_dirty[] = "h (not cleanly unmounted)\r\n$";
static char msg_size[] = "  NTFS volume not supported (sector or record size) on $";

static struct drive *probe_disk;
static oa_u8 sec[512];
static unsigned quiet_init;               /* /Q */
static oa_s16 tz;                         /* /Z: minutes */

static void print(const char *s)
{
    struct iregs q;
    memset(&q, 0, sizeof(q));
    q.ax = 0x0900; q.dx = (oa_u16)s; q.ds = DS_SEG();
    int21(&q);
}

static void print_hex(oa_u8 v)
{
    static char s[4] = "00$";
    s[0] = hexdig[v >> 4]; s[1] = hexdig[v & 15];
    print(s);
}

static int read_sec(oa_u32 lba) { return bios_read(probe_disk, lba, sec); }

static void add_volume(oa_u32 start)
{
    struct drive *d = &drv[ndrv];
    int rc;
    if (ndrv >= MAXVOL || read_sec(start) || !ofat_ntfs_probe(sec)) return;
    *d = *probe_disk;
    rc = ofat_ntfs_mount(&d->v, bios_read, d, start, cp, nbuf);
    if (rc == OFAT_NTFS_ESIZE && !quiet_init) { print(msg_size); print_hex(d->pub.bios); print(msg_h + 1); }
    if (rc) return;
    d->v.tz = tz;
    d->pub.letter = 0xFF; d->pub.start = start;
    ++ndrv;
}

static void scan_gpt(void)
{
    static const oa_u8 basic[16] = { 0xA2,0xA0,0xD0,0xEB,0xE5,0xB9,0x33,0x44,0x87,0xC0,0x68,0xB6,0xB7,0x26,0x99,0xC7 };
    oa_u32 lba, n, size, i, start[8];
    unsigned found = 0, k;
    if (read_sec(1) || memcmp(sec, efi_part, 8) || rd32(sec+76)) return;
    lba = rd32(sec+72); n = rd32(sec+80); size = rd32(sec+84);
    if (size < 128 || size > 512 || 512 % size || n > 256) return;
    for (i = 0; i < n && found < 8; ++i) {
        if (!(i % (512 / size)) && read_sec(lba + i / (512 / size))) return;
        k = (unsigned)(i % (512 / size) * size);
        if (!memcmp(sec + k, basic, 16) && !rd32(sec + k + 36)) start[found++] = rd32(sec + k + 32);
    }
    for (k = 0; k < found; ++k) add_volume(start[k]);
}

static void scan_disk(void)
{
    oa_u8 part[64], type;
    oa_u32 ext, ebr, start;
    unsigned i, n;
    if (read_sec(0)) return;
    if (ofat_ntfs_probe(sec)) { add_volume(0); return; }
    if (sec[510] != 0x55 || sec[511] != 0xAA) return;
    memcpy(part, sec + 446, 64);
    for (i = 0; i < 4; ++i) if (part[16*i+4] == 0xEE) { scan_gpt(); return; }
    for (i = 0; i < 4; ++i) if (part[16*i+4] == 0x07) add_volume(rd32(part + 16*i + 8));
    for (i = 0; i < 4; ++i) {
        type = part[16*i+4];
        if (type != 0x05 && type != 0x0F && type != 0x85) continue;
        ext = ebr = rd32(part + 16*i + 8);
        for (n = 0; n < 64; ++n) {
            if (read_sec(ebr) || sec[510] != 0x55 || sec[511] != 0xAA) break;
            type = sec[446+4+16]; start = rd32(sec+446+8+16);
            if (sec[446+4] == 0x07) add_volume(ebr + rd32(sec+446+8));
            if (type != 0x05 && type != 0x0F) break;
            ebr = ext + start;
        }
    }
}

int __cdecl drv_init(void __far *req)
{
    oa_u8 __far *rq = req;
    const char __far *p = *(const char __far * __far *)(rq + 18);
    struct iregs q;
    unsigned i, disks, chs = 0;
    struct drive probe;
    memset(bss_start, 0, resident_end - bss_start - STACKSIZE);
    /* the command line after the file name: /L:x, /Q, /C and /Z:h */
    while (*p && *p != ' ' && *p != '\r' && *p != '\n') ++p;
    for (; *p && *p != '\r' && *p != '\n'; ++p) {
        if (*p != '/') continue;
        if ((p[1] == 'L' || p[1] == 'l') && p[2] == ':' && (p[3] | 32) >= 'a' && (p[3] | 32) <= 'z')
            first_letter = (oa_u8)((p[3] | 32) - 'a');
        if (p[1] == 'Q' || p[1] == 'q') quiet_init = 1;
        if (p[1] == 'C' || p[1] == 'c') chs = 1;
        if ((p[1] == 'Z' || p[1] == 'z') && p[2] == ':') {   /* /Z:[-]h[:mm] */
            const char __far *z = p + 3;
            int neg = *z == '-', h = 0, m = 0;
            if (*z == '-' || *z == '+') ++z;
            while (*z >= '0' && *z <= '9') h = h * 10 + *z++ - '0';
            if (*z == ':') { ++z; while (*z >= '0' && *z <= '9') m = m * 10 + *z++ - '0'; }
            if (h <= 14 && m < 60) tz = (oa_s16)(neg ? -(h * 60 + m) : h * 60 + m);
        }
    }
    memset(&q, 0, sizeof(q));
    q.ax = 0x6601;
    cptab = !int21(&q) && q.bx == 850 ? ofat_cp850 : ofat_cp437;
    cp = &cptab;
    if (!quiet_init) print(msg_hello);
    disks = *(oa_u8 __far *)MK_FP(0x40, 0x75);
    for (i = 0; i < disks && i < 8; ++i) {
        memset(&probe, 0, sizeof(probe));
        probe.pub.bios = (oa_u8)(0x80 + i);
        memset(&q, 0, sizeof(q));
        q.ax = 0x4100; q.bx = 0x55AA; q.dx = probe.pub.bios;
        if (!chs && !int13(&q) && q.bx == 0xAA55 && (q.cx & 1)) probe.pub.ext = 1;
        memset(&q, 0, sizeof(q));
        q.ax = 0x0800; q.dx = probe.pub.bios;
        if (int13(&q)) continue;
        probe.pub.spt = q.cx & 63; probe.pub.heads = (q.dx >> 8) + 1;
        if (!probe.pub.spt) continue;
        probe_disk = &probe;
        scan_disk();
    }
    if (!ndrv) {
        if (!quiet_init) print(msg_none);
        W(rq, 14) = 0; W(rq, 16) = DS_SEG();
        W(rq, 3) = 0x0100;
        return 0;
    }
    if (!quiet_init)
        for (i = 0; i < ndrv; ++i) {
            print(msg_bios);
            print_hex(drv[i].pub.bios);
            print(drv[i].v.dirty ? msg_dirty : msg_h);
        }
    buf_owner = 0;
    hook();
    W(rq, 14) = (oa_u16)resident_end;
    W(rq, 16) = DS_SEG();
    W(rq, 3) = 0x0100;
    return 0;
}
