/* ASPIDD UI boundary: zero-based drive numbers; sector progress is not bytes.
 * Selection/confirmation/exchange return user decisions; progress returns a
 * cancellation request. The copy engine retains all raw-media ownership and
 * error policy. Pair screen setup with teardown, including failure paths.
 */

#ifndef OA_COPY_UI_H
#define OA_COPY_UI_H
#include "openaspi/types.h"
/* Selection writes source/target (A=0) and rescue toggle. Return 0 to start,
 * -1 to cancel. Confirmation returns 1=yes, 0=no. Neither opens a raw session.
 */
int dd_ui_select(unsigned *,unsigned *,int *);
int dd_ui_confirm(unsigned,unsigned);
/* Screen lifecycle; stop is safe after an earlier teardown. These functions
 * do not close the copy engine's files, map or media sessions.
 */
void dd_ui_start(void);
void dd_ui_stop(void);
/* Map/file paths are copied into bounded display storage (possibly shortened);
 * this never changes the engine's full path. Device index 26 means file/image.
 */
void dd_ui_map(const char *);
void dd_ui_file(const char *);
void dd_ui_devices(unsigned,unsigned);
/* Begin a progress phase (sector total). The label pointer is borrowed and
 * must remain alive while displayed; progress returns -1 for Escape, else 0.
 */
void dd_ui_phase(const char *,unsigned,oa_u32);
int dd_ui_progress(oa_u32,oa_u32);
/* Synchronous media-swap prompt returns DOS-style Enter=13 or Escape=27;
 * the caller has already released the source and decides whether to acquire
 * the target. finish displays rc=0 clean, rc=3 rescue gaps, other rc incomplete,
 * waits for dismissal and tears down the screen.
 */
int dd_ui_exchange(unsigned);
void dd_ui_finish(int,oa_u32);
#endif
