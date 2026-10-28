/* EXFMT: creates an exFAT file system on a drive of EXFAT.SYS, a drive of
   ASPIDSK/ASPIFDD (FAT or blank medium) or a BIOS disk.
   EXFMT d: | /D:nn  [/P:n | /WHOLE] [/V:label] [/A:size] [/TEXFAT] [/Q] [/YES]
   Exit codes: 0 formatted (or the layout shown), 1 format failed, 2 wrong
   use or no such drive, 3 read or write error. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <dos.h>
#include <i86.h>
#include <malloc.h>
#include <stddef.h>
#include "openaspi/exfat_format.h"
#include "openaspi/exfatsys.h"

#define VERSION "0.1"
#define NBUF 32                         /* sectors of the transfer buffer */

#pragma pack(1)
struct packet { oa_u8 func, unit; oa_u16 status; oa_u32 lba; oa_u16 count; void __far *buf; oa_u16 result; };
struct dap { oa_u8 size, res; oa_u16 count; void __far *buf; oa_u32 lba, lba_hi; };
#pragma pack()

enum { SVC_INFO = 0, SVC_PREAD = 5, SVC_PWRITE = 6, SVC_CAPACITY = 7, SVC_RELOAD = 8 };

/* far call of the exFAT service of ASPIDSK/ASPIFDD, ES:BX -> packet */
void svc(void __far *entry, struct packet __far *p);
#pragma aux svc = \
    "push bp" "push dx" "push ax" "mov bp, sp" "call dword ptr [bp]" "add sp, 4" "pop bp" \
    parm [dx ax] [es bx] modify [ax bx cx dx si di es];

/* the medium: a BIOS disk or a unit of ASPIDSK/ASPIFDD */
static struct {
    int aspi;
    oa_u8 bios, ext;
    oa_u16 spt, heads;
    void __far *entry;
    oa_u8 unit;
    oa_u32 capacity;
} m;
static oa_u32 vstart;                   /* first sector of the volume */
static oa_u8 __far *vol_in_driver;      /* EXFAT.SYS's table entry, for "changed" */
static oa_u8 bounce_area[1024];

static oa_u8 __far *bounce(void)
{
    oa_u32 lin = (oa_u32)FP_SEG(bounce_area) * 16 + FP_OFF(bounce_area);
    return (lin & 0xFFFF) > 0xFE00 ? bounce_area + 512 : bounce_area;
}

/* one sector through INT 13h AH 02h/03h, with the DMA boundary bounce */
static int chs_io(int write, oa_u32 lba, void __far *buf)
{
    union REGS r;
    struct SREGS s;
    oa_u32 t = lba / m.spt;
    unsigned cx = (unsigned)(lba - t * m.spt + 1), dh = (unsigned)(t % m.heads), tries;
    void __far *p = buf;
    t /= m.heads;
    if (t > 1023) return -1;
    cx |= (unsigned)((t & 0xFF) << 8 | (t >> 2 & 0xC0));
    for (tries = 0; tries < 3; ++tries) {
        segread(&s);
        memset(&r, 0, sizeof(r));
        r.x.ax = write ? 0x0301 : 0x0201; r.x.cx = cx; r.h.dh = (oa_u8)dh; r.h.dl = m.bios;
        r.x.bx = FP_OFF(p); s.es = FP_SEG(p);
        int86x(0x13, &r, &r, &s);
        if (!r.x.cflag) {
            if (p != buf && !write) _fmemcpy(buf, p, 512);
            return 0;
        }
        if (r.h.ah == 0x09 && p == buf) {       /* DMA boundary */
            p = bounce();
            if (write) _fmemcpy(p, buf, 512);
            continue;
        }
        memset(&r, 0, sizeof(r));
        r.h.dl = m.bios;
        int86(0x13, &r, &r);                    /* reset */
    }
    return -1;
}

