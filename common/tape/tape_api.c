/* Native OpenTape v1 packet construction and reply validation.
 *
 * This module performs no DOS calls or SCSI I/O. Initializers build requests;
 * validators check returned packets, including relationships between fields.
 * A delivered IOCTL, an accepted packet and a successful tape operation are
 * separate outcomes: validation returns 0 even for a well-formed error reply.
 * Callers must then inspect result, diagnostics and completion/stream flags.
 *
 * All counts are bytes at this boundary. Fixed I/O additionally specifies a
 * block size; conversion to the CDB's block count belongs to the provider.
 * Wire layouts and masks live in tape_api.h; the resident DOS implementation
 * mirrors them in common/aspi/native_tape_defs.inc. See docs/native-tape-*.md
 * for the protocol and tests/tape_abi.c for byte offsets.
 */

#include <string.h>
#include "openaspi/tape_api.h"

/* Build a snapshot request, or a read-only probe request with REFRESH.
 * Invalid arguments leave the destination untouched; no probing happens here.
 */
int ot_tape_info_init(struct ot_tape_info_v1 *info, oa_u16 flags)
{
    if (info == 0 || (flags & ~OT_TAPE_API_REFRESH) != 0u) return -1;
    memset(info, 0, sizeof(*info));
    memcpy(info->magic, "OTAP", 4u);
    info->size = OT_TAPE_API_INFO_SIZE;
    info->version = OT_TAPE_API_VERSION;
    info->flags = flags;
    return 0;
}

/* Validate a complete v1 QUERY reply, not an outgoing request. Check available
 * before reading the packed object; exact output size/version reject an ABI
 * mismatch. Reserved fields must remain zero so extensions cannot silently
 * acquire a meaning that this consumer does not understand.
 */
int ot_tape_info_validate(const void *packet, oa_u16 available)
{
    const struct ot_tape_info_v1 *p;
    unsigned i;
    if (packet == 0 || available < OT_TAPE_API_INFO_SIZE) return -1;
    p = (const struct ot_tape_info_v1 *)packet;
    if (memcmp(p->magic, "OTAP", 4u) != 0 ||
        p->size != OT_TAPE_API_INFO_SIZE || p->version != OT_TAPE_API_VERSION ||
        (p->flags & ~OT_TAPE_API_REFRESH) != 0u ||
        p->result > OT_TAPE_RESULT_BUSY || p->diagnostic_class > OT_TAPE_DIAG_UNSUPPORTED ||
        (p->operations & OT_TAPE_OP_QUERY) == 0UL ||
        (p->valid_fields & ~0x7fUL) != 0UL ||
        (p->valid_fields & OT_TAPE_VALID_SESSION) == 0UL ||
        (p->features_known & ~OT_TAPE_FEATURE_COMPRESSION) != 0UL ||
        (p->features_supported & ~p->features_known) != 0UL ||
        (p->current_state & ~0x0fUL) != 0UL || (p->session_state & ~0x7fu) != 0u ||
        (p->probe_flags & ~OT_TAPE_PROBE_UNVERIFIED_LENGTH) != 0UL ||
        p->reserved_word != 0u) return -1;
    for (i = 0; i < sizeof(p->reserved); ++i)
        if (p->reserved[i] != 0u) return -1;
    /* Boolean inequality implements "PARTIAL iff a diagnostic is present".
     * Known/supported are separate: supported bits must be a subset of known;
     * an enabled setting also needs the corresponding valid probe group.
     */
    if ((p->result == OT_TAPE_RESULT_PARTIAL) !=
        (p->diagnostic_class != OT_TAPE_DIAG_NONE)) return -1;
    if ((p->valid_fields & OT_TAPE_VALID_COMPRESSION) == 0UL) {
        if (p->features_known != 0UL || (p->current_state & OT_TAPE_STATE_COMPRESSION) != 0UL)
            return -1;
    } else if (p->features_known != OT_TAPE_FEATURE_COMPRESSION) return -1;
    if ((p->current_state & OT_TAPE_STATE_COMPRESSION) != 0UL &&
        (p->features_supported & OT_TAPE_FEATURE_COMPRESSION) == 0UL) return -1;
    if ((p->current_state & OT_TAPE_STATE_WRITE_PROTECT) != 0UL &&
        (p->valid_fields & OT_TAPE_VALID_MODE) == 0UL) return -1;
    if ((p->current_state & OT_TAPE_STATE_SETMARKS) != 0UL &&
        (p->valid_fields & OT_TAPE_VALID_CONFIG) == 0UL) return -1;
    /* SCSI limits are 24-bit maximum / 16-bit minimum. Granularity must
     * be a nonzero power of two: x & (x-1) is zero only for one set bit.
     */
    if ((p->valid_fields & OT_TAPE_VALID_LIMITS) != 0UL &&
        (p->maximum_block > 0xffffffUL || p->minimum_block > 0xffffUL ||
         (p->maximum_block != 0UL && p->minimum_block > p->maximum_block) ||
         p->block_granularity == 0UL ||
         (p->block_granularity & (p->block_granularity-1UL)) != 0UL)) return -1;
    /* A nonzero current block size means fixed mode; zero means variable.
     * Require MODE as well, rather than treating absent data as variable.
     */
    if ((p->valid_fields & OT_TAPE_VALID_BLOCK) != 0UL) {
        if ((p->valid_fields & OT_TAPE_VALID_MODE) == 0UL || p->current_block > 0xffffffUL ||
            ((p->current_block != 0UL) != ((p->current_state & OT_TAPE_STATE_FIXED) != 0UL)))
            return -1;
    } else if ((p->current_state & OT_TAPE_STATE_FIXED) != 0UL) return -1;
    if ((p->valid_fields & OT_TAPE_VALID_IDENTITY) != 0UL) {
        /* These adjacent fixed-width fields form the 28-byte identity. */
        const oa_u8 *identity = (const oa_u8 *)packet + 48u;
        for (i = 0; i < 28u; ++i)
            if (identity[i] < 0x20u || identity[i] > 0x7eu) return -1;
    }
    /* Snapshot and busy replies expose session state only. They must not
     * return stale capability/mode data that looks freshly probed.
     */
    if (p->flags == 0u || p->result == OT_TAPE_RESULT_BUSY) {
        if (p->valid_fields != OT_TAPE_VALID_SESSION || p->features_known != 0UL ||
            p->current_state != 0UL || p->diagnostic_class != OT_TAPE_DIAG_NONE)
            return -1;
    }
    return 0;
}

