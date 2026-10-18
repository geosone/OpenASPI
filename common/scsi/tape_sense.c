#include <string.h>

#include "openaspi/scsi_tape.h"

int oa_scsi_decode_sense(const oa_u8 *data, oa_u16 length,
                         struct oa_tape_sense *result)
{
    oa_u8 response;

    if (data == 0 || result == 0 || length < 4u) {
        return -1;
    }

    memset(result, 0, sizeof(*result));
    response = data[0] & 0x7Fu;
    result->response_code = response;

    if (response == 0x70u || response == 0x71u) {
        result->information_valid = (data[0] & 0x80u) != 0u;
        result->filemark = (data[2] & 0x80u) != 0u;
        result->end_of_medium = (data[2] & 0x40u) != 0u;
        result->incorrect_length = (data[2] & 0x20u) != 0u;
        result->sense_key = data[2] & 0x0Fu;

        if (length >= 7u) {
            result->information = ((oa_u32)data[3] << 24) |
                                  ((oa_u32)data[4] << 16) |
                                  ((oa_u32)data[5] << 8) |
                                  (oa_u32)data[6];
        }
        if (length >= 14u) {
            result->asc = data[12];
            result->ascq = data[13];
        }
        return 0;
    }

    if (response == 0x72u || response == 0x73u) {
        result->sense_key = data[1] & 0x0Fu;
        result->asc = data[2];
        result->ascq = data[3];
        return 0;
    }

    return -1;
}
