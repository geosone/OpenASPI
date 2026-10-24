/* EXFAT.SYS: exFAT drives for DOS through the network redirector interface
   (INT 2Fh AH=11h), read-only.  The volumes are found on the BIOS disks
   (INT 13h): superfloppies, MBR partitions of type 07h (also logical ones)
   and GPT basic data partitions; and on the units of ASPIDSK and ASPIFDD,
   whose drive letters EXFAT.SYS takes over while an exFAT medium is in
   (common/dos/exfat_svc.inc).  The exFAT part is common/exfat/exfat.c.

   DOS structures as SHSUCDX uses them (DOS 4 and later): SDA from INT 21h
   AX=5D06h, CDS entries of 58h bytes, SFT, search data block. */
#include <string.h>
#include <i86.h>
#include "openaspi/exfat.h"

#define VERSION "0.2"
#define MAXVOL 8
#define STACKSIZE 1024                  /* as in exfatsys.asm */

#pragma pack(1)
struct regs { oa_u16 es, ds, bp, di, si, dx, cx, bx, ax, sp, ss, flags; };
struct iregs { oa_u16 ax, bx, cx, dx, si, di, ds, es; };
struct dap { oa_u8 size, res; oa_u16 count; void __far *buf; oa_u32 lba, lba_hi; };
struct packet { oa_u8 func, unit; oa_u16 status; oa_u32 lba; oa_u16 count; void __far *buf; oa_u16 result; };
#pragma pack()

#define SVC_INFO     0
#define SVC_READ     1
#define SVC_CHECK    2
#define SVC_CALLBACK 3
#define UF_EXFAT     0x80

extern int __cdecl int13(struct iregs *);
extern int __cdecl int21(struct iregs *);
extern void __cdecl hook(void);
extern int __cdecl svc_call(oa_u16 off, oa_u16 seg, struct packet *);
extern oa_u16 aspi_callback_off;      /* far procedure in exfatsys.asm */
extern char bss_start[], resident_end[];

struct drive {
    struct oa_exfat v;
    oa_u8 bios, ext, letter;    /* letter: 0 = A:, 0FFh none yet */
    oa_u16 spt, heads;
    oa_u32 free_clusters;       /* 0FFFFFFFFh: not counted yet */
    /* ASPIDSK/ASPIFDD units: the letter is DOS's while the medium is FAT */
    oa_u8 aspi, unit, state;
    oa_u16 svc_off, svc_seg;
    oa_u16 checked;             /* BIOS tick of the last media check */
};
#define ST_OURS    0            /* exFAT, the letter redirected */
#define ST_DOS     1            /* another medium: DOS and the block driver */
#define ST_PENDING 2            /* exFAT inserted: mount at the next use */

static struct drive drv[MAXVOL];
static unsigned ndrv;
static oa_u8 __far *sda;
static oa_u8 first_letter;
static const struct oa_exfat_cp *cp;
static struct oa_exfat_cp cptab;           /* the active one, copied at INIT */
static struct oa_exfat_ent ent;
typedef char ent_bounces[sizeof(struct oa_exfat_ent) >= 512 ? 1 : -1];
static oa_u8 secbuf[OA_EXFAT_MAXSECT];     /* the sector cache of all volumes */
static struct drive *buf_owner;
static oa_u8 __far *cds;
static oa_u8 saved_cds[MAXVOL][12];    /* 43h-4Eh of the CDS entries taken over */
static int gone;                        /* the medium of a drive was taken out */

/* walk cache of open files: the cluster last read of a FAT chain */
static struct { struct drive *d; oa_u32 first, idx, clu; } walks[4];
static unsigned next_walk;

#define DS_SEG() FP_SEG((void __far *)&ndrv)
#define W(p, o) (*(oa_u16 __far *)((p) + (o)))
#define D(p, o) (*(oa_u32 __far *)((p) + (o)))

