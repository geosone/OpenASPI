# Portable SCSI helpers

C90 code shared by the DOS tools (OpenWatcom, 16-bit) and the native layer
([`common/native`](../native/README.md), 32/64-bit kernels). `make check`
builds it for the host with `-std=c90 -pedantic` and as 16-bit DOS objects.

| File | Content | Interface |
| --- | --- | --- |
| `sense.c` | fixed and descriptor sense into `struct oa_scsi_sense` | [`scsi.h`](../../include/openaspi/scsi.h) |
| `inquiry.c` | standard INQUIRY data and identification strings | `scsi.h` |
| `block_cdb.c` | block CDB builders, READ CAPACITY decoding | `scsi.h` |
| `wire.c` | big-endian access | `scsi.h` |
| `tape_cdb.c` | six-byte sequential-access commands | [`scsi_tape.h`](../../include/openaspi/scsi_tape.h) |

The sense decoder accepts available metadata from a recognized response with
at least four bytes. Successful decoding is not proof of a complete response
or a successful SCSI command. Callers must check the command result, sense key
and validity of any information they use.

Fixed-format VALID only makes `information_valid` true when all four
information bytes are present. ASC/ASCQ require both bytes within the supplied
buffer and the declared additional sense length. Descriptor fields are used
only when their complete descriptor fits both lengths. Missing optional
metadata remains zero; information wider than the public 32-bit field is not
marked valid. The DOS driver's assembly decoder is a separate implementation.

## Checks

`make check` runs host tests and compiles the helpers as 16-bit DOS objects.
Prefix-buffer tests cover truncated fixed/descriptor responses, unavailable
fields, malformed descriptor lengths and unsupported information widths.

With a host compiler supporting AddressSanitizer and UBSan, after `make check`:

```sh
cc -Iinclude -std=c90 -Wall -Wextra -Werror -pedantic -g -O1 \
  -fsanitize=address,undefined -fno-omit-frame-pointer \
  -o build/host/test_tape_sanitized tests/test_tape.c \
  common/scsi/tape_cdb.c common/scsi/sense.c
build/host/test_tape_sanitized
```

The tests allocate exact-size prefix buffers so sanitizer checks can detect
reads beyond the supplied response, not merely beyond a larger backing array.
