/* WINCHECK.EXE - Win16 companion environment probe for OpenASPI.
 * Returns zero when /3X or /9X matches. Without a selector it displays the
 * version, providing the first Win16 executable for the future Windows setup.
 * GNU General Public License version 3. */

#include <windows.h>

#define WANT_ANY  0
#define WANT_WIN3 1
#define WANT_WIN9 2

static int upper( int ch )
{
    return ch >= 'a' && ch <= 'z' ? ch - ( 'a' - 'A' ) : ch;
}

int PASCAL WinMain( HINSTANCE instance, HINSTANCE previous,
                    LPSTR command_line, int show )
{
    DWORD version = GetVersion();
    unsigned major = LOBYTE( LOWORD( version ) );
    unsigned minor = HIBYTE( LOWORD( version ) );
    int environment = major >= 4 || ( major == 3 && minor >= 90 )
                    ? WANT_WIN9 : WANT_WIN3;
    int wanted = WANT_ANY;
    int quiet = 0;
    char text[96];
    LPSTR p;

    (void)instance;
    (void)previous;
    (void)show;
    for ( p = command_line; *p; p++ ) {
        if ( *p != '/' && *p != '-' )
            continue;
        p++;
        if ( upper( *p ) == '3' )
            wanted = WANT_WIN3;
        else if ( upper( *p ) == '9' )
            wanted = WANT_WIN9;
        else if ( upper( *p ) == 'Q' )
            quiet = 1;
        if ( !*p )
            break;
    }

    if ( !quiet && wanted == WANT_ANY ) {
        wsprintf( text, "OpenASPI detected Windows %u.%02u (%s).",
                  major, minor,
                  environment == WANT_WIN9 ? "Windows 9x/ME" : "Windows 3.x" );
        MessageBox( NULL, text, "OpenASPI Windows detection",
                    MB_OK | MB_ICONINFORMATION );
    }
    return wanted == WANT_ANY || wanted == environment ? 0 : 1;
}