/* DOS errors */
#define E_NOTFOUND 2
#define E_PATH     3
#define E_ACCESS   5
#define E_NOMORE   0x12
#define E_NOTREADY 0x15
#define E_GENERAL  0x1F
#define E_EXISTS   0x50

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
    oa_u16 cx = 0, dx = d->bios;
    oa_u32 t;
    if (!d->ext) {
        t = lba / d->spt;
        cx = (oa_u16)(lba - t * d->spt + 1);
        dx |= (oa_u16)(t % d->heads) << 8;
        t /= d->heads;
        if (t > 1023) return -1;
        cx |= (oa_u16)((t & 0xFF) << 8 | (t >> 2 & 0xC0));
    }
    for (tries = 0; tries < 3; ++tries) {
        memset(&r, 0, sizeof(r));
        r.dx = dx;
        if (d->ext) {
            p.size = 16; p.res = 0; p.count = 1; p.buf = buf; p.lba = lba; p.lba_hi = 0;
            r.ax = 0x4200; r.si = (oa_u16)&p; r.ds = DS_SEG();
            if (!int13(&r)) return 0;
        } else {
            r.ax = 0x0201; r.cx = cx;
            r.bx = FP_OFF(buf); r.es = FP_SEG(buf);
            if (!int13(&r)) return 0;
            /* DMA boundary: through ent, unused while a file is read into
               DOS's buffer (the sector cache itself is not moved) */
            if (r.ax >> 8 == 0x09 && FP_OFF(buf) != (oa_u16)secbuf) {
                r.ax = 0x0201; r.cx = cx; r.dx = dx; r.bx = (oa_u16)&ent; r.es = DS_SEG();
                if (!int13(&r)) { _fmemcpy(buf, &ent, 512); return 0; }
            }
        }
        memset(&r, 0, sizeof(r));
        r.dx = d->bios;
        int13(&r);                              /* reset */
    }
    return -1;
}

static int aspi_read(void *dev, oa_u32 lba, void __far *buf)
{
    struct drive *d = dev;
    struct packet k;
    memset(&k, 0, sizeof(k));
    k.func = SVC_READ; k.unit = d->unit; k.lba = lba; k.count = 1; k.buf = buf;
    return svc_call(d->svc_off, d->svc_seg, &k) ? -1 : 0;
}

static int mount(struct drive *d)
{
    unsigned i;
    for (i = 0; i < 4; ++i) if (walks[i].d == d) walks[i].d = 0;
    d->free_clusters = 0xFFFFFFFFUL;
    buf_owner = d;
    return oa_exfat_mount(&d->v, aspi_read, d, 0, cp, secbuf);
}

/* The drive letter to EXFAT.SYS: the DOS entry is kept for give_back. */
static void take_letter(struct drive *d)
{
    oa_u8 __far *e = cds + 0x58 * d->letter;
    if (d->state == ST_DOS) _fmemcpy(saved_cds[d - drv], e + 0x43, 12);
    _fmemset(e, 0, 0x58);
    e[0] = (oa_u8)('A' + d->letter); e[1] = ':'; e[2] = '\\';
    W(e, 0x43) = 0xC080;
    W(e, 0x4F) = 2;
}

/* The DOS entry again, its current directory the root: the medium has
   been changed. */
static void give_back(struct drive *d)
{
    oa_u8 __far *e = cds + 0x58 * d->letter;
    _fmemset(e, 0, 0x58);
    e[0] = (oa_u8)('A' + d->letter); e[1] = ':'; e[2] = '\\';
    _fmemcpy(e + 0x43, saved_cds[d - drv], 12);
    W(e, 0x49) = 0xFFFF;                        /* not looked up yet */
    W(e, 0x4F) = 2;
    d->state = ST_DOS;
}

/* Is the exFAT medium of an ASPI drive still in (checked at most once a
   second)?  A new exFAT medium is mounted; another one gives the letter
   back to DOS. */
static int aspi_ready(struct drive *d)
{
    struct packet k;
    oa_u16 now = *(oa_u16 __far *)MK_FP(0x40, 0x6C);
    if (d->state == ST_OURS && (oa_u16)(now - d->checked) < 18) return 1;
    d->checked = now;
    memset(&k, 0, sizeof(k));
    k.unit = d->unit;
    if (d->state == ST_OURS) {
        k.func = SVC_CHECK;
        if (svc_call(d->svc_off, d->svc_seg, &k)) return 1;
        if (!k.result) return 1;
        k.func = SVC_INFO;
    }
    if (!svc_call(d->svc_off, d->svc_seg, &k) && (k.count & UF_EXFAT) && !mount(d)) {
        d->state = ST_OURS;
        return 1;
    }
    give_back(d);
    gone = 1;
    return 0;
}

