#ifndef OPENTAPE_NATIVE_TAPE_API_H
#define OPENTAPE_NATIVE_TAPE_API_H

#include "openaspi/types.h"

/* Native OpenTape API: DOS binding, separate from ASPITAPE category 07h.
 * Pointer-free v1 snapshot; other platform bindings marshal their own calls.
 * Initialize the entire packet to zero, then magic/size/version/flags.
 * Successful DOS IOCTL delivery does not imply a complete hardware probe:
 * inspect result, valid_fields and diagnostic_class.
 */
#define OT_TAPE_API_CATEGORY       0x80u
#define OT_TAPE_API_QUERY          0u
#define OT_TAPE_API_CONTROL        1u
#define OT_TAPE_API_READ           2u
#define OT_TAPE_API_WRITE          3u
#define OT_TAPE_API_POSITION       4u
#define OT_TAPE_API_LOCATE         5u
#define OT_TAPE_API_PARTITIONS     6u
#define OT_TAPE_API_ALERTS         7u
#define OT_TAPE_API_ALERTS_SIZE    64u
#define OT_TAPE_ALERTS_ACKNOWLEDGE  1u
#define OT_TAPE_ALERTS_VALID       1UL
#define OT_TAPE_API_PARTITIONS_SIZE 64u
#define OT_TAPE_LAYOUT_VALID       1UL
#define OT_TAPE_API_LOCATE_SIZE    64u
#define OT_TAPE_LOCATE_PARTITION   1u
#define OT_TAPE_API_POSITION_SIZE  64u
#define OT_TAPE_POSITION_VALID    1UL
#define OT_TAPE_API_VERSION        0x0100u
#define OT_TAPE_API_INFO_SIZE      128u
#define OT_TAPE_API_REFRESH        1u

/* Result codes are alternatives, not bits. A well-formed ERROR/BUSY reply
 * can pass validation; successful DOS delivery alone says nothing about result.
 */
#define OT_TAPE_RESULT_OK          0u
#define OT_TAPE_RESULT_PARTIAL     1u
#define OT_TAPE_RESULT_BUSY        2u
#define OT_TAPE_RESULT_ERROR       3u
#define OT_TAPE_RESULT_UNSUPPORTED 4u
#define OT_TAPE_RESULT_STREAM      5u

/* valid_fields gates groups of reported facts. Missing means unknown,
 * not false. operations instead advertises implemented provider entry points;
 * it does not promise that the attached device accepts every operation.
 */
#define OT_TAPE_VALID_IDENTITY     0x0001UL
#define OT_TAPE_VALID_LIMITS       0x0002UL
#define OT_TAPE_VALID_MODE         0x0004UL
#define OT_TAPE_VALID_COMPRESSION  0x0008UL
#define OT_TAPE_VALID_CONFIG       0x0010UL
#define OT_TAPE_VALID_SESSION      0x0020UL
#define OT_TAPE_VALID_BLOCK        0x0040UL
#define OT_TAPE_OP_QUERY           0x0001UL
#define OT_TAPE_OP_READY           0x0002UL
#define OT_TAPE_OP_REWIND          0x0004UL
#define OT_TAPE_OP_READ            0x0008UL
#define OT_TAPE_OP_WRITE           0x0010UL
#define OT_TAPE_OP_BEGIN_WRITE     0x0020UL
#define OT_TAPE_OP_FLUSH           0x0040UL
#define OT_TAPE_OP_FILEMARK        0x0080UL
#define OT_TAPE_OP_END_WRITE       0x0100UL
#define OT_TAPE_OP_ABORT_WRITE     0x0200UL
#define OT_TAPE_OP_FIXED_IO        0x0400UL
#define OT_TAPE_OP_SPACE_RECORDS   0x0800UL
#define OT_TAPE_OP_SPACE_FILEMARKS 0x1000UL
#define OT_TAPE_OP_SPACE_EOD       0x2000UL
#define OT_TAPE_OP_LOAD            0x4000UL
#define OT_TAPE_OP_UNLOAD          0x8000UL
#define OT_TAPE_OP_LOCK            0x10000UL
#define OT_TAPE_OP_UNLOCK          0x20000UL
#define OT_TAPE_OP_POSITION        0x40000UL
#define OT_TAPE_OP_LOCATE          0x80000UL
#define OT_TAPE_OP_POSITION64      0x100000UL
#define OT_TAPE_OP_LOCATE64        0x200000UL
#define OT_TAPE_OP_PARTITIONS      0x400000UL
#define OT_TAPE_OP_SPACE_SEQ_FILEMARKS 0x800000UL
#define OT_TAPE_OP_SPACE_SETMARKS   0x1000000UL
#define OT_TAPE_OP_SPACE_SEQ_SETMARKS 0x2000000UL
#define OT_TAPE_OP_READ_SETMARK    0x4000000UL
#define OT_TAPE_OP_SETMARK         0x8000000UL
#define OT_TAPE_OP_ALERTS          0x10000000UL
#define OT_TAPE_POSITION_FILE_VALID 2UL
/* Separate namespaces: OP_* above are capability bits, CONTROL_* and
 * RECORD_* below are operation enums. FIXED is a request flag in those packets,
 * unrelated to QUERY's numerically equal REFRESH flag.
 */
