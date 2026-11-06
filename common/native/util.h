/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Internal helpers of the native layer: no C library. */

#ifndef OPENASPI_NATIVE_UTIL_H
#define OPENASPI_NATIVE_UTIL_H

#include <stddef.h>
#include <stdint.h>

static inline void oa_zero(void *p, size_t n)
{
	volatile uint8_t *b = p; /* volatile: no call to memset */
	while (n--)
		*b++ = 0;
}

static inline void oa_copy(void *dst, const void *src, size_t n)
{
	volatile uint8_t *d = dst;
	const uint8_t *s = src;
	while (n--)
		*d++ = *s++;
}

static inline uint16_t oa_be16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }
static inline uint32_t oa_be32(const uint8_t *p)
{
	return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
}
static inline uint64_t oa_be64(const uint8_t *p)
{
	return (uint64_t)oa_be32(p) << 32 | oa_be32(p + 4);
}
static inline void oa_put_be16(uint8_t *p, uint16_t v) { p[0] = (uint8_t)(v >> 8); p[1] = (uint8_t)v; }
static inline void oa_put_be32(uint8_t *p, uint32_t v)
{
	p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16); p[2] = (uint8_t)(v >> 8); p[3] = (uint8_t)v;
}
static inline void oa_put_be64(uint8_t *p, uint64_t v)
{
	oa_put_be32(p, (uint32_t)(v >> 32));
	oa_put_be32(p + 4, (uint32_t)v);
}

/* Copy a fixed-width, space-padded field and trim trailing blanks. */
static inline void oa_trim_copy(char *dst, const uint8_t *src, size_t n)
{
	size_t len = n;
	for (size_t i = 0; i < n; i++)
		dst[i] = (src[i] >= 0x20 && src[i] < 0x7f) ? (char)src[i] : ' ';
	while (len && dst[len - 1] == ' ')
		len--;
	dst[len] = 0;
}

#endif