static oa_u16 rd16(const oa_u8 *p) { return (oa_u16)(p[0] | p[1] << 8); }
static oa_u32 rd32(const oa_u8 *p) { return rd16(p) | (oa_u32)rd16(p+2) << 16; }

/* ---- the redirector ---- */

static struct drive *drive_of(oa_u8 letter)
{
    struct drive *d;
    for (d = drv; d < drv + ndrv; ++d) {
        if (d->letter != letter || (d->aspi && d->state == ST_DOS)) continue;
        if (buf_owner != d) { d->v.buf_lba = 0xFFFFFFFFUL; buf_owner = d; }
        if (d->aspi && !aspi_ready(d)) return 0;
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

static void dir_file(struct oa_exfat_file *f, const struct oa_exfat_file *from)
{
    *f = *from;
    if (!f->nofat) f->root = 1;                 /* the chain gives the size */
}

/* The directory of a path and its last part; E_PATH when a directory
   on the way is missing. */
static int split_path(struct drive *d, const char __far *p, struct oa_exfat_file *dir, char fcb[11])
{
    oa_exfat_rootdir(&d->v, dir);
    p += 3;                                     /* "X:\" */
    memset(fcb, ' ', 11);
    while (*p) {
        p = to_fcb(p, fcb);
        if (!*p) return 0;
        ++p;
        if (oa_exfat_lookup(&d->v, dir, fcb, &ent) || !(ent.attr & OA_EXFAT_DIR)) return E_PATH;
        dir_file(dir, &ent.file);
        memset(fcb, ' ', 11);
    }
    return 0;
}

static char last_fcb[11];

/* Finds a path: 0 and ent (last_fcb its 8.3 name), -1 for the root
   directory, or a DOS error. */
static int find_path(struct drive *d, const char __far *p)
{
    struct oa_exfat_file dir;
    char *fcb = last_fcb;
    int r = split_path(d, p, &dir, fcb);
    if (r) return r;
    if (fcb[0] == ' ') return -1;
    r = oa_exfat_lookup(&d->v, &dir, fcb, &ent);
    if (r == OA_EXFAT_END) return E_NOTFOUND;
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

static void fill_sft(oa_u8 __far *sft, struct drive *d)
{
    sft[4] = (oa_u8)ent.attr;
    W(sft, 5) = 0x8040 | d->letter;
    D(sft, 7) = ent.file.valid;
    W(sft, 0x0B) = (oa_u16)(ent.file.nofat | ent.file.big << 1);
    W(sft, 0x0D) = ent.time; W(sft, 0x0F) = ent.date;
    D(sft, 0x11) = ent.file.size;
    D(sft, 0x15) = 0;
    W(sft, 0x19) = 0;
    D(sft, 0x1B) = ent.file.first;
    sft[0x1F] = 0;
    _fmemcpy(sft + 0x20, last_fcb, 11);
}

static void sft_file(struct drive *d, const oa_u8 __far *sft, struct oa_exfat_file *f)
{
    unsigned i;
    memset(f, 0, sizeof(*f));
    f->first = D(sft, 0x1B); f->size = D(sft, 0x11); f->valid = D(sft, 7);
    f->nofat = (oa_u8)(W(sft, 0x0B) & 1);
    for (i = 0; i < 4; ++i)
        if (walks[i].d == d && walks[i].first == f->first) { f->idx = walks[i].idx; f->clu = walks[i].clu; }
}

static void sft_walk(struct drive *d, const struct oa_exfat_file *f)
{
    unsigned i;
    for (i = 0; i < 4 && (walks[i].d != d || walks[i].first != f->first); ++i) ;
    if (i == 4) { i = next_walk; next_walk = (next_walk + 1) & 3; }
    walks[i].d = d; walks[i].first = f->first; walks[i].idx = f->idx; walks[i].clu = f->clu;
}

static int match(const char *name, const oa_u8 __far *tpl)
{
    unsigned i;
    for (i = 0; i < 11; ++i) if (tpl[i] != '?' && tpl[i] != (oa_u8)name[i]) return 0;
    return 1;
}

/* Search data block (21 bytes): drive|C0h, template, attribute, then
   WORD entry (0 ".", 1 "..", 2.. entries of a subdirectory), DWORD first
   cluster of the directory, WORD size in clusters | 8000h no FAT chain. */
static int find(struct regs *r, struct drive *d, oa_u8 __far *sdb)
{
    struct oa_exfat_file dir;
    oa_u8 __far *fdb = *(oa_u8 __far * __far *)(sda + SDA_DTA) + 21;
    oa_u8 attr = sdb[12];
    oa_u16 idx = W(sdb, 13), info = W(sdb, 19);
    oa_u32 pos;
    int sub, rc;
    char name[11];
    memset(&dir, 0, sizeof(dir));
    dir.first = D(sdb, 15);
    sub = dir.first != d->v.root;
    if (info & 0x8000) { dir.nofat = 1; dir.size = (oa_u32)(info & 0x7FFF) << (d->v.sshift + d->v.cshift); }
    else dir.root = 1;
    if (idx == 0xFFFF) return error(r, E_NOMORE);
    _fmemset(fdb, 0, 32);
    while (sub && idx < 2) {
        memset(name, ' ', 11); name[0] = '.';
        if (idx++) name[1] = '.';
        if ((attr & OA_EXFAT_DIR) && match(name, sdb + 1)) {
            _fmemcpy(fdb, name, 11); fdb[11] = OA_EXFAT_DIR;
            W(sdb, 13) = idx;
            return ok(r);
        }
    }
    pos = (oa_u32)(idx - (sub ? 2 : 0)) << 5;
    for (;;) {
        rc = oa_exfat_dir_next(&d->v, &dir, &pos, &ent);
        if (rc == OA_EXFAT_END) break;
        if (rc) return error(r, E_NOTREADY);
        if ((ent.attr & ~attr) & (OA_EXFAT_HIDDEN | OA_EXFAT_SYSTEM | OA_EXFAT_DIR)) continue;
        if (oa_exfat_short(&d->v, &dir, &ent, name)) return error(r, E_NOTREADY);
        if (!match(name, sdb + 1)) continue;
        _fmemcpy(fdb, name, 11);
        fdb[11] = (oa_u8)ent.attr;
        W(fdb, 22) = ent.time; W(fdb, 24) = ent.date;
        D(fdb, 28) = ent.file.size;
        W(sdb, 13) = (oa_u16)((pos >> 5) + (sub ? 2 : 0));
        return ok(r);
    }
    W(sdb, 13) = 0xFFFF;
    return error(r, E_NOMORE);
}

static int find_first(struct regs *r, struct drive *d)
{
    struct oa_exfat_file dir;
    oa_u8 __far *sdb = sda + SDA_SDB;
    oa_u8 __far *fdb = *(oa_u8 __far * __far *)(sda + SDA_DTA) + 21;
    char fcb[11];
    unsigned i;
    oa_u8 c;
    oa_u16 info = 0;
    if (split_path(d, (const char __far *)(sda + SDA_FN1), &dir, fcb)) return error(r, E_PATH);
    if (fcb[0] == ' ') memset(fcb, '?', 11);
    sdb[0] = (oa_u8)(d->letter | 0xC0);
    _fmemcpy(sdb + 1, fcb, 11);
    sdb[12] = sda[SDA_SATTR];
    W(sdb, 13) = 0;
    D(sdb, 15) = dir.first;
    if (dir.nofat) {
        oa_u32 n = dir.size >> (d->v.sshift + d->v.cshift);
        info = (oa_u16)(0x8000 | (n > 0x7FFF ? 0x7FFF : n));
    }
    W(sdb, 19) = info;
    if (sdb[12] == 0x08) {                      /* the volume label */
        _fmemset(fdb, 0, 32);
        _fmemset(fdb, ' ', 11);
        for (i = 0; i < d->v.label_len; ++i) {
            c = d->v.label[i] < 0x80 ? (oa_u8)d->v.label[i] : '_';
            fdb[i] = c >= 'a' && c <= 'z' ? (oa_u8)(c - 32) : c;
        }
        fdb[11] = 0x08;
        W(sdb, 13) = 0xFFFF;
        return d->v.label_len ? ok(r) : error(r, E_NOMORE);
    }
    return find(r, d, sdb);
}

static int disk_space(struct regs *r, struct drive *d)
{
    oa_u32 total = d->v.clusters, avail, bytes = 1UL << (d->v.sshift + d->v.cshift);
    oa_u16 bps = 512;
    if (d->free_clusters == 0xFFFFFFFFUL && oa_exfat_free(&d->v, &d->free_clusters))
        return error(r, E_NOTREADY);
    avail = d->free_clusters;
    while (total > 0xFFFF) { total >>= 1; avail >>= 1; bytes <<= 1; }
    while (bytes / bps > 128 && bps < 0x8000) bps <<= 1;
    if (bytes / bps > 128) { bytes = 128UL * bps; }
    r->ax = (oa_u16)(bytes / bps) | 0xF8 << 8;
    r->bx = (oa_u16)total; r->cx = bps; r->dx = (oa_u16)avail;
    return ok(r);
}

static int do_open(struct regs *r, struct drive *d, oa_u16 mode)
{
    int rc;
    if (mode & 3) return error(r, E_ACCESS);
    rc = find_path(d, (const char __far *)(sda + SDA_FN1));
    if (rc < 0 || (!rc && (ent.attr & OA_EXFAT_DIR))) return error(r, E_ACCESS);
    if (rc) return error(r, (oa_u16)rc);
    fill_sft((oa_u8 __far *)MK_FP(r->es, r->di), d);
    return ok(r);
}

static int redir2(struct regs *r);

/* The drive of an SFT of a redirector file, if it is ours. */
static struct drive *sft_drive(const oa_u8 __far *sft)
{
    return W(sft, 5) & 0x8000 ? drive_of((oa_u8)(W(sft, 5) & 0x3F)) : 0;
}

int __cdecl redir(struct regs *r)
{
    int rc = redir2(r);
    if (gone) {                                 /* the medium was changed */
        gone = 0;
        return error(r, E_NOTREADY);
    }
    return rc;
}

/* BUILD BPB of ASPIDSK/ASPIFDD found a new exFAT medium on a unit whose
   letter DOS has: take the letter, mount at the next use. */
void __cdecl aspi_notify(unsigned unit, unsigned seg)
{
    struct drive *d;
    for (d = drv; d < drv + ndrv; ++d) {
        if (!d->aspi || d->svc_seg != seg || d->unit != unit || d->state != ST_DOS) continue;
        take_letter(d);
        d->state = ST_PENDING;
    }
}

static int redir2(struct regs *r)
{
    oa_u8 fn = (oa_u8)r->ax;
    oa_u8 __far *sft = (oa_u8 __far *)MK_FP(r->es, r->di);
    const char __far *fn1 = (const char __far *)(sda + SDA_FN1);
    struct oa_exfat_file f;
    struct drive *d;
    oa_u16 done;
    oa_u32 pos;
    int rc;
    if (!sda) return 1;                         /* no drives yet */
    switch (fn) {
    case 0x00:                                  /* installation check */
        r->ax = 0x11FF;
        return 0;
    case 0x01: case 0x03: case 0x0E: case 0x11: case 0x13: case 0x17:  /* changes */
        if (!(d = drive_of_path(fn1))) return 1;
        return error(r, E_ACCESS);
    case 0x05:                                  /* change directory */
        if (!(d = drive_of_path(fn1))) return 1;
        rc = find_path(d, fn1);
        if (rc > 0 || (!rc && !(ent.attr & OA_EXFAT_DIR))) return error(r, E_PATH);
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
        rc = oa_exfat_read(&d->v, &f, pos, *(void __far * __far *)(sda + SDA_DTA), r->cx, &done);
        sft_walk(d, &f);
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
        if (rc < 0) { r->ax = OA_EXFAT_DIR; r->bx = r->di = r->cx = r->dx = 0; return ok(r); }
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
        if (rc == E_NOTFOUND && (sda[SDA_ACTION] & 0x10)) return error(r, E_ACCESS);
        if (!rc && (sda[SDA_ACTION] & 0x0F) == 0) return error(r, E_EXISTS);
        if (!rc && (sda[SDA_ACTION] & 0x0F) == 2) return error(r, E_ACCESS);
        do_open(r, d, sda[SDA_MODE]);
        if (!(r->flags & 1)) r->cx = 1;
        return 0;
    }
    return 1;
}

/* Called at the first program start: drive letters for the volumes. */
/* The units of ASPIDSK and ASPIFDD ("EXF1" in the device header) and their
   DOS drive letters. */
static void find_aspi(oa_u8 __far *lol)
{
    oa_u8 __far *dev = lol + 0x22, __far *dpb;
    struct packet k;
    struct drive *d;
    unsigned u, units;
    for (; FP_OFF(dev) != 0xFFFF; dev = *(oa_u8 __far * __far *)dev) {
        if ((W(dev, 4) & 0x8000) || _fmemcmp(dev + 0x0B, "EXF1", 4)) continue;
        units = dev[0x0A];
        memset(&k, 0, sizeof(k));
        k.func = SVC_CALLBACK; k.buf = MK_FP(DS_SEG(), aspi_callback_off);
        svc_call(W(dev, 0x0F), FP_SEG(dev), &k);
        for (u = 0; u < units && ndrv < MAXVOL; ++u) {
            d = &drv[ndrv];
            memset(d, 0, sizeof(*d));
            d->aspi = 1; d->unit = (oa_u8)u; d->svc_off = W(dev, 0x0F); d->svc_seg = FP_SEG(dev);
            d->letter = 0xFF; d->state = ST_DOS;
            for (dpb = *(oa_u8 __far * __far *)lol; FP_OFF(dpb) != 0xFFFF; dpb = *(oa_u8 __far * __far *)(dpb + 0x19))
                if (*(oa_u8 __far * __far *)(dpb + 0x13) == dev && dpb[1] == u) d->letter = dpb[0];
            if (d->letter == 0xFF) continue;
            ++ndrv;
            memset(&k, 0, sizeof(k));
            k.unit = (oa_u8)u;
            if (svc_call(d->svc_off, d->svc_seg, &k) || !(k.count & UF_EXFAT) || mount(d)) continue;
            take_letter(d);
            d->state = ST_OURS;
        }
    }
}

/* A BIOS volume that is also an ASPI unit (the BIOS of a USB stick). */
static int on_aspi(struct drive *b)
{
    struct drive *d;
    for (d = drv; d < drv + ndrv; ++d)
        if (d->aspi && d->state == ST_OURS && d->v.serial == b->v.serial && d->v.clusters == b->v.clusters) return 1;
    return 0;
}

int __cdecl assign(void __far *unused)
{
    struct iregs q;
    oa_u8 __far *lol, __far *e;
    unsigned i, l, last, nbios;
    (void)unused;
    /* the SDA only now: DR-DOS and EDR-DOS move the DOS data segment
       after CONFIG.SYS */
    memset(&q, 0, sizeof(q));
    q.ax = 0x5D06;
    int21(&q);
    sda = (oa_u8 __far *)MK_FP(q.ds, q.si);
    memset(&q, 0, sizeof(q));
    q.ax = 0x5200;
    int21(&q);
    lol = (oa_u8 __far *)MK_FP(q.es, q.bx);
    cds = *(oa_u8 __far * __far *)(lol + 0x16);
    last = lol[0x21];
    if (!cds || FP_OFF(cds) == 0xFFFF) return 0;
    nbios = ndrv;
    find_aspi(lol);
    l = first_letter;
    for (i = 0; i < nbios; ++i) {
        if (on_aspi(&drv[i])) continue;
        for (; l < last; ++l) if (!(W(cds + 0x58 * l, 0x43) & 0xC000)) break;
        if (l >= last) break;
        drv[i].letter = (oa_u8)l;
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
/* string literals would stay resident in CONST */
static char efi_part[] = "EFI PART", hexdig[] = "0123456789ABCDEF";
static char msg_hello[] = "EXFAT " VERSION " - exFAT drives, read-only\r\n$";
static char msg_none[] = "No exFAT volumes and no ASPIDSK/ASPIFDD - EXFAT not installed\r\n$";
static char msg_bios[] = "  exFAT volume on BIOS disk $", msg_h[] = "h\r\n$";
static char msg_aspi[] = "  exFAT media on the drives of ASPIDSK/ASPIFDD\r\n$";

static struct drive *probe_disk;
#define sec secbuf

static int read_sec(oa_u32 lba) { return bios_read(probe_disk, lba, sec); }

static void add_volume(oa_u32 start)
{
    struct drive *d = &drv[ndrv];
    if (ndrv >= MAXVOL || read_sec(start) || !oa_exfat_probe(sec)) return;
    *d = *probe_disk;
    if (oa_exfat_mount(&d->v, bios_read, d, start, cp, secbuf)) return;
    d->letter = 0xFF; d->free_clusters = 0xFFFFFFFFUL;
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
    if (oa_exfat_probe(sec)) { add_volume(0); return; }
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

/* ASPIDSK or ASPIFDD loaded before EXFAT.SYS? */
static int aspi_drivers(void)
{
    struct iregs q;
    oa_u8 __far *dev;
    unsigned n = 0;
    memset(&q, 0, sizeof(q));
    q.ax = 0x5200;
    int21(&q);
    for (dev = (oa_u8 __far *)MK_FP(q.es, q.bx + 0x22); FP_OFF(dev) != 0xFFFF; dev = *(oa_u8 __far * __far *)dev)
        if (!(W(dev, 4) & 0x8000) && !_fmemcmp(dev + 0x0B, "EXF1", 4)) ++n;
    return n;
}

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

int __cdecl drv_init(void __far *req)
{
    oa_u8 __far *rq = req;
    const char __far *p = *(const char __far * __far *)(rq + 18);
    struct iregs q;
    unsigned i, disks, aspi, quiet = 0, chs = 0;
    struct drive probe;
    memset(bss_start, 0, resident_end - bss_start - STACKSIZE);
    /* the command line after the file name: /L:x, /Q and /C */
    while (*p && *p != ' ' && *p != '\r' && *p != '\n') ++p;
    for (; *p && *p != '\r' && *p != '\n'; ++p) {
        if (*p != '/') continue;
        if ((p[1] == 'L' || p[1] == 'l') && p[2] == ':' && (p[3] | 32) >= 'a' && (p[3] | 32) <= 'z')
            first_letter = (oa_u8)((p[3] | 32) - 'a');
        if (p[1] == 'Q' || p[1] == 'q') quiet = 1;
        if (p[1] == 'C' || p[1] == 'c') chs = 1;
    }
    memset(&q, 0, sizeof(q));
    q.ax = 0x6601;
    cptab = !int21(&q) && q.bx == 850 ? oa_exfat_cp850 : oa_exfat_cp437;
    cp = &cptab;
    if (!quiet) print(msg_hello);
    disks = *(oa_u8 __far *)MK_FP(0x40, 0x75);
    for (i = 0; i < disks && i < 8; ++i) {
        memset(&probe, 0, sizeof(probe));
        probe.bios = (oa_u8)(0x80 + i);
        memset(&q, 0, sizeof(q));
        q.ax = 0x4100; q.bx = 0x55AA; q.dx = probe.bios;
        if (!chs && !int13(&q) && q.bx == 0xAA55 && (q.cx & 1)) probe.ext = 1;
        memset(&q, 0, sizeof(q));
        q.ax = 0x0800; q.dx = probe.bios;
        if (int13(&q)) continue;
        probe.spt = q.cx & 63; probe.heads = (q.dx >> 8) + 1;
        if (!probe.spt) continue;
        probe_disk = &probe;
        scan_disk();
    }
    aspi = aspi_drivers();
    if (!ndrv && !aspi) {
        if (!quiet) print(msg_none);
        W(rq, 14) = 0; W(rq, 16) = DS_SEG();
        W(rq, 3) = 0x0100;
        return 0;
    }
    if (!quiet) {
        for (i = 0; i < ndrv; ++i) {
            print(msg_bios);
            print_hex(drv[i].bios);
            print(msg_h);
        }
        if (aspi) print(msg_aspi);
    }
    buf_owner = 0;
    hook();
    W(rq, 14) = (oa_u16)resident_end;
    W(rq, 16) = DS_SEG();
    W(rq, 3) = 0x0100;
    return 0;
}