#define OT_TAPE_IO_FIXED           1u
#define OT_TAPE_CONTROL_READY      0u
#define OT_TAPE_CONTROL_REWIND     1u
#define OT_TAPE_CONTROL_BEGIN_WRITE 2u
#define OT_TAPE_CONTROL_FLUSH      3u
#define OT_TAPE_CONTROL_FILEMARK   4u
#define OT_TAPE_CONTROL_END_WRITE  5u
#define OT_TAPE_CONTROL_ABORT_WRITE 6u
#define OT_TAPE_CONTROL_SPACE_RECORDS 7u
#define OT_TAPE_CONTROL_SPACE_FILEMARKS 8u
#define OT_TAPE_CONTROL_SPACE_EOD 9u
#define OT_TAPE_CONTROL_LOAD      10u
#define OT_TAPE_CONTROL_UNLOAD    11u
#define OT_TAPE_CONTROL_LOCK      12u
#define OT_TAPE_CONTROL_UNLOCK    13u
#define OT_TAPE_CONTROL_SPACE_SEQ_FILEMARKS 14u
#define OT_TAPE_CONTROL_SPACE_SETMARKS 15u
#define OT_TAPE_CONTROL_SPACE_SEQ_SETMARKS 16u
/* One explicit synchronous mark in an owned native writer; count stays zero. */
#define OT_TAPE_CONTROL_SETMARK    17u
#define OT_TAPE_RECORD_READ       0u
#define OT_TAPE_RECORD_WRITE      1u
#define OT_TAPE_API_CONTROL_SIZE   64u
/* Completion facts, not mutually exclusive results. COUNT_VALID qualifies
 * actual; actual=0 without it means unknown. UNKNOWN forbids assuming a known
 * tape position; CLAIMED/RELEASED report native writer ownership changes.
 */
#define OT_TAPE_COMPLETION_SUBMITTED 0x0001u
#define OT_TAPE_COMPLETION_DONE    0x0002u
#define OT_TAPE_POSITION_UNKNOWN   0x0004u
#define OT_TAPE_POSITION_BOT       0x0008u
#define OT_TAPE_COMPLETION_READY   0x0010u
#define OT_TAPE_COUNT_VALID        0x0020u
#define OT_TAPE_COMPLETION_CLAIMED  0x0040u
#define OT_TAPE_COMPLETION_RELEASED 0x0080u
/* Stream observations: SHORT requires a proven actual < requested count.
 * FILEMARK/SETMARK/EOD describe tape boundaries, not filesystem EOF or transport errors.
 * TRUNCATED is data loss and cannot be accepted as a successful boundary.
 */
