/* Same QUILIB and colors as ASPIMGR/OpenTape/Open386MAX. */
#include <stdio.h>
#include <string.h>
#include <commfunc.h>
#include <input.h>
#include <libcolor.h>
#include <screen.h>
#include <ui.h>
#include <video.h>
#include <windowfn.h>
#include "copy_ui.h"
static int active;
static const char *phase;
static unsigned drive;
static oa_u32 total,done,errors,painted;
#ifdef LANG_GR
#define MSG(en,de) de
#else
#define MSG(en,de) en
#endif
static void line(WINDESC *panel,int row,const char *s,char color)
{
    WINDESC w=*panel;
    unsigned n=strlen(s);
    w.row+=row; w.col+=2; w.nrows=1; w.ncols-=4;
    if(n<(unsigned)w.ncols) w.ncols=(int)n;
    if(w.ncols>0) wput_csa(&w,(char *)s,color);
}
void dd_ui_start(void)
{
    if(active) return;
    initializeScreenInfo(FALSE); init_input(NULL); hide_cursor(); active=1;
}
static void close_ui(void)
{
    WINDESC w;
    if(!active) return;
    end_input(); SETWINDOW(&w,0,0,ScreenSize.row,ScreenSize.col);
    wput_sca(&w,VIDWORD(7,' ')); move_cursor(0,0); show_cursor(); active=0;
}
void abortprep(int flag) { (void)flag; close_ui(); }
static void draw(void)
{
    char text[96],bar[43];
    unsigned percent=total ? (unsigned)(done*100UL/total) : 0, filled=percent*40/100;
    paintBackgroundScreen();
    line(&DataWin,1,"OpenASPI - ASPIDD",DataYellowColor);
    line(&DataWin,3,phase ? phase : "",DataColor);
    sprintf(text,MSG("Drive: %c:","Laufwerk: %c:"),'A'+drive);
    line(&DataWin,5,text,DataColor);
    sprintf(text,"%lu / %lu %s",(unsigned long)done,(unsigned long)total,MSG("sectors","Sektoren"));
    line(&DataWin,7,text,DataColor);
    memset(bar,'-',40); memset(bar,'#',filled>40 ? 40 : filled); bar[40]=0;
    line(&DataWin,9,bar,DataYellowColor);
    sprintf(text,"%u%%",percent); line(&DataWin,11,text,DataColor);
    sprintf(text,MSG("Unreadable sectors: %lu","Unlesbare Sektoren: %lu"),(unsigned long)errors);
    line(&DataWin,13,text,DataYellowColor);
    line(&QuickWin,2,MSG("Copy progress","Kopierfortschritt"),QuickBackColor);
    line(&QuickWin,5,MSG("Esc: cancel","Esc: Abbruch"),QuickBackColor);
    line(&QuickWin,8,MSG("Writes verified","Schreibpruefung"),QuickBackColor);
}
void dd_ui_phase(const char *s,unsigned d,oa_u32 n)
{
    dd_ui_start(); phase=s; drive=d; total=n; done=0; painted=0xFFFFFFFFUL; draw();
}
int dd_ui_progress(oa_u32 n,oa_u32 bad)
{
    INPUTEVENT event;
    done=n;
    if(n==total || painted==0xFFFFFFFFUL || n-painted>=256 || errors!=bad) {
        errors=bad; painted=n; draw();
    }
    return get_input(0,&event) && event.key==KEY_ESCAPE ? -1 : 0;
}
static int wait_key(void)
{
    INPUTEVENT event;
    for(;;) { if(get_input(INPUT_WAIT,&event) && event.key) return event.key; }
}
int dd_ui_exchange(unsigned d)
{
    int key;
    drive=d; phase=MSG("Insert TARGET medium","ZIELmedium einlegen"); draw();
    line(&DataWin,16,MSG("Enter: write target  Esc: cancel","Enter: Ziel schreiben  Esc: Abbruch"),DataColor);
    do { key=wait_key(); } while(key!=KEY_ENTER && key!=KEY_ESCAPE);
    return key==KEY_ENTER ? 13 : 27;
}
int dd_ui_confirm(unsigned s,unsigned d)
{
    char text[80]; int key;
    dd_ui_start();
    sprintf(text,MSG("Copy %c: to %c: - overwrite target? Y/N","%c: auf %c: kopieren - Ziel loeschen? J/N"),'A'+s,'A'+d);
    phase=text; draw(); key=wait_key(); phase=0;
#ifdef LANG_GR
    return key=='j' || key=='J';
#else
    return key=='y' || key=='Y';
#endif
}
int dd_ui_select(unsigned *source,unsigned *target,int *rescue)
{
    unsigned field=0; int key; char text[80];
    *source=0; *target=1; dd_ui_start();
    for(;;) {
        phase=MSG("Choose source and target","Quelle und Ziel waehlen"); draw();
        sprintf(text,"%c %s %c:",field==0?'>':' ',MSG("Source","Quelle"),'A'+*source);
        line(&DataWin,5,text,DataYellowColor);
        sprintf(text,"%c %s %c:",field==1?'>':' ',MSG("Target","Ziel"),'A'+*target);
        line(&DataWin,7,text,DataYellowColor);
        line(&DataWin,9,*rescue ? "RESCUE: ON" : "RESCUE: OFF",DataColor);
        line(&DataWin,13,MSG("Tab: field  A-Z: drive  Space: same drive","Tab: Feld  A-Z: Laufwerk  Leertaste: gleich"),DataColor);
        line(&DataWin,15,"F2: Rescue  Enter: Start  Esc: Cancel",DataColor);
        key=wait_key();
        if(key==KEY_ESCAPE) return -1;
        if(key==KEY_ENTER) return 0;
        if(key==KEY_TAB) field=!field;
        if(key==KEY_F2) *rescue=!*rescue;
        if(key==' ') *target=*source;
        if(key>='a' && key<='z') key-='a'-'A';
        if(key>='A' && key<='Z') { if(field) *target=key-'A'; else *source=key-'A'; }
    }
}
void dd_ui_finish(int rc,oa_u32 bad)
{
    dd_ui_start();
    errors=bad;
    phase=rc==0 ? MSG("Copy completed","Kopie abgeschlossen") : rc==3 ?
        MSG("Rescue completed with gaps","Rettung mit Leseluecken beendet") :
        MSG("Copy incomplete/cancelled","Kopie unvollstaendig/abgebrochen");
    draw(); line(&DataWin,16,MSG("Enter/Esc: return to DOS","Enter/Esc: zurueck zu DOS"),DataColor);
    while(1) { int k=wait_key(); if(k==KEY_ENTER || k==KEY_ESCAPE) break; }
    close_ui();
}