/* Query one feature of an already validated reply. x & (x-1) removes the
 * lowest set bit, so zero afterward means exactly one feature was requested.
 * Unknown is distinct from a device explicitly reporting no support.
 */
int ot_tape_info_feature(const struct ot_tape_info_v1 *info, oa_u32 feature)
{
    if (info == 0 || feature == 0UL || (feature & (feature - 1UL)) != 0UL ||
        (info->features_known & feature) == 0UL) return -1;
    return (info->features_supported & feature) != 0UL;
}

/* Test ONE physical block/record size against reported device limits.
 * Return -1 for unusable/unknown limits, 0 for a size outside them, 1 inside.
 * maximum=0 is unspecified, not a zero-byte maximum. Granularity is measured
 * from minimum_block; this does not test the provider's total-transfer limit.
 */
int ot_tape_info_block_valid(const struct ot_tape_info_v1 *info, oa_u32 bytes)
{
    if (info == 0 || (info->valid_fields & OT_TAPE_VALID_LIMITS) == 0UL ||
        info->block_granularity == 0UL ||
        (info->block_granularity & (info->block_granularity-1UL)) != 0UL ||
        info->maximum_block > 0xffffffUL || info->minimum_block > 0xffffUL ||
        (info->maximum_block != 0UL && info->minimum_block > info->maximum_block)) return -1;
    if (bytes < info->minimum_block ||
        (info->maximum_block != 0UL && bytes > info->maximum_block)) return 0;
    return (bytes - info->minimum_block) % info->block_granularity == 0UL;
}

/* Prepare a control request with no optional flags. BEGIN/ABORT only manage
 * writer ownership; constructing a packet neither claims nor moves the tape.
 */
int ot_tape_control_init(struct ot_tape_control_v1 *p, oa_u16 operation)
{
    if (p == 0 || operation > OT_TAPE_CONTROL_SETMARK) return -1;
    memset(p, 0, sizeof(*p));
    memcpy(p->magic, "OTAP", 4u);
    p->size = OT_TAPE_API_CONTROL_SIZE;
    p->version = OT_TAPE_API_VERSION;
    p->operation = operation;
    return 0;
}

/* CONTROL enums are not contiguous: 10..13 remain media/removal controls. */
static int space_operation(oa_u16 operation)
{
    return (operation>=OT_TAPE_CONTROL_SPACE_RECORDS && operation<=OT_TAPE_CONTROL_SPACE_EOD) ||
        (operation>=OT_TAPE_CONTROL_SPACE_SEQ_FILEMARKS && operation<=OT_TAPE_CONTROL_SPACE_SEQ_SETMARKS);
}
static int space_count_valid(oa_u16 operation, oa_s32 count)
{
    if (operation == OT_TAPE_CONTROL_SPACE_EOD) return count == 0;
    if (space_operation(operation))
        return count >= (oa_s32)-8388608L && count <= (oa_s32)8388607L;
    return count == 0;
}
int ot_tape_space_init(struct ot_tape_control_v1 *p, oa_u16 operation, oa_s32 count)
{
    if (p == 0 || !space_operation(operation) || !space_count_valid(operation, count)) return -1;
    ot_tape_control_init(p, operation);
    p->count = count;
    return 0;
}

/* Check control completion against the requested operation. In particular,
 * a claim/release without a CDB must not masquerade as submitted hardware I/O,
 * and failed mutating controls must not claim a known position or release.
 */