#define OT_TAPE_STREAM_FILEMARK    0x0001UL
#define OT_TAPE_STREAM_EOM         0x0002UL
#define OT_TAPE_STREAM_ILI         0x0004UL
#define OT_TAPE_STREAM_SHORT       0x0008UL
#define OT_TAPE_STREAM_TRUNCATED   0x0010UL
#define OT_TAPE_STREAM_EOD         0x0020UL
/* The SCSI mark bit alone is ambiguous: current ASC/ASCQ 00/03 identifies a
 * setmark. It never also claims FILEMARK and is not an archive EOF. */
#define OT_TAPE_STREAM_SETMARK     0x0040UL
#define OT_TAPE_API_RECORD_SIZE    64u
#define OT_TAPE_FEATURE_COMPRESSION 0x0001UL
#define OT_TAPE_STATE_COMPRESSION  0x0001UL
#define OT_TAPE_STATE_WRITE_PROTECT 0x0002UL
#define OT_TAPE_STATE_SETMARKS     0x0004UL
#define OT_TAPE_STATE_FIXED       0x0008UL

/* Session facts combine legacy state (low four bits) and native writer
 * ownership/dirty/failure state (next three). These differ from current_state,
 * which describes probed device settings such as compression or fixed mode.
 */
#define OT_TAPE_SESSION_REWINDING  0x0001u
#define OT_TAPE_SESSION_WRITTEN    0x0002u
#define OT_TAPE_SESSION_BUFFERED   0x0004u
#define OT_TAPE_SESSION_WRITE_ERROR 0x0008u
#define OT_TAPE_SESSION_NATIVE_WRITER 0x0010u
#define OT_TAPE_SESSION_NATIVE_DIRTY  0x0020u
#define OT_TAPE_SESSION_NATIVE_FAILED 0x0040u
#define OT_TAPE_TRANSPORT_ASPI     1u

#define OT_TAPE_DIAG_NONE          0u
#define OT_TAPE_DIAG_TRANSPORT     1u
#define OT_TAPE_DIAG_TARGET        2u
#define OT_TAPE_DIAG_MALFORMED     3u
#define OT_TAPE_DIAG_UNSUPPORTED   4u
#define OT_TAPE_DIAG_INCOMPLETE    5u
#define OT_TAPE_PROBE_UNVERIFIED_LENGTH 1UL

#if defined(__WATCOMC__)
#pragma pack(push, 1)
#endif
/* QUERY reply: 128 bytes, little-endian scalar fields, no native pointers.
 * Identity fields are space-padded bytes, never NUL-terminated strings.
 * Initialize reserved storage to zero; consume only groups in valid_fields.
 */
struct ot_tape_info_v1 {
    oa_u8 magic[4];                 /* OTAP */
    oa_u16 size;                    /* bytes, >=128 on input; 128 on output */
    oa_u16 version;
    oa_u16 flags;                   /* zero: snapshot only; REFRESH: probes */
    oa_u16 result;
    oa_u32 valid_fields;
    oa_u32 operations;              /* provider API operations, not HW wishes */
    oa_u32 features_known;
    oa_u32 features_supported;
    oa_u32 current_state;           /* gated by corresponding valid_fields */
    oa_u32 minimum_block;
    oa_u32 maximum_block;
    oa_u32 current_block;
    oa_u8 host_id, target_id, lun, transport;
    oa_u8 vendor[8], product[16], revision[4]; /* fixed width, not C strings */
    oa_u16 session_state;
    oa_u16 diagnostic_class;
    oa_u8 host_status, target_status, sense_key, sense_response;
    oa_u8 asc, ascq;
    oa_u16 reserved_word;
    oa_u32 probe_flags;             /* legacy manager cannot prove byte count */
    oa_u32 block_granularity;       /* n-minimum is a multiple; gated by LIMITS */
    oa_u8 reserved[32];
}
#if !defined(__WATCOMC__)
__attribute__((packed))
#endif
;

