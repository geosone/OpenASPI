/* NTFS.SYS: NTFS volumes as DOS drives through the network redirector
   interface (INT 2Fh AH=11h), read-only.  The volumes are found on the BIOS
   hard disks (INT 13h), and so on the disks of ASPIDSK /I13 too:
   superfloppies, MBR partitions of type 07h (also logical ones) and GPT
   basic data partitions.  The NTFS part is OpenFileSystem's src/ntfs/ntfs.c; the
   DOS side follows EXFAT.SYS (drivers/exfat/exfatsys.c), whose assembler
   frame it shares (exfatsys.asm with NTFS_SYS).  8.3 names: the DOS names
   Windows gave, else "~n" names as EXFAT.SYS makes them.  Compressed files
   are read (LZNT1); encrypted ones cannot be (access denied).  NTFS keeps UTC: /Z:h
   (or /Z:-h, /Z:h:mm) gives the local time for DOS.

   Copyright (C) 2026 GeosOne.  GNU General Public License version 2 or later. */
#include <string.h>
#include <i86.h>
#include "ofs/ntfs.h"
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
extern oa_u8 __far * __far *lol_cds;   /* exfatsys.asm: LoL+16h, and the */
extern oa_u8 __far *cds_seen;          /* CDS the letters were put in */
extern int __cdecl int21(struct iregs *);
extern void __cdecl hook(void);
extern char bss_start[], resident_end[];

struct drive {
    struct oa_exfatsys_vol pub; /* as EXFAT.SYS's table (BIOS disks only) */
    struct ofs_ntfs v;
};

static struct drive drv[MAXVOL];
static unsigned ndrv;
/* "NTI1" in the device header: the volumes, as EXFAT.SYS's "EXI1" */
const struct { oa_u16 version; unsigned *count; struct drive *table; oa_u16 stride; }
    exfat_info = { 1, &ndrv, drv, sizeof(struct drive) };
static oa_u8 __far *sda;
static oa_u8 __far *nul_dev;          /* the DOS device chain */
#ifdef NTFS_LFN
static oa_u8 __far *sft_list;         /* the first SFT block, for 71A6h */
#endif
static oa_u8 first_letter;
static const struct ofs_cp *cp;
static struct ofs_cp cptab;           /* the active one, copied at INIT */
static struct ofs_ntfs_ent ent;
typedef char ent_bounces[sizeof(struct ofs_ntfs_ent) >= 512 ? 1 : -1];
/* the buffers of all volumes: two MFT records, an index block, a sector */
static oa_u8 nbuf[OFS_NTFS_BUF];
static struct drive *buf_owner;
static oa_u8 __far *cds;

/* run cache of open files: the run last read */
static struct { struct drive *d; oa_u32 first, idx, clu, rlen; } walks[4];
static unsigned next_walk;