int ot_tape_control_validate(const void *packet, oa_u16 available)
{
    const struct ot_tape_control_v1 *p;
    unsigned i, expected;
    if (packet == 0 || available < OT_TAPE_API_CONTROL_SIZE) return -1;
    p = (const struct ot_tape_control_v1 *)packet;
    if (memcmp(p->magic, "OTAP", 4u) != 0 || p->size != OT_TAPE_API_CONTROL_SIZE ||
        p->version != OT_TAPE_API_VERSION || p->operation > OT_TAPE_CONTROL_SETMARK ||
        !space_count_valid(p->operation, p->count) ||
        (p->flags & ~OT_TAPE_IO_FIXED) != 0u ||
        (p->flags != 0u && (p->operation != OT_TAPE_CONTROL_BEGIN_WRITE ||
                            p->block_size == 0UL || p->block_size > 65535UL)) ||
        (p->flags == 0u && p->block_size != 0UL) || (p->session_state & ~0x7fu) != 0u ||
        p->diagnostic_class > OT_TAPE_DIAG_UNSUPPORTED || p->reserved_byte != 0u)
        return -1;
    for (i = 0; i < sizeof(p->reserved); ++i) if (p->reserved[i] != 0u) return -1;
    /* BUSY and unsupported BEGIN reject before submission: no CDB/status
     * or completion bits may imply that the device was touched.
     */
    if (p->result == OT_TAPE_RESULT_BUSY) {
        return p->completion_flags == 0u && p->diagnostic_class == 0u &&
            p->scsi_opcode == 0u && p->host_status == 0u && p->target_status == 0u &&
            p->sense_key == 0u && p->sense_response == 0u && p->asc == 0u && p->ascq == 0u ? 0 : -1;
    }
    if (p->result == OT_TAPE_RESULT_UNSUPPORTED) {
        return p->operation == OT_TAPE_CONTROL_BEGIN_WRITE && p->diagnostic_class == OT_TAPE_DIAG_UNSUPPORTED &&
            p->completion_flags == 0u && p->scsi_opcode == 0u && p->host_status == 0u &&
            p->target_status == 0u && p->sense_key == 0u && p->sense_response == 0u &&
            p->asc == 0u && p->ascq == 0u ? 0 : -1;
    }
    /* BEGIN claims and ABORT releases in memory only. ABORT is not a flush
     * or rollback and does not promise that an uncertain position is repaired.
     */
    if (p->operation == OT_TAPE_CONTROL_BEGIN_WRITE || p->operation == OT_TAPE_CONTROL_ABORT_WRITE) {
        expected = OT_TAPE_COMPLETION_DONE |
            (p->operation == OT_TAPE_CONTROL_BEGIN_WRITE ? OT_TAPE_COMPLETION_CLAIMED : OT_TAPE_COMPLETION_RELEASED);
        return p->result == OT_TAPE_RESULT_OK && p->completion_flags == expected &&
            p->diagnostic_class == 0u && p->scsi_opcode == 0u && p->host_status == 0u &&
            p->target_status == 0u && p->sense_key == 0u && p->sense_response == 0u &&
            p->asc == 0u && p->ascq == 0u &&
            (p->operation == OT_TAPE_CONTROL_BEGIN_WRITE ? p->session_state == OT_TAPE_SESSION_NATIVE_WRITER :
                (p->session_state & OT_TAPE_SESSION_NATIVE_WRITER) == 0u) ? 0 : -1;
    }
    /* Actual CDBs: READY=00h, REWIND=01h, FILEMARKS=10h, SPACE=11h,
     * sequential LOAD/UNLOAD=1Bh, PREVENT/ALLOW MEDIUM REMOVAL=1Eh.
     * FLUSH/END use zero marks; FILEMARK uses one. Exact success flags below
     * prevent a response from claiming completion of a different operation.
     */
    expected = p->operation == OT_TAPE_CONTROL_READY ? 0u :
        p->operation == OT_TAPE_CONTROL_REWIND ? 1u :
        p->operation == OT_TAPE_CONTROL_SETMARK ? 0x10u :
        space_operation(p->operation) ? 0x11u :
        p->operation >= OT_TAPE_CONTROL_LOCK ? 0x1eu :
        p->operation >= OT_TAPE_CONTROL_LOAD ? 0x1bu :
        p->operation >= OT_TAPE_CONTROL_SPACE_RECORDS ? 0x11u : 0x10u;
    if (p->scsi_opcode != expected) return -1;
    /* A submitted setmark can change media even without any data WRITE.
     * Dirty is set before submission, and ownership survives an error. */
    if(p->operation==OT_TAPE_CONTROL_SETMARK &&
       ((p->result==OT_TAPE_RESULT_OK && p->session_state!=0x30u) ||
        (p->result==OT_TAPE_RESULT_ERROR && p->session_state!=0x70u))) return -1;
    if (space_operation(p->operation)) {
        /* Motion never claims a writer or BOT. A submitted failure latches
         * native uncertainty until explicit REWIND; counts are not residuals. */
        if (p->result == OT_TAPE_RESULT_OK && p->session_state != 0u) return -1;
        if (p->result == OT_TAPE_RESULT_ERROR && p->session_state != OT_TAPE_SESSION_NATIVE_FAILED)
            return -1;
    }
    if (p->operation >= OT_TAPE_CONTROL_LOAD && !space_operation(p->operation) &&
        p->operation != OT_TAPE_CONTROL_SETMARK) {
        /* A media action may complete while earlier uncertainty remains.
         * Loading is permitted for recovery, but cannot repair position or
         * finalize abandoned data. Pure DIRTY without FAILED is unreachable. */
        if ((p->session_state & ~0x60u) != 0u ||
            ((p->session_state & OT_TAPE_SESSION_NATIVE_DIRTY) != 0u &&
             (p->session_state & OT_TAPE_SESSION_NATIVE_FAILED) == 0u) ||
            (p->result == OT_TAPE_RESULT_ERROR && p->operation < OT_TAPE_CONTROL_LOCK &&
             (p->session_state & OT_TAPE_SESSION_NATIVE_FAILED) == 0u)) return -1;
    }
    if (p->result == OT_TAPE_RESULT_OK) {
        expected = OT_TAPE_COMPLETION_SUBMITTED | OT_TAPE_COMPLETION_DONE;
        if (p->operation == OT_TAPE_CONTROL_READY) expected |= OT_TAPE_COMPLETION_READY;
        else if (p->operation == OT_TAPE_CONTROL_REWIND) expected |= OT_TAPE_POSITION_BOT;
        else if (p->operation == OT_TAPE_CONTROL_END_WRITE) expected |= OT_TAPE_COMPLETION_RELEASED;
        if (p->operation == OT_TAPE_CONTROL_END_WRITE && p->session_state != 0u) return -1;
        if ((p->operation == OT_TAPE_CONTROL_FLUSH || p->operation == OT_TAPE_CONTROL_FILEMARK) &&
            ((p->session_state & (OT_TAPE_SESSION_NATIVE_WRITER | OT_TAPE_SESSION_NATIVE_FAILED | 0x0fu)) !=
                OT_TAPE_SESSION_NATIVE_WRITER ||
             (p->operation == OT_TAPE_CONTROL_FILEMARK && (p->session_state & OT_TAPE_SESSION_NATIVE_DIRTY) == 0u))) return -1;
        return p->completion_flags == expected && p->diagnostic_class == 0u &&
            p->host_status == 0u && p->target_status == 0u && p->sense_key == 0u &&
            p->sense_response == 0u && p->asc == 0u && p->ascq == 0u &&
            (p->session_state & OT_TAPE_SESSION_REWINDING) == 0u ? 0 : -1;
    }
    /* After a failed moving/writing command, position is uncertain. The
     * writer remains claimed and failed until explicitly released by ABORT.
     * READY and removal policy do not move tape and have no UNKNOWN flag.
     */
    expected = OT_TAPE_COMPLETION_SUBMITTED |
        ((p->operation == OT_TAPE_CONTROL_READY ||
          (p->operation >= OT_TAPE_CONTROL_LOCK && p->operation <= OT_TAPE_CONTROL_UNLOCK)) ?
         0u : OT_TAPE_POSITION_UNKNOWN);
    if (p->operation >= OT_TAPE_CONTROL_FLUSH && p->operation <= OT_TAPE_CONTROL_END_WRITE &&
        (p->session_state & (OT_TAPE_SESSION_NATIVE_WRITER | OT_TAPE_SESSION_NATIVE_FAILED)) !=
            (OT_TAPE_SESSION_NATIVE_WRITER | OT_TAPE_SESSION_NATIVE_FAILED)) return -1;
    return p->result == OT_TAPE_RESULT_ERROR && p->diagnostic_class != 0u &&
        p->completion_flags == expected ? 0 : -1;
}

