#include <assert.h>
#include <stdio.h>
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

    assert(oa_scsi_cdb_space(cdb, OA_SCSI_SPACE_FILEMARKS, -2) == 0);
    assert_bytes(cdb, expected_space, OA_SCSI_CDB6_SIZE);
    assert(oa_scsi_cdb_write_filemarks(cdb, 2u, 1) == 0);
    assert_bytes(cdb, expected_marks, OA_SCSI_CDB6_SIZE);
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

int main(void)
{
    test_abi_sizes();
    test_read_write_cdb();
    test_positioning_cdb();
    test_fixed_sense();
    test_descriptor_sense();
    puts("OpenASPI tape protocol tests passed");
    return 0;
}
