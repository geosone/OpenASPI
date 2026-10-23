#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "openaspi/aspitape.h"
#include "openaspi/scsi_tape.h"

static void assert_bytes(const oa_u8 *actual, const oa_u8 *expected,
                         oa_u16 length)
{
    assert(memcmp(actual, expected, length) == 0);
}

static void test_abi_sizes(void)
{
    assert(sizeof(struct oa_aspitape_mtop) == 6u);
    assert(sizeof(struct oa_aspitape_mtget) == 14u);
    assert(sizeof(struct oa_aspitape_mtget16) == 16u);
    assert(offsetof(struct oa_aspitape_mtget16, driver_error) == 7u);
    assert(offsetof(struct oa_aspitape_mtget16, last_scsi_status) == 10u);
    assert(offsetof(struct oa_aspitape_mtget16, residual_bytes) == 14u);
    assert(OA_MT16_STATE_WRITE_ERROR == 0x0200u);
}

static void test_read_write_cdb(void)
{
    oa_u8 cdb[OA_SCSI_CDB6_SIZE];
    const oa_u8 expected_read[OA_SCSI_CDB6_SIZE] =
        { 0x08u, 0x01u, 0x01u, 0x02u, 0x03u, 0x00u };
    const oa_u8 expected_write[OA_SCSI_CDB6_SIZE] =
        { 0x0Au, 0x00u, 0x00u, 0x20u, 0x00u, 0x00u };

    assert(oa_scsi_cdb_read_write(cdb, 0, 1, 0x010203UL) == 0);
    assert_bytes(cdb, expected_read, OA_SCSI_CDB6_SIZE);
    assert(oa_scsi_cdb_read_write(cdb, 1, 0, 0x2000UL) == 0);
    assert_bytes(cdb, expected_write, OA_SCSI_CDB6_SIZE);
    assert(oa_scsi_cdb_read_write(cdb, 0, 0, 0x01000000UL) == -1);
}

static void test_positioning_cdb(void)
{
    oa_u8 cdb[OA_SCSI_CDB6_SIZE];
    const oa_u8 expected_space[OA_SCSI_CDB6_SIZE] =
        { 0x11u, 0x01u, 0xFFu, 0xFFu, 0xFEu, 0x00u };
    const oa_u8 expected_marks[OA_SCSI_CDB6_SIZE] =
        { 0x10u, 0x01u, 0x00u, 0x00u, 0x02u, 0x00u };
    const oa_u8 forward_limit[OA_SCSI_CDB6_SIZE] =
        { 0x11u, 0x01u, 0x7Fu, 0xFFu, 0xFFu, 0x00u };
    const oa_u8 backward_limit[OA_SCSI_CDB6_SIZE] =
        { 0x11u, 0x00u, 0x80u, 0x00u, 0x00u, 0x00u };
    const oa_u8 marks_limit[OA_SCSI_CDB6_SIZE] =
        { 0x10u, 0x00u, 0xFFu, 0xFFu, 0xFFu, 0x00u };

    assert(oa_scsi_cdb_space(cdb, OA_SCSI_SPACE_FILEMARKS, -2) == 0);
    assert_bytes(cdb, expected_space, OA_SCSI_CDB6_SIZE);
    assert(oa_scsi_cdb_write_filemarks(cdb, 2u, 1) == 0);
    assert_bytes(cdb, expected_marks, OA_SCSI_CDB6_SIZE);
    assert(oa_scsi_cdb_space(cdb, OA_SCSI_SPACE_FILEMARKS, 8388607L) == 0);
    assert_bytes(cdb, forward_limit, OA_SCSI_CDB6_SIZE);
    assert(oa_scsi_cdb_space(cdb, OA_SCSI_SPACE_FILEMARKS, 8388608L) == -1);
    assert_bytes(cdb, forward_limit, OA_SCSI_CDB6_SIZE);
    assert(oa_scsi_cdb_space(cdb, OA_SCSI_SPACE_FILEMARKS, 16777215L) == -1);
    assert_bytes(cdb, forward_limit, OA_SCSI_CDB6_SIZE);
    assert(oa_scsi_cdb_space(cdb, OA_SCSI_SPACE_BLOCKS, -8388608L) == 0);
    assert_bytes(cdb, backward_limit, OA_SCSI_CDB6_SIZE);
    assert(oa_scsi_cdb_space(cdb, OA_SCSI_SPACE_BLOCKS, -8388609L) == -1);
    assert_bytes(cdb, backward_limit, OA_SCSI_CDB6_SIZE);
    assert(oa_scsi_cdb_write_filemarks(cdb, 0x00FFFFFFUL, 0) == 0);
    assert_bytes(cdb, marks_limit, OA_SCSI_CDB6_SIZE);
    assert(oa_scsi_cdb_write_filemarks(cdb, 0x01000000UL, 0) == -1);
    assert_bytes(cdb, marks_limit, OA_SCSI_CDB6_SIZE);
}