/* Default to one variable-record READ. A real-mode transfer must fit in
 * 1..65535 bytes; the DOS adapter supplies the buffer's segment and offset.
 */
int ot_tape_record_init(struct ot_tape_record_v1 *p, oa_u32 capacity)
{
    if (p == 0 || capacity == 0UL || capacity > 65535UL) return -1;
    memset(p, 0, sizeof(*p));
    memcpy(p->magic, "OTAP", 4u);
    p->size = OT_TAPE_API_RECORD_SIZE;
    p->version = OT_TAPE_API_VERSION;
    p->requested = capacity;
    return 0;
}

/* Same wire envelope as READ, with an explicit WRITE operation. A separate
 * successful BEGIN_WRITE is still required before the provider accepts it.
 */
int ot_tape_write_init(struct ot_tape_record_v1 *p, oa_u32 bytes)
{
    if (ot_tape_record_init(p, bytes) != 0) return -1;
    p->operation = OT_TAPE_RECORD_WRITE;
    return 0;
}

/* Validate a READ/WRITE reply as a state transition, not just a struct.
 * COUNT_VALID grants permission to use actual; DONE grants permission to
 * accept completion. A valid error reply may lack either permission.
 * Never infer EOF, retry safety or a write count from a bare zero field.
 */
int ot_tape_record_validate(const void *packet, oa_u16 available)
{
    const struct ot_tape_record_v1 *p;
    unsigned i, submitted, known;
    if (packet == 0 || available < OT_TAPE_API_RECORD_SIZE) return -1;
    p = (const struct ot_tape_record_v1 *)packet;
    if (memcmp(p->magic, "OTAP", 4u) != 0 || p->size != OT_TAPE_API_RECORD_SIZE ||
        p->version != OT_TAPE_API_VERSION || p->operation > OT_TAPE_RECORD_WRITE || (p->flags & ~OT_TAPE_IO_FIXED) != 0u ||
        (p->flags == 0u && p->block_size != 0UL) ||
        (p->flags != 0u && (p->block_size == 0UL || p->block_size > 65535UL ||
                            p->requested % p->block_size != 0UL || p->actual % p->block_size != 0UL)) ||
        p->requested == 0UL || p->requested > 65535UL ||
        p->actual > p->requested || (p->session_state & ~0x7fu) != 0u ||
        p->diagnostic_class > OT_TAPE_DIAG_INCOMPLETE || p->reserved_byte != 0u ||
        (p->stream_flags & ~0x7fUL) != 0UL ||
        (p->completion_flags & ~0x27u) != 0u) return -1;
    for (i = 0; i < sizeof(p->reserved); ++i) if (p->reserved[i] != 0u) return -1;
    /* The wire mark flag denotes a classified stream event, not the raw SCSI
     * FM bit. Reject older providers' FILEMARK+00/03 interpretation as well as
     * forged setmarks from stale/deferred/transport sense. */
    if((p->stream_flags & OT_TAPE_STREAM_SETMARK)!=0UL) {
        if(p->operation!=OT_TAPE_RECORD_READ ||
           (p->stream_flags & (OT_TAPE_STREAM_FILEMARK|OT_TAPE_STREAM_EOD))!=0UL ||
           p->host_status!=0 || p->target_status!=2 || p->diagnostic_class!=OT_TAPE_DIAG_TARGET ||
           (p->sense_response!=0x70 && p->sense_response!=0x72) || p->asc!=0 || p->ascq!=3) return -1;
    }
    if((p->stream_flags & OT_TAPE_STREAM_FILEMARK)!=0UL && p->host_status==0 && p->target_status==2 &&
       (p->sense_response==0x70 || p->sense_response==0x72) && p->asc==0 && p->ascq==3) return -1;
    /* Allowed record completion bits (27h): SUBMITTED, DONE, UNKNOWN and
     * COUNT_VALID. SHORT is derived from a known count, never from zero-fill.
     * TRUNCATED requires ILI, but an ILI need not mean truncation.
     */
    submitted = p->completion_flags & OT_TAPE_COMPLETION_SUBMITTED;
    known = p->completion_flags & OT_TAPE_COUNT_VALID;
    if (!known && p->actual != 0UL) return -1;
    if (((p->stream_flags & OT_TAPE_STREAM_SHORT) != 0UL) !=
        (known && p->actual < p->requested)) return -1;
    if ((p->stream_flags & OT_TAPE_STREAM_TRUNCATED) != 0UL &&
        (p->stream_flags & OT_TAPE_STREAM_ILI) == 0UL) return -1;
    if (p->result == OT_TAPE_RESULT_BUSY || p->result == OT_TAPE_RESULT_UNSUPPORTED)
        return p->completion_flags == 0u && p->stream_flags == 0UL &&
            p->diagnostic_class == (p->result == OT_TAPE_RESULT_BUSY ? 0u : OT_TAPE_DIAG_UNSUPPORTED) &&
            p->scsi_opcode == 0u && p->host_status == 0u && p->target_status == 0u &&
            p->sense_key == 0u && p->sense_response == 0u && p->asc == 0u && p->ascq == 0u ? 0 : -1;
    if (!submitted || p->scsi_opcode != (p->operation == OT_TAPE_RECORD_WRITE ? 0x0au : 8u)) return -1;
    /* WRITE state 30h = native writer + dirty; 70h additionally latches
     * failure. A short write is an error, not a successful stream boundary.
     * The allowed write stream mask 0Ah contains only EOM and SHORT.
     */
    if (p->operation == OT_TAPE_RECORD_WRITE) {
        if (p->result == OT_TAPE_RESULT_OK && (p->actual != p->requested || p->session_state != 0x30u)) return -1;
        if (p->result == OT_TAPE_RESULT_ERROR && p->session_state != 0x70u) return -1;
        if (p->result == OT_TAPE_RESULT_STREAM || (p->stream_flags & ~0x0aUL) != 0UL) return -1;
    }
    /* INCOMPLETE is a clean transport/target completion with a proven short
     * WRITE. Preserve that count without inventing SCSI sense for the error.
     */
    if (p->diagnostic_class == OT_TAPE_DIAG_INCOMPLETE &&
        (p->operation != OT_TAPE_RECORD_WRITE || p->result != OT_TAPE_RESULT_ERROR || !known ||
         p->stream_flags != OT_TAPE_STREAM_SHORT || p->host_status != 0u || p->target_status != 0u ||
         p->sense_key != 0u || p->sense_response != 0u || p->asc != 0u || p->ascq != 0u)) return -1;
    /* 23h = SUBMITTED | DONE | COUNT_VALID. A clean READ can be short; a
     * clean WRITE was already required above to transfer every requested byte.
     */
    if (p->result == OT_TAPE_RESULT_OK)
        return p->completion_flags == 0x23u && p->diagnostic_class == 0u &&
            p->host_status == 0u && p->target_status == 0u && p->sense_key == 0u &&
            p->sense_response == 0u && p->asc == 0u && p->ascq == 0u &&
            (p->stream_flags & ~OT_TAPE_STREAM_SHORT) == 0UL ? 0 : -1;
    /* Fixed-block ILI and truncated records are errors, not benign EOF.
     * STREAM is reserved for current CHECK CONDITION (70h/72h), with a proven
     * count and a normal tape boundary. Deferred sense cannot prove this I/O.
     * BLANK CHECK is accepted as EOD only for the explicit 00/05 indication.
     */
    if (p->flags != 0u && (p->stream_flags & OT_TAPE_STREAM_TRUNCATED) != 0UL) return -1;
    if (p->flags != 0u && p->result == OT_TAPE_RESULT_STREAM &&
        (p->stream_flags & OT_TAPE_STREAM_ILI) != 0UL) return -1;
    if (p->result == OT_TAPE_RESULT_STREAM &&
        (p->stream_flags & OT_TAPE_STREAM_EOD) != 0UL && p->sense_key != 8u) return -1;
    if (p->result == OT_TAPE_RESULT_STREAM)
        return p->completion_flags == 0x23u && p->diagnostic_class == OT_TAPE_DIAG_TARGET &&
            p->host_status == 0u && p->target_status == 2u &&
            (p->sense_response == 0x70u || p->sense_response == 0x72u) &&
            (p->sense_key <= 1u ||
             (p->sense_key == 8u && p->stream_flags == (OT_TAPE_STREAM_EOD | OT_TAPE_STREAM_SHORT) &&
              p->asc == 0u && p->ascq == 5u && p->actual == 0UL)) &&
            (p->stream_flags & (OT_TAPE_STREAM_FILEMARK | OT_TAPE_STREAM_EOM |
                               OT_TAPE_STREAM_ILI | OT_TAPE_STREAM_EOD | OT_TAPE_STREAM_SETMARK)) != 0UL &&
            (p->stream_flags & OT_TAPE_STREAM_TRUNCATED) == 0UL ? 0 : -1;
    if (p->result != OT_TAPE_RESULT_ERROR || p->diagnostic_class == 0u ||
        (p->completion_flags & (OT_TAPE_COMPLETION_DONE | OT_TAPE_POSITION_UNKNOWN)) !=
            OT_TAPE_POSITION_UNKNOWN) return -1;
    /* Transport/malformed replies provide no trustworthy count or boundary;
     * accepting one could advance the archive reader past missing data.
     */
    if ((p->diagnostic_class == OT_TAPE_DIAG_TRANSPORT ||
         p->diagnostic_class == OT_TAPE_DIAG_MALFORMED) &&
        (known || p->stream_flags != 0UL)) return -1;
    return 0;
}