/* CONTROL is an in/out 64-byte envelope. BEGIN/ABORT manage ownership;
 * READY/REWIND/FLUSH/FILEMARK/END/SPACE/LOAD/UNLOAD/LOCK/UNLOCK submit CDBs.
 * LOCK/UNLOCK control medium removal, not writer ownership or write protection.
 * block_size occupies a fixed extension slot (offset 28), preserving the
 * original packet size.
 */
struct ot_tape_control_v1 {
    oa_u8 magic[4];
    oa_u16 size, version;
    oa_u16 operation, flags;        /* FIXED allowed only for BEGIN_WRITE */
    oa_u16 result, diagnostic_class;
    oa_u16 session_state;
    oa_u8 scsi_opcode, host_status, target_status, sense_key;
    oa_u8 sense_response, asc, ascq, reserved_byte;
    oa_u16 completion_flags;
    oa_u32 block_size;              /* BEGIN fixed block size, otherwise zero */
    oa_s32 count;                   /* SPACE signed count at 32; otherwise zero */
    oa_u8 reserved[28];
}
#if !defined(__WATCOMC__)
__attribute__((packed))
#endif
;
/* DOS READ/WRITE request/response. The two buffer words are DOS-binding fields;
 * common consumers pass their data buffer separately to the platform adapter.
 * FIXED requests carry block_size and byte counts aligned to that size.
 */
struct ot_tape_record_v1 {
    oa_u8 magic[4];
    oa_u16 size, version, operation, flags;
    oa_u16 result, diagnostic_class, session_state;
    oa_u8 scsi_opcode, host_status, target_status, sense_key;
    oa_u8 sense_response, asc, ascq, reserved_byte;
    oa_u16 completion_flags;
    oa_u32 requested, actual, stream_flags;
    oa_u16 buffer_offset, buffer_segment;
    oa_u32 block_size;              /* zero for variable records */
    oa_u8 reserved[16];
}
#if !defined(__WATCOMC__)
__attribute__((packed))
#endif
;
/* Non-moving READ POSITION short logical form. Raw flags are observations,
 * not operation completion facts. Coordinates are usable only with VALID;
 * all locations are logical objects, never byte offsets or archive file IDs. */
struct ot_tape_position_v1 {
    oa_u8 magic[4];
    oa_u16 size, version, format, flags;
    oa_u16 result, diagnostic_class, session_state;
    oa_u8 scsi_opcode, host_status, target_status, sense_key;
    oa_u8 sense_response, asc, ascq, reserved_byte;
    oa_u16 completion_flags;
    oa_u32 valid_fields, partition, first_block, last_block;
    oa_u32 device_flags, probe_flags;
    oa_u8 reserved[12];
}
#if !defined(__WATCOMC__)
__attribute__((packed))
#endif
;
/* Explicit logical LOCATE(10). With PARTITION clear, partition must be zero
 * and means current partition, not partition 0. Coordinates are echoed request
 * values; completion does not manufacture BOT or release writer failure state. */
struct ot_tape_locate_v1 {
    oa_u8 magic[4];
    oa_u16 size, version, format, flags;
    oa_u16 result, diagnostic_class, session_state;
    oa_u8 scsi_opcode, host_status, target_status, sense_key;
    oa_u8 sense_response, asc, ascq, reserved_byte;
    oa_u16 completion_flags;
    oa_u32 partition, block;
    oa_u8 reserved[28];
}
#if !defined(__WATCOMC__)
__attribute__((packed))
#endif
;
/* Format 1 long logical observation. Each 64-bit quantity is low/high DWORDs;
 * this works with 16-bit DOS compilers without long long. The file identifier
 * counts filemarks, not filesystem files; its validity is independent of block. */
