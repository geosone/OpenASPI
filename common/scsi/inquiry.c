/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Bounded decoding of standard INQUIRY data. */

#include <string.h>

#include "openaspi/scsi.h"

void oa_scsi_identity(char *out, const oa_u8 *in, oa_u16 size)
{
    oa_u16 i;
    oa_u16 len = size;

    for (i = 0; i < size; i++) {
        out[i] = (in[i] >= 0x20u && in[i] < 0x7Fu) ? (char)in[i] : ' ';
    }
    while (len > 0u && out[len - 1u] == ' ') {
        len--;
    }
    out[len] = '\0';
}

int oa_scsi_decode_inquiry(const oa_u8 *data, oa_u16 length,
                           struct oa_scsi_inquiry *result)
{
    if (data == 0 || result == 0 || length < 5u) {
        return -1;
    }
    memset(result, 0, sizeof(*result));
    result->qualifier = (oa_u8)(data[0] >> 5);
    result->device_type = (oa_u8)(data[0] & 0x1Fu);
    result->removable = (data[1] & 0x80u) != 0u;
    result->version = data[2];
    if (length >= 16u) {
        oa_scsi_identity(result->vendor, data + 8, 8u);
    }
    if (length >= 32u) {
        oa_scsi_identity(result->product, data + 16, 16u);
    }
    if (length >= 36u) {
        oa_scsi_identity(result->revision, data + 32, 4u);
    }
    return 0;
}
