/* Fixed-width scalar vocabulary for host tests, 16-bit DOS builds and the
 * native layer (32/64-bit kernels).
 * Widths are part of the packet ABI; native int/pointer sizes are not. These
 * typedefs alone provide neither packing nor byte-order conversion: each public
 * wire structure and serializer must specify those separately.
 */

#ifndef OPENASPI_TYPES_H
#define OPENASPI_TYPES_H

/* OpenWatcom's 16-bit DOS targets use 8/16/32-bit char/short/long. */
#ifdef __WATCOMC__
typedef unsigned char  oa_u8;
typedef signed char    oa_s8;
typedef unsigned short oa_u16;
typedef signed short   oa_s16;
typedef unsigned long  oa_u32;
typedef signed long    oa_s32;
typedef unsigned long long oa_u64; /* OpenWatcom has it in every model */
typedef signed long long   oa_s64;
#else
#include <stdint.h>
typedef uint8_t  oa_u8;
typedef int8_t   oa_s8;
typedef uint16_t oa_u16;
typedef int16_t  oa_s16;
typedef uint32_t oa_u32;
typedef int32_t  oa_s32;
typedef uint64_t oa_u64; /* also under -std=c90: stdint.h declares it */
typedef int64_t  oa_s64;
#endif

#endif