static void test_fixed_sense(void)
{
    const oa_u8 data[18] = {
        0xF0u, 0x00u, 0xC3u, 0x00u, 0x00u, 0x00u, 0x20u, 0x0Au,
        0x00u, 0x00u, 0x00u, 0x00u, 0x00u, 0x02u, 0x00u, 0x00u,
        0x00u, 0x00u
    };
    struct oa_tape_sense sense;

    assert(oa_scsi_decode_sense(data, sizeof(data), &sense) == 0);
    assert(sense.response_code == 0x70u);
    assert(sense.sense_key == OA_SENSE_MEDIUM_ERROR);
    assert(sense.filemark == 1u);
    assert(sense.end_of_medium == 1u);
    assert(sense.information_valid == 1u);
    assert(sense.information == 0x20u);
    assert(sense.asc == 0x00u);
    assert(sense.ascq == 0x02u);
}

static void test_truncated_fixed_sense(void)
{
    oa_u8 data[18] = {
        0xF0u, 0x00u, 0xE0u, 0x00u, 0x00u, 0x00u, 0x20u, 0x0Au,
        0x00u, 0x00u, 0x00u, 0x00u, 0x11u, 0x22u, 0x00u, 0x00u,
        0x00u, 0x00u
    };
    struct oa_tape_sense sense;
    oa_u16 length;
    oa_u8 *prefix;

    for (length = 4u; length <= sizeof(data); ++length) {
        prefix = (oa_u8 *)malloc(length);
        assert(prefix != 0);
        memcpy(prefix, data, length);
        memset(&sense, 0xA5, sizeof(sense));
        assert(oa_scsi_decode_sense(prefix, length, &sense) == 0);
        free(prefix);
        assert(sense.filemark == 1u);
        assert(sense.end_of_medium == 1u);
        assert(sense.incorrect_length == 1u);
        assert(sense.information_valid == (length >= 7u));
        assert(sense.information == (length >= 7u ? 0x20u : 0u));
        assert(sense.asc == (length >= 14u ? 0x11u : 0u));
        assert(sense.ascq == (length >= 14u ? 0x22u : 0u));
    }
    data[7] = 0u;                    /* trailing buffer bytes are not sense */
    assert(oa_scsi_decode_sense(data, sizeof(data), &sense) == 0);
    assert(sense.information_valid == 1u);
    assert(sense.information == 0x20u);
    assert(sense.asc == 0u);
    assert(sense.ascq == 0u);
    data[7] = 5u;                    /* ASC present, ASCQ missing */
    assert(oa_scsi_decode_sense(data, sizeof(data), &sense) == 0);
    assert(sense.asc == 0u);
    assert(sense.ascq == 0u);
    data[7] = 6u;
    data[0] = 0x71u;                 /* deferred, without VALID */
    assert(oa_scsi_decode_sense(data, sizeof(data), &sense) == 0);
    assert(sense.information_valid == 0u);
    assert(sense.asc == 0x11u);
    assert(sense.ascq == 0x22u);
}

