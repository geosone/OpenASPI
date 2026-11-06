/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Transport-independent SCSI helpers shared by the DOS tools (OpenWatcom,
 * 16-bit) and the native layer (32/64-bit kernels): opcodes, sense keys,
 * bounded sense and INQUIRY decoding, block command builders and big-endian
 * wire access. Nothing here submits a command; callers qualify completion
 * (host and target status) before trusting decoded data. Tape-specific
 * builders are in scsi_tape.h.
 */

#ifndef OPENASPI_SCSI_H
#define OPENASPI_SCSI_H

#include "openaspi/types.h"

/* Operation codes. */
#define OA_SCSI_TEST_UNIT_READY   0x00u
#define OA_SCSI_REWIND            0x01u
#define OA_SCSI_REQUEST_SENSE     0x03u
#define OA_SCSI_FORMAT_UNIT       0x04u
#define OA_SCSI_READ_6            0x08u
#define OA_SCSI_WRITE_6           0x0Au
#define OA_SCSI_WRITE_FILEMARKS   0x10u
#define OA_SCSI_SPACE             0x11u
#define OA_SCSI_INQUIRY           0x12u
#define OA_SCSI_ERASE             0x19u
#define OA_SCSI_MODE_SENSE_6      0x1Au
#define OA_SCSI_LOAD_UNLOAD       0x1Bu
#define OA_SCSI_START_STOP_UNIT   0x1Bu /* same opcode, block devices */
#define OA_SCSI_PREVENT_ALLOW     0x1Eu
#define OA_SCSI_READ_CAPACITY_10  0x25u
#define OA_SCSI_READ_10           0x28u
#define OA_SCSI_WRITE_10          0x2Au
#define OA_SCSI_SYNC_CACHE_10     0x35u
#define OA_SCSI_MODE_SENSE_10     0x5Au
#define OA_SCSI_READ_16           0x88u
#define OA_SCSI_WRITE_16          0x8Au
#define OA_SCSI_SYNC_CACHE_16     0x91u
#define OA_SCSI_SERVICE_ACTION_IN 0x9Eu
#define OA_SCSI_SAI_READ_CAPACITY 0x10u /* service action of 9Eh */
#define OA_SCSI_READ_12           0xA8u
#define OA_SCSI_WRITE_12          0xAAu

/* Sense keys. */
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

/* Additional sense codes used by the block helpers. */
#define OA_ASC_INVALID_OPCODE     0x20u
#define OA_ASC_LBA_OUT_OF_RANGE   0x21u
#define OA_ASC_INVALID_FIELD      0x24u
#define OA_ASC_WRITE_PROTECTED    0x27u
#define OA_ASC_MEDIUM_CHANGED     0x28u
#define OA_ASC_RESET              0x29u
#define OA_ASC_MEDIUM_NOT_PRESENT 0x3Au

/* Decoded host-side sense, not a packed copy of sense bytes. Zero optional
 * fields can mean absent: information needs information_valid, and callers use
 * response_code to distinguish current 70h/72h from deferred 71h/73h sense.
 * information retains the raw 32-bit value, not a sign-extended byte count.
 * This structure has no separate ASC-presence flag; zero ASC alone cannot prove
 * that a partial reply actually supplied ASC/ASCQ. The flags filemark,
 * end_of_medium and incorrect_length matter for sequential devices.
 */
struct oa_scsi_sense {
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

/* Decode available metadata from recognized fixed/descriptor sense (0),
 * or return -1 for invalid arguments, fewer than four bytes or unknown format.
 * information_valid requires the complete information field, not just VALID.
 * Optional fields are bounded by both supplied and declared lengths.
 */
int oa_scsi_decode_sense(const oa_u8 *data, oa_u16 length,
                         struct oa_scsi_sense *result);

/* Standard INQUIRY data, decoded. Strings are NUL-terminated, unprintable
 * bytes become blanks and trailing blanks are removed. */
struct oa_scsi_inquiry {
    oa_u8 qualifier;     /* 0: device present at this LUN */
    oa_u8 device_type;   /* OA_ASPI_DEVICE_* */
    oa_u8 removable;
    oa_u8 version;
    char vendor[9];
    char product[17];
    char revision[5];
};

#define OA_SCSI_INQUIRY_SIZE 36u

/* Decode at least five bytes of standard INQUIRY data (0), -1 otherwise.
 * Identification fields missing from a short reply stay empty. */
int oa_scsi_decode_inquiry(const oa_u8 *data, oa_u16 length,
                           struct oa_scsi_inquiry *result);
/* Copy a fixed-width, space-padded identification field into out[size+1]. */
void oa_scsi_identity(char *out, const oa_u8 *in, oa_u16 size);

/* Block command builders. cdb must hold 6, 10 or 16 bytes as named; they
 * clear the whole CDB first. Checked builders return -1 without mutation when
 * a value does not fit the command. */
void oa_scsi_cdb_inquiry(oa_u8 cdb[6], oa_u8 allocation_length);
void oa_scsi_cdb_start_stop(oa_u8 cdb[6], int start, int load_eject, int immediate);
void oa_scsi_cdb_mode_sense6(oa_u8 cdb[6], oa_u8 page, oa_u8 allocation_length);
void oa_scsi_cdb_read_capacity10(oa_u8 cdb[10]);
void oa_scsi_cdb_read_capacity16(oa_u8 cdb[16], oa_u32 allocation_length);
int oa_scsi_cdb_rw10(oa_u8 cdb[10], int write, oa_u64 lba, oa_u32 blocks);
void oa_scsi_cdb_rw16(oa_u8 cdb[16], int write, oa_u64 lba, oa_u32 blocks);
void oa_scsi_cdb_sync_cache10(oa_u8 cdb[10]);

/* READ CAPACITY replies. last_lba of the 10-byte form is FFFFFFFFh when the
 * 16-byte form is needed. Return 0, or -1 for a short reply. */
int oa_scsi_decode_capacity10(const oa_u8 *data, oa_u16 length,
                              oa_u32 *last_lba, oa_u32 *block_size);
int oa_scsi_decode_capacity16(const oa_u8 *data, oa_u16 length,
                              oa_u64 *last_lba, oa_u32 *block_size);

/* Big-endian wire access. */
oa_u16 oa_get_be16(const oa_u8 *p);
oa_u32 oa_get_be32(const oa_u8 *p);
oa_u64 oa_get_be64(const oa_u8 *p);
void oa_put_be16(oa_u8 *p, oa_u16 v);
void oa_put_be32(oa_u8 *p, oa_u32 v);
void oa_put_be64(oa_u8 *p, oa_u64 v);
/* Little-endian, for ATA and NVMe data structures. */
oa_u16 oa_get_le16(const oa_u8 *p);
oa_u32 oa_get_le32(const oa_u8 *p);
oa_u64 oa_get_le64(const oa_u8 *p);

#endif
