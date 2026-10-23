#ifndef OA_COPY_UI_H
#define OA_COPY_UI_H
#include "openaspi/types.h"
int dd_ui_select(unsigned *,unsigned *,int *);
int dd_ui_confirm(unsigned,unsigned);
void dd_ui_start(void);
void dd_ui_phase(const char *,unsigned,oa_u32);
int dd_ui_progress(oa_u32,oa_u32);
int dd_ui_exchange(unsigned);
void dd_ui_finish(int,oa_u32);
#endif
