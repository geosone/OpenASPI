/* Transport-independent tape CDB construction. Generic opcodes, sense
 * keys and sense decoding (struct oa_scsi_sense) are in scsi.h.
 * CDB fields are big-endian wire bytes. Builders neither submit nor retry.
 * Sense decoding does not qualify ASPI completion or distinguish a safe retry;
 * those decisions belong to the transport/session layer. See common/scsi/.
 */

#ifndef OPENASPI_SCSI_TAPE_H
#define OPENASPI_SCSI_TAPE_H

#include "openaspi/scsi.h" /* opcodes, sense keys, oa_scsi_decode_sense */

#define OA_SCSI_CDB6_SIZE 6u

#define OA_SCSI_SPACE_BLOCKS     0u
#define OA_SCSI_SPACE_FILEMARKS  1u
#define OA_SCSI_SPACE_SEQ_FM     2u
#define OA_SCSI_SPACE_EOD        3u

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
#endif