/* Build an aligned fixed-block transfer. Validate everything before the
 * initializer clears the destination, leaving it untouched on bad input.
 * bytes is the whole transfer; block_size is the device's existing mode.
 */
int ot_tape_record_fixed_init(struct ot_tape_record_v1 *p, oa_u16 operation,
                                oa_u32 bytes, oa_u32 block_size)
{
    if (p == 0 || operation > OT_TAPE_RECORD_WRITE || block_size == 0UL || block_size > 65535UL ||
        bytes == 0UL || bytes > 65535UL || bytes % block_size != 0UL) return -1;
    ot_tape_record_init(p, bytes);
    p->operation = operation;
    p->flags = OT_TAPE_IO_FIXED;
    p->block_size = block_size;
    return 0;
}
/* Claim fixed-mode writing with an explicit block size. This request does
 * not issue MODE SELECT: the provider checks compatibility with device mode.
 */
int ot_tape_control_fixed_init(struct ot_tape_control_v1 *p, oa_u32 block_size)
{
    if (p == 0 || block_size == 0UL || block_size > 65535UL) return -1;
    ot_tape_control_init(p, OT_TAPE_CONTROL_BEGIN_WRITE);
    p->flags = OT_TAPE_IO_FIXED;
    p->block_size = block_size;
    return 0;
}

