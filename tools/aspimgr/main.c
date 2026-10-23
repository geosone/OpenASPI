/* ASPIMGR: shared QUILIB DOS interface for the OpenASPI suite. GPL-3.0. */
#include <stdio.h>
#include <string.h>
#include <dos.h>
#include <i86.h>
#include <commfunc.h>
#include <input.h>
#include <libcolor.h>
#include <screen.h>
#include <ui.h>
#include <video.h>
#include <windowfn.h>
#include "openaspi/aspi.h"

#define MAX_ROWS 256
#ifdef LANG_GR
#define TEXT(en, de) de
#else
#define TEXT(en, de) en
#endif

struct row {
    unsigned char host, target, lun, type, removable, status;
    unsigned char adapter;
    unsigned extensions;
    char vendor[17], product[17], revision[5];
};
static struct row rows[MAX_ROWS];
static unsigned count, selected, adapters, devices, truncated;
static int scan_error;
static void (__far *entry)(void);
static union {
    struct oa_aspi_header header;
    struct oa_aspi_ha_inquiry ha;
    struct oa_aspi_get_device_type type;
    struct oa_aspi_exec_scsi exec;
} request;
static unsigned char inquiry[36];
extern void __far __cdecl aspi_submit(void (__far *)(void), void __far *);

static void submit(void)
{
    aspi_submit(entry, &request);
    /* The ASPI manager owns command timeout handling. Never reuse a pending
       SRB or its transfer buffer while an asynchronous manager still owns it. */
    while (((volatile struct oa_aspi_header *)&request)->status == OA_ASPI_PENDING)
        ;
}

static int open_manager(void)
{
    int handle;
    union REGS r;
    struct SREGS s;
    int ok;
    entry = 0;
    if (_dos_open("SCSIMGR$", 0, &handle)) return 0;
    memset(&r, 0, sizeof(r));
    segread(&s);
    r.x.ax = 0x4402; r.x.bx = handle; r.x.cx = 4;
    r.x.dx = FP_OFF(&entry); s.ds = FP_SEG(&entry);
    intdosx(&r, &r, &s);
    ok = !r.x.cflag && r.x.ax == 4 && entry != 0;
    _dos_close(handle);
    return ok;
}

static void identity(char *out, const unsigned char *in, unsigned size)
{
    unsigned i;
    for (i = 0; i < size; ++i)
        out[i] = in[i] >= 32 && in[i] < 127 ? in[i] : '?';
    while (size && out[size - 1] == ' ') --size;
    out[size] = 0;
}

static struct row *add_row(unsigned host, int adapter)
{
    struct row *p;
    if (count == MAX_ROWS) { truncated = 1; return 0; }
    p = &rows[count++];
    memset(p, 0, sizeof(*p));
    p->host = (unsigned char)host;
    p->adapter = (unsigned char)adapter;
    return p;
}

static void scan(void)
{
    unsigned h, t, l, hosts, targets, initiator;
    struct row *p;
    count = selected = adapters = devices = truncated = 0;
    scan_error = 0;
    if (!open_manager()) { scan_error = 1; return; }
    memset(&request, 0, sizeof(request));
    request.header.command = OA_ASPI_HA_INQUIRY;
    submit();
    if (request.header.status != OA_ASPI_COMPLETE) { scan_error = 2; return; }
    hosts = request.ha.adapter_count;
    if (!hosts) { scan_error = 2; return; }
    for (h = 0; h < hosts; ++h) {
        memset(&request, 0, sizeof(request));
        request.header.command = OA_ASPI_HA_INQUIRY;
        request.header.host_adapter = (oa_u8)h;
        submit();
        if (request.header.status != OA_ASPI_COMPLETE) { scan_error = 2; continue; }
        ++adapters;
        targets = request.ha.unique[3];
        if (!targets || targets > 32) targets = 8;
        initiator = request.ha.adapter_scsi_id;
        p = add_row(h, 1);
        if (!p) return;
        p->target = (unsigned char)initiator;
        p->extensions = request.ha.extension_flags;
        identity(p->vendor, request.ha.manager_id, 16);
        identity(p->product, request.ha.identifier, 16);
        for (t = 0; t < targets; ++t) {
            if (t == initiator) continue;
            for (l = 0; l < 8; ++l) {
                memset(&request, 0, sizeof(request));
                request.header.command = OA_ASPI_GET_DEVICE_TYPE;
                request.header.host_adapter = (oa_u8)h;
                request.type.target = (oa_u8)t; request.type.lun = (oa_u8)l;
                submit();
                if (request.header.status != OA_ASPI_COMPLETE) continue;
                p = add_row(h, 0);
                if (!p) return;
                ++devices;
                p->target = (unsigned char)t; p->lun = (unsigned char)l;
                p->type = request.type.device_type & 31;
                memset(&request, 0, sizeof(request));
                memset(inquiry, 0, sizeof(inquiry));
                request.header.command = OA_ASPI_EXEC_SCSI;
                request.header.host_adapter = (oa_u8)h;
                request.header.flags = OA_ASPI_DIRECTION_IN;
                request.exec.target = (oa_u8)t; request.exec.lun = (oa_u8)l;
                request.exec.buffer_length = sizeof(inquiry);
                request.exec.buffer.offset = FP_OFF(inquiry);
                request.exec.buffer.segment = FP_SEG(inquiry);
                request.exec.sense_length = 18;
                request.exec.cdb_length = 6;
                request.exec.cdb[0] = 0x12;
                request.exec.cdb[1] = (oa_u8)(l << 5);
                request.exec.cdb[4] = sizeof(inquiry);
                submit();
                p->status = request.header.status;
                if (p->status == OA_ASPI_COMPLETE &&
                    !request.exec.ha_status && !request.exec.target_status) {
                    p->removable = !!(inquiry[1] & 0x80);
                    identity(p->vendor, inquiry + 8, 8);
                    identity(p->product, inquiry + 16, 16);
                    identity(p->revision, inquiry + 32, 4);
                } else strcpy(p->product, TEXT("INQUIRY failed", "INQUIRY Fehler"));
            }
        }
    }
}