/* count sectors (up to NBUF) of the medium at lba */
static int io(int write, oa_u32 lba, unsigned count, void __far *buf)
{
    union REGS r;
    struct SREGS s;
    struct dap p;
    struct packet k;
    unsigned i, tries;
    if (lba + count > m.capacity || lba + count < lba) return -1;
    if (m.aspi) {
        memset(&k, 0, sizeof(k));
        k.func = write ? SVC_PWRITE : SVC_PREAD; k.unit = m.unit; k.lba = lba; k.count = count; k.buf = buf;
        svc(m.entry, &k);
        return k.status ? -1 : 0;
    }
    if (!m.ext) {
        for (i = 0; i < count; ++i)
            if (chs_io(write, lba + i, (oa_u8 __far *)buf + i * 512)) return -1;
        return 0;
    }
    for (tries = 0; tries < 3; ++tries) {
        segread(&s);
        memset(&r, 0, sizeof(r));
        p.size = 16; p.res = 0; p.count = count; p.buf = buf; p.lba = lba; p.lba_hi = 0;
        r.h.ah = write ? 0x43 : 0x42; r.h.dl = m.bios;
        r.x.si = FP_OFF((void __far *)&p); s.ds = FP_SEG((void __far *)&p);
        int86x(0x13, &r, &r, &s);
        if (!r.x.cflag) return 0;
        memset(&r, 0, sizeof(r));
        r.h.dl = m.bios;
        int86(0x13, &r, &r);
    }
    return -1;
}

static int vol_write(void *dev, oa_u32 lba, unsigned count, const void __far *buf)
{
    (void)dev;
    return io(1, vstart + lba, count, (void __far *)buf);
}

static int aspi_call(oa_u8 func, struct packet *k)
{
    memset(k, 0, sizeof(*k));
    k->func = func; k->unit = m.unit;
    svc(m.entry, k);
    return k->status ? -1 : 0;
}

/* size and kind of access of BIOS disk m.bios */
static int bios_disk(void)
{
    union REGS r;
    struct SREGS s;
    static oa_u8 params[30];
    memset(&r, 0, sizeof(r));
    r.h.ah = 0x08; r.h.dl = m.bios;
    int86(0x13, &r, &r);
    if (r.x.cflag || !(r.h.cl & 0x3F)) return -1;
    m.spt = r.h.cl & 0x3F;
    m.heads = r.h.dh + 1;
    m.capacity = ((oa_u32)(r.h.ch | (r.h.cl & 0xC0) << 2) + 1) * m.heads * m.spt;
    memset(&r, 0, sizeof(r));
    r.h.ah = 0x41; r.x.bx = 0x55AA; r.h.dl = m.bios;
    int86(0x13, &r, &r);
    if (r.x.cflag || r.x.bx != 0xAA55 || !(r.x.cx & 1)) return 0;
    m.ext = 1;
    segread(&s);
    memset(&r, 0, sizeof(r));
    memset(params, 0, sizeof(params));
    params[0] = 30;
    r.h.ah = 0x48; r.h.dl = m.bios; r.x.si = FP_OFF((void __far *)params); s.ds = FP_SEG((void __far *)params);
    int86x(0x13, &r, &r, &s);
    if (!r.x.cflag && !params[0x14] && !params[0x15] && !params[0x16] && !params[0x17] && *(oa_u32 *)(params + 0x10))
        m.capacity = *(oa_u32 *)(params + 0x10);
    return 0;
}

static oa_u8 __far *list_of_lists(void)
{
    union REGS r;
    struct SREGS s;
    segread(&s);
    r.h.ah = 0x52;
    intdosx(&r, &r, &s);
    return (oa_u8 __far *)MK_FP(s.es, r.x.bx);
}

/* EXFAT.SYS's volume of drive letter (0 = A:): 0 found, -1 none */
static int exfatsys_volume(unsigned letter)
{
    oa_u8 __far *dev, __far *v;
    const struct oa_exfatsys_info __far *info;
    struct oa_exfatsys_vol vol;
    struct packet k;
    unsigned i, n;
    for (dev = list_of_lists() + 0x22; FP_OFF(dev) != 0xFFFF; dev = *(oa_u8 __far * __far *)dev) {
        if (!(*(oa_u16 __far *)(dev + 4) & 0x8000) || _fmemcmp(dev + 10, "$EXFAT$ EXI1", 12)) continue;
        info = MK_FP(FP_SEG(dev), *(oa_u16 __far *)(dev + 22));
        if (info->version != 1) return -1;
        n = *(oa_u16 __far *)MK_FP(FP_SEG(dev), info->count);
        for (i = 0; i < n; ++i) {
            v = (oa_u8 __far *)MK_FP(FP_SEG(dev), info->table + i * info->stride);
            _fmemcpy(&vol, v, sizeof(vol));
            if (vol.letter != letter || (vol.aspi && vol.state == OA_EXFATSYS_DOS)) continue;
            vol_in_driver = v;
            vstart = vol.start;
            if (vol.aspi) {
                m.aspi = 1; m.unit = vol.unit; m.entry = MK_FP(vol.svc_seg, vol.svc_off);
                if (!aspi_call(SVC_INFO, &k)) vstart = k.lba;
            } else {
                m.bios = vol.bios;
                if (bios_disk()) return -1;
            }
            return 0;
        }
        return -1;
    }
    return -1;
}