/* Position has its own envelope rather than overloading CONTROL.count. The
 * parser publishes no guessed address after a short/unverified/unknown reply.
 * Successful observation is not evidence that an abandoned writer recovered. */
int ot_tape_position_init(struct ot_tape_position_v1 *p)
{
    if (p == 0) return -1;
    memset(p,0,sizeof(*p)); memcpy(p->magic,"OTAP",4);
    p->size=OT_TAPE_API_POSITION_SIZE; p->version=OT_TAPE_API_VERSION;
    return 0;
}
int ot_tape_position_validate(const void *packet, oa_u16 available)
{
    const struct ot_tape_position_v1 *p;
    unsigned i;
    if(packet==0 || available<OT_TAPE_API_POSITION_SIZE) return -1;
    p=(const struct ot_tape_position_v1 *)packet;
    if(memcmp(p->magic,"OTAP",4)!=0 || p->size!=64 || p->version!=OT_TAPE_API_VERSION ||
       p->format!=0 || p->flags!=0 || p->reserved_byte!=0 || (p->session_state & ~0x7fu)!=0 ||
       (p->valid_fields & ~OT_TAPE_POSITION_VALID)!=0UL ||
       (p->device_flags & ~0xf7UL)!=0UL || (p->probe_flags & ~1UL)!=0UL) return -1;
    for(i=0;i<sizeof(p->reserved);++i) if(p->reserved[i]!=0) return -1;
    if(p->result==OT_TAPE_RESULT_BUSY)
        return p->completion_flags==0 && p->scsi_opcode==0 && p->diagnostic_class==0 &&
            p->host_status==0 && p->target_status==0 && p->sense_key==0 && p->sense_response==0 &&
            p->asc==0 && p->ascq==0 && p->valid_fields==0UL && p->device_flags==0UL &&
            p->probe_flags==0UL && p->partition==0UL && p->first_block==0UL && p->last_block==0UL ? 0 : -1;
    if(p->scsi_opcode!=0x34 || (p->session_state & ~0x60u)!=0 ||
       (p->session_state==0x20)) return -1;
    if(p->valid_fields==0UL && (p->partition!=0UL || p->first_block!=0UL || p->last_block!=0UL)) return -1;
    if(p->result==OT_TAPE_RESULT_OK) {
        if(p->completion_flags!=3 || p->diagnostic_class!=0 || p->probe_flags!=0UL ||
           p->host_status!=0 || p->target_status!=0 || p->sense_key!=0 || p->sense_response!=0 ||
           p->asc!=0 || p->ascq!=0 || p->partition>255UL) return -1;
        return p->valid_fields==((p->device_flags & 6UL) ? 0UL : OT_TAPE_POSITION_VALID) ? 0 : -1;
    }
    if(p->valid_fields!=0UL || p->device_flags!=0UL) return -1;
    if(p->result==OT_TAPE_RESULT_PARTIAL)
        return p->completion_flags==3 && p->diagnostic_class==OT_TAPE_DIAG_INCOMPLETE && p->probe_flags==1UL &&
            p->host_status==0 && p->target_status==0 && p->sense_key==0 && p->sense_response==0 && p->asc==0 && p->ascq==0 ? 0 : -1;
    if(p->result!=OT_TAPE_RESULT_ERROR || p->probe_flags!=0UL) return -1;
    if(p->diagnostic_class==OT_TAPE_DIAG_MALFORMED)
        return p->completion_flags==3 && p->host_status==0 && p->target_status==0 &&
            p->sense_key==0 && p->sense_response==0 && p->asc==0 && p->ascq==0 ? 0 : -1;
    return p->completion_flags==1 && (p->diagnostic_class==1 || p->diagnostic_class==2 || p->diagnostic_class==4) ? 0 : -1;
}

/* LOCATE is a moving request with echoed coordinates, unlike READ POSITION.
 * A failed submitted movement retains uncertainty; only explicit native REWIND
 * is recovery in this binding. Do not validate it as a position observation. */
