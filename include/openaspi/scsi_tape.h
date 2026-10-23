/* Transport-independent tape CDB construction and sense decoding.
 * CDB fields are big-endian wire bytes; oa_tape_sense is a decoded host-side
 * result with separate information validity. Builders neither submit nor retry.
 * Sense decoding does not qualify ASPI completion or distinguish a safe retry;
 * those decisions belong to the transport/session layer. See common/scsi/.
 */

#ifndef OPENASPI_SCSI_TAPE_H
#define OPENASPI_SCSI_TAPE_H

#include "openaspi/types.h"

#define OA_SCSI_CDB6_SIZE 6u

#define OA_SCSI_TEST_UNIT_READY  0x00u
#define OA_SCSI_REQUEST_SENSE    0x03u
#define OA_SCSI_READ_6           0x08u
#define OA_SCSI_WRITE_6          0x0Au
#define OA_SCSI_WRITE_FILEMARKS  0x10u
#define OA_SCSI_SPACE            0x11u
#define OA_SCSI_INQUIRY          0x12u
#define OA_SCSI_ERASE            0x19u
#define OA_SCSI_LOAD_UNLOAD      0x1Bu
#define OA_SCSI_REWIND           0x01u

#define OA_SCSI_SPACE_BLOCKS     0u
#define OA_SCSI_SPACE_FILEMARKS  1u
#define OA_SCSI_SPACE_SEQ_FM     2u
#define OA_SCSI_SPACE_EOD        3u

#define OA_SENSE_NO_SENSE         0x00u
#define OA_SENSE_RECOVERED_ERROR  0x01u
#define OA_SENSE_NOT_READY        0x02u
#define OA_SENSE_MEDIUM_ERROR     0x03u
#define OA_SENSE_HARDWARE_ERROR   0x04u
#define OA_SENSE_ILLEGAL_REQUEST  0x05u
#define OA_SENSE_UNIT_ATTENTION   0x06u
#define OA_SENSE_DATA_PROTECT     0x07u
#define OA_SENSE_BLANK_CHECK      0x08u
#define OA_SENSE_ABORTED_COMMAND  0x0Bu
#define OA_SENSE_VOLUME_OVERFLOW  0x0Du

/* Decoded host-side state, not a packed copy of sense bytes. Zero optional
 * fields can mean absent: information needs information_valid, and callers use
 * response_code to distinguish current 70h/72h from deferred 71h/73h sense.
 * information retains the raw 32-bit value, not a sign-extended byte count.
 * This structure has no separate ASC-presence flag; zero ASC alone cannot prove
 * that a partial reply actually supplied ASC/ASCQ.
 */
struct oa_tape_sense {
    oa_u8 response_code;
    oa_u8 sense_key;
    oa_u8 asc;
    oa_u8 ascq;
    oa_u8 filemark;
    oa_u8 end_of_medium;
    oa_u8 incorrect_length;
    oa_u8 information_valid;
    oa_u32 information;
};

/* All builders require a writable six-byte array. Void builders always fill
 * it; checked int builders return 0 on encoding success, -1 without mutation
 * when a range is unencodable. They do not check buffer pointers or drive support.
 */
void oa_scsi_cdb_test_unit_ready(oa_u8 cdb[OA_SCSI_CDB6_SIZE]);
void oa_scsi_cdb_rewind(oa_u8 cdb[OA_SCSI_CDB6_SIZE], int immediate);
/* transfer_length is unsigned 24-bit: bytes for variable records, whole
 * blocks for FIXED. The builder does not derive the count from a buffer size.
 */
int oa_scsi_cdb_read_write(oa_u8 cdb[OA_SCSI_CDB6_SIZE], int write,
                           int fixed_blocks, oa_u32 transfer_length);
/* count is unsigned 24-bit marks. immediate controls the CDB's IMMED bit;
 * encoding IMMED does not implement completion polling or prove media is ready.
 */
int oa_scsi_cdb_write_filemarks(oa_u8 cdb[OA_SCSI_CDB6_SIZE],
                                oa_u32 count, int immediate);
/* code selects a SPACE operation; count is signed 24-bit, with negative
 * counts encoding backward movement. Encoding does not validate whether a drive
 * can perform that movement or emulate an unsupported operation.
 */
int oa_scsi_cdb_space(oa_u8 cdb[OA_SCSI_CDB6_SIZE], oa_u8 code,
                      oa_s32 count);
void oa_scsi_cdb_load_unload(oa_u8 cdb[OA_SCSI_CDB6_SIZE], int load,
                             int retension, int immediate);
void oa_scsi_cdb_request_sense(oa_u8 cdb[OA_SCSI_CDB6_SIZE],
                               oa_u8 allocation_length);
/* Decode available metadata from recognized fixed/descriptor sense (0),
 * or return -1 for invalid arguments, fewer than four bytes or unknown format.
 * information_valid requires the complete information field, not just VALID.
 * Optional fields are bounded by both supplied and declared lengths.
 */
int oa_scsi_decode_sense(const oa_u8 *data, oa_u16 length,
                         struct oa_tape_sense *result);

#endif