/* a drive letter of ASPIDSK/ASPIFDD ("EXF1" in the device header) */
static int aspi_volume(unsigned letter)
{
    oa_u8 __far *lol = list_of_lists(), __far *dpb, __far *dev;
    for (dpb = *(oa_u8 __far * __far *)lol; FP_OFF(dpb) != 0xFFFF; dpb = *(oa_u8 __far * __far *)(dpb + 0x19)) {
        if (dpb[0] != letter) continue;
        dev = *(oa_u8 __far * __far *)(dpb + 0x13);
        if ((*(oa_u16 __far *)(dev + 4) & 0x8000) || _fmemcmp(dev + 0x0B, "EXF1", 4)) return -1;
        m.aspi = 1; m.unit = dpb[1];
        m.entry = MK_FP(FP_SEG(dev), *(oa_u16 __far *)(dev + 0x0F));
        return 0;
    }
    return -1;
}

static oa_u32 rd32(const oa_u8 *p) { return p[0] | (oa_u32)p[1] << 8 | (oa_u32)p[2] << 16 | (oa_u32)p[3] << 24; }

static int fat_type(oa_u8 t) { return t == 0x01 || t == 0x04 || t == 0x06 || t == 0x07 || t == 0x0B || t == 0x0C || t == 0x0E; }

/* a boot sector of FAT or exFAT (a superfloppy) */
static int boot_sector(const oa_u8 *b)
{
    if (b[510] != 0x55 || b[511] != 0xAA) return 0;
    if (!memcmp(b + 3, "EXFAT   ", 8)) return 1;
    return (b[0] == 0xEB || b[0] == 0xE9) && b[11] == 0 && b[12] == 2 && b[13] && b[16];
}

/* the boot drive, 1 = A: */
static unsigned boot_drive(void)
{
    union REGS r;
    r.x.ax = 0x3305;
    intdos(&r, &r);
    return r.h.dl;
}

static void usage(void)
{
    puts("EXFMT d: | /D:nn  [/P:n | /WHOLE] [/V:label] [/A:size] [/TEXFAT] [/Q] [/YES]\n"
         "  d:       drive of EXFAT.SYS or ASPIDSK/ASPIFDD    /D:nn  BIOS disk (80 = first)\n"
         "  /P:n     partition n (1-4) of the MBR    /WHOLE  the whole medium, no partitions\n"
         "  /V:label volume label    /A:size cluster size (512, 4K ... 32M)\n"
         "  /TEXFAT  two FATs and allocation bitmaps    /Q  no surface read\n"
         "  /YES     format; without it only the layout is shown");
}

