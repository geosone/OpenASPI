/* Read-only native OTAP QUERY client for DOS, distinct from legacy TAPECTL.
 * Default is a session snapshot; /REFRESH explicitly requests read-only probes.
 * Accept raw no-rewind device aliases and verify a character handle before the
 * IOCTL, so inspection/close does not introduce rewind or buffered close effects.
 * Validate the reply before reading optional facts; unknown is not unsupported.
 * Temporarily fail DOS critical errors, close every acquired handle and restore
 * the old INT 24h handler. Exit 0=complete, 2=partial/busy/saved write error,
 * 1=usage, delivery, validation or output failure.
 */

#include <dos.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include "openaspi/tape_api.h"

static int __far fail(unsigned device, unsigned error, unsigned __far *header)
{
    (void)device; (void)error; (void)header;
    return _HARDERR_FAIL;
}

/* Restrict open to NR?T0..3 aliases (optional trailing $). DOS also allows
 * ordinary files to be opened by name; the handle check below rejects those.
 */
static int name_valid(const char *s)
{
    unsigned i, n = (unsigned)strlen(s);
    char name[7];
    if (n != 5u && n != 6u) return 0;
    for (i = 0; i < n; ++i) name[i] = s[i] >= 'a' && s[i] <= 'z' ? s[i]-'a'+'A' : s[i];
    return name[0] == 'N' && name[1] == 'R' && name[2] >= 'A' && name[2] <= 'Z' &&
           name[3] == 'T' && name[4] >= '0' && name[4] <= '3' &&
           (n == 5u || name[5] == '$');
}

int main(int argc, char **argv)
{
    const char *name = "NRMT0";
    struct ot_tape_info_v1 info;
    union REGS in, out;
    struct SREGS segments;
    void (__interrupt __far *old24)(void);
    unsigned flags = 0u, error, close_error;
    int handle, i, seen_name = 0, rc = 1, feature;
    for (i = 1; i < argc; ++i) {
        if (stricmp(argv[i], "/REFRESH") == 0 && flags == 0u) flags = OT_TAPE_API_REFRESH;
        else if (!seen_name && name_valid(argv[i])) { name = argv[i]; seen_name = 1; }
        else { puts("OTAPINFO [NRMT0] [/REFRESH]"); return 1; }
    }
    ot_tape_info_init(&info, (oa_u16)flags);
    old24 = _dos_getvect(0x24);
    _harderr(fail);
    error = _dos_open(name, O_RDONLY, &handle);
    if (error != 0u) goto done;
    memset(&in, 0, sizeof(in));
    in.x.ax = 0x4400u;
    in.x.bx = (unsigned)handle;
    intdos(&in, &out);
    error = out.x.cflag ? out.x.ax : 0u;
    if (error == 0u && (out.x.dx & 0x80u) == 0u) error = 1u;
    if (error == 0u) {
        segread(&segments);
        memset(&in, 0, sizeof(in));
        in.x.ax = 0x440cu;
        in.x.bx = (unsigned)handle;
        in.x.cx = OT_TAPE_API_CATEGORY << 8;
        in.x.dx = FP_OFF(&info);
        segments.ds = FP_SEG(&info);
        intdosx(&in, &out, &segments);
        error = out.x.cflag ? out.x.ax : 0u;
        if (error == 0u && (ot_tape_info_validate(&info, sizeof(info)) != 0 || info.flags != flags)) {
            puts("Invalid native tape API response.");
            error = 1u;
        }
    }
    close_error = _dos_close(handle);
    if (error == 0u) error = close_error;
    if (error != 0u) goto done;
    printf("Native tape API %04X result=%u valid=%08lX session=%04X\n",
        info.version, info.result, (unsigned long)info.valid_fields, info.session_state);
    if ((info.valid_fields & OT_TAPE_VALID_IDENTITY) != 0UL)
        printf("Device: %.8s %.16s %.4s\n", (const char *)info.vendor,
            (const char *)info.product, (const char *)info.revision);
    if ((info.valid_fields & OT_TAPE_VALID_LIMITS) != 0UL) {
        if (info.maximum_block == 0UL)
            printf("Record minimum: %lu bytes; maximum unspecified\n", (unsigned long)info.minimum_block);
        else printf("Record limits: %lu..%lu bytes\n", (unsigned long)info.minimum_block,
            (unsigned long)info.maximum_block);
        printf("Record size step from minimum: %lu bytes\n", (unsigned long)info.block_granularity);
    }
    if ((info.valid_fields & OT_TAPE_VALID_BLOCK) != 0UL)
        printf("Current block: %lu bytes (0=variable)\n", (unsigned long)info.current_block);
    feature = ot_tape_info_feature(&info, OT_TAPE_FEATURE_COMPRESSION);
    printf("Hardware compression: %s\n", feature < 0 ? "unknown" : feature ? "supported" : "unsupported");
    if (info.diagnostic_class != 0u)
        printf("Diagnostic: class=%u host=%02X target=%02X sense=%02X ASC/ASCQ=%02X/%02X\n",
            info.diagnostic_class, info.host_status, info.target_status, info.sense_key, info.asc, info.ascq);
    if (info.probe_flags != 0UL) puts("Probe byte counts are unverified by the legacy ASPI manager.");
    rc = info.result == OT_TAPE_RESULT_OK ? 0 : 2;
    if ((info.session_state & OT_TAPE_SESSION_WRITE_ERROR) != 0u) {
        puts("Saved write/finalization failure is present; inspect TAPECTL diagnostics.");
        rc = 2;
    }
    if (fflush(stdout) != 0 || ferror(stdout)) rc = 1;
done:
    _dos_setvect(0x24, old24);
    if (error != 0u) printf("Native tape query failed (DOS %u).\n", error);
    return rc;
}