static void test_descriptor_sense(void)
{
    const oa_u8 data[24] = {
        0x72u, 0x06u, 0x28u, 0x00u, 0x00u, 0x00u, 0x00u, 0x10u,
        0x00u, 0x0Au, 0x80u, 0x00u, 0x00u, 0x00u, 0x00u, 0x00u,
        0x00u, 0x00u, 0x00u, 0x20u,
        0x04u, 0x02u, 0x00u, 0xE0u
    };
    struct oa_tape_sense sense;

    assert(oa_scsi_decode_sense(data, sizeof(data), &sense) == 0);
    assert(sense.sense_key == OA_SENSE_UNIT_ATTENTION);
    assert(sense.asc == 0x28u);
    assert(sense.ascq == 0x00u);
    assert(sense.information_valid == 1u);
    assert(sense.information == 0x20u);
    assert(sense.filemark == 1u);
    assert(sense.end_of_medium == 1u);
    assert(sense.incorrect_length == 1u);
}

static void test_truncated_descriptor_sense(void)
{
    oa_u8 data[24] = {
        0x72u, 0x06u, 0x28u, 0x00u, 0x00u, 0x00u, 0x00u, 0x10u,
        0x00u, 0x0Au, 0x80u, 0x00u, 0x00u, 0x00u, 0x00u, 0x00u,
        0x00u, 0x00u, 0x00u, 0x20u,
        0x04u, 0x02u, 0x00u, 0xE0u
    };
    struct oa_tape_sense sense;
    oa_u16 length;
    oa_u8 *prefix;

    for (length = 1u; length <= sizeof(data); ++length) {
        prefix = (oa_u8 *)malloc(length);
        assert(prefix != 0);
        memcpy(prefix, data, length);
        memset(&sense, 0xA5, sizeof(sense));
        if (length < 4u) {
            assert(oa_scsi_decode_sense(prefix, length, &sense) == -1);
            assert(sense.response_code == 0xA5u);
        } else {
            assert(oa_scsi_decode_sense(prefix, length, &sense) == 0);
            assert(sense.sense_key == OA_SENSE_UNIT_ATTENTION);
            assert(sense.asc == 0x28u);
            assert(sense.information_valid == (length >= 20u));
            assert(sense.information == (length >= 20u ? 0x20u : 0u));
            assert(sense.filemark == (length >= 24u));
            assert(sense.end_of_medium == (length >= 24u));
            assert(sense.incorrect_length == (length >= 24u));
        }
        free(prefix);
    }
    data[7] = 0u;                    /* no descriptors declared */
    data[0] = 0xF2u;                 /* descriptor byte 0 has no VALID bit */
    assert(oa_scsi_decode_sense(data, sizeof(data), &sense) == -1);
    data[0] = 0xF3u;
    assert(oa_scsi_decode_sense(data, sizeof(data), &sense) == -1);
    data[0] = 0x72u;
    assert(oa_scsi_decode_sense(data, sizeof(data), &sense) == 0);
    assert(sense.information_valid == 0u);
    assert(sense.filemark == 0u);
    data[7] = 16u;
    data[9] = 0xFFu;                 /* descriptor exceeds available data */
    assert(oa_scsi_decode_sense(data, sizeof(data), &sense) == 0);
    assert(sense.information_valid == 0u);
    assert(sense.filemark == 0u);
    data[9] = 10u;
    data[12] = 1u;                   /* unsupported nonzero upper 32 bits */
    assert(oa_scsi_decode_sense(data, sizeof(data), &sense) == 0);
    assert(sense.information_valid == 0u);
    assert(sense.filemark == 1u);
    assert(oa_scsi_decode_sense(0, sizeof(data), &sense) == -1);
    assert(oa_scsi_decode_sense(data, sizeof(data), 0) == -1);
    assert(oa_scsi_decode_sense(data, 0u, &sense) == -1);
    data[0] = 0x7Fu;
    assert(oa_scsi_decode_sense(data, sizeof(data), &sense) == -1);
}

int main(void)
{
    test_abi_sizes();
    test_read_write_cdb();
    test_positioning_cdb();
    test_fixed_sense();
    test_truncated_fixed_sense();
    test_descriptor_sense();
    test_truncated_descriptor_sense();
    puts("OpenASPI tape protocol tests passed");
    return 0;
}