int main(int argc, char **argv)
{
    static oa_u8 mbr[512];
    static oa_u32 bad[OA_EXFMT_MAXBAD];
    struct oa_exfmt f;
    struct packet k;
    struct dosdate_t dd;
    struct dostime_t dt;
    oa_u8 __far *buf;
    oa_u8 *e = 0;
    const char *label = 0, *a;
    unsigned i, j, nbad = 0, part = 0, whole = 0, quick = 0, yes = 0, letter = 0xFF, cp;
    oa_u32 csz = 0, lba, n, c, size;
    int rc;
    printf("EXFMT " VERSION " - exFAT format\n");
    memset(&f, 0, sizeof(f));
    f.nfats = 1;
    m.bios = 0xFF;
    for (i = 1; i < (unsigned)argc; ++i) {
        a = argv[i];
        if (strlen(a) == 2 && a[1] == ':' && isalpha((unsigned char)a[0])) letter = toupper((unsigned char)a[0]) - 'A';
        else if (!strnicmp(a, "/D:", 3)) m.bios = (oa_u8)strtoul(a + 3, 0, 16);
        else if (!strnicmp(a, "/P:", 3) && a[3] >= '1' && a[3] <= '4' && !a[4]) part = a[3] - '0';
        else if (!stricmp(a, "/WHOLE")) whole = 1;
        else if (!strnicmp(a, "/V:", 3)) label = a + 3;
        else if (!strnicmp(a, "/A:", 3)) {
            csz = strtoul(a + 3, (char **)&a, 10);
            if (toupper((unsigned char)*a) == 'K') csz <<= 10, ++a;
            else if (toupper((unsigned char)*a) == 'M') csz <<= 20, ++a;
            if (*a) { usage(); return 2; }
        }
        else if (!stricmp(a, "/TEXFAT")) f.nfats = 2;
        else if (!stricmp(a, "/Q")) quick = 1;
        else if (!stricmp(a, "/YES")) yes = 1;
        else { usage(); return 2; }
    }
    if ((letter == 0xFF) == (m.bios == 0xFF) || (part && whole)) { usage(); return 2; }
    memset(&k, 0, sizeof(k));
    {
        union REGS r;
        memset(&r, 0, sizeof(r));
        r.x.ax = 0x6601;
        intdos(&r, &r);
        cp = !r.x.cflag && r.x.bx == 850 ? 850 : 437;
    }
    /* the volume label in UTF-16 */
    if (label) {
        for (; label[f.label_len]; ++f.label_len) {
            c = (oa_u8)label[f.label_len];
            if (f.label_len == 11 || c < 0x20 || strchr("\"*/:<>?\\|", (int)c)) {
                printf("Invalid volume label.\n"); return 2;
            }
            f.label[f.label_len] = c < 0x80 ? (oa_u16)c : (cp == 850 ? oa_exfat_cp850 : oa_exfat_cp437).uni[c - 0x80];
        }
    }
    /* the medium */
    if (letter != 0xFF) {
        if (exfatsys_volume(letter) && aspi_volume(letter)) {
            printf("%c: is no drive of EXFAT.SYS, ASPIDSK or ASPIFDD; use /D:nn for a BIOS disk.\n", 'A' + letter);
            return 2;
        }
    } else if (m.bios < 0x80 || bios_disk()) {
        printf("No BIOS disk %02Xh.\n", m.bios); return 2;
    }
    if (m.aspi) {
        if (aspi_call(SVC_CAPACITY, &k)) { printf("The medium is not ready.\n"); return 3; }
        m.capacity = k.lba;
    }
    if (io(0, 0, 1, (void __far *)mbr)) { printf("Read error in sector 0.\n"); return 3; }
    /* the volume: the whole medium, or a partition */
    if (!whole && !part && vol_in_driver && vstart) {
        for (i = 0; i < 4; ++i) if (rd32(mbr + 0x1C6 + 16 * i) == vstart) part = i + 1;
        if (!part) { printf("The partition of %c: is not in the MBR.\n", 'A' + letter); return 2; }
    }
    if (!whole && !part && mbr[510] == 0x55 && mbr[511] == 0xAA && !boot_sector(mbr)) {
        for (i = 4; i-- > 0; ) if (fat_type(mbr[0x1C2 + 16 * i])) part = i + 1;
        if (!part) { printf("No FAT or exFAT partition in the MBR: use /P:n or /WHOLE.\n"); return 2; }
        if (!m.aspi && !vol_in_driver && mbr[0x1C2 + 16 * (part - 1)] != 0x07) {
            printf("Partition %u is FAT and may be a DOS drive: name it with /P:n.\n", part); return 2;
        }
    }
    if (part) {
        e = mbr + 0x1BE + 16 * (part - 1);
        if (!m.aspi && !vol_in_driver && m.bios == 0x80 && e[4] != 0x07 && fat_type(e[4]) && boot_drive() == 3) {
            for (i = 0; i < 4 && !fat_type(mbr[0x1C2 + 16 * i]); ++i) ;
            if (i == part - 1) { printf("Partition %u of disk 80h is the boot drive C:.\n", part); return 2; }
        }
        vstart = rd32(e + 8);
        size = rd32(e + 12);
        if (!e[4] || !size || vstart + size > m.capacity || vstart + size < vstart) {
            printf("Partition %u is empty or larger than the medium.\n", part); return 2;
        }
    } else {
        vstart = 0;
        size = m.capacity;
    }
    f.sectors = size; f.hidden = vstart; f.cluster = csz;
    _dos_getdate(&dd);
    _dos_gettime(&dt);
    f.serial = ((oa_u32)(dd.day | dd.month << 8) + (dt.second | dt.hsecond << 8)) << 16
             | (oa_u16)((dt.hour << 8 | dt.minute) + dd.year);
    if (oa_exfmt_layout(&f)) {
        printf("No exFAT for %lu sectors with this cluster size.\n", (unsigned long)size); return 2;
    }
    if (m.aspi) printf("ASPI unit %u", m.unit);
    else printf("BIOS disk %02Xh", m.bios);
    if (part) printf(", partition %u (type %02Xh)", part, e[4]);
    else printf(", whole medium");
    printf(": %lu sectors at sector %lu, %lu MB\n", (unsigned long)size, (unsigned long)vstart, (unsigned long)(size >> 11));
    printf("exFAT%s: %lu clusters of %lu bytes, FAT %lu sectors at %lu, data at %lu\n",
           f.nfats == 2 ? " (TexFAT, 2 FATs)" : "", (unsigned long)f.clusters, 512UL << f.cshift,
           (unsigned long)f.fat_len, (unsigned long)f.fat_off, (unsigned long)f.heap);
    if (!yes) { puts("Layout only. Add /YES to format; all data of the volume will be lost."); return 0; }
    if (!(buf = _fmalloc(NBUF * 512))) { printf("Not enough memory.\n"); return 2; }
    /* the surface: read the data area, bad clusters in the list */
    if (!quick) {
        n = f.sectors - f.heap;
        for (lba = 0; lba < n; lba += j) {
            j = n - lba < NBUF ? (unsigned)(n - lba) : NBUF;
            if ((lba & 0x3FFF) < j) printf("\rReading the surface: %3lu%%", (unsigned long)(lba / (n / 100 + 1)));
            if (!io(0, vstart + f.heap + lba, j, buf)) continue;
            for (i = 0; i < j; ++i) {
                if (!io(0, vstart + f.heap + lba + i, 1, buf)) continue;
                c = 2 + ((lba + i) >> f.cshift);
                if (c >= f.clusters + 2 || (nbad && bad[nbad - 1] == c)) continue;
                if (nbad == OA_EXFMT_MAXBAD) { printf("\nMore than %u bad clusters.\n", OA_EXFMT_MAXBAD); return 1; }
                bad[nbad++] = c;
            }
        }
        printf("\rReading the surface: done, %u bad clusters\n", nbad);
    }
    printf("Writing the file system...\n");
    {                                           /* DOS's buffers of the old volume out */
        union REGS r;
        r.h.ah = 0x0D;
        intdos(&r, &r);
    }
    if (e && e[4] != 0x07) {                    /* the partition type: exFAT */
        e[4] = 0x07;
        if (io(1, 0, 1, (void __far *)mbr)) { printf("Write error in the MBR.\n"); return 3; }
    }
    rc = oa_exfmt_write(&f, vol_write, 0, bad, nbad, buf, NBUF);
    if (rc) {
        printf(rc == -2 ? "Bad clusters where the file system must go.\n" : "Write error.\n");
        return rc == -2 ? 1 : 3;
    }
    /* EXFAT.SYS and ASPIDSK/ASPIFDD read the volume again */
    if (vol_in_driver) {
        if (!m.aspi) *(oa_u32 __far *)(vol_in_driver + offsetof(struct oa_exfatsys_vol, start)) = vstart;
        vol_in_driver[(unsigned)offsetof(struct oa_exfatsys_vol, changed)] = 1;
    }
    if (m.aspi) aspi_call(SVC_RELOAD, &k);
    {
        union REGS r;
        r.h.ah = 0x0D;
        intdos(&r, &r);
    }
    printf("Serial number %04lX-%04lX\n", (unsigned long)(f.serial >> 16), (unsigned long)(f.serial & 0xFFFF));
    printf("%10lu KB total\n%10lu KB in bad clusters\n", (unsigned long)(f.clusters << f.cshift >> 1),
           (unsigned long)((oa_u32)nbad << f.cshift >> 1));
    if (!vol_in_driver && !m.aspi) puts("Restart the computer for EXFAT.SYS to find the new volume.");
    else if (m.aspi && !(k.count & 0x80)) puts("The drive does not see the new volume yet.");
    puts("Format complete.");
    return 0;
}