struct ot_tape_position64_v1 {
    oa_u8 magic[4];
    oa_u16 size, version, format, flags;
    oa_u16 result, diagnostic_class, session_state;
    oa_u8 scsi_opcode, host_status, target_status, sense_key;
    oa_u8 sense_response, asc, ascq, reserved_byte;
    oa_u16 completion_flags;
    oa_u32 valid_fields, partition, block, block_high, file, file_high;
    oa_u32 device_flags, probe_flags;
    oa_u8 reserved[4];
}
#if !defined(__WATCOMC__)
__attribute__((packed))
#endif
;
/* Format 1 LOCATE(16). CP policy matches LOCATE(10); target is low/high DWORDs.
 * The old format-0 packet and its reserved layout remain unchanged. */
struct ot_tape_locate64_v1 {
    oa_u8 magic[4];
    oa_u16 size, version, format, flags;
    oa_u16 result, diagnostic_class, session_state;
    oa_u8 scsi_opcode, host_status, target_status, sense_key;
    oa_u8 sense_response, asc, ascq, reserved_byte;
    oa_u16 completion_flags;
    oa_u32 partition, block, block_high;
    oa_u8 reserved[24];
}
#if !defined(__WATCOMC__)
__attribute__((packed))
#endif
;
/* Read-only MODE SENSE page 11h report. Counts describe additional partitions
 * in the reported (possibly pending/stale) layout, not proven live targets.
 * No active partition, media identity or byte capacity is inferred here. */
struct ot_tape_partitions_v1 {
    oa_u8 magic[4];
    oa_u16 size, version, format, flags;
    oa_u16 result, diagnostic_class, session_state;
    oa_u8 scsi_opcode, host_status, target_status, sense_key;
    oa_u8 sense_response, asc, ascq, reserved_byte;
    oa_u16 completion_flags;
    oa_u32 valid_fields, maximum_additional, defined_additional;
    oa_u32 partition_flags, format_recognition, partition_units;
    oa_u32 size_descriptors, probe_flags;
    oa_u8 reserved[4];
}
#if !defined(__WATCOMC__)
__attribute__((packed))
#endif
;
/* Explicit TapeAlert retrieval. Reading page 2Eh may acknowledge drive flags:
 * flags must include ACKNOWLEDGE. Missing reported bits mean unknown, not clear.
 * Bit 0 of each low DWORD denotes flag 1; high DWORD bit 31 denotes flag 64. */
struct ot_tape_alerts_v1 {
    oa_u8 magic[4];
    oa_u16 size, version, format, flags;
    oa_u16 result, diagnostic_class, session_state;
    oa_u8 scsi_opcode, host_status, target_status, sense_key;
    oa_u8 sense_response, asc, ascq, reserved_byte;
    oa_u16 completion_flags;
    oa_u32 valid_fields, reported_low, reported_high, active_low, active_high;
    oa_u32 probe_flags;
    oa_u8 reserved[12];
}
#if !defined(__WATCOMC__)
__attribute__((packed))
#endif
;
#if defined(__WATCOMC__)
#pragma pack(pop)
#endif

/* Initializers return 0/-1 and perform no I/O. Validators accept returned
 * v1 packets only: 0 means internally consistent, -1 malformed/truncated.
 * Always validate before interpreting a response, then inspect its result.
 * requested/actual remain BYTES even for fixed mode; block_size is one block.
 * Record packets use offset 44 for block_size, unlike CONTROL's offset 28.
 */
/* Decimal conversion uses bounded 16-bit limbs, never floating point or a
 * compiler-specific 64-bit scalar. Invalid input/capacity preserves outputs. */
int ot_tape_u64_parse(const char *,oa_u32 *low,oa_u32 *high);
int ot_tape_u64_format(oa_u32 low,oa_u32 high,char *,oa_u16 capacity);
/* Format 1 uses the same function numbers with distinct wide packet types;
 * coordinate validity, movement completion and native recovery stay separate. */
