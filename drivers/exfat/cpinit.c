/* The code page tables in EXFAT.SYS's INIT data: INIT copies the active one
   to the resident part, the other one is freed with INIT. */
#pragma data_seg("INIT_DATA", "INIT")
#include "../../common/exfat/codepage.c"