int ot_tape_locate_init(struct ot_tape_locate_v1 *p, oa_u16 flags, oa_u32 partition, oa_u32 block)
{
    if(p==0 || flags>OT_TAPE_LOCATE_PARTITION || partition>255UL || (flags==0 && partition!=0UL)) return -1;
    memset(p,0,sizeof(*p)); memcpy(p->magic,"OTAP",4);
    p->size=OT_TAPE_API_LOCATE_SIZE; p->version=OT_TAPE_API_VERSION;
    p->flags=flags; p->partition=partition; p->block=block;
    return 0;
}
int ot_tape_locate_validate(const void *packet, oa_u16 available)
{
    const struct ot_tape_locate_v1 *p;
    unsigned i;
    if(packet==0 || available<OT_TAPE_API_LOCATE_SIZE) return -1;
    p=(const struct ot_tape_locate_v1 *)packet;
    if(memcmp(p->magic,"OTAP",4)!=0 || p->size!=64 || p->version!=OT_TAPE_API_VERSION ||
       p->format!=0 || p->flags>OT_TAPE_LOCATE_PARTITION || p->partition>255UL ||
       (p->flags==0 && p->partition!=0UL) || p->reserved_byte!=0 || (p->session_state & ~0x7fu)!=0) return -1;
    for(i=0;i<sizeof(p->reserved);++i) if(p->reserved[i]!=0) return -1;
    if(p->result==OT_TAPE_RESULT_BUSY)
        return p->completion_flags==0 && p->scsi_opcode==0 && p->diagnostic_class==0 &&
            p->host_status==0 && p->target_status==0 && p->sense_key==0 && p->sense_response==0 && p->asc==0 && p->ascq==0 ? 0 : -1;
    if(p->scsi_opcode!=0x2b) return -1;
    if(p->result==OT_TAPE_RESULT_OK)
        return p->completion_flags==3 && p->session_state==0 && p->diagnostic_class==0 &&
            p->host_status==0 && p->target_status==0 && p->sense_key==0 && p->sense_response==0 && p->asc==0 && p->ascq==0 ? 0 : -1;
    return p->result==OT_TAPE_RESULT_ERROR && p->completion_flags==5 && p->session_state==0x40 &&
        (p->diagnostic_class==1 || p->diagnostic_class==2 || p->diagnostic_class==4) ? 0 : -1;
}

/* Four little-endian 16-bit limbs keep multiply/divide intermediates within
 * 32 bits on the 8086 toolchain. Publish only after every digit/size check. */
int ot_tape_u64_parse(const char *text,oa_u32 *low,oa_u32 *high)
{
    oa_u16 words[4]={0,0,0,0};
    unsigned i;
    if(text==0 || *text==0 || low==0 || high==0 || low==high) return -1;
    while(*text) {
        oa_u32 carry;
        if(*text<'0' || *text>'9') return -1;
        carry=(unsigned)(*text++-'0');
        for(i=0;i<4;++i) {
            oa_u32 n=(oa_u32)words[i]*10UL+carry;
            words[i]=(oa_u16)n; carry=n>>16;
        }
        if(carry!=0UL) return -1;
    }
    *low=(oa_u32)words[0]|((oa_u32)words[1]<<16);
    *high=(oa_u32)words[2]|((oa_u32)words[3]<<16);
    return 0;
}
int ot_tape_u64_format(oa_u32 low,oa_u32 high,char *out,oa_u16 capacity)
{
    oa_u16 words[4];
    char reverse[20];
    unsigned n=0,i;
    if(out==0) return -1;
    words[0]=(oa_u16)low; words[1]=(oa_u16)(low>>16);
    words[2]=(oa_u16)high; words[3]=(oa_u16)(high>>16);
    do {
        oa_u32 carry=0;
        for(i=4;i>0;--i) {
            oa_u32 v=(carry<<16)|words[i-1];
            words[i-1]=(oa_u16)(v/10UL); carry=v%10UL;
        }
        reverse[n++]=(char)('0'+(unsigned)carry);
    } while(words[0] || words[1] || words[2] || words[3]);
    if(capacity<=n) return -1;
    for(i=0;i<n;++i) out[i]=reverse[n-1-i];
    out[n]=0; return 0;
}
int ot_tape_position64_init(struct ot_tape_position64_v1 *p)
{
    if(p==0) return -1;
    memset(p,0,sizeof(*p)); memcpy(p->magic,"OTAP",4);
    p->size=64; p->version=OT_TAPE_API_VERSION; p->format=1; return 0;
}
int ot_tape_position64_validate(const void *packet,oa_u16 available)
{
    const struct ot_tape_position64_v1 *p;
    struct ot_tape_position_v1 base;
    unsigned i;
    oa_u32 expected;
    if(packet==0 || available<64) return -1;
    p=(const struct ot_tape_position64_v1 *)packet;
    if(p->format!=1 || (p->valid_fields & ~3UL)!=0UL || (p->device_flags & ~0xcdUL)!=0UL) return -1;
    for(i=0;i<sizeof(p->reserved);++i) if(p->reserved[i]) return -1;
    if(!(p->valid_fields & 1UL) && (p->partition || p->block || p->block_high)) return -1;
    if(!(p->valid_fields & 2UL) && (p->file || p->file_high)) return -1;
    /* Reuse the common prefix/completion checks through a local short packet;
     * long flags and independent coordinate validity are checked separately. */
    ot_tape_position_init(&base); memcpy(&base,p,28); base.format=0;
    base.valid_fields=p->result==0 ? 1UL : 0UL;
    base.probe_flags=p->probe_flags;
    if(ot_tape_position_validate(&base,sizeof(base))!=0) return -1;
    if(p->result!=0) return p->valid_fields==0 && p->device_flags==0 ? 0 : -1;
    expected=(p->device_flags & 4UL ? 0UL : 1UL)|(p->device_flags & 8UL ? 0UL : 2UL);
    return p->valid_fields==expected ? 0 : -1;
}
int ot_tape_locate64_init(struct ot_tape_locate64_v1 *p,oa_u16 flags,oa_u32 part,oa_u32 low,oa_u32 high)
{
    struct ot_tape_locate_v1 base;
    if(p==0 || ot_tape_locate_init(&base,flags,part,low)!=0) return -1;
    memset(p,0,sizeof(*p)); memcpy(p,&base,36); p->format=1; p->block_high=high; return 0;
}
int ot_tape_locate64_validate(const void *packet,oa_u16 available)
{
    const struct ot_tape_locate64_v1 *p;
    struct ot_tape_locate_v1 base;
    unsigned i;
    if(packet==0 || available<64) return -1;
    p=(const struct ot_tape_locate64_v1 *)packet;
    if(p->format!=1) return -1;
    for(i=0;i<sizeof(p->reserved);++i) if(p->reserved[i]) return -1;
    if(p->scsi_opcode!=(p->result==2 ? 0u : 0x92u)) return -1;
    memset(&base,0,sizeof(base)); memcpy(&base,p,36); base.format=0;
    if(p->result!=2) base.scsi_opcode=0x2b;
    return ot_tape_locate_validate(&base,sizeof(base));
}

