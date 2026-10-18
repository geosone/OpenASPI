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
#else
#include <stdint.h>
typedef uint8_t  oa_u8;
typedef int8_t   oa_s8;
typedef uint16_t oa_u16;
typedef int16_t  oa_s16;
typedef uint32_t oa_u32;
typedef int32_t  oa_s32;
#endif

#endif
