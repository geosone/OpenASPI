# Native tape packet helpers

[`tape_api.c`](tape_api.c) implements the portable helpers declared by
[`tape_api.h`](../../include/openaspi/tape_api.h). It constructs requests and
validates replies without DOS services, ASPI submission or device access.

The order for a consumer is:

1. Initialize the request, including fixed-mode flags/size when applicable.
2. Supply any binding-specific buffer address and submit through the adapter.
3. Check delivery, then validate the returned packet and available size.
4. Inspect result, completion/count validity, stream conditions and diagnostics.

A validator returns zero for any internally consistent reply, including
BUSY/ERROR. It does not turn such a reply into successful I/O, compare every
response field with the original request, or protect caller storage from an
incorrectly supplied available length. The binding retains the original intent
and storage lifetime.

QUERY distinguishes valid groups, known features, supported features, current
settings and session state. CONTROL checks operation-specific claim/release,
submission and position facts. Record validation separates known counts from
unknown zero, successful boundaries from errors, and READ from stricter WRITE
completion. Data-record counts remain bytes, including fixed-block I/O.
[Position observations](../../docs/native-tape-position.md) instead qualify
logical coordinates; [LOCATE](../../docs/native-tape-locate.md) echoes requested
object/partition coordinates and checks movement failure state. A returned
address does not imply recovery, and a LOCATE target is not an observed position.

Public layouts are mirrored in
[`native_tape_defs.inc`](../aspi/native_tape_defs.inc); the resident DOS provider
is under [`common/aspi`](../aspi/README.md). Protocol documents begin at the
[native API overview](../../docs/native-tape-api.md). The
[host validation tests](../../tests/native_tape_api_test.c) exercise contradictory
fields and fixed-mode rules; [ABI checks](../../tests/tape_abi.c) verify offsets.

[Wide positioning](../../docs/native-tape-wide.md) keeps each address as explicit
low/high DWORDs. Decimal helpers use 16-bit limbs; wide validators marshal a
local diagnostic prefix for shared checks and validate wide fields separately.
They never alias incompatible packets or silently discard high address bits.
