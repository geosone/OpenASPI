#ifndef OA_EXFATSYS_H
#define OA_EXFATSYS_H
/* EXFAT.SYS's volumes for the tools (EXCHK, EXFMT): the device header
   "$EXFAT$ " is followed by "EXI1" and the offset of struct
   oa_exfatsys_info in the driver's segment.  The fields have fixed sizes,
   so programs of any memory model can read them. */
#include "openaspi/types.h"

#define OA_EXFATSYS_OURS    0   /* exFAT, the letter redirected */
#define OA_EXFATSYS_DOS     1   /* another medium: DOS and the block driver */
#define OA_EXFATSYS_PENDING 2   /* exFAT inserted: mounted at the next use */

#pragma pack(1)
/* at the start of each volume of the table */
struct oa_exfatsys_vol {
    oa_u8 letter;               /* 0 = A:, 0FFh none yet */
    oa_u8 aspi;                 /* 0: BIOS disk, 1: ASPIDSK/ASPIFDD unit */
    oa_u8 bios, ext;            /* BIOS disk number, INT 13h extensions */
    oa_u16 spt, heads;          /* BIOS geometry without extensions */
    oa_u32 start;               /* BIOS: first sector of the volume */
    oa_u8 unit, state;          /* ASPI: unit and OA_EXFATSYS_* */
    oa_u16 svc_off, svc_seg;    /* ASPI: the driver's exFAT service */
    oa_u8 changed;              /* set by a tool that wrote the volume:
                                   EXFAT.SYS reads it again at the next use */
};
struct oa_exfatsys_info {
    oa_u16 version;             /* 1 */
    oa_u16 count;               /* offset of the volume count (a word) */
    oa_u16 table;               /* offset of the first volume */
    oa_u16 stride;              /* bytes from one volume to the next */
};
#pragma pack()
#endif
