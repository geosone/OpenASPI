/* Compile-only checks for the actual 16-bit DOS C compiler. */
#include <stddef.h>
#include "openaspi/aspitape.h"

typedef char oa_check_mtop[sizeof(struct oa_aspitape_mtop) == 6 ? 1 : -1];
typedef char oa_check_mtget[sizeof(struct oa_aspitape_mtget) == 14 ? 1 : -1];
typedef char oa_check_mtget16[sizeof(struct oa_aspitape_mtget16) == 16 ? 1 : -1];
typedef char oa_check_error[
    offsetof(struct oa_aspitape_mtget16, driver_error) == 7 ? 1 : -1];
typedef char oa_check_status[
    offsetof(struct oa_aspitape_mtget16, last_scsi_status) == 10 ? 1 : -1];
typedef char oa_check_residual[
    offsetof(struct oa_aspitape_mtget16, residual_bytes) == 14 ? 1 : -1];
