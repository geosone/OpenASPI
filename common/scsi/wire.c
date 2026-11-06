/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Byte order helpers: big-endian for CDBs and replies, little-endian for
 * ATA and NVMe structures. */

#include "openaspi/scsi.h"

oa_u16 oa_get_be16(const oa_u8 *p)
{
    return (oa_u16)(((oa_u16)p[0] << 8) | p[1]);
}

oa_u32 oa_get_be32(const oa_u8 *p)
{
    return ((oa_u32)p[0] << 24) | ((oa_u32)p[1] << 16) |
           ((oa_u32)p[2] << 8) | (oa_u32)p[3];
}

oa_u64 oa_get_be64(const oa_u8 *p)
{
    return ((oa_u64)oa_get_be32(p) << 32) | oa_get_be32(p + 4);
}

void oa_put_be16(oa_u8 *p, oa_u16 v)
{
    p[0] = (oa_u8)(v >> 8);
    p[1] = (oa_u8)v;
}

void oa_put_be32(oa_u8 *p, oa_u32 v)
{
    p[0] = (oa_u8)(v >> 24);
    p[1] = (oa_u8)(v >> 16);
    p[2] = (oa_u8)(v >> 8);
    p[3] = (oa_u8)v;
}

void oa_put_be64(oa_u8 *p, oa_u64 v)
{
    oa_put_be32(p, (oa_u32)(v >> 32));
    oa_put_be32(p + 4, (oa_u32)v);
}

oa_u16 oa_get_le16(const oa_u8 *p)
{
    return (oa_u16)(p[0] | ((oa_u16)p[1] << 8));
}

oa_u32 oa_get_le32(const oa_u8 *p)
{
    return (oa_u32)p[0] | ((oa_u32)p[1] << 8) | ((oa_u32)p[2] << 16) | ((oa_u32)p[3] << 24);
}

oa_u64 oa_get_le64(const oa_u8 *p)
{
    return (oa_u64)oa_get_le32(p) | ((oa_u64)oa_get_le32(p + 4) << 32);
}
