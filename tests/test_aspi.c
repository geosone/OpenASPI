#include <assert.h>
#include <stddef.h>
#include <stdio.h>

#include "openaspi/aspi.h"

static void test_common_layout(void)
{
    assert(sizeof(struct oa_aspi_far_pointer) == 4u);
    assert(sizeof(struct oa_aspi_header) == 8u);
    assert(offsetof(struct oa_aspi_header, reserved) == 4u);
}

static void test_inquiry_layout(void)
{
    assert(sizeof(struct oa_aspi_ha_inquiry) == 60u);
    assert(offsetof(struct oa_aspi_ha_inquiry, adapter_count) == 8u);
    assert(offsetof(struct oa_aspi_ha_inquiry, manager_id) == 10u);
    assert(offsetof(struct oa_aspi_ha_inquiry, identifier) == 26u);
    assert(offsetof(struct oa_aspi_ha_inquiry, unique) == 42u);
    assert(offsetof(struct oa_aspi_ha_inquiry, extension_flags) == 58u);
}

static void test_device_type_layout(void)
{
    assert(sizeof(struct oa_aspi_get_device_type) == 11u);
    assert(offsetof(struct oa_aspi_get_device_type, target) == 8u);
    assert(offsetof(struct oa_aspi_get_device_type, lun) == 9u);
    assert(offsetof(struct oa_aspi_get_device_type, device_type) == 10u);
}

static void test_execute_layout(void)
{
    assert(sizeof(struct oa_aspi_exec_scsi) == 112u);
    assert(offsetof(struct oa_aspi_exec_scsi, buffer_length) == 10u);
    assert(offsetof(struct oa_aspi_exec_scsi, buffer) == 15u);
    assert(offsetof(struct oa_aspi_exec_scsi, cdb_length) == 23u);
    assert(offsetof(struct oa_aspi_exec_scsi, ha_status) == 24u);
    assert(offsetof(struct oa_aspi_exec_scsi, workspace) == 30u);
    assert(offsetof(struct oa_aspi_exec_scsi, cdb) == 64u);
    assert(offsetof(struct oa_aspi_exec_scsi, sense_tail) == 80u);
    assert(OA_ASPI_SENSE_OFFSET(6u) == 70u);
    assert(OA_ASPI_SENSE_OFFSET(10u) == 74u);
    assert(OA_ASPI_SENSE_OFFSET(12u) == 76u);
    assert(OA_ASPI_SENSE_OFFSET(16u) == 80u);
}

int main(void)
{
    test_common_layout();
    test_inquiry_layout();
    test_device_type_layout();
    test_execute_layout();
    puts("OpenASPI SRB layout tests passed");
    return 0;
}
