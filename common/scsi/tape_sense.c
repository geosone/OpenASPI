#include <string.h>

#include "openaspi/scsi_tape.h"

int oa_scsi_decode_sense(const oa_u8 *data, oa_u16 length,
                         struct oa_tape_sense *result)
{
    oa_u8 response;
    oa_u16 end;
    oa_u16 offset;
    oa_u16 descriptor_size;

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
        if (length < 8u) {
            return 0;
        }

        end = (oa_u16)(8u + (oa_u16)data[7]);
        if (end > length) {
            end = length;
        }
        offset = 8u;
        while ((oa_u16)(end - offset) >= 2u) {
            descriptor_size = (oa_u16)(2u + (oa_u16)data[offset + 1u]);
            if (descriptor_size > (oa_u16)(end - offset)) {
                break;
            }
            if (data[offset] == 0x00u && data[offset + 1u] >= 0x0Au &&
                (data[offset + 2u] & 0x80u) != 0u &&
                data[offset + 4u] == 0u && data[offset + 5u] == 0u &&
                data[offset + 6u] == 0u && data[offset + 7u] == 0u) {
                result->information_valid = 1u;
                result->information =
                    ((oa_u32)data[offset + 8u] << 24) |
                    ((oa_u32)data[offset + 9u] << 16) |
                    ((oa_u32)data[offset + 10u] << 8) |
                    (oa_u32)data[offset + 11u];
            } else if (data[offset] == 0x04u &&
                       data[offset + 1u] >= 0x02u) {
                result->filemark =
                    (data[offset + 3u] & 0x80u) != 0u;
                result->end_of_medium =
                    (data[offset + 3u] & 0x40u) != 0u;
                result->incorrect_length =
                    (data[offset + 3u] & 0x20u) != 0u;
            }
            offset = (oa_u16)(offset + descriptor_size);
        }
        return 0;
    }

    return -1;
}
