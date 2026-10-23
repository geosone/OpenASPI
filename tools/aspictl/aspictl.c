/* Drive-letter front end: use MSCDEX/SHSUCDX requests for CDs and DOS generic
 * block IOCTLs for removable disks. The driver owns SCSI transport and device
 * policy. commands.def is the common command-name registry for both ASPICTL
 * subcommands and renamed/copied executable aliases. /FORCE releases accepted
 * locks before EJECT; every unlock/eject must still report DONE without ERROR.
 */

/* DOS drive-letter media controls. The same binary supports EJECT/CLOSE
 * aliases via argv[0]; no ASPI transport or device policy is duplicated.
 * GPL-3.0. */
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <dos.h>
#include <i86.h>

static unsigned char packet[32], control[5];
static int known_command(const char *name)
{
#define OA_COMMAND(command) if (!stricmp(name, #command)) return 1;
#include "commands.def"
#undef OA_COMMAND
    return 0;
}

/* Strip directory/drive and the extension, preserving DOS's 8-character
 * basename. A registered basename is equivalent to an ASPICTL subcommand.
 */
static const char *invoked_name(char *out, const char *path)
{
    const char *p, *base = path;
    unsigned i;
    for (p = path; *p; ++p)
        if (*p == '\\' || *p == '/' || *p == ':') base = p + 1;
    for (i = 0; i < 8 && base[i] && base[i] != '.'; ++i)
        out[i] = (char)toupper((unsigned char)base[i]);
    out[i] = 0;
    return out;
}

static int is_cd(unsigned drive)
{
    union REGS r;
    memset(&r, 0, sizeof(r));
    r.x.ax = 0x150B; r.x.cx = drive;
    int86(0x2F, &r, &r);
    return r.x.bx == 0xADAD && r.x.ax != 0;
}

/* MSCDEX driver request packet: command 03h reads IOCTL state, 0Ch writes
 * control. The far pointer targets a separate control block. Return the DOS
 * driver status word; neither a clear ERROR bit nor DONE alone proves success.
 */
static unsigned cd_control(unsigned drive, const char *operation)
{
    union REGS r;
    struct SREGS s;
    unsigned length = 1, cmd = 0x0C;
    memset(packet, 0, sizeof(packet));
    memset(control, 0, sizeof(control));
    if (!stricmp(operation, "CLOSE")) control[0] = 5;
    else if (!stricmp(operation, "LOCK") || !stricmp(operation, "UNLOCK")) {
        control[0] = 1; control[1] = !stricmp(operation, "LOCK"); length = 2;
    } else if (!stricmp(operation, "STATUS")) {
        cmd = 3; control[0] = 6; length = 5;
    }
    packet[0] = sizeof(packet); packet[2] = (unsigned char)cmd;
    *(unsigned *)(packet + 0x0E) = FP_OFF(control);
    *(unsigned *)(packet + 0x10) = FP_SEG(control);
    *(unsigned *)(packet + 0x12) = length;
    memset(&r, 0, sizeof(r)); segread(&s);
    r.x.ax = 0x1510; r.x.cx = drive;
    r.x.bx = FP_OFF(packet); s.es = FP_SEG(packet);
    int86x(0x2F, &r, &r, &s);
    return *(unsigned *)(packet + 3);
}

/* DOS block IOCTL uses one-based drive numbers, unlike MSCDEX's zero-based
 * CX. Normalize carry/AX to a DONE/ERROR status for the shared result path.
 */
static unsigned block_control(unsigned drive, const char *operation)
{
    union REGS r;
    struct SREGS s;
    memset(&r, 0, sizeof(r)); segread(&s);
    control[0] = !stricmp(operation, "LOCK") ? 0 :
                 !stricmp(operation, "UNLOCK") ? 1 : 2;
    control[1] = 0;
    r.x.ax = 0x440D; r.x.bx = drive + 1;
    r.x.cx = !stricmp(operation, "EJECT") ? 0x0849 : 0x0848;
    r.x.dx = FP_OFF(control); s.ds = FP_SEG(control);
    intdosx(&r, &r, &s);
    return r.x.cflag ? 0x8100 | (r.x.ax & 0xFF) : 0x0100;
}

int main(int argc, char **argv)
{
    const char *operation, *letter;
    char name[9];
    unsigned drive, status;
    int cd, force = 0;
    unsigned locks;
    invoked_name(name, argv[0]);
    if (argc > 1 && !stricmp(argv[argc - 1], "/FORCE")) {
        force = 1; --argc;
    }
    if (known_command(name) && argc == 2) {
        operation = name; letter = argv[1];
    } else if (argc == 3 && !strcmp(name, "ASPICTL")) {
        operation = argv[1]; letter = argv[2];
    } else goto usage;
    if (strlen(letter) != 2 || letter[1] != ':' ||
        toupper((unsigned char)letter[0]) < 'A' ||
        toupper((unsigned char)letter[0]) > 'Z') goto usage;
    if (!known_command(operation)) goto usage;
    if (force && stricmp(operation, "EJECT")) goto usage;
    drive = (unsigned)(toupper((unsigned char)letter[0]) - 'A');
    cd = is_cd(drive);
    if (!cd && !stricmp(operation, "CLOSE")) {
        puts("CLOSE requires an MSCDEX/SHSUCDX CD drive."); return 2;
    }
    if (!cd && !stricmp(operation, "EJECT")) {
        union REGS r;
        memset(&r, 0, sizeof(r)); r.h.ah = 0x0D;
        intdos(&r, &r);                    /* flush DOS filesystem buffers */
    }
    if (force) {
        if (cd) {
            status = cd_control(drive, "UNLOCK");
            if (status & 0x8000 || !(status & 0x0100)) goto result;
        } else {
            status = block_control(drive, "STATUS");
            if (status & 0x8000 || !(status & 0x0100)) goto result;
            locks = control[1];
            while (locks--) {
                status = block_control(drive, "UNLOCK");
                if (status & 0x8000 || !(status & 0x0100)) goto result;
            }
        }
    }
    status = cd ? cd_control(drive, operation) : block_control(drive, operation);
result:
    if (!(status & 0x0100) || (status & 0x8000)) {
        printf("%s %c: failed (status %04X).\n", operation, 'A' + drive, status);
        return 1;
    }
    printf("%s %c: OK (%s)", operation, 'A' + drive, cd ? "CD" : "removable");
    if (!stricmp(operation, "STATUS")) {
        if (cd) printf(" status=%04X%04X", *(unsigned *)(control + 3), *(unsigned *)(control + 1));
        else printf(" locks=%u", control[1]);
    }
    puts(""); return 0;
usage:
    puts("ASPICTL EJECT|CLOSE|LOCK|UNLOCK|STATUS X:");
    puts("Each command also works as COMMAND.EXE X:");
    puts("EJECT accepts /FORCE to release media locks first.");
    return 2;
}
