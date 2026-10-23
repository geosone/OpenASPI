/* DOS client state for the RAW1 block service, not a packed public packet.
 * packet stores the 32-byte wire envelope/token; remaining fields cache results.
 * A=0 drive numbering, physical 512-byte LBAs, 1..32 sectors per I/O call.
 * INFO does not claim; successful OPEN requires CLOSE. Return 0/-1 and inspect
 * error/sense fields on failure. sectors is device capacity; start/length select
 * the FAT volume within it. Callers must not copy or share an active session.
 */

#ifndef OA_RAW_MEDIA_H
#define OA_RAW_MEDIA_H
#include "openaspi/types.h"
struct oa_raw_media {
    unsigned char packet[32];
    unsigned drive, error, active, fat32, sense_key, asc, driver_error;
    oa_u32 sectors, start, length;
    unsigned char address[3];
};
/* Initialize *m and acquire a read/write raw session. Do not call on an
 * already-active instance: initialization would discard its ownership token.
 * A failed open owns no session; a successful one must be ended even after I/O
 * failure. write authorizes raw writes, not an automatic format or erase.
 */
int oa_raw_open(struct oa_raw_media *, unsigned drive, int write);
/* Initialize *m and query capacity/volume/address without claiming a session.
 * As with open, this overwrites instance state; use a separate inactive object
 * when querying while another session must retain its token.
 */
int oa_raw_info(struct oa_raw_media *, unsigned drive);
/* Require an active instance and count*512 bytes of storage. Reject count
 * outside 1..32 or a span beyond device capacity; the provider also checks FAR
 * buffer bounds. READ/WRITE use physical LBAs, including partition metadata.
 */
int oa_raw_io(struct oa_raw_media *, int write, oa_u32 lba, unsigned count, void *);
/* Rescue callback adapter: returns zero or a DOS error, optionally tagged
 * DEVICE_READ after sense qualification. A tag permits bounded rescue attempts;
 * it never means that data were recovered or should be counted as clean.
 */
unsigned oa_raw_read_source(void *,oa_u32,unsigned,void *);
/* End an active session once, clear client active state and reset DOS caches.
 * Return cleanup status; successful cleanup retains preceding I/O diagnostics.
 * After failed END the client still becomes inactive, so error handling must not
 * assume it can resume using the old token.
 */
int oa_raw_close(struct oa_raw_media *);
/* Parse exactly X: into a zero-based drive index. Return 0/-1; on rejection
 * the output is not assigned. This does not check existence or device class.
 */
int oa_drive(const char *, unsigned *);
/* Flush/reset the DOS filesystem view (INT 21h/AH=0Dh), not SCSI hardware.
 * No completion/error result is exposed by this wrapper.
 */
void oa_disk_reset(void);
#endif