static const char *kind(const struct row *p)
{
    if (p->adapter) return "HA";
    if (p->type == OA_ASPI_DEVICE_TAPE) return "TAPE";
    if (p->type == OA_ASPI_DEVICE_CDA) return "CD/DVD";
    if (p->type == OA_ASPI_DEVICE_DISK) return p->removable ? "FDD/RM" : "DISK";
    if (p->type == 8) return "CHANGER";
    return TEXT("OTHER", "ANDERE");
}

static void put_line(WINDESC *panel, int row, const char *text, char color)
{
    WINDESC line = *panel;
    unsigned length = strlen(text);
    line.row += row; line.col += 2; line.nrows = 1; line.ncols -= 4;
    if (length < (unsigned)line.ncols) line.ncols = (int)length;
    if (line.ncols > 0) wput_csa(&line, (char *)text, color);
}

void abortprep(int flag)
{
    WINDESC screen;
    (void)flag;
    end_input();
    SETWINDOW(&screen, 0, 0, ScreenSize.row, ScreenSize.col);
    wput_sca(&screen, VIDWORD(7, ' '));
    move_cursor(0, 0); show_cursor();
}

static void draw(void)
{
    unsigned i, first = selected / 8 * 8;
    char line[100];
    const struct row *p;
    paintBackgroundScreen();
    put_line(&DataWin, 0, "OpenASPI - ASPI Manager", DataYellowColor);
    sprintf(line, TEXT("Adapters: %u  Devices: %u", "Adapter: %u  Geraete: %u"), adapters, devices);
    put_line(&DataWin, 2, line, DataColor);
    if (scan_error) put_line(&DataWin, 3, scan_error == 1 ?
        TEXT("No ASPI manager (SCSIMGR$)", "Kein ASPI-Manager (SCSIMGR$)") :
        TEXT("Adapter query failed", "Adapterabfrage fehlgeschlagen"), DataYellowColor);
    if (truncated) put_line(&DataWin, 3, TEXT("List full (256 entries)", "Liste voll (256 Eintraege)"), DataYellowColor);
    for (i = first; i < count && i < first + 8; ++i) {
        p = &rows[i];
        sprintf(line, "%c %02X:%02X:%02X %-7s %.24s", i == selected ? '>' : ' ',
                p->host, p->target, p->lun, kind(p), p->product);
        put_line(&DataWin, 5 + (int)(i - first), line, i == selected ? DataYellowColor : DataColor);
    }
    if (count) {
        p = &rows[selected];
        sprintf(line, "%s: %.16s", TEXT("Vendor/manager", "Hersteller/Manager"), p->vendor);
        put_line(&DataWin, 14, line, DataColor);
        sprintf(line, "%s: %.16s", TEXT("Product/adapter", "Produkt/Adapter"), p->product);
        put_line(&DataWin, 15, line, DataColor);
        if (p->adapter) sprintf(line, "ASPI extensions: %04X  initiator: %02X", p->extensions, p->target);
        else sprintf(line, "Type: %02X  Rev: %.4s  RMB: %u  SRB: %02X", p->type, p->revision, p->removable, p->status);
        put_line(&DataWin, 16, line, DataColor);
    }
    put_line(&QuickWin, 1, TEXT("ASPI information", "ASPI-Informationen"), QuickBackColor);
    put_line(&QuickWin, 3, TEXT("Up/Down: select", "Pfeile: Auswahl"), QuickBackColor);
    put_line(&QuickWin, 5, TEXT("R: rescan", "R: neu suchen"), QuickBackColor);
    put_line(&QuickWin, 7, TEXT("Esc: exit", "Esc: beenden"), QuickBackColor);
    put_line(&QuickWin, 10, TEXT("Read-only scan", "Nur Infoabfrage"), QuickBackColor);
}

int main(int argc, char **argv)
{
    INPUTEVENT event;
    unsigned i;
    int text = argc == 2 && !stricmp(argv[1], "/TEXT");
    if (argc > 1 && !text) {
        puts("ASPIMGR [/TEXT]"); return 2;
    }
    scan();
    if (text) {
        printf("OpenASPI ASPI Manager\nAdapters: %u Devices: %u Error: %d Truncated: %u\n",
               adapters, devices, scan_error, truncated);
        for (i = 0; i < count; ++i)
            printf("%02X:%02X:%02X %-7s %s | %s | %s\n", rows[i].host,
                   rows[i].target, rows[i].lun, kind(&rows[i]), rows[i].vendor,
                   rows[i].product, rows[i].revision);
        return scan_error || truncated ? 2 : 0;
    }
    initializeScreenInfo(FALSE); init_input(NULL); hide_cursor();
    for (;;) {
        draw();
        if (!get_input(INPUT_WAIT, &event)) continue;
        if (event.key == KEY_ESCAPE) break;
        if (event.key == KEY_DOWN && selected + 1 < count) ++selected;
        if (event.key == KEY_UP && selected) --selected;
        if (event.key == 'r' || event.key == 'R') scan();
    }
    abortprep(0);
    return scan_error || truncated ? 2 : 0;
}
