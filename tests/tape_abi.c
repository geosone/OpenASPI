/* Compile-only checks for the actual 16-bit DOS C compiler. */
#include <stddef.h>
#include "openaspi/aspitape.h"
#include "openaspi/tape_api.h"

typedef char ot_check_info[sizeof(struct ot_tape_info_v1) == 128 ? 1 : -1];
typedef char ot_check_valid[offsetof(struct ot_tape_info_v1, valid_fields) == 12 ? 1 : -1];
typedef char ot_check_identity[offsetof(struct ot_tape_info_v1, vendor) == 48 ? 1 : -1];
typedef char ot_check_diag[offsetof(struct ot_tape_info_v1, diagnostic_class) == 78 ? 1 : -1];
typedef char ot_check_probe[offsetof(struct ot_tape_info_v1, probe_flags) == 88 ? 1 : -1];
typedef char ot_check_granularity[offsetof(struct ot_tape_info_v1, block_granularity) == 92 ? 1 : -1];
typedef char ot_check_control[sizeof(struct ot_tape_control_v1) == 64 ? 1 : -1];
typedef char ot_check_completion[offsetof(struct ot_tape_control_v1, completion_flags) == 26 ? 1 : -1];

typedef char oa_check_mtop[sizeof(struct oa_aspitape_mtop) == 6 ? 1 : -1];
typedef char oa_check_mtget[sizeof(struct oa_aspitape_mtget) == 14 ? 1 : -1];
typedef char oa_check_mtget16[sizeof(struct oa_aspitape_mtget16) == 16 ? 1 : -1];
typedef char oa_check_error[
    offsetof(struct oa_aspitape_mtget16, driver_error) == 7 ? 1 : -1];
typedef char oa_check_status[
    offsetof(struct oa_aspitape_mtget16, last_scsi_status) == 10 ? 1 : -1];
typedef char oa_check_residual[
    offsetof(struct oa_aspitape_mtget16, residual_bytes) == 14 ? 1 : -1];

typedef char ot_check_record[sizeof(struct ot_tape_record_v1) == 64 ? 1 : -1];
typedef char ot_check_count[offsetof(struct ot_tape_record_v1, requested) == 28 ? 1 : -1];
typedef char ot_check_buffer[offsetof(struct ot_tape_record_v1, buffer_offset) == 40 ? 1 : -1];

typedef char ot_check_control_block[offsetof(struct ot_tape_control_v1, block_size) == 28 ? 1 : -1];
typedef char ot_check_record_block[offsetof(struct ot_tape_record_v1, block_size) == 44 ? 1 : -1];

typedef char ot_check_space_count[offsetof(struct ot_tape_control_v1, count) == 32 ? 1 : -1];
typedef char ot_check_control_reserved[offsetof(struct ot_tape_control_v1, reserved) == 36 ? 1 : -1];

typedef char ot_check_position[sizeof(struct ot_tape_position_v1)==64 ? 1 : -1];
typedef char ot_check_position_valid[offsetof(struct ot_tape_position_v1,valid_fields)==28 ? 1 : -1];
typedef char ot_check_position_first[offsetof(struct ot_tape_position_v1,first_block)==36 ? 1 : -1];
typedef char ot_check_position_probe[offsetof(struct ot_tape_position_v1,probe_flags)==48 ? 1 : -1];

typedef char ot_check_locate[sizeof(struct ot_tape_locate_v1)==64 ? 1 : -1];
typedef char ot_check_locate_block[offsetof(struct ot_tape_locate_v1,block)==32 ? 1 : -1];

typedef char ot_wide_position[sizeof(struct ot_tape_position64_v1)==64 ? 1 : -1];
typedef char ot_wide_file[offsetof(struct ot_tape_position64_v1,file)==44 ? 1 : -1];
typedef char ot_wide_probe[offsetof(struct ot_tape_position64_v1,probe_flags)==56 ? 1 : -1];
typedef char ot_wide_locate[sizeof(struct ot_tape_locate64_v1)==64 ? 1 : -1];
typedef char ot_wide_high[offsetof(struct ot_tape_locate64_v1,block_high)==36 ? 1 : -1];

/* MODE SENSE partition report uses the same 64-byte native envelope. */
typedef char ot_check_partitions[sizeof(struct ot_tape_partitions_v1)==64 ? 1 : -1];
typedef char ot_check_partitions_valid[offsetof(struct ot_tape_partitions_v1,valid_fields)==28 ? 1 : -1];
typedef char ot_check_partitions_max[offsetof(struct ot_tape_partitions_v1,maximum_additional)==32 ? 1 : -1];
typedef char ot_check_partitions_probe[offsetof(struct ot_tape_partitions_v1,probe_flags)==56 ? 1 : -1];

typedef char ot_check_alerts_size[sizeof(struct ot_tape_alerts_v1)==64 ? 1 : -1];
typedef char ot_check_alerts_reported[offsetof(struct ot_tape_alerts_v1,reported_low)==32 ? 1 : -1];
typedef char ot_check_alerts_active[offsetof(struct ot_tape_alerts_v1,active_low)==40 ? 1 : -1];
typedef char ot_check_alerts_probe[offsetof(struct ot_tape_alerts_v1,probe_flags)==48 ? 1 : -1];
