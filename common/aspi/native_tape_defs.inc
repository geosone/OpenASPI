; DOS wire ABI mirror, not an in-memory driver-state layout. NT_* describes
; the 128-byte QUERY packet; NC_* and NR_* describe distinct 64-byte CONTROL
; and record packets. Equal offsets in those namespaces may mean different
; things. Keep packed C offsets, assembly definitions and ABI tests together;
; adding a field must not move the existing v1 fields or enlarge a reply.

NT_SIZE equ 128
NT_VERSION equ 0100h
; QUERY prefix after magic/size/version: flags/result, then 32-bit validity,
; operation, feature and mode masks. Identity/session/diagnostics follow. Offsets
; are bytes from the packet start; little-endian DWORDs use paired WORD accesses.
NT_FLAGS equ 8
NT_RESULT equ 10
NT_VALID equ 12
NT_OPERATIONS equ 16
NT_KNOWN equ 20
NT_SUPPORTED equ 24
NT_STATE equ 28
NT_MIN equ 32
NT_MAX equ 36
NT_BLOCK equ 40
NT_ADDRESS equ 44
NT_VENDOR equ 48
NT_SESSION equ 76
NT_DIAG equ 78
NT_HOST equ 80
NT_TARGET equ 81
NT_KEY equ 82
NT_RESPONSE equ 83
NT_ASC equ 84
NT_ASCQ equ 85
; CONTROL and record packets share the prefix through completion_flags.
; They diverge at byte 28: CONTROL block_size versus record requested count.
; Never use a QUERY offset simply because it names a similar status field.
NC_SIZE equ 64
NC_OPERATION equ 8
NC_FLAGS equ 10
NC_RESULT equ 12
NC_DIAG equ 14
NC_SESSION equ 16
NC_OPCODE equ 18
NC_HOST equ 19
NC_TARGET equ 20
NC_KEY equ 21
NC_RESPONSE equ 22
NC_ASC equ 23
NC_ASCQ equ 24
NC_COMPLETION equ 26

; Record payload: requested/actual/stream are DWORDs, buffer is offset then
; segment, and fixed block_size is at byte 44. Every count remains bytes here;
; conversion to CDB block units must not change the public packet's units.
NR_SIZE equ 64
NR_REQUESTED equ 28
NR_ACTUAL equ 32
NR_STREAM equ 36
NR_OFFSET equ 40
NR_SEGMENT equ 42

NC_BLOCK equ 28
NR_BLOCK equ 44

; CONTROL signed SPACE count; record byte 32 remains NR_ACTUAL.
NC_COUNT equ 32