int ot_tape_partitions_init(struct ot_tape_partitions_v1 *p)
{
    if(p==0) return -1;
    memset(p,0,sizeof(*p)); memcpy(p->magic,"OTAP",4);
    p->size=OT_TAPE_API_PARTITIONS_SIZE; p->version=OT_TAPE_API_VERSION; return 0;
}
/* Reuse checked read-only completion facts via an explicit local prefix copy.
 * Raw partition quantities keep their own bounds and validity, independently
 * of logical block position and of whether the reported layout is committed. */
int ot_tape_partitions_validate(const void *packet,oa_u16 available)
{
    const struct ot_tape_partitions_v1 *p;
    struct ot_tape_position_v1 base;
    unsigned i;
    if(packet==0 || available<OT_TAPE_API_PARTITIONS_SIZE) return -1;
    p=(const struct ot_tape_partitions_v1 *)packet;
    if(p->result==OT_TAPE_RESULT_OK && p->valid_fields!=OT_TAPE_LAYOUT_VALID) return -1;
    if(p->format!=0 || (p->valid_fields & ~1UL)!=0UL || p->maximum_additional>255UL ||
       p->defined_additional>255UL || p->partition_flags>255UL || p->format_recognition>255UL ||
       p->partition_units>255UL || p->size_descriptors>26UL) return -1;
    for(i=0;i<sizeof(p->reserved);++i) if(p->reserved[i]) return -1;
    if(!p->valid_fields && (p->maximum_additional || p->defined_additional || p->partition_flags ||
        p->format_recognition || p->partition_units || p->size_descriptors)) return -1;
    if(p->scsi_opcode!=(p->result==OT_TAPE_RESULT_BUSY ? 0u : 0x1au)) return -1;
    ot_tape_position_init(&base); memcpy(&base,p,28);
    base.scsi_opcode=p->result==OT_TAPE_RESULT_BUSY ? 0u : 0x34u;
    base.valid_fields=p->valid_fields; base.probe_flags=p->probe_flags;
    return ot_tape_position_validate(&base,sizeof(base));
}

int ot_tape_alerts_init(struct ot_tape_alerts_v1 *p,oa_u16 flags)
{
    if(p==0 || flags!=OT_TAPE_ALERTS_ACKNOWLEDGE) return -1;
    memset(p,0,sizeof(*p)); memcpy(p->magic,"OTAP",4);
    p->size=OT_TAPE_API_ALERTS_SIZE; p->version=OT_TAPE_API_VERSION; p->flags=flags; return 0;
}
/* Validate the observation prefix through a local packet, after checking the
 * alert-specific acknowledgment and subset invariants. No packed aliasing. */
int ot_tape_alerts_validate(const void *packet,oa_u16 available)
{
    const struct ot_tape_alerts_v1 *p;
    struct ot_tape_position_v1 base;
    unsigned i;
    if(packet==0 || available<OT_TAPE_API_ALERTS_SIZE) return -1;
    p=(const struct ot_tape_alerts_v1 *)packet;
    if(p->format!=0 || p->flags!=OT_TAPE_ALERTS_ACKNOWLEDGE ||
       (p->valid_fields & ~OT_TAPE_ALERTS_VALID)!=0UL ||
       (p->active_low & ~p->reported_low)!=0UL || (p->active_high & ~p->reported_high)!=0UL ||
       (p->result==OT_TAPE_RESULT_OK && p->valid_fields!=OT_TAPE_ALERTS_VALID)) return -1;
    for(i=0;i<sizeof(p->reserved);++i) if(p->reserved[i]) return -1;
    if(!p->valid_fields && (p->reported_low || p->reported_high || p->active_low || p->active_high)) return -1;
    if(p->scsi_opcode!=(p->result==OT_TAPE_RESULT_BUSY ? 0u : 0x4du)) return -1;
    ot_tape_position_init(&base); memcpy(&base,p,28); base.flags=0;
    base.scsi_opcode=p->result==OT_TAPE_RESULT_BUSY ? 0u : 0x34u;
    base.valid_fields=p->valid_fields; base.probe_flags=p->probe_flags;
    return ot_tape_position_validate(&base,sizeof(base));
}
int ot_tape_alert_state(const struct ot_tape_alerts_v1 *p,oa_u16 number)
{
    oa_u32 bit,reported,active;
    if(number<1 || number>64 || ot_tape_alerts_validate(p,OT_TAPE_API_ALERTS_SIZE)!=0 ||
       !(p->valid_fields & OT_TAPE_ALERTS_VALID)) return -1;
    bit=1UL << ((number-1u)&31u);
    reported=number<=32 ? p->reported_low : p->reported_high;
    active=number<=32 ? p->active_low : p->active_high;
    return !(reported & bit) ? -1 : (active & bit)!=0UL;
}
