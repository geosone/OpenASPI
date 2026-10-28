/* LFNTEST: the long file name calls (INT 21h AX=71xxh) for the DOS tests
   of EXFAT.SYS; one line per result, "error n" for a failed call.
   LFNTEST DIR pattern | TRUE path | CD dir | TYPE file | ATTR path |
           VOL X:\ | DEL file | MD dir | INFO file | LEAK pattern */
#include <stdio.h>
#include <string.h>
#include <dos.h>
#include <i86.h>

static char fd[318], buf[300];
static unsigned char info[52];

static int call(union REGS *r, struct SREGS *s)
{
    r->x.cflag = 1;
    intdosx(r, r, s);
    if (r->x.cflag || r->x.ax == 0x7100) { printf("error %u\n", r->x.cflag ? r->x.ax : 0x7100); return -1; }
    return 0;
}

static void show(void)
{
    unsigned long size = *(unsigned long *)(fd + 32);
    printf("%s|%s|%02X|%lu|%04X%04X\n", fd + 44, fd + 304, (unsigned char)fd[0], size,
           *(unsigned *)(fd + 22), *(unsigned *)(fd + 20));
}

int main(int argc, char **argv)
{
    union REGS r;
    struct SREGS s;
    const char *op = argc > 1 ? argv[1] : "", *arg = argc > 2 ? argv[2] : "";
    unsigned h, i, n;
    segread(&s);
    s.es = s.ds;                        /* ES:DI buffers */
    memset(&r, 0, sizeof(r));
    if (!strcmp(op, "DIR")) {
        r.x.ax = 0x714E; r.x.cx = 0x0016; r.x.si = 1;
        r.x.dx = (unsigned)arg; r.x.di = (unsigned)fd;
        if (call(&r, &s)) return 1;
        h = r.x.ax;
        do {
            show();
            memset(&r, 0, sizeof(r));
            r.x.ax = 0x714F; r.x.bx = h; r.x.si = 1; r.x.di = (unsigned)fd;
            r.x.cflag = 1;
            intdosx(&r, &r, &s);
        } while (!r.x.cflag);
        printf("end %u\n", r.x.ax);
        r.x.ax = 0x71A1; r.x.bx = h;
        return call(&r, &s) ? 1 : 0;
    }
    if (!strcmp(op, "TRUE")) {
        for (i = 0; i < 3; ++i) {
            memset(&r, 0, sizeof(r));
            r.x.ax = 0x7160; r.x.cx = i; r.x.si = (unsigned)arg; r.x.di = (unsigned)buf;
            if (!call(&r, &s)) printf("%u %s\n", i, buf);
        }
        return 0;
    }
    if (!strcmp(op, "CD")) {
        r.x.ax = 0x713B; r.x.dx = (unsigned)arg;
        if (call(&r, &s)) return 1;
        memset(&r, 0, sizeof(r));
        r.x.ax = 0x7147; r.x.si = (unsigned)buf;
        if (arg[0] && arg[1] == ':') r.h.dl = (unsigned char)((arg[0] | 0x20) - 'a' + 1);
        if (call(&r, &s)) return 1;
        printf("cwd \\%s\n", buf);
        return 0;
    }
    if (!strcmp(op, "TYPE")) {
        r.x.ax = 0x716C; r.x.bx = 0; r.x.dx = 1; r.x.si = (unsigned)arg;
        if (call(&r, &s)) return 1;
        h = r.x.ax;
        printf("action %u\n", r.x.cx);
        memset(&r, 0, sizeof(r));
        r.h.ah = 0x3F; r.x.bx = h; r.x.cx = sizeof(buf) - 1; r.x.dx = (unsigned)buf;
        if (call(&r, &s)) return 1;
        n = r.x.ax; buf[n] = 0;
        printf("read %u: %s", n, buf);
        r.h.ah = 0x3E; r.x.bx = h;
        intdosx(&r, &r, &s);
        return 0;
    }
    if (!strcmp(op, "ATTR")) {
        r.x.ax = 0x7143; r.x.bx = 0; r.x.dx = (unsigned)arg;
        if (call(&r, &s)) return 1;
        printf("attr %02X\n", r.x.cx);
        memset(&r, 0, sizeof(r));
        r.x.ax = 0x7143; r.x.bx = 2; r.x.dx = (unsigned)arg;
        if (call(&r, &s)) return 1;
        printf("size %lu\n", (unsigned long)r.x.dx << 16 | r.x.ax);
        return 0;
    }
    if (!strcmp(op, "INFO")) {          /* 71A6h on a handle opened by long name */
        r.x.ax = 0x716C; r.x.bx = 0; r.x.dx = 1; r.x.si = (unsigned)arg;
        if (call(&r, &s)) return 1;
        h = r.x.ax;
        memset(&r, 0, sizeof(r));
        r.x.ax = 0x71A6; r.x.bx = h; r.x.dx = (unsigned)info;
        if (!call(&r, &s))
            printf("info attr %02X size %lu links %lu serial %08lX time %04X%04X\n", info[0],
                   *(unsigned long *)(info + 0x24), *(unsigned long *)(info + 0x28),
                   *(unsigned long *)(info + 0x1C), *(unsigned *)(info + 0x16), *(unsigned *)(info + 0x14));
        r.h.ah = 0x3E; r.x.bx = h;
        intdosx(&r, &r, &s);
        return 0;
    }
    if (!strcmp(op, "LEAK")) {          /* searches never closed, as by a program that ends */
        for (i = 0; i < 8; ++i) {
            memset(&r, 0, sizeof(r));
            r.x.ax = 0x714E; r.x.cx = 0x0016; r.x.si = 1;
            r.x.dx = (unsigned)arg; r.x.di = (unsigned)fd;
            if (call(&r, &s)) return 1;
        }
        printf("leak %u searches\n", i);
        return 0;
    }
    if (!strcmp(op, "VOL")) {
        r.x.ax = 0x71A0; r.x.cx = sizeof(buf); r.x.dx = (unsigned)arg; r.x.di = (unsigned)buf;
        if (call(&r, &s)) return 1;
        printf("fs %s flags %04X name %u path %u\n", buf, r.x.bx, r.x.cx, r.x.dx);
        return 0;
    }
    if (!strcmp(op, "DEL") || !strcmp(op, "MD")) {
        r.x.ax = op[0] == 'D' ? 0x7141 : 0x7139; r.x.dx = (unsigned)arg;
        if (!call(&r, &s)) printf("done\n");
        return 0;
    }
    printf("LFNTEST DIR|TRUE|CD|TYPE|ATTR|VOL|DEL|MD|INFO|LEAK arg\n");
    return 2;
}