int ot_tape_position64_init(struct ot_tape_position64_v1 *);
int ot_tape_position64_validate(const void *,oa_u16 available);
int ot_tape_locate64_init(struct ot_tape_locate64_v1 *,oa_u16 flags,oa_u32 partition,oa_u32 low,oa_u32 high);
int ot_tape_locate64_validate(const void *,oa_u16 available);
/* Flags 0: current partition; PARTITION: explicitly select partition 0..255.
 * Block is a full unsigned 32-bit logical object address, not a byte offset.
 * Invalid initializers preserve the destination and issue no I/O. */
int ot_tape_locate_init(struct ot_tape_locate_v1 *, oa_u16 flags, oa_u32 partition, oa_u32 block);
int ot_tape_locate_validate(const void *, oa_u16 available);
/* Retrieval may clear drive flags. An invalid/missing acknowledgment preserves
 * the destination. State helper: -1 unknown/invalid, 0 clear, 1 active. */
int ot_tape_alerts_init(struct ot_tape_alerts_v1 *,oa_u16 flags);
int ot_tape_alerts_validate(const void *,oa_u16 available);
int ot_tape_alert_state(const struct ot_tape_alerts_v1 *,oa_u16 number);
/* A complete bounded page supplies raw layout facts only. Legacy unproven
 * transfer lengths remain PARTIAL; the report does not authorize a LOCATE. */
int ot_tape_partitions_init(struct ot_tape_partitions_v1 *);
int ot_tape_partitions_validate(const void *,oa_u16 available);
/* Format 0 requests the 20-byte short logical response. Observation cannot
 * clear native failure state; BPU/LOLU or PERR suppress coordinate validity. */
int ot_tape_position_init(struct ot_tape_position_v1 *);
int ot_tape_position_validate(const void *, oa_u16 available);
int ot_tape_info_init(struct ot_tape_info_v1 *info, oa_u16 flags);
int ot_tape_info_validate(const void *packet, oa_u16 available);
/* Use a validated response. -1 unknown, 0 unsupported, 1 supported. */
int ot_tape_info_feature(const struct ot_tape_info_v1 *info, oa_u32 feature);
/* -1 unknown/invalid limits, 0 outside limits, 1 within device limits.
 * maximum_block=0 means no maximum specified; not a provider transfer limit.
 */
int ot_tape_info_block_valid(const struct ot_tape_info_v1 *info, oa_u32 bytes);
/* Variable READ/WRITE constructors take 1..65535 bytes. Fixed construction
 * additionally requires whole blocks of size 1..65535; every invalid initializer
 * leaves the destination unchanged. Constructors set no DOS buffer pointer.
 */
int ot_tape_record_init(struct ot_tape_record_v1 *, oa_u32 capacity);
int ot_tape_write_init(struct ot_tape_record_v1 *, oa_u32 bytes);
int ot_tape_record_validate(const void *, oa_u16 available);
int ot_tape_record_fixed_init(struct ot_tape_record_v1 *, oa_u16 operation, oa_u32 bytes, oa_u32 block_size);
/* Fixed BEGIN requests a compatible claim, not MODE SELECT. CONTROL init
 * selects an operation; CONTROL validate checks reply consistency, including
 * whether submission/release/position flags are possible for that operation.
 */
int ot_tape_control_fixed_init(struct ot_tape_control_v1 *, oa_u32 block_size);
int ot_tape_control_init(struct ot_tape_control_v1 *, oa_u16 operation);
/* Signed record/filemark movement is -8388608..8388607; EOD requires zero.
 * Construction leaves invalid destinations untouched and performs no I/O.
 */
int ot_tape_space_init(struct ot_tape_control_v1 *, oa_u16 operation, oa_s32 count);
int ot_tape_control_validate(const void *, oa_u16 available);
#endif