static struct ofs_ntfs_file pdir;      /* the directory of the last part of a path */

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
static int split_path(struct drive *d, const char __far *p, struct ofs_ntfs_file *dir, char fcb[11])
{
    ofs_ntfs_rootdir(&d->v, dir);
    p += 3;                                     /* "X:\" */
    memset(fcb, ' ', 11);
    while (*p) {
        p = to_fcb(p, fcb);
        if (!*p) return 0;
        ++p;
        if (ofs_ntfs_lookup(&d->v, dir, fcb, &ent) || !(ent.attr & OFS_NTFS_DIR)) return E_PATH;
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
    r = ofs_ntfs_lookup(&d->v, &pdir, fcb, &ent);
    if (r == OFS_NTFS_END) return E_NOTFOUND;
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

/* SFT: 7 initialized size, 0Bh flags (bits 0-1: 1 resident, 2 encrypted,
   3 compressed; 4 cut at 4 GB), 11h size, 1Bh MFT record */
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

static void sft_file(struct drive *d, const oa_u8 __far *sft, struct ofs_ntfs_file *f)
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

static void sft_walk(struct drive *d, const struct ofs_ntfs_file *f)
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
    struct ofs_ntfs_file dir;
    oa_u8 __far *fdb = *(oa_u8 __far * __far *)(sda + SDA_DTA) + 21;
    oa_u8 attr = sdb[12];
    oa_u16 hi = W(sdb, 19);
    oa_u32 pos;
    int rc;
    char name[11];
    ofs_ntfs_rootdir(&d->v, &dir);
    dir.first = D(sdb, 15);
    if (hi == 0xFFFF && W(sdb, 13) == 0xFFFF) return error(r, E_NOMORE);
    _fmemset(fdb, 0, 32);
    while (hi >= DOTS && hi < DOTS + 2) {
        memset(name, ' ', 11); name[0] = '.';
        if (hi++ != DOTS) name[1] = '.';
        W(sdb, 19) = hi;
        if ((attr & OFS_NTFS_DIR) && match(name, sdb + 1)) {
            _fmemcpy(fdb, name, 11); fdb[11] = OFS_NTFS_DIR;
            return ok(r);
        }
    }
    pos = hi >= DOTS ? 0 : (oa_u32)hi << 16 | W(sdb, 13);
    for (;;) {
        rc = ofs_ntfs_dir_next(&d->v, &dir, &pos, &ent);
        if (rc == OFS_NTFS_END) break;
        if (rc) return error(r, E_NOTREADY);
        if ((ent.attr & ~attr) & (OFS_NTFS_HIDDEN | OFS_NTFS_SYSTEM | OFS_NTFS_DIR)) continue;
        if (ofs_ntfs_short(&d->v, &dir, &ent, name)) return error(r, E_NOTREADY);
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
    struct ofs_ntfs_file dir;
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
    W(sdb, 19) = dir.first == OFS_NTFS_ROOT ? 0 : DOTS;
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
    if (d->v.free == NONE && ofs_ntfs_free(&d->v, &avail)) return error(r, E_NOTREADY);
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
    if (rc < 0 || (!rc && (ent.attr & OFS_NTFS_DIR))) return error(r, E_ACCESS);
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
    struct ofs_ntfs_file f;
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
        if (rc > 0 || (!rc && !(ent.attr & OFS_NTFS_DIR))) return error(r, E_PATH);
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
        rc = ofs_ntfs_read(&d->v, &f, pos, *(void __far * __far *)(sda + SDA_DTA), r->cx, &done);
        sft_walk(d, &f);
        if (rc == OFS_NTFS_ECOMP) return error(r, E_ACCESS);
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
        if (rc < 0) { r->ax = OFS_NTFS_DIR; r->bx = r->di = r->cx = r->dx = 0; return ok(r); }
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

#ifdef NTFS_LFN
/* ---- long file names: INT 21h AX=71xxh for the own drives (NTFSL.SYS,
   installed as NTFS.SYS when the long names are chosen) ----
   As EXFATL.SYS (exfatsys.c), read-only: find, open, change directory,
   current directory, attributes and times, TRUENAME, volume information,
   file information by handle.  Paths may use the long names and the 8.3
   names of NTFS.SYS.  The calls that would write (make and remove
   directory, delete, rename, set attributes or times, create) give
   "access denied" for our drives.  Other drives go on to the next
   handler. */
#define LFN_MAX 260
#define NFIND 6
#define PATMAX 80
#define E_FUNC     1
#define E_DIFFDEV  0x11

struct lfind {
    struct drive *d;            /* 0: free */
    oa_u16 handle;
    struct ofs_ntfs_file dir;
    oa_u32 pos;
    oa_u8 dots;                 /* "." and ".." of a subdirectory given */
    oa_u8 allow, need, dosdate;
    oa_u16 used;                /* for reuse: a program may end without 71A1h */
    char pat[PATMAX];
};
static struct lfind finds[NFIND];
static oa_u16 find_clock;
static char lpath[LFN_MAX + 2];         /* the path made absolute: "X:\..." */
static char spath[LFN_MAX + 2];         /* the parts found, 8.3 */
static char lout[LFN_MAX + 2];          /* the parts found, long */
static char lname[256], sname[13], comp[256];
static char drv_name[3] = "?:";
static oa_u16 unconv;                   /* bit 0: a long name lacks characters */

static oa_u8 up(oa_u8 c)
{
    if (c >= 'a' && c <= 'z') return (oa_u8)(c - 32);
    return c >= 0x80 ? cp->upper[c - 0x80] : c;
}

/* the long name of ent in the code page */
static void ent_name(void)
{
    unsigned i, j;
    oa_u16 u;
    oa_u8 c;
    for (i = 0; i < ent.name_len; ++i) {
        u = ent.name[i];
        c = u < 0x80 ? (oa_u8)u : 0;
        for (j = 0; !c && j < 128; ++j) if (cp->uni[j] == u) c = (oa_u8)(0x80 + j);
        if (!c) { c = '_'; unconv |= 1; }
        lname[i] = (char)c;
    }
    lname[i] = 0;
}

static void fcb_name(const char *fcb, char *out)
{
    unsigned i;
    for (i = 0; i < 8 && fcb[i] != ' '; ++i) *out++ = fcb[i];
    if (fcb[8] != ' ') {
        *out++ = '.';
        for (i = 8; i < 11 && fcb[i] != ' '; ++i) *out++ = fcb[i];
    }
    *out = 0;
}

static int same(const char *a, const char *b)
{
    while (*a && up(*a) == up(*b)) ++a, ++b;
    return !*a && !*b;
}

/* p with '*' and '?' against s; "x.*" also matches "x" */
static int glob(const char *p, const char *s)
{
    const char *bp = 0, *bs = 0;
    while (*s) {
        if (*p == '*') { bp = ++p; bs = s; continue; }
        if (*p && (*p == '?' || up(*p) == up(*s))) { ++p; ++s; continue; }
        if (!bp) return 0;
        p = bp; s = ++bs;
    }
    while (*p == '*') ++p;
    if (p[0] == '.' && p[1] == '*') for (p += 2; *p == '*'; ++p) ;
    return !*p;
}

static int is_sep(char c) { return c == '\\' || c == '/'; }

static int device;                      /* full_path: the path is a device on one of our drives */

/* the last part of lpath names a DOS device (AUX, NUL, ...): DOS's */
static int is_device(void)
{
    const char *p = strrchr(lpath, '\\') + 1;
    char name[8];
    unsigned i;
    memset(name, ' ', 8);
    for (i = 0; p[i] && p[i] != '.' && i < 8; ++i) name[i] = (char)up((oa_u8)p[i]);
    if (p[i] && p[i] != '.') return 0;
    return dev_name(name);
}

/* p made absolute in lpath ("." and ".." resolved); its drive if ours */
static struct drive *full_path(const char __far *p)
{
    struct iregs q;
    oa_u8 __far *e;
    char *o;
    unsigned n;
    oa_u8 letter;
    device = 0;
    if (!sda) return 0;
    if (p[0] && p[1] == ':') { letter = (oa_u8)(up((oa_u8)p[0]) - 'A'); p += 2; }
    else {
        memset(&q, 0, sizeof(q));
        q.ax = 0x1900;
        int21(&q);
        letter = (oa_u8)q.ax;
    }
    if (letter >= 26) return 0;
    for (n = 0; n < ndrv && drv[n].pub.letter != letter; ++n) ;
    if (n == ndrv) return 0;                    /* quick: not one of ours */
    lpath[0] = (char)('A' + letter); lpath[1] = ':'; lpath[2] = 0;
    o = lpath + 2;
    if (!is_sep(*p)) {                          /* from the current directory */
        e = cds + 0x58 * letter;
        if (e[0] == lpath[0] && e[1] == ':')
            for (n = 2; e[n] && n < 67; ++n) *o++ = (char)e[n];
        while (o > lpath + 2 && o[-1] == '\\') --o;
    }
    for (;;) {
        while (is_sep(*p)) ++p;
        if (!*p) break;
        for (n = 0; p[n] && !is_sep(p[n]); ++n) ;
        if (n == 1 && p[0] == '.') ;
        else if (n == 2 && p[0] == '.' && p[1] == '.') { while (o > lpath + 2 && *--o != '\\') ; }
        else {
            if (o - lpath + n + 1 > LFN_MAX) return 0;
            *o++ = '\\';
            _fmemcpy(o, p, n); o += n;
        }
        p += n;
    }
    if (o == lpath + 2) *o++ = '\\';
    *o = 0;
    if (!drive_of(letter)) return 0;
    if (is_device()) { device = 1; return 0; }
    return drive_of(letter);
}

/* ent: the entry of comp in dir (long name, or 8.3 name); the names
   first without their MFT records, which only the one found is read for */
static int find_comp(struct drive *d, struct ofs_ntfs_file *dir)
{
    char fcb[11];
    oa_u32 pos = 0;
    unsigned n = strlen(comp);
    int rc;
    for (;;) {
        rc = ofs_ntfs_dir_name(&d->v, dir, &pos, &ent);
        if (rc == OFS_NTFS_END) break;
        if (rc) return E_NOTREADY;
        ent_name();
        if (same(comp, lname)) return ofs_ntfs_stat(&d->v, &ent) ? E_NOTREADY : 0;
    }
    if (n > 12 || strchr(comp, ' ') || strchr(comp, '*') || strchr(comp, '?')) return E_NOTFOUND;
    to_fcb((const char __far *)comp, fcb);
    rc = ofs_ntfs_lookup(&d->v, dir, fcb, &ent);
    return rc == OFS_NTFS_END ? E_NOTFOUND : rc ? E_NOTREADY : 0;
}

/* lpath on d: spath and lout of the parts found, the last in ent and
   lname/sname.  0, -1 the root, E_NOTFOUND (the last part is missing;
   dir is its directory), E_PATH, E_NOTREADY. */
static int resolve(struct drive *d, struct ofs_ntfs_file *dir)
{
    char *p = lpath + 3, *q, *s = spath + 3, *l = lout + 3, fcb[11];
    unsigned n;
    int rc;
    memcpy(spath, lpath, 3); memcpy(lout, lpath, 3);
    *s = *l = 0;
    ofs_ntfs_rootdir(&d->v, dir);
    if (!*p) return -1;
    for (;;) {
        for (q = p; *q && *q != '\\'; ++q) ;
        n = (unsigned)(q - p);
        if (n > 255) return E_PATH;
        memcpy(comp, p, n); comp[n] = 0;
        if ((rc = find_comp(d, dir)) != 0) return *q ? (rc == E_NOTFOUND ? E_PATH : rc) : rc;
        ent_name();
        if (ofs_ntfs_short(&d->v, dir, &ent, fcb)) return E_NOTREADY;
        fcb_name(fcb, sname);
        if (s > spath + 3) *s++ = '\\';
        if (l > lout + 3) *l++ = '\\';
        strcpy(s, sname); s += strlen(sname);
        if (l - lout + strlen(lname) > LFN_MAX) return E_PATH;
        strcpy(l, lname); l += strlen(lname);
        if (!*q) return 0;
        if (!(ent.attr & OFS_NTFS_DIR)) return E_PATH;
        *dir = ent.file;
        p = q + 1;
    }
}

/* ---- the find data (WIN32_FIND_DATA) ---- */

/* v = v * m + a, v of four 16-bit words, lowest first */
static void mul_add(oa_u16 *v, oa_u16 m, oa_u16 a)
{
    unsigned i;
    oa_u32 x, carry = a;
    for (i = 0; i < 4; ++i) { x = (oa_u32)v[i] * m + carry; v[i] = (oa_u16)x; carry = x >> 16; }
}

/* v = v / d, the remainder returned */
static oa_u16 div16(oa_u16 *v, oa_u16 d)
{
    unsigned i = 4;
    oa_u32 x, rem = 0;
    while (i--) { x = rem << 16 | v[i]; v[i] = (oa_u16)(x / d); rem = x % d; }
    return (oa_u16)rem;
}

static const oa_u16 before[12] = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 };
static int leap(oa_u32 y) { return !(y & 3) && (y % 100 || !(y % 400)); }

/* FILETIME to DOS date and time (CX, DX) and 10 ms (BH), for 71A7h */
static void dos_time(const oa_u8 __far *p, struct regs *r)
{
    oa_u16 v[4], ms;
    oa_u32 days, y = 1601, n, mon;
    _fmemcpy(v, p, 8);
    div16(v, 10000);                            /* milliseconds */
    ms = div16(v, 1000);                        /* seconds */
    n = div16(v, 400);
    n += (oa_u32)div16(v, 216) * 400;           /* seconds of the day, v the days */
    days = v[0] | (oa_u32)v[1] << 16;
    for (; days >= (oa_u32)(365 + leap(y)); ++y) days -= 365 + leap(y);
    for (mon = 12; mon > 1 && days < before[mon - 1] + (mon > 2 && leap(y)); --mon) ;
    days -= before[mon - 1] + (mon > 2 && leap(y));
    if (y < 1980) { y = 1980; mon = 1; days = 0; n = 0; }
    r->cx = (oa_u16)((n / 3600) << 11 | (n / 60 % 60) << 5 | (n % 60) / 2);
    r->dx = (oa_u16)((y - 1980) << 9 | mon << 5 | (days + 1));
    r->bx = (r->bx & 0xFF) | (oa_u16)(((n & 1) * 100 + ms / 10) << 8);
}

/* the DOS date and time as FILETIME (100 ns from 1601) or DOS (dosdate);
   cs10: 10 ms units to add */
static void put_time(oa_u8 __far *p, oa_u16 time, oa_u16 date, int dosdate, oa_u16 cs10)
{
    oa_u16 v[4];
    oa_u32 days, y = 1980 + (date >> 9) - 1601, mon = (date >> 5) & 15, secs;
    if (dosdate) { W(p, 0) = time; W(p, 2) = date; D(p, 4) = 0; return; }
    if (mon < 1 || mon > 12) mon = 1;
    days = y * 365 + y / 4 - y / 100 + y / 400 + before[mon - 1] + (date & 31) - 1;
    y += 1601;
    if (mon > 2 && leap(y)) ++days;
    secs = (oa_u32)(time >> 11) * 3600 + ((time >> 5) & 63) * 60 + (time & 31) * 2;
    v[0] = (oa_u16)days; v[1] = (oa_u16)(days >> 16); v[2] = v[3] = 0;
    mul_add(v, 400, 0); mul_add(v, 216, (oa_u16)secs);     /* * 86400 + seconds */
    if (secs >> 16) { v[2] += (v[1] += (oa_u16)(secs >> 16)) < (oa_u16)(secs >> 16); }
    mul_add(v, 100, cs10);
    mul_add(v, 1000, 0); mul_add(v, 100, 0);    /* 10 ms to 100 ns */
    _fmemcpy(p, v, 8);
}

/* ent (or "." / ".." when dots) into the find data at fd */
static void fill_find(oa_u8 __far *fd, int dosdate)
{
    unsigned i;
    _fmemset(fd, 0, 318);
    D(fd, 0) = ent.attr;
    for (i = 4; i <= 20; i += 8) put_time(fd + i, ent.time, ent.date, dosdate, 0);
    D(fd, 28) = ent.file.big ? 1 : 0;
    D(fd, 32) = ent.file.size;
    _fmemcpy(fd + 44, lname, strlen(lname) + 1);
    if (strcmp(lname, sname)) _fmemcpy(fd + 304, sname, strlen(sname) + 1);
}

/* the next match of a search, 0 or a DOS error */
static int find_next(struct lfind *f, oa_u8 __far *fd)
{
    char fcb[11];
    int rc;
    while (f->dots < 2) {
        memset(&ent, 0, sizeof(ent));
        ent.attr = OFS_NTFS_DIR;
        strcpy(lname, f->dots++ ? ".." : ".");
        strcpy(sname, lname);
        if ((f->allow & OFS_NTFS_DIR) && !(f->need & ~OFS_NTFS_DIR) && glob(f->pat, lname)) {
            fill_find(fd, f->dosdate);
            return 0;
        }
    }
    for (;;) {
        rc = ofs_ntfs_dir_next(&f->d->v, &f->dir, &f->pos, &ent);
        if (rc == OFS_NTFS_END) return E_NOMORE;
        if (rc) return E_NOTREADY;
        if ((ent.attr & ~f->allow) & (OFS_NTFS_HIDDEN | OFS_NTFS_SYSTEM | OFS_NTFS_DIR)) continue;
        if ((ent.attr & f->need) != f->need) continue;
        ent_name();
        if (ofs_ntfs_short(&f->d->v, &f->dir, &ent, fcb)) return E_NOTREADY;
        fcb_name(fcb, sname);
        if (glob(f->pat, lname) || glob(f->pat, sname)) {
            fill_find(fd, f->dosdate);
            return 0;
        }
    }
}

/* a handle number the provider above (DOSLFN) does not take for one of its
   own: it looks for the byte ACh or ADh at that offset of its segment */
static oa_u16 new_handle(unsigned i)
{
    oa_u16 seg = *(oa_u16 __far *)MK_FP(0, 0x86), h = 0;
    unsigned k;
    oa_u8 b;
    for (k = 0; k < 16; ++k) {
        h = (oa_u16)(0xF001 + (k << 8) + i * 2);
        b = *(oa_u8 __far *)MK_FP(seg, h);
        if (seg == DS_SEG() || (b != 0xAC && b != 0xAD)) break;
    }
    return h;
}

static struct lfind *find_handle(oa_u16 h)
{
    unsigned i;
    for (i = 0; i < NFIND; ++i) if (finds[i].d && finds[i].handle == h) return &finds[i];
    return 0;
}

static int lfn_find_first(struct regs *r, struct drive *d)
{
    struct lfind *f;
    char *last;
    unsigned i, n;
    int rc;
    for (i = 0; i < NFIND && finds[i].d; ++i) ;
    if (i == NFIND)                             /* all taken: the least used */
        for (i = 0, n = 1; n < NFIND; ++n)
            if ((oa_u16)(finds[n].used - finds[i].used) & 0x8000) i = n;
    f = &finds[i];
    f->used = ++find_clock;
    last = strrchr(lpath, '\\');
    if (!last[1]) return error(r, E_NOTFOUND);
    if (strlen(last + 1) >= PATMAX) return error(r, E_PATH);
    strcpy(f->pat, last + 1);
    if (!strcmp(f->pat, "*.*")) f->pat[1] = 0;
    if (last == lpath + 2) last[1] = 0; else *last = 0;
    rc = resolve(d, &f->dir);
    if (rc > 0) return error(r, rc == E_NOTFOUND ? E_PATH : (oa_u16)rc);
    if (!rc) {
        if (!(ent.attr & OFS_NTFS_DIR)) return error(r, E_PATH);
        f->dir = ent.file;
    }
    f->dots = (oa_u8)(rc < 0 ? 2 : 0);
    f->pos = 0;
    f->allow = (oa_u8)r->cx; f->need = (oa_u8)(r->cx >> 8); f->dosdate = (oa_u8)(r->si & 1);
    unconv = 0;
    f->d = d;
    if ((rc = find_next(f, (oa_u8 __far *)MK_FP(r->es, r->di))) != 0) { f->d = 0; return error(r, (oa_u16)rc); }
    f->handle = new_handle(i);
    r->ax = f->handle; r->cx = unconv;
    return ok(r);
}

/* the SFT of handle h of the current program, 0 if closed */
static oa_u8 __far *handle_sft(oa_u16 h)
{
    oa_u8 __far *psp = (oa_u8 __far *)MK_FP(W(sda, 0x10), 0), __far *blk;
    oa_u8 n;
    if (!sft_list || h >= W(psp, 0x32)) return 0;
    n = (*(oa_u8 __far * __far *)(psp + 0x34))[h];
    if (n == 0xFF) return 0;
    for (blk = sft_list; FP_OFF(blk) != 0xFFFF; blk = *(oa_u8 __far * __far *)blk) {
        if (n < W(blk, 4)) return blk + 6 + n * 0x3B;
        n = (oa_u8)(n - W(blk, 4));
    }
    return 0;
}

/* 71A6h: BY_HANDLE_FILE_INFORMATION of a file of ours at DS:DX */
static int lfn_handle_info(struct regs *r)
{
    oa_u8 __far *sft = handle_sft(r->bx), __far *out;
    struct drive *d;
    unsigned i;
    if (!sft || !(d = sft_drive(sft))) return 1;
    out = (oa_u8 __far *)MK_FP(r->ds, r->dx);
    _fmemset(out, 0, 52);
    D(out, 0) = sft[4];
    for (i = 4; i <= 0x14; i += 8) put_time(out + i, W(sft, 0x0D), W(sft, 0x0F), 0, 0);
    D(out, 0x1C) = d->v.serial;
    D(out, 0x24) = D(sft, 0x11);
    D(out, 0x28) = 1;                           /* links */
    D(out, 0x30) = D(sft, 0x1B);                /* the MFT record as the index */
    return ok(r);
}

/* a DOS call with a path of our own (spath) in DS:DX */
static int dos_path(struct regs *r, oa_u16 ax)
{
    struct iregs q;
    memset(&q, 0, sizeof(q));
    q.ax = ax; q.bx = r->bx; q.cx = r->cx; q.dx = FP_OFF((void __far *)spath); q.si = q.dx; q.di = r->di;
    q.ds = q.es = DS_SEG();
    if (ax == 0x6C00) q.dx = r->dx;
    if (int21(&q)) return error(r, q.ax);
    r->ax = q.ax;
    if (ax == 0x6C00) r->cx = q.cx;             /* the action */
    return ok(r);
}

/* a device on our drive: the old call with the caller's registers (the
   caller does not fall back to it, as the drive has long names) */
static int dos_device(struct regs *r, oa_u16 ax)
{
    struct iregs q;
    q.ax = ax; q.bx = r->bx; q.cx = r->cx; q.dx = r->dx; q.si = r->si; q.di = r->di;
    q.ds = r->ds; q.es = r->es;
    if (int21(&q)) return error(r, q.ax);
    r->ax = q.ax; r->cx = q.cx;
    return ok(r);
}

static int lfn_call(struct regs *r);

/* An error of ours must also be DOS's last error (SDA 3: locus, 4: code,
   6: action, 7: class): COMMAND.COM of MS-DOS 7 asks AH=59h for it. */
int __cdecl lfn(struct regs *r)
{
    int rc = lfn_call(r);
    if (!rc && (r->flags & 1) && r->ax != 0x7100) {
        W(sda, 4) = r->ax;
        sda[3] = 2;                             /* block device */
        sda[6] = 4;                             /* abort with cleanup */
        sda[7] = r->ax == E_NOTFOUND || r->ax == E_PATH ? 8 : r->ax == E_ACCESS ? 3 : 13;
    }
    return rc;
}

static int lfn_call(struct regs *r)
{
    struct ofs_ntfs_file dir;
    struct lfind *f;
    struct drive *d;
    const char __far *dx = (const char __far *)MK_FP(r->ds, r->dx);
    const char __far *si = (const char __far *)MK_FP(r->ds, r->si);
    char __far *out;
    oa_u8 fn = (oa_u8)r->ax;
    int rc;
    unsigned n;
    switch (fn) {
    case 0xA7:                                  /* time conversion, for any drive */
        if (!(oa_u8)r->bx) { dos_time(si, r); return ok(r); }
        if ((oa_u8)r->bx != 1) return 1;
        put_time((oa_u8 __far *)MK_FP(r->es, r->di), r->cx, r->dx, 0, r->bx >> 8);
        return ok(r);
    case 0x39: case 0x3A: case 0x41:            /* make, remove directory, delete */
        if (!full_path(dx)) return 1;
        return error(r, E_ACCESS);
    case 0x56:                                  /* rename */
        if (!full_path(dx)) return full_path((const char __far *)MK_FP(r->es, r->di)) ? error(r, E_DIFFDEV) : 1;
        return error(r, E_ACCESS);
    case 0x3B:                                  /* change directory */
        if (!(d = full_path(dx))) return 1;
        rc = resolve(d, &dir);
        if (rc > 0 || (!rc && !(ent.attr & OFS_NTFS_DIR))) return error(r, E_PATH);
        return dos_path(r, 0x3B00);
    case 0x43:                                  /* attributes and times */
        if (!(d = full_path(dx))) return device && !(oa_u8)r->bx ? dos_device(r, 0x4300) : 1;
        rc = resolve(d, &dir);
        if (rc > 0) return error(r, (oa_u16)rc);
        if (rc < 0) { memset(&ent, 0, sizeof(ent)); ent.attr = OFS_NTFS_DIR; }
        switch ((oa_u8)r->bx) {
        case 0: r->cx = ent.attr; break;
        case 4: r->cx = ent.time; r->di = ent.date; break;
        case 2: r->ax = (oa_u16)ent.file.size; r->dx = (oa_u16)(ent.file.size >> 16); break;
        case 6: r->di = ent.date; break;
        case 8: r->cx = ent.time; r->di = ent.date; r->si = 0; break;
        case 1: case 3: case 5: case 7: return error(r, E_ACCESS);
        default: return error(r, E_FUNC);
        }
        return ok(r);
    case 0x47:                                  /* current directory */
        drv_name[0] = (char)((oa_u8)r->dx ? '@' + (oa_u8)r->dx : 0);
        if (!(d = full_path(drv_name))) return 1;
        rc = resolve(d, &dir);
        out = (char __far *)MK_FP(r->ds, r->si);
        if (rc > 0) _fmemcpy(out, lpath + 3, strlen(lpath + 3) + 1);
        else _fmemcpy(out, lout + 3, strlen(lout + 3) + 1);
        return ok(r);
    case 0x4E:                                  /* find first */
        if (!(d = full_path(dx))) return 1;
        return lfn_find_first(r, d);
    case 0x4F:                                  /* find next */
        if (!(f = find_handle(r->bx))) return 1;
        if (!drive_of(f->d->pub.letter)) { f->d = 0; return error(r, E_NOTREADY); }
        unconv = 0;
        f->used = ++find_clock;
        if ((rc = find_next(f, (oa_u8 __far *)MK_FP(r->es, r->di))) != 0) return error(r, (oa_u16)rc);
        r->cx = unconv;
        return ok(r);
    case 0xA1:                                  /* find close */
        if (!(f = find_handle(r->bx))) return 1;
        f->d = 0;
        return ok(r);
    case 0x60:                                  /* TRUENAME: 0 as given, 1 short, 2 long */
        if (!(d = full_path(si))) return device ? dos_device(r, 0x6000) : 1;
        out = (char __far *)MK_FP(r->es, r->di);
        if (!((oa_u8)r->cx & 3)) { _fmemcpy(out, lpath, strlen(lpath) + 1); return ok(r); }
        rc = resolve(d, &dir);
        if (rc > 0) return error(r, (oa_u16)rc);
        if (((oa_u8)r->cx & 3) == 1) _fmemcpy(out, spath, strlen(spath) + 1);
        else _fmemcpy(out, lout, strlen(lout) + 1);
        return ok(r);
    case 0x6C:                                  /* extended open/create */
        if (!(d = full_path(si))) return device ? dos_device(r, 0x6C00) : 1;
        rc = resolve(d, &dir);
        if (rc == E_NOTFOUND) return error(r, (r->dx & 0x10) ? E_ACCESS : E_NOTFOUND);
        if (rc) return error(r, (oa_u16)(rc < 0 ? E_ACCESS : rc));
        if (ent.attr & OFS_NTFS_DIR) return error(r, E_ACCESS);
        return dos_path(r, 0x6C00);             /* DOS with the 8.3 path */
    case 0xA6:                                  /* file information by handle */
        return lfn_handle_info(r);
    case 0xA0:                                  /* volume information */
        n = (oa_u8)dx[0];
        if (n >= 'a') n -= 32;
        if (n < 'A' || n > 'Z' || dx[1] != ':' || !full_path(dx)) return 1;
        r->bx = 0x4006;                         /* case kept, Unicode, the 71xxh calls */
        r->dx = LFN_MAX; n = r->cx; r->cx = 255;
        if (n >= 5) _fmemcpy(MK_FP(r->es, r->di), "NTFS", 5);
        return ok(r);
    }
    return 1;
}
#endif /* NTFS_LFN */

/* EXFAT.SYS's frame calls it for ASPI units; NTFS.SYS has none. */
void __cdecl aspi_notify(unsigned unit, unsigned seg)
{
    (void)unit; (void)seg;
}

/* Called at the first program start: drive letters for the volumes.
   0: done; 1: call again at the next trigger (no CDS yet, or LASTDRIVE was
   too low for all volumes: MS-DOS 7.10 has its final LASTDRIVE only after
   the shell's EXEC, so it is tried again while that value changes). */
int __cdecl assign(void __far *unused)
{
    static unsigned next, tried;            /* tried: LASTDRIVE + 1 */
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
#ifdef NTFS_LFN
    sft_list = *(oa_u8 __far * __far *)(lol + 4);
#endif
    last = lol[0x21];
    lol_cds = (oa_u8 __far * __far *)(lol + 0x16);
    if (!cds || FP_OFF(cds) == 0xFFFF) return 1;
    if (cds_seen && cds != cds_seen) next = tried = 0;  /* a new drive table */
    cds_seen = cds;
    l = first_letter;
    for (i = next; i < ndrv; ++i) {
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
    next = i;
    if (i >= ndrv || tried == last + 1) return 0;
    tried = last + 1;
    return 1;
}

/* ---- INIT: after the resident part, freed when INIT returns ---- */
#pragma code_seg("INIT_TEXT", "INIT")
#pragma data_seg("INIT_DATA", "INIT")
static char efi_part[] = "EFI PART", hexdig[] = "0123456789ABCDEF";
#ifdef NTFS_LFN
static char msg_hello[] = "NTFS " VERSION " - NTFS drives, read-only, long names\r\n$";
#else
static char msg_hello[] = "NTFS " VERSION " - NTFS drives, read-only\r\n$";
#endif
static char msg_none[] = "No NTFS volumes - NTFS not installed\r\n$";
static char msg_bios[] = "  NTFS volume on BIOS disk $", msg_h[] = "h\r\n$";
static char msg_dirty[] = "h (not cleanly unmounted)\r\n$";
static char msg_size[] = "  NTFS volume not supported (sector or record size) on $";

static struct drive *probe_disk;
static oa_u8 sec[OFS_NTFS_MAXSECT];
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
    unsigned sh = 9;
    int rc;
    if (ndrv >= MAXVOL || read_sec(start) || !ofs_ntfs_probe(sec)) return;
    *d = *probe_disk;
    /* the disk's sectors are the volume's (as EXFAT.SYS takes them) */
    while (sh < 12 && (1u << sh) < (unsigned)(sec[0x0B] | sec[0x0C] << 8)) ++sh;
    rc = ofs_ntfs_mount(&d->v, bios_read, d, start, sh, cp, nbuf);
    if (rc == OFS_NTFS_ESIZE && !quiet_init) { print(msg_size); print_hex(d->pub.bios); print(msg_h + 1); }
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
    if (ofs_ntfs_probe(sec)) { add_volume(0); return; }
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
    cptab = !int21(&q) && q.bx == 850 ? ofs_cp850 : ofs_cp437;
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
